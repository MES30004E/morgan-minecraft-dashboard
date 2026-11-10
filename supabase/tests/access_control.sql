-- Synthetic fixtures are rolled back; run against an isolated test database.
begin;
insert into auth.users(id,email) values
 ('10000000-0000-4000-8000-000000000001','owner@example.invalid'),
 ('10000000-0000-4000-8000-000000000002','member@example.invalid');
insert into public.servers(id,name,gameplay_address) values
 ('20000000-0000-4000-8000-000000000001','Test','example.invalid');
insert into public.roles(id,server_id,name) values
 ('30000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','Owner'),
 ('30000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000001','Member');
insert into public.role_permissions select '30000000-0000-4000-8000-000000000001',name from public.permissions;
insert into public.role_permissions values('30000000-0000-4000-8000-000000000002','status.view');
insert into public.memberships values
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','approved'),
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','30000000-0000-4000-8000-000000000002','approved');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
do $$ begin
 if (select count(*) from public.servers)<>1 then raise exception 'Member cannot read permitted status'; end if;
 if (select count(*) from public.memberships)<>1 then raise exception 'Cross-user membership leak'; end if;
 begin
 perform public.enqueue_command('20000000-0000-4000-8000-000000000001','start','{}','40000000-0000-4000-8000-000000000001');
 raise exception 'Member gained control';
 exception when insufficient_privilege then null; end;
 begin
 update public.memberships set state='approved',role_id='30000000-0000-4000-8000-000000000001';
 raise exception 'Member can escalate role';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
do $$ declare first_id uuid; second_id uuid; i integer; begin
 first_id:=public.enqueue_command('20000000-0000-4000-8000-000000000001','start','{}','40000000-0000-4000-8000-000000000001');
 second_id:=public.enqueue_command('20000000-0000-4000-8000-000000000001','start','{}','40000000-0000-4000-8000-000000000001');
 if first_id<>second_id or (select count(*) from public.commands)<>1 then raise exception 'Deduplication failed'; end if;
 begin
 perform public.enqueue_command('20000000-0000-4000-8000-000000000001','shell','{}',gen_random_uuid());
 raise exception 'Shell allowed'; exception when insufficient_privilege then null; end;
 for i in 1..4 loop
 perform public.enqueue_command('20000000-0000-4000-8000-000000000001','start','{}',gen_random_uuid()); end loop;
 begin
 perform public.enqueue_command('20000000-0000-4000-8000-000000000001','start','{}',gen_random_uuid());
 exception when raise_exception then
 if sqlerrm<>'Rate limit exceeded' then raise; end if;
 return;
 end;
 raise exception 'Rate limit bypassed';
end $$;
reset role;
update public.memberships set state='suspended' where user_id='10000000-0000-4000-8000-000000000001';
set local role authenticated;
do $$ begin
 if (select count(*) from public.servers)<>0 then raise exception 'Revoked user still sees status'; end if;
 begin
 perform public.enqueue_command('20000000-0000-4000-8000-000000000001','start','{}',gen_random_uuid());
 raise exception 'Revoked user controls server'; exception when insufficient_privilege then null; end;
end $$;
set local role anon;
do $$ begin
 begin
 perform * from public.servers;
 raise exception 'Anonymous data access'; exception when insufficient_privilege then null; end;
end $$;
rollback;
