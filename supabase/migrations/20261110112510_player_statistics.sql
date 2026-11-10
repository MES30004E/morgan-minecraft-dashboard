create table public.player_statistics (
 server_id uuid not null references public.servers(id), minecraft_uuid uuid not null,
 username text not null check(username ~ '^[A-Za-z0-9_]{3,16}$'), first_recorded_at timestamptz not null default now(),
 last_seen_at timestamptz not null default now(), online boolean not null,
 play_time_ticks bigint check(play_time_ticks>=0), deaths bigint check(deaths>=0), mob_kills bigint check(mob_kills>=0),
 blocks_mined bigint check(blocks_mined>=0), advancements_done integer check(advancements_done>=0),
 advancements_total integer check(advancements_total>=advancements_done), primary key(server_id,minecraft_uuid)
);
alter table public.player_statistics enable row level security;
revoke all on public.player_statistics from anon,authenticated;
grant select on public.player_statistics to authenticated;
create function private.may_view_stats(target uuid,player uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.mc_identities i left join public.profiles p on p.id=i.user_id where i.minecraft_uuid=player
 and (i.user_id=auth.uid() or (coalesce(p.statistics_public,false) and private.allowed(target,'players.view'))))
$$;
revoke all on function private.may_view_stats(uuid,uuid) from public,anon;
grant execute on function private.may_view_stats(uuid,uuid) to authenticated;
create policy statistics_read on public.player_statistics for select to authenticated using(private.may_view_stats(server_id,minecraft_uuid));
create function private.record_player_stats(player_uuid uuid,player_name text,stats jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare target uuid:=private.agent_server();
begin
 if target is null then raise exception 'Agent required' using errcode='42501'; end if;
 if jsonb_typeof(stats)<>'object' or stats is null or stats-array['online','play_time_ticks','deaths','mob_kills','blocks_mined','advancements_done','advancements_total']<>'{}'::jsonb then raise exception 'Invalid statistics'; end if;
 insert into public.player_statistics(server_id,minecraft_uuid,username,online,play_time_ticks,deaths,mob_kills,blocks_mined,advancements_done,advancements_total)
 values(target,player_uuid,player_name,(stats->>'online')::boolean,(stats->>'play_time_ticks')::bigint,(stats->>'deaths')::bigint,(stats->>'mob_kills')::bigint,(stats->>'blocks_mined')::bigint,(stats->>'advancements_done')::integer,(stats->>'advancements_total')::integer)
 on conflict(server_id,minecraft_uuid) do update set username=excluded.username,last_seen_at=now(),online=excluded.online,
 play_time_ticks=excluded.play_time_ticks,deaths=excluded.deaths,mob_kills=excluded.mob_kills,blocks_mined=excluded.blocks_mined,
 advancements_done=excluded.advancements_done,advancements_total=excluded.advancements_total;
end $$;
create function public.record_player_stats(player_uuid uuid,player_name text,stats jsonb) returns void
language sql security invoker set search_path='' as $$ select private.record_player_stats(player_uuid,player_name,stats) $$;
create function private.publish_backups(archives jsonb) returns void language plpgsql security definer set search_path='' as $$
declare target uuid:=private.agent_server(); entry jsonb;
begin
 if target is null then raise exception 'Agent required' using errcode='42501'; end if;
 if jsonb_typeof(archives)<>'array' or archives is null or jsonb_array_length(archives)>120 or octet_length(archives::text)>32768 then raise exception 'Invalid backup metadata'; end if;
 for entry in select * from jsonb_array_elements(archives) loop
 insert into public.backups(server_id,backup_id,created_at,state,size_bytes) values(target,entry->>'backup_id',(entry->>'created_at')::timestamptz,'completed',(entry->>'size_bytes')::bigint)
 on conflict(server_id,backup_id) do update set size_bytes=excluded.size_bytes;
 end loop;
end $$;
create function public.publish_backups(archives jsonb) returns void language sql security invoker set search_path='' as $$ select private.publish_backups(archives) $$;
do $$ declare f record; begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('private','public') and p.proname in ('record_player_stats','publish_backups') loop
 execute format('revoke all on function %s from public,anon',f.signature);
 execute format('grant execute on function %s to authenticated',f.signature);
 end loop;
end $$;
