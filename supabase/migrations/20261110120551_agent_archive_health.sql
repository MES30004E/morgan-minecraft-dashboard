create table public.agent_health (
 server_id uuid primary key references public.servers(id), updated_at timestamptz not null default now(),
 archive_state text not null check(archive_state in ('disabled','running','ok','failed')),
 archive_bytes bigint check(archive_bytes>=0), quota_bytes bigint check(quota_bytes>0),
 disk_free_bytes bigint check(disk_free_bytes>=0), last_archive_success timestamptz
);
alter table public.agent_health enable row level security;
revoke all on public.agent_health from anon,authenticated;
grant select on public.agent_health to authenticated;
create policy archive_health_read on public.agent_health for select to authenticated using(private.allowed(server_id,'audit.view'));
create function private.publish_agent_health(archive_state text,archive_bytes bigint,quota_bytes bigint,disk_free_bytes bigint,last_archive_success timestamptz) returns void
language plpgsql security definer set search_path='' as $$
declare target uuid:=private.lock_agent_server();
begin
 insert into public.agent_health values(target,now(),archive_state,archive_bytes,quota_bytes,disk_free_bytes,last_archive_success)
 on conflict(server_id) do update set updated_at=excluded.updated_at,archive_state=excluded.archive_state,archive_bytes=excluded.archive_bytes,
 quota_bytes=excluded.quota_bytes,disk_free_bytes=excluded.disk_free_bytes,last_archive_success=excluded.last_archive_success;
end $$;
create function public.publish_agent_health(archive_state text,archive_bytes bigint,quota_bytes bigint,disk_free_bytes bigint,last_archive_success timestamptz) returns void
language sql security invoker set search_path='' as $$ select private.publish_agent_health(archive_state,archive_bytes,quota_bytes,disk_free_bytes,last_archive_success) $$;
revoke all on function private.publish_agent_health(text,bigint,bigint,bigint,timestamptz) from public,anon;
revoke all on function public.publish_agent_health(text,bigint,bigint,bigint,timestamptz) from public,anon;
grant execute on function private.publish_agent_health(text,bigint,bigint,bigint,timestamptz) to authenticated;
grant execute on function public.publish_agent_health(text,bigint,bigint,bigint,timestamptz) to authenticated;
