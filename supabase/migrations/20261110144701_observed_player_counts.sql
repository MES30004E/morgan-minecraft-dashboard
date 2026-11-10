-- Counts and sampled player names are independent Crafty statistics.
alter table public.online_players add column player_count integer check(player_count between 0 and 1000);
create or replace function private.publish_snapshot(server_state text,cpu numeric,memory bigint,uptime bigint,online_players jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare target uuid:=private.lock_agent_server();
begin
 if target is null then raise exception 'Agent required' using errcode='42501'; end if;
 if exists(select 1 from public.snapshots where server_id=target and heartbeat_at>now()-interval '30 seconds') then return; end if;
 insert into public.snapshots values(target,now(),server_state,cpu,memory,uptime)
 on conflict(server_id) do update set heartbeat_at=excluded.heartbeat_at,state=excluded.state,cpu_percent=excluded.cpu_percent,
 memory_bytes=excluded.memory_bytes,uptime_seconds=excluded.uptime_seconds;
 insert into public.online_players(server_id,updated_at,players,player_count) values(target,now(),online_players,null)
 on conflict(server_id) do update set updated_at=excluded.updated_at,players=excluded.players,player_count=null;
end $$;
create or replace function private.agent_metrics(samples jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare sample jsonb; results jsonb:='[]'; target uuid;
begin
 if jsonb_typeof(samples)<>'array' or jsonb_array_length(samples)>10 or octet_length(samples::text)>32768 then raise exception 'Invalid metrics batch' using errcode='22023';end if;
 for sample in select value from jsonb_array_elements(samples) order by value->>'server_id' loop
  begin
   target:=(sample->>'server_id')::uuid;
   perform private.agent_call(target,'publish_snapshot',sample->'snapshot');
   if sample->'snapshot'->'player_count' is not null and sample->'snapshot'->'player_count'<>'null'::jsonb then
    if jsonb_typeof(sample->'snapshot'->'player_count')<>'number' or (sample->'snapshot'->>'player_count') !~ '^[0-9]{1,4}$' then raise exception 'Invalid player count' using errcode='22023';end if;
    update public.online_players set player_count=(sample->'snapshot'->>'player_count')::int where server_id=target and updated_at=now();
   end if;
   results:=results||jsonb_build_array(jsonb_build_object('server_id',target,'accepted',true));
  exception when others then
   results:=results||jsonb_build_array(jsonb_build_object('server_id',sample->>'server_id','accepted',false));
  end;
 end loop;
 return results;
end $$;
