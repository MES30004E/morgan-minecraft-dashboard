begin;
insert into auth.users(id,email) values
('11000000-0000-4000-8000-000000000001','stats-owner@example.invalid'),
('11000000-0000-4000-8000-000000000002','stats-viewer@example.invalid'),
('11000000-0000-4000-8000-000000000003','stats-agent@example.invalid');
insert into public.profiles(id,display_name) values('11000000-0000-4000-8000-000000000001','Steve');
insert into public.servers(id,name,gameplay_address) values('22000000-0000-4000-8000-000000000001','Statistics fixture','example.invalid');
insert into public.roles(id,server_id,name) values('33000000-0000-4000-8000-000000000001','22000000-0000-4000-8000-000000000001','Viewer');
insert into public.role_permissions values('33000000-0000-4000-8000-000000000001','players.view');
insert into public.memberships values('22000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000002','33000000-0000-4000-8000-000000000001','approved');
insert into public.mc_identities(minecraft_uuid,user_id,username) values('44000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000001','Steve');
insert into private.agents values('11000000-0000-4000-8000-000000000003','22000000-0000-4000-8000-000000000001',true);
set local role authenticated;
select set_config('request.jwt.claim.sub','11000000-0000-4000-8000-000000000003',true);
select public.record_player_stats('44000000-0000-4000-8000-000000000001','Steve','{"online":true,"play_time_ticks":1200,"deaths":0,"mob_kills":1,"blocks_mined":2,"advancements_done":1,"advancements_total":10}');
select set_config('request.jwt.claim.sub','11000000-0000-4000-8000-000000000002',true);
do $$ begin
 if (select count(*) from public.player_statistics)<>0 then raise exception 'Private statistics leaked';end if;
 begin perform public.record_player_stats('44000000-0000-4000-8000-000000000001','Steve','{}');raise exception 'Human forged stats';exception when insufficient_privilege then null;end;
end $$;
update public.profiles set statistics_public=true where id='11000000-0000-4000-8000-000000000001';
do $$ begin if (select count(*) from public.player_statistics)<>0 then raise exception 'Viewer changed another profile privacy';end if;end $$;
select set_config('request.jwt.claim.sub','11000000-0000-4000-8000-000000000001',true);
do $$ begin if (select play_time_ticks from public.player_statistics)<>1200 then raise exception 'Owner cannot see collected stats';end if;end $$;
update public.profiles set statistics_public=true where id=auth.uid();
select set_config('request.jwt.claim.sub','11000000-0000-4000-8000-000000000002',true);
do $$ begin
 if (select count(*) from public.player_statistics)<>1 then raise exception 'Opt-in statistics not visible to approved viewer';end if;
 if (select count(*) from public.mc_identities)<>0 then raise exception 'Sharing statistics leaked website identity association';end if;
end $$;
rollback;
