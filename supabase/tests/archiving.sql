-- Synthetic fixtures only; run after all migrations as postgres. Always rollback.
begin;
insert into auth.users(id,email) values
('91000000-0000-4000-8000-000000000001','archive-agent@example.invalid'),
('91000000-0000-4000-8000-000000000002','archive-human@example.invalid'),
('91000000-0000-4000-8000-000000000003','other-agent@example.invalid');
insert into public.servers(id,name,gameplay_address) values
('92000000-0000-4000-8000-000000000001','Archive fixture','example.invalid'),
('92000000-0000-4000-8000-000000000002','Other fixture','example.invalid');
insert into private.agents values
('91000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000001',true),
('91000000-0000-4000-8000-000000000003','92000000-0000-4000-8000-000000000002',true);
insert into public.commands(id,server_id,requested_by,operation,idempotency_key,state,created_at,expires_at,result,claim_token)
select ('93000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
'92000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000002','start',gen_random_uuid(),
case when n=3 then 'uncertain' else 'completed' end,
now()-case when n=2 then interval '3 days' else interval '10 days' end,
now()-interval '2 days','NEVER_EXPORT_RESULT',gen_random_uuid() from generate_series(1,4) n;
insert into public.audit_events(server_id,actor,action,details,created_at) values
('92000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000002','role.permission_changed',
'{"note":"NEVER_EXPORT_NOTE","permission":"access.manage","enabled":true,"role_id":"94000000-0000-4000-8000-000000000001","user_id":"NEVER_EXPORT_FAKE_UUID"}',now()-interval '100 days');
insert into public.audit_events(server_id,actor,action,details,created_at)
select '92000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000002',action,'{}',now()-interval '100 days'
from unnest(array['owner.bootstrapped','agent.registered','agent.revoked','command.reconciled']) action;
insert into public.backups values('92000000-0000-4000-8000-000000000001','old-backup',now()-interval '100 days','completed',123);
insert into public.roles(id,server_id,name) values('94000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000001','Owner');
insert into public.role_permissions values('94000000-0000-4000-8000-000000000001','access.manage');
insert into public.memberships values('92000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000002','94000000-0000-4000-8000-000000000001','approved');
insert into public.player_statistics(server_id,minecraft_uuid,username,online)
select '92000000-0000-4000-8000-000000000001',md5(n::text)::uuid,'Steve',false from generate_series(1,501) n;
insert into private.pairing_challenges(id,token_hash,direction,expires_at) values
('95000000-0000-4000-8000-000000000001',decode('abcd','hex'),'web',now()-interval '2 days'),
('95000000-0000-4000-8000-000000000002',decode('abce','hex'),'web',now()-interval '12 hours');
create temporary table archive_test_batches(kind text primary key,b jsonb);
grant all on archive_test_batches to authenticated;
set local role anon;
do $$ begin
 begin perform public.prepare_archive('commands'); raise exception 'Anon export accepted'; exception when insufficient_privilege then null; end;
 begin perform * from public.audit_security_summaries('92000000-0000-4000-8000-000000000001'); raise exception 'Anon summaries accepted'; exception when insufficient_privilege then null; end;
 begin perform public.ack_archive(gen_random_uuid(),repeat('a',64),1,repeat('b',64)); raise exception 'Anon ack accepted'; exception when insufficient_privilege then null; end;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000002',true);
do $$ begin
 begin perform public.prepare_archive('commands'); raise exception 'Human export accepted'; exception when insufficient_privilege then null; end;
 begin perform private.housekeeping(); raise exception 'Human housekeeping accepted'; exception when insufficient_privilege then null; end;
 begin perform * from public.audit_security_summaries('92000000-0000-4000-8000-000000000001'); raise exception 'Unauthorised summaries accepted'; exception when insufficient_privilege then null; end;
 begin perform public.ack_archive(gen_random_uuid(),repeat('a',64),1,repeat('b',64)); raise exception 'Human ack accepted'; exception when insufficient_privilege then null; end;
 begin perform 1 from private.archive_batches; raise exception 'Private batch table exposed'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000001',true);
insert into archive_test_batches select k,public.prepare_archive(k) from unnest(array['commands','audit','backups','statistics','memberships']) k;
do $$ declare b jsonb; payload jsonb; begin
 select t.b into b from archive_test_batches t where kind='commands';
 if (b->>'record_count')::int<>3 then raise exception 'Terminal eligibility wrong'; end if;
 if b<>public.prepare_archive('commands') then raise exception 'Retry changed payload'; end if;
 if b->>'sha256'<>encode(sha256(convert_to(b->>'payload_text','UTF8')),'hex') then raise exception 'UTF8 checksum wrong'; end if;
 if (b->>'payload_text') like '%NEVER_EXPORT%' or (b->>'payload_text') like '%claim_token%' or (b->>'payload_text') like '%"result"%' then raise exception 'Command secret exported'; end if;
 if octet_length(b->>'payload_text')>524288 then raise exception 'Oversize payload'; end if;
 payload:=(b->>'payload_text')::jsonb;
 if (payload->>'format')::int<>1 or jsonb_array_length(payload->'records')<>3 then raise exception 'Envelope invalid'; end if;
 begin perform public.ack_archive((b->>'id')::uuid,repeat('0',64),3,repeat('a',64)); raise exception 'Wrong digest accepted'; exception when raise_exception then if sqlerrm<>'Archive acknowledgment mismatch' then raise; end if; end;
 begin perform public.ack_archive((b->>'id')::uuid,b->>'sha256',2,repeat('a',64)); raise exception 'Wrong count accepted'; exception when raise_exception then if sqlerrm<>'Archive acknowledgment mismatch' then raise; end if; end;
 begin perform public.ack_archive((b->>'id')::uuid,b->>'sha256',3,'not-a-sha'); raise exception 'Bad cipher digest accepted'; exception when raise_exception then if sqlerrm<>'Archive acknowledgment mismatch' then raise; end if; end;
 select t.b into b from archive_test_batches t where kind='audit';
 if b->>'payload_text' like '%NEVER_EXPORT%' or b->>'payload_text' like '%"note"%' then raise exception 'Audit freeform leak'; end if;
 if exists(select 1 from jsonb_array_elements((b->>'payload_text')::jsonb->'records') r where r->>'action'='other') then raise exception 'Important audit action lost'; end if;
 select t.b into b from archive_test_batches t where kind='memberships';
 payload:=(b->>'payload_text')::jsonb;
 if payload->'records'->0->>'role_name'<>'Owner' or payload->'records'->0->'permissions'<>'["access.manage"]'::jsonb then raise exception 'Permission snapshot missing'; end if;
 if b->>'payload_text' like '%@example%' then raise exception 'Email exported'; end if;
 select t.b into b from archive_test_batches t where kind='statistics';
 if (b->>'record_count')::int<>500 then raise exception 'Statistics chunk not capped at 500'; end if;
end $$;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000003',true);
do $$ declare b jsonb; begin
 select t.b into b from archive_test_batches t where kind='commands';
 if public.prepare_archive('commands') is not null then raise exception 'Cross-server batch read'; end if;
 begin perform public.ack_archive((b->>'id')::uuid,b->>'sha256',3,repeat('a',64)); raise exception 'Wrong agent acknowledged'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select private.housekeeping();
do $$ begin
 if (select count(*) from public.commands where server_id='92000000-0000-4000-8000-000000000001')<>4 then raise exception 'Unacked commands deleted'; end if;
 if exists(select 1 from private.pairing_challenges where id='95000000-0000-4000-8000-000000000001') or not exists(select 1 from private.pairing_challenges where id='95000000-0000-4000-8000-000000000002') then raise exception 'Pairing expiry grace incorrect'; end if;
 if not exists(select 1 from public.audit_events where server_id='92000000-0000-4000-8000-000000000001') or not exists(select 1 from public.backups where backup_id='old-backup') then raise exception 'Unacked old metadata deleted'; end if;
end $$;
-- Change a field intentionally omitted from export. Its hash must still change.
update public.commands set result='CHANGED_AFTER_EXPORT' where id='93000000-0000-4000-8000-000000000004';
-- Frozen queued remainder must survive source mutation between chunks.
update public.player_statistics set online=true where server_id='92000000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000001',true);
do $$ declare r record; b jsonb; begin
 for r in select t.b from archive_test_batches t loop
 perform public.ack_archive((r.b->>'id')::uuid,r.b->>'sha256',(r.b->>'record_count')::int,repeat('a',64));
 perform public.ack_archive((r.b->>'id')::uuid,r.b->>'sha256',(r.b->>'record_count')::int,repeat('a',64));
 end loop;
 b:=public.prepare_archive('statistics');
 if (b->>'record_count')::int<>1 then raise exception 'Statistics remainder omitted'; end if;
 if ((b->>'payload_text')::jsonb->'records'->0->>'online')::boolean then raise exception 'Snapshot changed between chunks'; end if;
 perform public.ack_archive((b->>'id')::uuid,b->>'sha256',1,repeat('b',64));
 if public.prepare_archive('statistics') is not null or public.prepare_archive('memberships') is not null then raise exception 'Daily snapshot repeated'; end if;
