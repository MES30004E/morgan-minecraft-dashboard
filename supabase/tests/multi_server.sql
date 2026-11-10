begin;
insert into auth.users(id,email) values('a1000000-0000-4000-8000-000000000001','multi-owner@example.invalid'),('a1000000-0000-4000-8000-000000000002','multi-other@example.invalid'),('a1000000-0000-4000-8000-000000000003','multi-agent@example.invalid');
insert into public.servers(id,name,gameplay_address) values('b1000000-0000-4000-8000-000000000001','Multi fixture','');
insert into public.roles(id,server_id,name) values('c1000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001','Owner');
insert into public.role_permissions select 'c1000000-0000-4000-8000-000000000001',name from public.permissions;
insert into public.memberships values('b1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','approved');
set local role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000002',true);
do $$ begin
 begin perform public.configure_server(null,'create','{"name":"Forbidden"}');raise exception 'Outsider created server';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000001',true);
select set_config('test.second_server',public.configure_server(null,'create','{"name":"Private Creative","version":"1.21.1"}')::text,true);
select public.configure_endpoint(current_setting('test.second_server')::uuid,null,'{"provider":"direct","hostname":"creative.example.invalid","public_port":25566}');
select public.configure_endpoint(current_setting('test.second_server')::uuid,null,'{"provider":"playit","hostname":"another.example.invalid"}');
do $$ begin
 if (select count(*) from public.server_endpoints where server_id=current_setting('test.second_server')::uuid)<>2 then raise exception 'Multiple endpoints unavailable';end if;
 if (select count(*) from public.memberships where user_id=auth.uid() and state='approved')<>2 then raise exception 'Owner not enrolled independently';end if;
end $$;
select public.configure_server(current_setting('test.second_server')::uuid,'edit','{"description":"Creative only","name":"Creative"}');
reset role;
insert into private.agents(user_id,server_id) values('a1000000-0000-4000-8000-000000000003','b1000000-0000-4000-8000-000000000001'),('a1000000-0000-4000-8000-000000000003',current_setting('test.second_server')::uuid);
set local role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000003',true);
do $$ begin
 if public.agent_identity() is not null then raise exception 'Multi-bound agent got implicit target';end if;
 begin perform public.agent_call('b1000000-0000-4000-8000-000000000099','claim_command','{}');raise exception 'Agent crossed binding';exception when insufficient_privilege then null;end;
 begin perform public.agent_call('b1000000-0000-4000-8000-000000000001','shell','{}');raise exception 'Arbitrary operation accepted';exception when invalid_parameter_value then null;end;
