create table private.agents (
 user_id uuid primary key references auth.users(id), server_id uuid not null unique references public.servers(id),
 enabled boolean not null default true
);
alter table private.agents enable row level security;
revoke all on private.agents from public,anon,authenticated;
create function private.agent_server() returns uuid language sql stable security definer set search_path='' as $$
 select server_id from private.agents where user_id=auth.uid() and enabled
$$;
revoke all on function private.agent_server() from public,anon;
grant execute on function private.agent_server() to authenticated;

create table public.snapshots (
 server_id uuid primary key references public.servers(id), heartbeat_at timestamptz not null default now(),
 state text not null check(state in ('online','offline','starting','stopping','unknown')),
 cpu_percent numeric check(cpu_percent between 0 and 100), memory_bytes bigint check(memory_bytes>=0),
 uptime_seconds bigint check(uptime_seconds>=0), players jsonb not null default '[]'
 check(jsonb_typeof(players)='array' and jsonb_array_length(players)<=100 and octet_length(players::text)<=16384)
);
create table public.console_tail (
 server_id uuid primary key references public.servers(id), updated_at timestamptz not null default now(),
 lines jsonb not null default '[]' check(jsonb_typeof(lines)='array' and jsonb_array_length(lines)<=100 and octet_length(lines::text)<=32768)
);
create table public.backups (
 server_id uuid not null references public.servers(id), backup_id text not null check(length(backup_id)<=128),
 created_at timestamptz not null, state text not null check(state in ('completed','failed','running')),
 size_bytes bigint check(size_bytes>=0), primary key(server_id,backup_id)
);
alter table public.snapshots enable row level security;
alter table public.console_tail enable row level security;
alter table public.backups enable row level security;
revoke all on public.snapshots,public.console_tail,public.backups from anon,authenticated;
grant select on public.snapshots,public.console_tail,public.backups to authenticated;
create policy snapshot_read on public.snapshots for select to authenticated using(private.allowed(server_id,'status.view'));
create policy console_read on public.console_tail for select to authenticated using(private.allowed(server_id,'console.view'));
create policy backup_read on public.backups for select to authenticated using(private.allowed(server_id,'backups.view'));
create policy agent_command_read on public.commands for select to authenticated using(server_id=private.agent_server());
alter table public.commands add column claimed_by uuid references auth.users(id), add column claim_token uuid,
 add column claimed_at timestamptz, add column finished_at timestamptz, add column result text check(length(result)<=1000);