end $$;
reset role;
select private.housekeeping();
do $$ begin
 if exists(select 1 from public.commands where id='93000000-0000-4000-8000-000000000001') then raise exception 'Ack did not allow old terminal deletion'; end if;
 if (select count(*) from public.commands where server_id='92000000-0000-4000-8000-000000000001')<>3 then raise exception 'Young/uncertain/mutated command lost'; end if;
 if exists(select 1 from public.audit_events where server_id='92000000-0000-4000-8000-000000000001') or exists(select 1 from public.backups where backup_id='old-backup') then raise exception 'Acked old metadata not deleted'; end if;
 if (select event_count from private.security_daily_rollups where server_id='92000000-0000-4000-8000-000000000001')<>5 then raise exception 'Security rollup missing'; end if;
 if (select count(*) from public.player_statistics where server_id='92000000-0000-4000-8000-000000000001')<>501 or not exists(select 1 from public.memberships where server_id='92000000-0000-4000-8000-000000000001') then raise exception 'Snapshot source deleted'; end if;
 if exists(select 1 from private.archive_batches where acknowledged_at is not null and payload_text is not null) then raise exception 'Acknowledged plaintext retained'; end if;
end $$;
insert into public.role_permissions values('94000000-0000-4000-8000-000000000001','audit.view');
set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000002',true);
do $$ declare summary record; begin
 select * into summary from public.audit_security_summaries('92000000-0000-4000-8000-000000000001');
 if summary.event_count<>5 or summary.event_sha256 !~ '^[0-9a-f]{64}$' then raise exception 'Authorized summary unavailable'; end if;
 begin perform * from public.audit_security_summaries('92000000-0000-4000-8000-000000000002'); raise exception 'Cross-server summary accepted'; exception when insufficient_privilege then null; end;
end $$;
reset role;
-- Current version needs a new archive and acknowledgment, then can expire.
set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000001',true);
do $$ declare b jsonb; begin
 b:=public.prepare_archive('commands');
 if (b->>'record_count')::int<>1 then raise exception 'Changed version not rearchived'; end if;
 perform public.ack_archive((b->>'id')::uuid,b->>'sha256',1,repeat('c',64));
end $$;
reset role;
select private.housekeeping();
do $$ begin
 if exists(select 1 from public.commands where id='93000000-0000-4000-8000-000000000004') then raise exception 'Changed version not expired after new ack'; end if;
end $$;
rollback;
