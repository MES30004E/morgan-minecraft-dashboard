begin;
insert into auth.users(id,email) values('d0000000-0000-4000-8000-000000000001','requester@example.invalid'),('d0000000-0000-4000-8000-000000000002','archiver@example.invalid');
insert into public.servers(id,name,gameplay_address) values('e0000000-0000-4000-8000-000000000001','Replay fixture','example.invalid');
insert into public.roles(id,server_id,name) values('f0000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000001','Operator');
insert into public.role_permissions values('f0000000-0000-4000-8000-000000000001','server.start');
insert into public.memberships values('e0000000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000001','f0000000-0000-4000-8000-000000000001','approved');
insert into private.agents values('d0000000-0000-4000-8000-000000000002','e0000000-0000-4000-8000-000000000001',true);
set local role authenticated;
select set_config('request.jwt.claim.sub','d0000000-0000-4000-8000-000000000001',true);
select public.enqueue_command('e0000000-0000-4000-8000-000000000001','start','{}','f0000000-0000-4000-8000-000000000002');
reset role;
update public.commands set state='completed',created_at=now()-interval '8 days',expires_at=now()-interval '7 days',finished_at=now()-interval '8 days'
 where server_id='e0000000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','d0000000-0000-4000-8000-000000000002',true);
do $$ declare batch jsonb; begin
 batch:=public.prepare_archive('commands');
 perform public.ack_archive((batch->>'id')::uuid,batch->>'sha256',(batch->>'record_count')::integer,repeat('a',64));
end $$;
reset role;
select private.housekeeping();
do $$ begin
 if exists(select 1 from public.commands where server_id='e0000000-0000-4000-8000-000000000001') then raise exception 'Verified terminal command not swept';end if;
 if to_regclass('private.used_command_requests') is not null then
  if not exists(select 1 from private.used_command_requests where server_id='e0000000-0000-4000-8000-000000000001') then raise exception 'Replay tombstone lost';end if;
 end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','d0000000-0000-4000-8000-000000000001',true);
do $$ begin
 begin
 perform public.enqueue_command('e0000000-0000-4000-8000-000000000001','start','{}','f0000000-0000-4000-8000-000000000002');
 exception when raise_exception then if sqlerrm<>'Request already archived; replay refused' then raise;end if;return;
 end;
 raise exception 'Old operation replayed after cloud retention';
end $$;
rollback;
