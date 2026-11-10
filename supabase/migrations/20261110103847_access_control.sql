-- Authorization data is independent of user-editable Auth metadata.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create table public.servers (
 id uuid primary key default gen_random_uuid(), name text not null,
 gameplay_address text not null, created_at timestamptz not null default now()
);
create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null check(length(display_name) between 1 and 64),
 statistics_public boolean not null default false,
 created_at timestamptz not null default now()
);
create table public.roles (
 id uuid primary key default gen_random_uuid(), server_id uuid not null references public.servers(id),
 name text not null check(length(name) between 1 and 40), unique(server_id,name), unique(server_id,id)
);
create table public.permissions (name text primary key);
insert into public.permissions values ('status.view'),('players.view'),('server.start'),('server.stop'),('server.restart'),('players.kick'),('players.ban'),('players.pardon'),('players.whitelist_add'),('players.whitelist_remove'),('console.view'),('backups.view'),('audit.view'),('access.manage');
create table public.role_permissions (
 role_id uuid not null references public.roles(id), permission text not null references public.permissions(name),
 primary key(role_id,permission)
);
create table public.memberships (
 server_id uuid not null references public.servers(id), user_id uuid not null references auth.users(id),
 role_id uuid, state text not null default 'pending' check(state in ('pending','approved','rejected','suspended')),
 primary key(server_id,user_id), foreign key(server_id,role_id) references public.roles(server_id,id)
);
create index memberships_user on public.memberships(user_id);
create table public.audit_events (
 id bigint generated always as identity primary key, server_id uuid not null references public.servers(id),
 actor uuid references auth.users(id), action text not null, details jsonb not null default '{}',
 created_at timestamptz not null default now()
);
create index audit_server_time on public.audit_events(server_id,created_at desc);
create table public.commands (
 id uuid primary key default gen_random_uuid(), server_id uuid not null references public.servers(id),
 requested_by uuid not null references auth.users(id), operation text not null,
 arguments jsonb not null default '{}', idempotency_key uuid not null,
 state text not null default 'queued' check(state in ('queued','claimed','completed','failed','expired','uncertain')),
 created_at timestamptz not null default now(), expires_at timestamptz not null,
 unique(server_id,requested_by,idempotency_key), check(expires_at>created_at)
);
create index commands_server_time on public.commands(server_id,created_at desc);

create function private.allowed(target uuid, capability text) returns boolean
language sql stable security definer set search_path = '' as $$
 select auth.uid() is not null and exists (
 select 1 from public.memberships m
 join public.role_permissions p on p.role_id=m.role_id
 where m.server_id=target and m.user_id=auth.uid() and m.state='approved' and p.permission=capability
 )
$$;
revoke all on function private.allowed(uuid,text) from public, anon;
grant execute on function private.allowed(uuid,text) to authenticated;

alter table public.servers enable row level security;
alter table public.profiles enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.memberships enable row level security;
alter table public.audit_events enable row level security;
alter table public.commands enable row level security;
revoke all on public.servers,public.profiles,public.roles,public.permissions,public.role_permissions,public.memberships,public.audit_events,public.commands from anon,authenticated;
grant select on public.servers,public.profiles,public.roles,public.permissions,public.role_permissions,public.memberships,public.audit_events,public.commands to authenticated;
grant insert(id,display_name),update(display_name,statistics_public) on public.profiles to authenticated;
create policy server_read on public.servers for select to authenticated using(private.allowed(id,'status.view'));
create policy profile_read on public.profiles for select to authenticated using(id=(select auth.uid()));
create policy profile_create on public.profiles for insert to authenticated with check(id=(select auth.uid()));
create policy profile_edit on public.profiles for update to authenticated using(id=(select auth.uid())) with check(id=(select auth.uid()));
create policy membership_read on public.memberships for select to authenticated using(user_id=(select auth.uid()) or private.allowed(server_id,'access.manage'));
create policy roles_read on public.roles for select to authenticated using(private.allowed(server_id,'status.view'));
create policy permission_read on public.permissions for select to authenticated using((select auth.uid()) is not null);
create policy role_permission_read on public.role_permissions for select to authenticated using(exists(select 1 from public.roles r where r.id=role_id and private.allowed(r.server_id,'status.view')));
create policy audit_read on public.audit_events for select to authenticated using(private.allowed(server_id,'audit.view'));
create policy commands_read on public.commands for select to authenticated using(private.allowed(server_id,'audit.view') or (requested_by=(select auth.uid()) and private.allowed(server_id,'status.view')));

-- Public wrappers are invokers; privileged implementations live outside exposed schemas.
create function private.enqueue(target uuid, action text, args jsonb, request_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare capability text; existing public.commands; result uuid;
begin
 capability:=case action when 'start' then 'server.start' when 'stop' then 'server.stop' when 'restart' then 'server.restart'
 when 'kick' then 'players.kick' when 'ban' then 'players.ban' when 'pardon' then 'players.pardon'
 when 'whitelist_add' then 'players.whitelist_add' when 'whitelist_remove' then 'players.whitelist_remove' else null end;
 if capability is null or not private.allowed(target,capability) then raise exception 'Forbidden' using errcode='42501'; end if;
 if request_id is null or args is null or jsonb_typeof(args)<>'object' then raise exception 'Invalid command'; end if;
 if action in ('start','stop','restart') then
   if args<>'{}'::jsonb then raise exception 'Unexpected arguments'; end if;
 else
   if not (args ? 'player') or args - 'player'<>'{}'::jsonb or jsonb_typeof(args->'player')<>'string' or args->>'player' !~ '^[A-Za-z0-9_]{3,16}$' then raise exception 'Invalid player'; end if;
 end if;
 -- Serialize requests per server so rate limits and deduplication cannot race.
 perform 1 from public.servers where id=target for update;
 select * into existing from public.commands where server_id=target and requested_by=auth.uid() and idempotency_key=request_id;
 if found then
   if existing.operation<>action or existing.arguments<>args then raise exception 'Idempotency conflict'; end if;
   return existing.id;
 end if;
 if (select count(*) from public.commands where server_id=target and created_at>now()-interval '1 minute')>=20
 or (select count(*) from public.commands where requested_by=auth.uid() and server_id=target and created_at>now()-interval '1 minute')>=5 then raise exception 'Rate limit exceeded'; end if;
 insert into public.commands(server_id,requested_by,operation,arguments,idempotency_key,expires_at)
 values(target,auth.uid(),action,args,request_id,now()+interval '60 seconds') returning id into result;
 insert into public.audit_events(server_id,actor,action,details) values(target,auth.uid(),'command.queued',jsonb_build_object('command_id',result,'operation',action));
 return result;
end $$;
revoke all on function private.enqueue(uuid,text,jsonb,uuid) from public,anon;
grant execute on function private.enqueue(uuid,text,jsonb,uuid) to authenticated;
create function public.enqueue_command(target uuid, action text, args jsonb, request_id uuid) returns uuid
language sql security invoker set search_path='' as $$ select private.enqueue(target,action,args,request_id) $$;
revoke all on function public.enqueue_command(uuid,text,jsonb,uuid) from public,anon;
grant execute on function public.enqueue_command(uuid,text,jsonb,uuid) to authenticated;
