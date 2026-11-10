create table public.online_players (
 server_id uuid primary key references public.servers(id), updated_at timestamptz not null default now(),
 players jsonb not null check(jsonb_typeof(players)='array' and jsonb_array_length(players)<=100 and octet_length(players::text)<=16384)
);
alter table public.online_players enable row level security;
revoke all on public.online_players from anon,authenticated;
grant select on public.online_players to authenticated;
create policy player_read on public.online_players for select to authenticated using(private.allowed(server_id,'players.view'));
-- Status and player visibility are independent permissions.
insert into public.online_players select server_id,heartbeat_at,players from public.snapshots;
alter table public.snapshots drop column players;
create or replace function private.publish_snapshot(server_state text,cpu numeric,memory bigint,uptime bigint,online_players jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare target uuid:=private.agent_server();
begin
 if target is null then raise exception 'Agent required' using errcode='42501'; end if;
 if exists(select 1 from public.snapshots where server_id=target and heartbeat_at>now()-interval '30 seconds') then return; end if;
 insert into public.snapshots values(target,now(),server_state,cpu,memory,uptime)
 on conflict(server_id) do update set heartbeat_at=excluded.heartbeat_at,state=excluded.state,cpu_percent=excluded.cpu_percent,
 memory_bytes=excluded.memory_bytes,uptime_seconds=excluded.uptime_seconds;
 insert into public.online_players values(target,now(),online_players)
 on conflict(server_id) do update set updated_at=excluded.updated_at,players=excluded.players;
end $$;
-- Explicit deny policy documents the intentional agent-table isolation.
create policy agent_registry_deny on private.agents for all to authenticated using(false) with check(false);