end $$;
select public.agent_call('b1000000-0000-4000-8000-000000000001','publish_snapshot','{"server_state":"online","cpu":1,"memory":1024,"uptime":null,"online_players":[]}');
select public.agent_call(current_setting('test.second_server')::uuid,'publish_snapshot','{"server_state":"offline","cpu":0,"memory":0,"uptime":null,"online_players":[]}');
select set_config('test.game_code',public.agent_call('b1000000-0000-4000-8000-000000000001','begin_game_link','{"player_uuid":"d1000000-0000-4000-8000-000000000001","player_name":"Alex"}')#>>'{}',true);
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000001',true);
select public.claim_server_link('b1000000-0000-4000-8000-000000000001',current_setting('test.game_code'));
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000003',true);
do $$ begin
 begin perform public.agent_call(current_setting('test.second_server')::uuid,'verify_link',jsonb_build_object('code',current_setting('test.game_code'),'player_uuid','d1000000-0000-4000-8000-000000000001','player_name','Alex','confirmed',true));raise exception 'Cross-server pairing accepted';exception when invalid_parameter_value then null;end;
end $$;
select public.agent_call('b1000000-0000-4000-8000-000000000001','verify_link',jsonb_build_object('code',current_setting('test.game_code'),'player_uuid','d1000000-0000-4000-8000-000000000001','player_name','Alex','confirmed',true));
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000001',true);
select set_config('test.second_code',public.begin_server_link(current_setting('test.second_server')::uuid,'Alex'),true);
select set_config('test.command_a',public.enqueue_command('b1000000-0000-4000-8000-000000000001','start','{}',gen_random_uuid())::text,true);
select set_config('test.command_b',public.enqueue_command(current_setting('test.second_server')::uuid,'start','{}',gen_random_uuid())::text,true);
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000003',true);
select public.agent_call(current_setting('test.second_server')::uuid,'verify_link',jsonb_build_object('code',current_setting('test.second_code'),'player_uuid','d1000000-0000-4000-8000-000000000001','player_name','Alex','confirmed',true));
select public.agent_call('b1000000-0000-4000-8000-000000000001','record_player_stats','{"player_uuid":"d1000000-0000-4000-8000-000000000001","player_name":"Alex","stats":{"online":true,"play_time_ticks":100}}');
select public.agent_call(current_setting('test.second_server')::uuid,'record_player_stats','{"player_uuid":"d1000000-0000-4000-8000-000000000001","player_name":"AlexNew","stats":{"online":true,"play_time_ticks":200}}');
select set_config('test.claim_a',public.agent_call('b1000000-0000-4000-8000-000000000001','claim_command','{}')::text,true);
select set_config('test.claim_b',public.agent_call(current_setting('test.second_server')::uuid,'claim_command','{}')::text,true);
do $$ declare a jsonb:=current_setting('test.claim_a')::jsonb; b jsonb:=current_setting('test.claim_b')::jsonb;begin
 if a->0->>'id'<>current_setting('test.command_a') or b->0->>'id'<>current_setting('test.command_b') then raise exception 'Command routed to wrong server';end if;
 begin perform public.agent_call(current_setting('test.second_server')::uuid,'finish_command',jsonb_build_object('command_id',a->0->>'id','token',a->0->>'claim_token','outcome','completed','summary','wrong target'));raise exception 'Cross-server completion accepted';exception when raise_exception then if sqlerrm<>'Invalid claim' then raise;end if;end;
 begin perform public.request_membership('b1000000-0000-4000-8000-000000000001');raise exception 'Multi-bound agent became a human member';exception when insufficient_privilege then null;end;
end $$;
select public.agent_call('b1000000-0000-4000-8000-000000000001','unlink_game_identity','{"player_uuid":"d1000000-0000-4000-8000-000000000001"}');
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000001',true);
do $$ begin
 if (select count(*) from public.identity_servers where minecraft_uuid='d1000000-0000-4000-8000-000000000001')<>1 or not exists(select 1 from public.identity_servers where server_id=current_setting('test.second_server')::uuid) then raise exception 'Unlink affected another server';end if;
 if (select play_time_ticks from public.player_statistics where server_id=current_setting('test.second_server')::uuid)<>200 then raise exception 'Statistics crossed server boundary';end if;
 if (select count(*) from public.identity_name_history where minecraft_uuid='d1000000-0000-4000-8000-000000000001')<>2 then raise exception 'Username history lost';end if;
end $$;
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000002',true);
do $$ begin
 if exists(select 1 from public.servers where id=current_setting('test.second_server')::uuid) or exists(select 1 from public.server_endpoints) or exists(select 1 from public.snapshots) then raise exception 'Private resource leaked to outsider';end if;
 begin perform public.enqueue_command(current_setting('test.second_server')::uuid,'start','{}',gen_random_uuid());raise exception 'Outsider controlled server';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000001',true);
select public.configure_server(current_setting('test.second_server')::uuid,'archive','{}');
do $$ begin
 begin perform public.enqueue_command(current_setting('test.second_server')::uuid,'start','{}',gen_random_uuid());raise exception 'Archived server accepted control';exception when insufficient_privilege then null;end;
end $$;
select public.configure_server(current_setting('test.second_server')::uuid,'remove','{}');
select public.configure_server(current_setting('test.second_server')::uuid,'restore','{}');
do $$ begin if not exists(select 1 from public.snapshots where server_id=current_setting('test.second_server')::uuid) then raise exception 'Remove lost operational history';end if;end $$;

-- One website account deliberately has different roles on the two servers.
reset role;
insert into public.roles(id,server_id,name) values('c1000000-0000-4000-8000-000000000002','b1000000-0000-4000-8000-000000000001','Member');
insert into public.role_permissions values('c1000000-0000-4000-8000-000000000002','status.view');
insert into public.memberships values('b1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000002','c1000000-0000-4000-8000-000000000002','approved');
insert into public.memberships select current_setting('test.second_server')::uuid,'a1000000-0000-4000-8000-000000000002',id,'approved' from public.roles where server_id=current_setting('test.second_server')::uuid and name='Admin';
set local role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000002',true);
do $$ begin
 if (select count(*) from public.servers)<>2 then raise exception 'Independent permitted server list failed';end if;
 begin perform public.enqueue_command('b1000000-0000-4000-8000-000000000001','start','{}',gen_random_uuid());raise exception 'Member inherited other server Admin rights';exception when insufficient_privilege then null;end;
 perform public.enqueue_command(current_setting('test.second_server')::uuid,'start','{}',gen_random_uuid());
 if (select count(*) from public.commands where requested_by=auth.uid())<>1 then raise exception 'Server-specific Admin control denied';end if;
end $$;

rollback;
