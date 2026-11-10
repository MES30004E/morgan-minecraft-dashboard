begin;
insert into auth.users(id,email) values('e1000000-0000-4000-8000-000000000001','observe-owner@example.invalid'),('e1000000-0000-4000-8000-000000000002','observe-agent@example.invalid'),('e1000000-0000-4000-8000-000000000003','observe-stranger@example.invalid');
insert into public.servers(id,name) values('e2000000-0000-4000-8000-000000000001','Observe fixture');
insert into public.roles(id,server_id,name) values('e3000000-0000-4000-8000-000000000001','e2000000-0000-4000-8000-000000000001','Owner');
insert into public.role_permissions select 'e3000000-0000-4000-8000-000000000001',name from public.permissions;
insert into public.memberships values('e2000000-0000-4000-8000-000000000001','e1000000-0000-4000-8000-000000000001','e3000000-0000-4000-8000-000000000001','approved');
insert into private.agents(user_id,server_id) values('e1000000-0000-4000-8000-000000000002','e2000000-0000-4000-8000-000000000001');
set local role authenticated;
select set_config('request.jwt.claim.sub','e1000000-0000-4000-8000-000000000001',true);
select public.enqueue_command('e2000000-0000-4000-8000-000000000001','start','{}',gen_random_uuid());
select set_config('request.jwt.claim.sub','e1000000-0000-4000-8000-000000000002',true);
do $$ begin
 if (select count(*) from public.claim_command())<>0 then raise exception 'Default observer claimed a command through legacy RPC';end if;
 if public.agent_call('e2000000-0000-4000-8000-000000000001','claim_command','{}')<>'[]'::jsonb then raise exception 'Observer claimed through scoped RPC';end if;
 begin update private.agents set control_enabled=true;raise exception 'Agent enabled its own control';exception when insufficient_privilege then null;end;
end $$;
select public.agent_call('e2000000-0000-4000-8000-000000000001','publish_snapshot','{"server_state":"online","cpu":12,"memory":2048,"uptime":null,"online_players":[]}');
select public.agent_call('e2000000-0000-4000-8000-000000000001','publish_agent_health','{"archive_state":"disabled","archive_bytes":null,"quota_bytes":null,"disk_free_bytes":null,"last_archive_success":null,"controls_enabled":true}');
select public.agent_metrics('[{"server_id":"e2000000-0000-4000-8000-000000000001","snapshot":{"server_state":"online","cpu":12,"memory":2048,"uptime":null,"online_players":[],"player_count":5}}]');
select set_config('request.jwt.claim.sub','e1000000-0000-4000-8000-000000000001',true);
do $$ begin
 if (select player_count from public.online_players where server_id='e2000000-0000-4000-8000-000000000001') is distinct from 5 then raise exception 'Player count was inferred from names';end if;
 if (public.server_readiness('e2000000-0000-4000-8000-000000000001')->>'control_ready')::boolean then raise exception 'Observer readiness trusted local control assertion';end if;
 if (select count(*) from public.metric_samples)<>1 then raise exception 'Real telemetry sample missing';end if;
 begin insert into public.metric_samples(server_id,sampled_at,cpu_percent) values('e2000000-0000-4000-8000-000000000001',now(),99);raise exception 'Human forged metrics';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','e1000000-0000-4000-8000-000000000003',true);
do $$ begin
 if (select count(*) from public.metric_samples)<>0 then raise exception 'Other-server telemetry leaked';end if;
 if public.server_readiness('e2000000-0000-4000-8000-000000000001') is not null then raise exception 'Readiness leaked';end if;
end $$;
reset role;
update private.agents set control_enabled=true where user_id='e1000000-0000-4000-8000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub','e1000000-0000-4000-8000-000000000002',true);
do $$ begin if jsonb_array_length(public.agent_call('e2000000-0000-4000-8000-000000000001','claim_command','{}'))<>1 then raise exception 'Explicit host-approved control failed';end if;end $$;
rollback;
