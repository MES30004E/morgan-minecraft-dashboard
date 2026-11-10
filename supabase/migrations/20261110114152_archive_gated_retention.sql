-- Retention is fail-closed: a trusted agent must first persist, decrypt and verify
-- encrypted Ubuntu storage, then acknowledge these exact plaintext bytes.
-- No cron job is installed by this migration.
create function private.archive_sha(value text) returns text language sql immutable strict
set search_path='' as $$ select encode(sha256(convert_to(value,'UTF8')),'hex') $$;
revoke all on function private.archive_sha(text) from public,anon,authenticated;

create table private.archive_batches (
 id uuid primary key default gen_random_uuid(), server_id uuid not null references public.servers(id),
 kind text not null check(kind in ('commands','audit','backups','statistics','memberships')),
 created_at timestamptz not null default now(), payload_text text,
 sha256 text not null check(sha256 ~ '^[0-9a-f]{64}$'),
 record_count integer not null check(record_count between 1 and 500),
 acknowledged_at timestamptz, ciphertext_sha text check(ciphertext_sha ~ '^[0-9a-f]{64}$'),
 check((acknowledged_at is null and payload_text is not null and ciphertext_sha is null)
    or (acknowledged_at is not null and payload_text is null and ciphertext_sha is not null)),
 check(payload_text is null or octet_length(payload_text)<=524288),
 unique(id,server_id,kind)
);
create unique index archive_one_pending on private.archive_batches(server_id,kind) where acknowledged_at is null;
create table private.archive_items (
 batch_id uuid not null, server_id uuid not null, kind text not null, record_key text not null,
 fingerprint text not null check(fingerprint ~ '^[0-9a-f]{64}$'),
 primary key(batch_id,record_key),
 foreign key(batch_id,server_id,kind) references private.archive_batches(id,server_id,kind)
);
create index archive_item_version on private.archive_items(server_id,kind,record_key,fingerprint);
-- A daily snapshot is frozen in one transaction, then drained in bounded chunks.
-- A stalled old snapshot is completed before another day is captured.
create table private.archive_snapshot_runs (
 server_id uuid not null references public.servers(id), kind text not null check(kind in ('statistics','memberships')),
 snapshot_day date not null, captured_at timestamptz not null, primary key(server_id,kind,snapshot_day)
);
create table private.archive_snapshot_rows (
 server_id uuid not null, kind text not null, snapshot_day date not null,
 record_key text not null, record_data jsonb not null,
 primary key(server_id,kind,snapshot_day,record_key),
 foreign key(server_id,kind,snapshot_day) references private.archive_snapshot_runs(server_id,kind,snapshot_day)
);
-- Permanent, small per-day summaries; no freeform text, identities or secrets.
create table private.security_daily_rollups (
 server_id uuid not null references public.servers(id), event_day date not null,
 event_count bigint not null, event_sha256 text not null check(event_sha256 ~ '^[0-9a-f]{64}$'),
 primary key(server_id,event_day)
);
do $$ declare t text; begin
 foreach t in array array['archive_batches','archive_items','archive_snapshot_runs','archive_snapshot_rows','security_daily_rollups'] loop
 execute format('alter table private.%I enable row level security',t);
 execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);
 execute format('create policy deny_client on private.%I for all to public using(false) with check(false)',t);
 end loop;
end $$;

-- Full-row fingerprints never leave the private schema. They include omitted
-- result/token/detail fields so any cloud mutation invalidates deletion consent.
create function private.archive_safe_audit(row_data jsonb) returns jsonb
language plpgsql stable set search_path='' as $$
declare detail jsonb:='{}'; k text; v text; action text:=row_data->>'action';
begin
 foreach k in array array['command_id','user_id','role_id','minecraft_uuid'] loop
 v:=row_data->'details'->>k;
 if v ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then detail:=detail||jsonb_build_object(k,v); end if;
 end loop;
 foreach k in array array['state','outcome'] loop
 v:=row_data->'details'->>k;
 if v in ('pending','approved','rejected','suspended','queued','claimed','completed','failed','expired','uncertain') then detail:=detail||jsonb_build_object(k,v); end if;
 end loop;
 v:=row_data->'details'->>'operation';
 if v in ('start','stop','restart','kick','ban','pardon','whitelist_add','whitelist_remove') then detail:=detail||jsonb_build_object('operation',v); end if;
 v:=row_data->'details'->>'permission';
 if v in ('status.view','players.view','server.start','server.stop','server.restart','players.kick','players.ban','players.pardon','players.whitelist_add','players.whitelist_remove','console.view','backups.view','audit.view','access.manage') then detail:=detail||jsonb_build_object('permission',v); end if;
 if jsonb_typeof(row_data->'details'->'enabled')='boolean' then detail:=detail||jsonb_build_object('enabled',row_data->'details'->'enabled'); end if;
 if action not in ('command.queued','command.completed','command.failed','command.uncertain','command.reconciled','membership.changed','role.permission_changed','identity.linked','identity.unlinked','owner.changed','security.changed','owner.bootstrapped','agent.registered','agent.revoked') then action:='other'; end if;
 return jsonb_build_object('id',row_data->'id','server_id',row_data->'server_id','actor',row_data->'actor','action',action,'details',detail,'created_at',row_data->'created_at');
