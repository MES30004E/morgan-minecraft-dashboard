begin;
insert into auth.users(id,email) values
('a0000000-0000-4000-8000-000000000001','first@example.invalid'),
('a0000000-0000-4000-8000-000000000002','second@example.invalid'),
('a0000000-0000-4000-8000-000000000003','bridge@example.invalid');
insert into public.servers(id,name,gameplay_address) values('b0000000-0000-4000-8000-000000000001','Pairing fixture','example.invalid');
insert into private.agents values('a0000000-0000-4000-8000-000000000003','b0000000-0000-4000-8000-000000000001',true);
set local role authenticated;
do $$ declare code text; message text; i integer; begin
 perform set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000001',true);
 code:=public.begin_web_link('Steve');
 if length(code)<>32 then raise exception 'Insufficient challenge entropy'; end if;
 begin perform public.begin_game_link(gen_random_uuid(),'Steve');raise exception 'Human impersonated agent';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000003',true);
 begin perform public.verify_link(code,'c0000000-0000-4000-8000-000000000001','Alex',true);raise exception 'Wrong username linked';exception when raise_exception then if sqlerrm<>'Invalid or expired pairing code' then raise;end if;end;
 message:=public.verify_link(code,'c0000000-0000-4000-8000-000000000001','Steve',false);
 if message not like '%a0000000%' then raise exception 'Preview omitted website account';end if;
 perform set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000001',true);
 if (select count(*) from public.mc_identities)<>0 then raise exception 'Preview linked without confirmation';end if;
 perform set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000003',true);
 perform public.verify_link(code,'c0000000-0000-4000-8000-000000000001','Steve',true);
 begin perform public.verify_link(code,'c0000000-0000-4000-8000-000000000001','Steve',true);raise exception 'Replay accepted';exception when raise_exception then if sqlerrm<>'Invalid or expired pairing code' then raise;end if;end;
 code:=public.begin_game_link('c0000000-0000-4000-8000-000000000002','Alex');
 perform set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000002',true);
 perform public.claim_game_link(code);
 if (select count(*) from public.mc_identities)<>0 then raise exception 'Website claim bypassed game confirmation or leaked other user';end if;
 perform set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000001',true);
 begin perform public.claim_game_link(code);raise exception 'Website stole claimed code';exception when raise_exception then if sqlerrm<>'Invalid or expired pairing code' then raise;end if;end;
 perform set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000003',true);
 perform public.verify_link(code,'c0000000-0000-4000-8000-000000000002','Alex',true);
 perform set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000002',true);
 if (select count(*) from public.mc_identities)<>1 then raise exception 'Owner visibility failed';end if;
 if not exists(select 1 from public.memberships where user_id=auth.uid() and state='pending') then raise exception 'Pairing granted privilege or omitted pending membership';end if;
 perform set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000001',true);
 for i in 1..4 loop perform public.begin_web_link('Steve');end loop;
 begin perform public.begin_web_link('Steve');exception when raise_exception then if sqlerrm<>'Pairing rate limit' then raise;end if;return;end;
 raise exception 'Challenge rate limit bypassed';
end $$;
rollback;
