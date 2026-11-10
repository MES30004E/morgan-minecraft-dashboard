begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','ffffffff-ffff-4fff-8fff-ffffffffffff',true);
do $$ begin
 begin perform public.publish_agent_health('ok',0,1073741824,100000000,null);raise exception 'Human forged archive health';exception when insufficient_privilege then null;end;
 if (select count(*) from public.agent_health)<>0 then raise exception 'Archive health leaked';end if;
end $$;
rollback;