end $$;
revoke all on function private.archive_safe_audit(jsonb) from public,anon,authenticated;

create function private.prepare_archive(kind text) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare target uuid:=private.agent_server(); batch private.archive_batches; row_data record;
 records jsonb:='[]'; envelope text; trial text; exported timestamptz:=now();
 batch_id uuid:=gen_random_uuid(); n integer:=0; day date; keys text[]:='{}'; hashes text[]:='{}';
begin
 if target is null then raise exception 'Agent required' using errcode='42501'; end if;
 if kind is null or kind not in ('commands','audit','backups','statistics','memberships') then raise exception 'Invalid archive kind'; end if;
 -- Shared with acknowledgement, commands and membership management.
 perform 1 from public.servers where id=target for update;
 select b.* into batch from private.archive_batches b where b.server_id=target and b.kind=prepare_archive.kind and b.acknowledged_at is null;
 if found then return jsonb_build_object('id',batch.id,'kind',batch.kind,'created_at',batch.created_at,'payload_text',batch.payload_text,'sha256',batch.sha256,'record_count',batch.record_count); end if;
 if kind in ('statistics','memberships') then
 select min(r.snapshot_day) into day from private.archive_snapshot_rows r where r.server_id=target and r.kind=prepare_archive.kind;
 if day is null then
 day:=(now() at time zone 'UTC')::date;
 if exists(select 1 from private.archive_snapshot_runs r where r.server_id=target and r.kind=prepare_archive.kind and r.snapshot_day=day) then return null; end if;
 insert into private.archive_snapshot_runs values(target,kind,day,exported);
 if kind='statistics' then
 insert into private.archive_snapshot_rows select target,kind,day,s.minecraft_uuid::text,to_jsonb(s) from public.player_statistics s where s.server_id=target;
 else
 insert into private.archive_snapshot_rows
 select target,kind,day,m.user_id::text,
 jsonb_build_object('server_id',m.server_id,'user_id',m.user_id,'state',m.state,'role_id',m.role_id,'role_name',r.name,
 'permissions',coalesce((select jsonb_agg(p.permission order by p.permission) from public.role_permissions p where p.role_id=r.id),'[]'::jsonb))
 from public.memberships m left join public.roles r on r.server_id=m.server_id and r.id=m.role_id where m.server_id=target;
 end if;
 end if;
 select r.captured_at into exported from private.archive_snapshot_runs r where r.server_id=target and r.kind=prepare_archive.kind and r.snapshot_day=day;
 end if;
 for row_data in
 with candidates as (
 select c.id::text key,private.archive_sha(to_jsonb(c)::text) fingerprint,
 jsonb_build_object('id',c.id,'server_id',c.server_id,'requested_by',c.requested_by,'operation',
 case when c.operation in ('start','stop','restart','kick','ban','pardon','whitelist_add','whitelist_remove') then c.operation else 'other' end,
 'arguments',case when c.arguments->>'player' ~ '^[A-Za-z0-9_]{3,16}$' then jsonb_build_object('player',c.arguments->>'player') else '{}'::jsonb end,
 'idempotency_key',c.idempotency_key,'state',c.state,'created_at',c.created_at,'expires_at',c.expires_at,
 'claimed_by',c.claimed_by,'claimed_at',c.claimed_at,'finished_at',c.finished_at) data,c.created_at ordering
 from public.commands c where kind='commands' and c.server_id=target and c.state in ('completed','failed','expired') and c.created_at<now()-interval '1 day'
 union all
 select a.id::text,private.archive_sha(to_jsonb(a)::text),private.archive_safe_audit(to_jsonb(a)),a.created_at
 from public.audit_events a where kind='audit' and a.server_id=target and a.created_at<now()-interval '1 day'
 union all
 select b.backup_id,private.archive_sha(to_jsonb(b)::text),to_jsonb(b),b.created_at
 from public.backups b where kind='backups' and b.server_id=target and b.created_at<now()-interval '1 day'
 union all
 select s.record_key,private.archive_sha(s.record_data::text),s.record_data,exported
 from private.archive_snapshot_rows s where s.server_id=target and s.kind=prepare_archive.kind and s.snapshot_day=day
 ) select * from candidates c where kind in ('statistics','memberships') or not exists(
 select 1 from private.archive_items i join private.archive_batches b on b.id=i.batch_id
 where i.server_id=target and i.kind=prepare_archive.kind and i.record_key=c.key and i.fingerprint=c.fingerprint and b.acknowledged_at is not null)
 order by c.ordering,c.key limit 501
 loop
 exit when n=500;
 trial:=jsonb_build_object('format',1,'kind',kind,'server_id',target,'exported_at',exported,'records',records||jsonb_build_array(row_data.data))::text;
 if octet_length(trial)>524288 then
 if n=0 then raise exception 'Archive record exceeds batch limit; preserve source and investigate'; end if;
 exit;
 end if;
 envelope:=trial; records:=records||jsonb_build_array(row_data.data); n:=n+1;
 keys:=array_append(keys,row_data.key); hashes:=array_append(hashes,row_data.fingerprint);
 end loop;
 if n=0 then return null; end if;
 insert into private.archive_batches(id,server_id,kind,created_at,payload_text,sha256,record_count)
 values(batch_id,target,kind,exported,envelope,private.archive_sha(envelope),n) returning * into batch;
 insert into private.archive_items(batch_id,server_id,kind,record_key,fingerprint)
 select batch_id,target,kind,keys[s],hashes[s] from generate_subscripts(keys,1) s;
 -- Queue rows disappear only after their exact bytes are durable in this pending batch.
 if kind in ('statistics','memberships') then
 delete from private.archive_snapshot_rows r where r.server_id=target and r.kind=prepare_archive.kind and r.snapshot_day=day and r.record_key=any(keys);
 end if;
 return jsonb_build_object('id',batch.id,'kind',batch.kind,'created_at',batch.created_at,'payload_text',batch.payload_text,'sha256',batch.sha256,'record_count',batch.record_count);