create function private.request_membership(target uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or private.agent_server() is not null then raise exception 'Forbidden' using errcode='42501'; end if;
 insert into public.memberships(server_id,user_id) values(target,auth.uid()) on conflict do nothing;
end $$;
create function public.request_membership(target uuid) returns void language sql security invoker set search_path='' as $$ select private.request_membership(target) $$;

create function private.manage_member(target uuid, person uuid, new_state text, new_role uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not private.allowed(target,'access.manage') then raise exception 'Forbidden' using errcode='42501'; end if;
 if new_state not in ('approved','rejected','suspended','pending') then raise exception 'Invalid membership state'; end if;
 perform 1 from public.servers where id=target for update;
 if person=auth.uid() then raise exception 'Self-modification requires another owner'; end if;
 if not exists(select 1 from public.roles where server_id=target and id=new_role) then raise exception 'Role belongs to another server'; end if;
 update public.memberships set state=new_state,role_id=new_role where server_id=target and user_id=person;
 if not found then raise exception 'Membership not found'; end if;
 insert into public.audit_events(server_id,actor,action,details) values(target,auth.uid(),'membership.changed',jsonb_build_object('user_id',person,'state',new_state,'role_id',new_role));
end $$;
create function public.manage_member(target uuid,person uuid,new_state text,new_role uuid) returns void
language sql security invoker set search_path='' as $$ select private.manage_member(target,person,new_state,new_role) $$;

create function private.set_role_permission(target uuid, target_role uuid, capability text, enabled boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not private.allowed(target,'access.manage') then raise exception 'Forbidden' using errcode='42501'; end if;
 perform 1 from public.servers where id=target for update;
 if not exists(select 1 from public.roles where id=target_role and server_id=target) then raise exception 'Invalid role'; end if;
 if exists(select 1 from public.memberships where server_id=target and user_id=auth.uid() and role_id=target_role) then raise exception 'Cannot modify your own role'; end if;
 if enabled then insert into public.role_permissions values(target_role,capability) on conflict do nothing;
 else delete from public.role_permissions where role_id=target_role and permission=capability; end if;
 insert into public.audit_events(server_id,actor,action,details) values(target,auth.uid(),'role.permission_changed',jsonb_build_object('role_id',target_role,'permission',capability,'enabled',enabled));
end $$;
create function public.set_role_permission(target uuid,target_role uuid,capability text,enabled boolean) returns void
language sql security invoker set search_path='' as $$ select private.set_role_permission(target,target_role,capability,enabled) $$;

create function private.claim_command() returns setof public.commands language plpgsql security definer set search_path='' as $$
declare target uuid:=private.agent_server(); candidate public.commands;
begin
 if target is null then raise exception 'Agent required' using errcode='42501'; end if;
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
create function public.claim_command() returns setof public.commands language sql security invoker set search_path='' as $$ select * from private.claim_command() $$;

create function private.finish_command(command_id uuid,token uuid,outcome text,summary text) returns void
language plpgsql security definer set search_path='' as $$
declare target uuid:=private.agent_server();
begin
 if target is null or outcome not in ('completed','failed','uncertain') or outcome is null then raise exception 'Forbidden' using errcode='42501'; end if;
 update public.commands set state=outcome,result=left(summary,1000),finished_at=now()
 where id=command_id and server_id=target and claimed_by=auth.uid() and claim_token=token and state in ('claimed','uncertain');
 if not found then raise exception 'Invalid claim'; end if;
 insert into public.audit_events(server_id,actor,action,details) values(target,auth.uid(),'command.'||outcome,jsonb_build_object('command_id',command_id));
end $$;
create function public.finish_command(command_id uuid,token uuid,outcome text,summary text) returns void
language sql security invoker set search_path='' as $$ select private.finish_command(command_id,token,outcome,summary) $$;

create function private.publish_snapshot(server_state text,cpu numeric,memory bigint,uptime bigint,online_players jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare target uuid:=private.agent_server();
begin
 if target is null then raise exception 'Agent required' using errcode='42501'; end if;
 if exists(select 1 from public.snapshots where server_id=target and heartbeat_at>now()-interval '30 seconds') then return; end if;
 insert into public.snapshots values(target,now(),server_state,cpu,memory,uptime,online_players)
 on conflict(server_id) do update set heartbeat_at=excluded.heartbeat_at,state=excluded.state,cpu_percent=excluded.cpu_percent,
 memory_bytes=excluded.memory_bytes,uptime_seconds=excluded.uptime_seconds,players=excluded.players;
end $$;
create function public.publish_snapshot(server_state text,cpu numeric,memory bigint,uptime bigint,online_players jsonb) returns void
language sql security invoker set search_path='' as $$ select private.publish_snapshot(server_state,cpu,memory,uptime,online_players) $$;

-- Explicit privileges on every RPC; no default PUBLIC EXECUTE.
do $$ declare f record; begin
 for f in select n.nspname, p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in ('public','private') and p.proname in ('request_membership','manage_member','set_role_permission','claim_command','finish_command','publish_snapshot') loop
 execute format('revoke all on function %s from public,anon',f.signature);
 execute format('grant execute on function %s to authenticated',f.signature);
 end loop;
end $$;

-- Single server metadata and role templates contain no credentials or live telemetry.
do $$ declare target uuid; r uuid; role_name text; begin
 insert into public.servers(name,gameplay_address) values('Morgan Minecraft','impairment-entering.tun.ply.gg') returning id into target;
 foreach role_name in array array['Owner','Admin','Moderator','Member','Pending'] loop
  insert into public.roles(server_id,name) values(target,role_name) returning id into r;
  if role_name='Owner' then insert into public.role_permissions select r,name from public.permissions;
  elsif role_name='Admin' then insert into public.role_permissions select r,name from public.permissions where name<>'access.manage';
  elsif role_name='Moderator' then insert into public.role_permissions select r,name from public.permissions where name in ('status.view','players.view','players.kick','players.ban','players.pardon');
  elsif role_name='Member' then insert into public.role_permissions select r,name from public.permissions where name in ('status.view','players.view');
  end if;
 end loop;
end $$;
-- Publication changes are conditional so migrations also run in standalone PostgreSQL CI.
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then
 alter publication supabase_realtime add table public.snapshots,public.commands;
 end if;
end $$;
