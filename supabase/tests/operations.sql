begin;
insert into auth.users(id,email) values
('50000000-0000-4000-8000-000000000001','operator@example.invalid'),
('50000000-0000-4000-8000-000000000002','agent@example.invalid'),
('50000000-0000-4000-8000-000000000003','viewer@example.invalid');
insert into public.servers(id,name,gameplay_address) values('60000000-0000-4000-8000-000000000001','Operation fixture','example.invalid');
insert into public.roles(id,server_id,name) values
('70000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000001','Operator'),
('70000000-0000-4000-8000-000000000002','60000000-0000-4000-8000-000000000001','Status only');
insert into public.role_permissions select '70000000-0000-4000-8000-000000000001',name from public.permissions;
insert into public.role_permissions values('70000000-0000-4000-8000-000000000002','status.view');
insert into public.memberships values
('60000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001','70000000-0000-4000-8000-000000000001','approved'),
('60000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000003','70000000-0000-4000-8000-000000000002','approved');
insert into private.agents values('50000000-0000-4000-8000-000000000002','60000000-0000-4000-8000-000000000001',true);
set local role authenticated;
select set_config('request.jwt.claim.sub','50000000-0000-4000-8000-000000000001',true);
select public.enqueue_command('60000000-0000-4000-8000-000000000001','start','{}','80000000-0000-4000-8000-000000000001');
do $$ begin
 begin perform * from public.claim_command(); raise exception 'Human claimed command'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','50000000-0000-4000-8000-000000000002',true);
do $$ declare command public.commands; begin
 select * into command from public.claim_command();
 if command.operation<>'start' then raise exception 'Agent could not claim authorized command'; end if;
 if (select count(*) from public.claim_command())<>0 then raise exception 'Command claimed twice'; end if;
 begin perform public.finish_command(command.id,gen_random_uuid(),'completed',''); raise exception 'Invalid claim token accepted'; exception when raise_exception then if sqlerrm<>'Invalid claim' then raise; end if; end;
 perform public.finish_command(command.id,command.claim_token,'completed','Accepted by Crafty');
 perform public.publish_snapshot('online',1,1024,60,'[{"uuid":"90000000-0000-4000-8000-000000000001","name":"Steve"}]');
end $$;
select set_config('request.jwt.claim.sub','50000000-0000-4000-8000-000000000003',true);
do $$ begin
 if (select count(*) from public.snapshots)<>1 then raise exception 'Viewer cannot see status'; end if;
 if (select count(*) from public.online_players)<>0 then raise exception 'Status-only viewer sees players'; end if;
 if (select count(*) from public.console_tail)<>0 then raise exception 'Status viewer sees console'; end if;
 begin perform public.publish_snapshot('online',1,1,1,'[]'); raise exception 'Human published telemetry'; exception when insufficient_privilege then null; end;
end $$;
rollback;