end $$;
create function public.prepare_archive(kind text) returns jsonb language sql security invoker set search_path='' as $$ select private.prepare_archive(kind) $$;

create function private.ack_archive(batch_id uuid,plaintext_sha text,record_count integer,ciphertext_sha text) returns void
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare target uuid:=private.agent_server(); batch private.archive_batches;
begin
 if target is null then raise exception 'Agent required' using errcode='42501'; end if;
 perform 1 from public.servers where id=target for update;
 select b.* into batch from private.archive_batches b where b.id=batch_id and b.server_id=target for update;
 if not found then raise exception 'Archive not found' using errcode='42501'; end if;
 if plaintext_sha is distinct from batch.sha256 or record_count is distinct from batch.record_count
 or ciphertext_sha is null or ciphertext_sha !~ '^[0-9a-f]{64}$' then raise exception 'Archive acknowledgment mismatch'; end if;
 if batch.acknowledged_at is not null then
 if batch.ciphertext_sha is distinct from ciphertext_sha then raise exception 'Archive acknowledgment conflict'; end if;
 return;
 end if;
 if private.archive_sha(batch.payload_text)<>plaintext_sha or (select count(*) from private.archive_items i where i.batch_id=batch.id)<>record_count then raise exception 'Stored archive integrity mismatch'; end if;
 update private.archive_batches b set acknowledged_at=now(),payload_text=null,ciphertext_sha=ack_archive.ciphertext_sha where b.id=batch.id;
end $$;
create function public.ack_archive(batch_id uuid,plaintext_sha text,record_count integer,ciphertext_sha text) returns void
language sql security invoker set search_path='' as $$ select private.ack_archive(batch_id,plaintext_sha,record_count,ciphertext_sha) $$;
do $$ declare f record; begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('private','public') and p.proname in ('prepare_archive','ack_archive') loop
 execute format('revoke all on function %s from public,anon,service_role',f.signature);
 execute format('grant execute on function %s to authenticated',f.signature);
 end loop;
