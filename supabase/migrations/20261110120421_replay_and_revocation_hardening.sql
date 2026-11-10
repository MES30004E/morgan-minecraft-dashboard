-- Compact replay tombstones survive removal of full command records.
create table private.used_command_requests (
 server_id uuid not null references public.servers(id), requested_by uuid not null references auth.users(id),
 idempotency_key uuid not null, command_id uuid not null, created_at timestamptz not null default now(),
 primary key(server_id,requested_by,idempotency_key)
);
alter table private.used_command_requests enable row level security;
revoke all on private.used_command_requests from public,anon,authenticated,service_role;
create policy requests_deny on private.used_command_requests for all to public using(false) with check(false);
insert into private.used_command_requests(server_id,requested_by,idempotency_key,command_id,created_at)
 select server_id,requested_by,idempotency_key,id,created_at from public.commands;
create function private.lock_agent_server() returns uuid language plpgsql security definer set search_path='' as $$
declare target uuid:=private.agent_server();
begin
 if target is null then raise exception 'Agent required' using errcode='42501'; end if;
 perform 1 from public.servers where id=target for update;
 if target is distinct from private.agent_server() then raise exception 'Agent authorization revoked' using errcode='42501'; end if;
 return target;
end $$;
revoke all on function private.lock_agent_server() from public,anon,authenticated,service_role;
create or replace function private.manage_member(target uuid, person uuid, new_state text, new_role uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not private.allowed(target,'access.manage') then raise exception 'Forbidden' using errcode='42501'; end if;
 if new_state not in ('approved','rejected','suspended','pending') then raise exception 'Invalid membership state'; end if;
 perform 1 from public.servers where id=target for update;
 if not private.allowed(target,'access.manage') then raise exception 'Authorization revoked' using errcode='42501'; end if;
 if person=auth.uid() then raise exception 'Self-modification requires another owner'; end if;
 if not exists(select 1 from public.roles where server_id=target and id=new_role) then raise exception 'Role belongs to another server'; end if;
 update public.memberships set state=new_state,role_id=new_role where server_id=target and user_id=person;
 if not found then raise exception 'Membership not found'; end if;
 insert into public.audit_events(server_id,actor,action,details) values(target,auth.uid(),'membership.changed',jsonb_build_object('user_id',person,'state',new_state,'role_id',new_role));
end $$;
create or replace function private.set_role_permission(target uuid, target_role uuid, capability text, enabled boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not private.allowed(target,'access.manage') then raise exception 'Forbidden' using errcode='42501'; end if;
 perform 1 from public.servers where id=target for update;
 if not private.allowed(target,'access.manage') then raise exception 'Authorization revoked' using errcode='42501'; end if;
 if not exists(select 1 from public.roles where id=target_role and server_id=target) then raise exception 'Invalid role'; end if;
 if exists(select 1 from public.memberships where server_id=target and user_id=auth.uid() and role_id=target_role) then raise exception 'Cannot modify your own role'; end if;
 if enabled then insert into public.role_permissions values(target_role,capability) on conflict do nothing;
 else delete from public.role_permissions where role_id=target_role and permission=capability; end if;
 insert into public.audit_events(server_id,actor,action,details) values(target,auth.uid(),'role.permission_changed',jsonb_build_object('role_id',target_role,'permission',capability,'enabled',enabled));
end $$;
create or replace function private.enqueue(target uuid, action text, args jsonb, request_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare capability text; existing public.commands; result uuid;
begin
 capability:=case action when 'start' then 'server.start' when 'stop' then 'server.stop' when 'restart' then 'server.restart'
 when 'kick' then 'players.kick' when 'ban' then 'players.ban' when 'pardon' then 'players.pardon'
 when 'whitelist_add' then 'players.whitelist_add' when 'whitelist_remove' then 'players.whitelist_remove' else null end;
 if capability is null or not private.allowed(target,capability) then raise exception 'Forbidden' using errcode='42501'; end if;
 if request_id is null or args is null or jsonb_typeof(args)<>'object' then raise exception 'Invalid command'; end if;
 if action in ('start','stop','restart') then
   if args<>'{}'::jsonb then raise exception 'Unexpected arguments'; end if;
 else
   if not (args ? 'player') or args - 'player'<>'{}'::jsonb or jsonb_typeof(args->'player')<>'string' or args->>'player' !~ '^[A-Za-z0-9_]{3,16}$' then raise exception 'Invalid player'; end if;
 end if;
 -- Serialize requests per server so rate limits and deduplication cannot race.
 perform 1 from public.servers where id=target for update;
 if not private.allowed(target,capability) then raise exception 'Authorization revoked' using errcode='42501'; end if;
 select * into existing from public.commands where server_id=target and requested_by=auth.uid() and idempotency_key=request_id;
 if found then
   if existing.operation<>action or existing.arguments<>args then raise exception 'Idempotency conflict'; end if;
   return existing.id;
 end if;
 if exists(select 1 from private.used_command_requests where server_id=target and requested_by=auth.uid() and idempotency_key=request_id) then raise exception 'Request already archived; replay refused'; end if;
 if (select count(*) from private.used_command_requests where server_id=target)>=100000 or pg_database_size(current_database())>400000000 then raise exception 'Cloud storage safety limit reached'; end if;
 if (select count(*) from public.commands where server_id=target and created_at>now()-interval '1 day')>=200 then raise exception 'Daily operation budget reached'; end if;
 if (select count(*) from public.commands where server_id=target and created_at>now()-interval '1 minute')>=20
 or (select count(*) from public.commands where requested_by=auth.uid() and server_id=target and created_at>now()-interval '1 minute')>=5 then raise exception 'Rate limit exceeded'; end if;
 insert into public.commands(server_id,requested_by,operation,arguments,idempotency_key,expires_at)
 values(target,auth.uid(),action,args,request_id,now()+interval '60 seconds') returning id into result;
 insert into private.used_command_requests(server_id,requested_by,idempotency_key,command_id) values(target,auth.uid(),request_id,result);
 insert into public.audit_events(server_id,actor,action,details) values(target,auth.uid(),'command.queued',jsonb_build_object('command_id',result,'operation',action));
 return result;
end $$;
create or replace function private.claim_command() returns setof public.commands language plpgsql security definer set search_path='' as $$
declare target uuid:=private.lock_agent_server(); candidate public.commands;
begin
 if target is null then raise exception 'Agent required' using errcode='42501'; end if;
 perform 1 from public.servers where id=target for update;
 update public.commands set state='expired',finished_at=now() where server_id=target and state='queued' and expires_at<=now();
 update public.commands set state='uncertain' where server_id=target and state='claimed' and claimed_at<now()-interval '2 minutes';
 if exists(select 1 from public.commands where server_id=target and state in ('claimed','uncertain')) then return; end if;
 for candidate in select * from public.commands where server_id=target and state='queued' and expires_at>now() order by created_at for update loop
  if not exists(select 1 from public.memberships m join public.role_permissions p on p.role_id=m.role_id
   where m.server_id=target and m.user_id=candidate.requested_by and m.state='approved'
   and p.permission=case when candidate.operation in ('start','stop','restart') then 'server.'||candidate.operation else 'players.'||candidate.operation end) then
   update public.commands set state='failed',result='Authorization revoked',finished_at=now() where id=candidate.id;
   continue;
  end if;
  return query update public.commands set state='claimed',claimed_at=now(),claimed_by=auth.uid(),claim_token=gen_random_uuid() where id=candidate.id returning *;
  return;
 end loop;
end $$;
create or replace function private.prepare_archive(kind text) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare target uuid:=private.lock_agent_server(); batch private.archive_batches; row_data record;
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
create or replace function private.ack_archive(batch_id uuid,plaintext_sha text,record_count integer,ciphertext_sha text) returns void
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare target uuid:=private.lock_agent_server(); batch private.archive_batches;
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
create or replace function private.publish_snapshot(server_state text,cpu numeric,memory bigint,uptime bigint,online_players jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare target uuid:=private.lock_agent_server();
begin
 if target is null then raise exception 'Agent required' using errcode='42501'; end if;
 if exists(select 1 from public.snapshots where server_id=target and heartbeat_at>now()-interval '30 seconds') then return; end if;
 insert into public.snapshots values(target,now(),server_state,cpu,memory,uptime)
 on conflict(server_id) do update set heartbeat_at=excluded.heartbeat_at,state=excluded.state,cpu_percent=excluded.cpu_percent,
 memory_bytes=excluded.memory_bytes,uptime_seconds=excluded.uptime_seconds;
 insert into public.online_players values(target,now(),online_players)
 on conflict(server_id) do update set updated_at=excluded.updated_at,players=excluded.players;
end $$;
create or replace function private.finish_command(command_id uuid,token uuid,outcome text,summary text) returns void
language plpgsql security definer set search_path='' as $$
declare target uuid:=private.lock_agent_server(); command public.commands;
begin
 if target is null or outcome not in ('completed','failed','uncertain') or outcome is null then raise exception 'Forbidden' using errcode='42501'; end if;
 select * into command from public.commands where id=command_id and server_id=target and claimed_by=auth.uid() and claim_token=token for update;
 if not found then raise exception 'Invalid claim'; end if;
 if command.state=outcome then return; end if;
 if command.state not in ('claimed','uncertain') then raise exception 'Claim already finalized'; end if;
 update public.commands set state=outcome,result=left(summary,1000),finished_at=now() where id=command.id;
 insert into public.audit_events(server_id,actor,action,details) values(target,auth.uid(),'command.'||outcome,jsonb_build_object('command_id',command_id));
end $$;
create or replace function private.publish_console(log_lines jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare target uuid:=private.lock_agent_server();
begin
 if target is null then raise exception 'Agent required' using errcode='42501'; end if;
 if exists(select 1 from public.console_tail where server_id=target and updated_at>now()-interval '60 seconds') then return; end if;
 insert into public.console_tail values(target,now(),log_lines) on conflict(server_id) do update set updated_at=excluded.updated_at,lines=excluded.lines;
end $$;
create or replace function private.verify_link(code text,player_uuid uuid,player_name text,confirmed boolean) returns text
language plpgsql security definer set search_path='' as $$
declare challenge private.pairing_challenges; label text; target uuid:=private.lock_agent_server();
begin
 if target is null then raise exception 'Agent required' using errcode='42501'; end if;
 select * into challenge from private.pairing_challenges where token_hash=extensions.digest(code,'sha256') for update;
 if not found or challenge.expires_at<=now() or challenge.consumed_at is not null or challenge.user_id is null
 or lower(challenge.expected_name)<>lower(player_name) or player_uuid is null or player_name is null
 or (challenge.minecraft_uuid is not null and challenge.minecraft_uuid<>player_uuid) then raise exception 'Invalid or expired pairing code'; end if;
 select display_name into label from public.profiles where id=challenge.user_id;
 label:=coalesce(label,'Website account')||' ['||left(challenge.user_id::text,8)||']';
 if not coalesce(confirmed,false) then return 'Link to '||label||'? If this is your website account, run /verify '||code||' confirm'; end if;
 insert into public.mc_identities(minecraft_uuid,user_id,username) values(player_uuid,challenge.user_id,player_name)
 on conflict(minecraft_uuid) do update set username=excluded.username where public.mc_identities.user_id=excluded.user_id;
 if not found then raise exception 'Minecraft identity already linked to another account'; end if;
 update private.pairing_challenges set minecraft_uuid=player_uuid,consumed_at=now() where id=challenge.id;
 insert into public.memberships(server_id,user_id) values(target,challenge.user_id) on conflict do nothing;
 insert into public.audit_events(server_id,actor,action,details) values(target,challenge.user_id,'identity.linked',jsonb_build_object('minecraft_uuid',player_uuid));
 return 'Linked to '||label||'. Membership approval is separate.';
end $$;
create or replace function private.unlink_game_identity(player_uuid uuid) returns text language plpgsql security definer set search_path='' as $$
declare person uuid; target uuid:=private.lock_agent_server();
begin
 if target is null then raise exception 'Agent required' using errcode='42501'; end if;
 delete from public.mc_identities where minecraft_uuid=player_uuid returning user_id into person;
 if found then insert into public.audit_events(server_id,actor,action,details) values(target,person,'identity.unlinked',jsonb_build_object('minecraft_uuid',player_uuid)); end if;
 return 'Identity unlinked. Website roles and Minecraft inventory are unchanged.';
end $$;
create or replace function private.record_player_stats(player_uuid uuid,player_name text,stats jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare target uuid:=private.lock_agent_server();
begin
 if target is null then raise exception 'Agent required' using errcode='42501'; end if;
 if jsonb_typeof(stats)<>'object' or stats is null or stats-array['online','play_time_ticks','deaths','mob_kills','blocks_mined','advancements_done','advancements_total']<>'{}'::jsonb then raise exception 'Invalid statistics'; end if;
 insert into public.player_statistics(server_id,minecraft_uuid,username,online,play_time_ticks,deaths,mob_kills,blocks_mined,advancements_done,advancements_total)
 values(target,player_uuid,player_name,(stats->>'online')::boolean,(stats->>'play_time_ticks')::bigint,(stats->>'deaths')::bigint,(stats->>'mob_kills')::bigint,(stats->>'blocks_mined')::bigint,(stats->>'advancements_done')::integer,(stats->>'advancements_total')::integer)
 on conflict(server_id,minecraft_uuid) do update set username=excluded.username,last_seen_at=now(),online=excluded.online,
 play_time_ticks=excluded.play_time_ticks,deaths=excluded.deaths,mob_kills=excluded.mob_kills,blocks_mined=excluded.blocks_mined,
 advancements_done=excluded.advancements_done,advancements_total=excluded.advancements_total;
end $$;
create or replace function private.publish_backups(archives jsonb) returns void language plpgsql security definer set search_path='' as $$
declare target uuid:=private.lock_agent_server(); entry jsonb;
begin
 if target is null then raise exception 'Agent required' using errcode='42501'; end if;
 if jsonb_typeof(archives)<>'array' or archives is null or jsonb_array_length(archives)>120 or octet_length(archives::text)>32768 then raise exception 'Invalid backup metadata'; end if;
 for entry in select * from jsonb_array_elements(archives) loop
 insert into public.backups(server_id,backup_id,created_at,state,size_bytes) values(target,entry->>'backup_id',(entry->>'created_at')::timestamptz,'completed',(entry->>'size_bytes')::bigint)
 on conflict(server_id,backup_id) do update set size_bytes=excluded.size_bytes;
 end loop;
end $$;
create or replace function private.begin_game_link(player_uuid uuid,player_name text) returns text language plpgsql security definer set search_path='' as $$
declare code text;
begin
 if private.lock_agent_server() is null then raise exception 'Agent required' using errcode='42501'; end if;
 if player_uuid is null or player_name is null or player_name !~ '^[A-Za-z0-9_]{3,16}$' then raise exception 'Invalid player'; end if;
 perform pg_advisory_xact_lock(hashtextextended(player_uuid::text,0));
 if (select count(*) from private.pairing_challenges where minecraft_uuid=player_uuid and created_at>now()-interval '1 hour')>=5 then raise exception 'Pairing rate limit'; end if;
 code:=encode(extensions.gen_random_bytes(16),'hex');
 insert into private.pairing_challenges(token_hash,minecraft_uuid,expected_name,direction) values(extensions.digest(code,'sha256'),player_uuid,player_name,'game');
 return code;
end $$;
create or replace function private.resolve_uncertain(command_id uuid,outcome text,note text) returns void
language plpgsql security definer set search_path='' as $$
declare command public.commands; target uuid;
begin
 select server_id into target from public.commands where id=command_id;
 if target is null then raise exception 'Forbidden' using errcode='42501'; end if;
 perform 1 from public.servers where id=target for update;
 if not private.allowed(target,'access.manage') then raise exception 'Forbidden' using errcode='42501'; end if;
 select * into command from public.commands where id=command_id for update;
 if command.state<>'uncertain' or outcome not in ('completed','failed') or outcome is null or length(note)<10 or note is null then raise exception 'Reconciliation note and terminal outcome required'; end if;
 update public.commands set state=outcome,result=left(note,1000),finished_at=now() where id=command_id;
 insert into public.audit_events(server_id,actor,action,details) values(target,auth.uid(),'command.reconciled',jsonb_build_object('command_id',command_id,'outcome',outcome,'note',left(note,1000)));
end $$;
create function private.audit_storage_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if (select count(*) from (select 1 from public.audit_events limit 100001) capped)>100000 then raise exception 'Audit storage safety limit reached; repair archival before further operations'; end if;
 return new;
end $$;
revoke all on function private.audit_storage_guard() from public,anon,authenticated,service_role;
create trigger audit_storage_budget before insert on public.audit_events for each statement execute function private.audit_storage_guard();
