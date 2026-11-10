-- Stage A requires separate local AND host-admin opt-ins before any command dispatch.
alter table private.agents add column control_enabled boolean not null default false;
create table public.agent_readiness(server_id uuid primary key references public.servers(id),updated_at timestamptz not null default now(),local_control boolean not null default false);
alter table public.agent_readiness enable row level security;
revoke all on public.agent_readiness from public,anon,authenticated;
-- No browser table access: expose only a permission-checked summary RPC.
create policy readiness_deny on public.agent_readiness for all to authenticated using(false) with check(false);
create function private.server_readiness(target uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('host_approved',coalesce(a.control_enabled,false),'mode',case when coalesce(a.control_enabled,false) and coalesce(r.local_control,false) then 'control' else 'observe' end,
 'control_ready',coalesce(a.control_enabled and r.local_control and r.updated_at>now()-interval '180 seconds' and snap.heartbeat_at>now()-interval '90 seconds' and snap.state<>'unknown' and s.lifecycle='active',false))
 from public.servers s left join private.agents a on a.server_id=s.id and a.enabled left join public.agent_readiness r on r.server_id=s.id left join public.snapshots snap on snap.server_id=s.id
 where s.id=target and private.allowed(target,'status.view')
$$;
create function public.server_readiness(target uuid) returns jsonb language sql stable security invoker set search_path='' as $$ select private.server_readiness(target) $$;
revoke all on function private.server_readiness(uuid),public.server_readiness(uuid) from public,anon;
grant execute on function private.server_readiness(uuid),public.server_readiness(uuid) to authenticated;

create table public.metric_samples(
 server_id uuid not null references public.servers(id),sampled_at timestamptz not null,
 cpu_percent numeric check(cpu_percent between 0 and 100),memory_bytes bigint check(memory_bytes>=0),
 primary key(server_id,sampled_at));
alter table public.metric_samples enable row level security;
revoke all on public.metric_samples from public,anon,authenticated;
grant select on public.metric_samples to authenticated;
create policy metrics_read on public.metric_samples for select to authenticated using(private.allowed(server_id,'status.view'));
create function private.sample_metrics() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.metric_samples(server_id,sampled_at,cpu_percent,memory_bytes)
 values(new.server_id,date_bin(interval '15 minutes',new.heartbeat_at,timestamptz '2000-01-01 UTC'),new.cpu_percent,new.memory_bytes)
 on conflict(server_id,sampled_at) do update set cpu_percent=excluded.cpu_percent,memory_bytes=excluded.memory_bytes;
 delete from public.metric_samples where server_id=new.server_id and sampled_at<now()-interval '24 hours';
 return new;
end $$;
revoke all on function private.sample_metrics() from public,anon,authenticated;
create trigger metric_sampling after insert or update on public.snapshots for each row execute function private.sample_metrics();

create or replace function private.claim_command() returns setof public.commands language plpgsql security definer set search_path='' as $$
declare target uuid:=private.lock_agent_server(); candidate public.commands;
begin
 if target is null then raise exception 'Agent required' using errcode='42501'; end if;
 if not exists(select 1 from private.agents where user_id=auth.uid() and server_id=target and enabled and control_enabled) then return;end if;
 if not exists(select 1 from public.servers where id=target and lifecycle='active') then return;end if;
 perform 1 from public.servers where id=target for update;
 update public.commands set state='expired',finished_at=now() where server_id=target and state='queued' and expires_at<=now();
 update public.commands set state='uncertain' where server_id=target and state='claimed' and claimed_at<now()-interval '2 minutes';
 if exists(select 1 from public.commands where server_id=target and state in ('claimed','uncertain')) then return; end if;
 for candidate in select * from public.commands where server_id=target and state='queued' and expires_at>now() order by created_at for update loop
  if not exists(select 1 from public.memberships m join public.role_permissions p on p.role_id=m.role_id
   where m.server_id=target and m.user_id=candidate.requested_by and m.state='approved'
   and p.permission=case when candidate.operation in ('start','stop','restart') then 'server.'||candidate.operation else 'players.'||candidate.operation end) then
   update public.commands set state='failed',result='Authorization revoked',finished_at=now() where id=candidate.id;
   continue;
  end if;
  return query update public.commands set state='claimed',claimed_at=now(),claimed_by=auth.uid(),claim_token=gen_random_uuid() where id=candidate.id returning *;
  return;
 end loop;
end $$;

create or replace function private.agent_call(target uuid,operation text,payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; previous text:=current_setting('morgan.agent_target',true);
begin
 if not exists(select 1 from private.agents where user_id=auth.uid() and server_id=target and enabled) then raise exception 'Agent server binding required' using errcode='42501';end if;
 if payload is null or jsonb_typeof(payload)<>'object' or octet_length(payload::text)>65536 then raise exception 'Invalid payload' using errcode='22023';end if;
 perform set_config('morgan.agent_target',target::text,true);
 -- All dispatched functions recheck the binding after taking the server lock.
 case operation
 when 'identity' then result:=to_jsonb(private.lock_agent_server());
 when 'claim_command' then select coalesce(jsonb_agg(to_jsonb(c)),'[]') into result from private.claim_command() c;
 when 'recover_commands' then
  perform private.lock_agent_server();
  select coalesce(jsonb_agg(to_jsonb(c)),'[]') into result from (select id,server_id,claim_token from public.commands where server_id=target and claimed_by=auth.uid() and state in ('claimed','uncertain') order by created_at limit 200) c;
 when 'finish_command' then perform private.finish_command((payload->>'command_id')::uuid,(payload->>'token')::uuid,payload->>'outcome',payload->>'summary');
 when 'publish_snapshot' then perform private.publish_snapshot(payload->>'server_state',(payload->>'cpu')::numeric,(payload->>'memory')::bigint,(payload->>'uptime')::bigint,payload->'online_players');
 when 'publish_agent_health' then perform public.publish_agent_health(payload->>'archive_state',(payload->>'archive_bytes')::bigint,(payload->>'quota_bytes')::bigint,(payload->>'disk_free_bytes')::bigint,(payload->>'last_archive_success')::timestamptz);
 insert into public.agent_readiness(server_id,updated_at,local_control) values(target,now(),coalesce((payload->>'controls_enabled')::boolean,false)) on conflict(server_id) do update set updated_at=excluded.updated_at,local_control=excluded.local_control;
 when 'publish_console' then perform private.publish_console(payload->'log_lines');
 when 'publish_backups' then perform private.publish_backups(payload->'archives');
 when 'prepare_archive' then result:=private.prepare_archive(payload->>'kind');
 when 'ack_archive' then perform private.ack_archive((payload->>'batch_id')::uuid,payload->>'plaintext_sha',(payload->>'record_count')::int,payload->>'ciphertext_sha');
 when 'begin_game_link' then result:=to_jsonb(private.begin_game_link((payload->>'player_uuid')::uuid,payload->>'player_name'));
 when 'verify_link' then result:=to_jsonb(private.verify_link(payload->>'code',(payload->>'player_uuid')::uuid,payload->>'player_name',(payload->>'confirmed')::boolean));
 when 'game_profile' then result:=to_jsonb(private.game_profile((payload->>'player_uuid')::uuid));
 when 'unlink_game_identity' then result:=to_jsonb(private.unlink_game_identity((payload->>'player_uuid')::uuid));
 when 'record_player_stats' then perform private.record_player_stats((payload->>'player_uuid')::uuid,payload->>'player_name',payload->'stats');
 else raise exception 'Unknown agent operation' using errcode='22023';end case;
 perform set_config('morgan.agent_target',coalesce(previous,''),true);
 return result;
end $$;