end $$;

create or replace function private.housekeeping() returns void language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare candidate record;
begin
 -- Serialize destructive sweep with agent batch preparation/acknowledgement.
 perform id from public.servers order by id for update;
 delete from public.commands c where c.state in ('completed','failed','expired') and c.created_at<now()-interval '7 days'
 and exists(select 1 from private.archive_items i join private.archive_batches b on b.id=i.batch_id where i.server_id=c.server_id and i.kind='commands' and i.record_key=c.id::text and i.fingerprint=private.archive_sha(to_jsonb(c)::text) and b.acknowledged_at is not null);
 -- Lock matching audit rows before hashing and deletion to prevent changed rows
 -- being erased under an old version's verification (including concurrent writers).
 for candidate in select a.* from public.audit_events a where a.created_at<now()-interval '90 days' and exists(
 select 1 from private.archive_items i join private.archive_batches b on b.id=i.batch_id where i.server_id=a.server_id and i.kind='audit' and i.record_key=a.id::text and i.fingerprint=private.archive_sha(to_jsonb(a)::text) and b.acknowledged_at is not null) order by a.id for update
 loop
 if candidate.action in ('command.reconciled','membership.changed','role.permission_changed','identity.linked','identity.unlinked','owner.changed','security.changed','owner.bootstrapped','agent.registered','agent.revoked') then
 insert into private.security_daily_rollups(server_id,event_day,event_count,event_sha256)
 values(candidate.server_id,(candidate.created_at at time zone 'UTC')::date,1,private.archive_sha(to_jsonb(candidate)::text))
 on conflict(server_id,event_day) do update set event_count=private.security_daily_rollups.event_count+1,
 event_sha256=private.archive_sha(private.security_daily_rollups.event_sha256||':'||excluded.event_sha256);
 end if;
 delete from public.audit_events where id=candidate.id;
 end loop;
 delete from private.pairing_challenges where expires_at<now()-interval '1 day';
 delete from public.backups c where c.created_at<now()-interval '90 days'
 and exists(select 1 from private.archive_items i join private.archive_batches b on b.id=i.batch_id where i.server_id=c.server_id and i.kind='backups' and i.record_key=c.backup_id and i.fingerprint=private.archive_sha(to_jsonb(c)::text) and b.acknowledged_at is not null);
 -- Remove acknowledged fingerprint receipts only after their source disappeared;
 -- compact batch digests remain. Snapshot receipts are never deletion authority.
 delete from private.archive_items i using private.archive_batches b where b.id=i.batch_id and b.acknowledged_at is not null and (
 i.kind in ('statistics','memberships') or
 (i.kind='commands' and not exists(select 1 from public.commands c where c.server_id=i.server_id and c.id::text=i.record_key)) or
 (i.kind='audit' and not exists(select 1 from public.audit_events a where a.server_id=i.server_id and a.id::text=i.record_key)) or
 (i.kind='backups' and not exists(select 1 from public.backups c where c.server_id=i.server_id and c.backup_id=i.record_key)));
end $$;
revoke all on function private.housekeeping() from public,anon,authenticated,service_role;
grant execute on function private.housekeeping() to postgres;

-- Restricted summaries expose neither event payloads nor identities.
create function private.audit_security_summaries(target uuid)
returns table(event_day date,event_count bigint,event_sha256 text)
language plpgsql stable security definer set search_path='' set timezone='UTC' as $$
begin
 if not private.allowed(target,'audit.view') then raise exception 'Forbidden' using errcode='42501'; end if;
 return query select r.event_day,r.event_count,r.event_sha256
 from private.security_daily_rollups r where r.server_id=target order by r.event_day desc;
end $$;
create function public.audit_security_summaries(target uuid)
returns table(event_day date,event_count bigint,event_sha256 text)
language sql stable security invoker set search_path='' as $$ select * from private.audit_security_summaries(target) $$;
revoke all on function private.audit_security_summaries(uuid),public.audit_security_summaries(uuid) from public,anon,service_role;
grant execute on function private.audit_security_summaries(uuid),public.audit_security_summaries(uuid) to authenticated;
