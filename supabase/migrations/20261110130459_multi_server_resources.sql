-- Configurations are independent resources. No game process or filesystem mutation.
alter table public.servers alter column gameplay_address set default '';
alter table public.servers add column description text not null default '' check(length(description)<=1000),
 add column game_type text not null default 'minecraft_java' check(game_type='minecraft_java'),
 add column version text not null default '' check(length(version)<=60),
 add column loader text not null default '' check(length(loader)<=60),
 add column icon text not null default '⛏' check(length(icon)<=8),
 add column machine_label text not null default '' check(length(machine_label)<=100),
 add column controller_server_id uuid,
 add column lifecycle text not null default 'active' check(lifecycle in ('active','archived','removed'));
insert into public.permissions values('server.configure'),('server.create');
insert into public.role_permissions select r.id,p.name from public.roles r cross join public.permissions p where r.name='Owner' and p.name in ('server.configure','server.create');
create or replace function private.allowed(target uuid,capability text) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.memberships m join public.role_permissions p on p.role_id=m.role_id join public.servers s on s.id=m.server_id
 where m.server_id=target and m.user_id=auth.uid() and m.state='approved' and p.permission=capability
 and (s.lifecycle='active' or capability in ('server.configure','access.manage','audit.view','status.view','backups.view')))
$$;
-- Pending users can see only the server they explicitly requested, not a directory.
alter policy server_read on public.servers using(private.allowed(id,'status.view') or exists(select 1 from public.memberships m where m.server_id=id and m.user_id=(select auth.uid()) and m.state='pending'));
create table public.server_endpoints(
 id uuid primary key default gen_random_uuid(),server_id uuid not null references public.servers(id),
 provider text not null check(provider ~ '^[a-z][a-z0-9_-]{0,31}$'),
 hostname text not null check(length(hostname) between 1 and 253 and hostname ~ '^[A-Za-z0-9.:-]+$'),
 public_port integer check(public_port between 1 and 65535),
 internal_host text not null default '' check(length(internal_host)<=253 and internal_host ~ '^[A-Za-z0-9.:-]*$'),
 internal_port integer check(internal_port between 1 and 65535),
 connection_state text not null default 'unknown' check(connection_state in ('unknown','online','offline')),
 created_at timestamptz not null default now());
create index endpoints_server on public.server_endpoints(server_id);
alter table public.server_endpoints enable row level security;
revoke all on public.server_endpoints from public,anon,authenticated;
grant select on public.server_endpoints to authenticated;
create policy endpoint_read on public.server_endpoints for select to authenticated using(private.allowed(server_id,'status.view'));
-- Preserve the original UUID and move its address into an endpoint resource.
insert into public.server_endpoints(server_id,provider,hostname,internal_host,internal_port)
 select id,'playit',gameplay_address,'127.0.0.1',25565 from public.servers where gameplay_address='impairment-entering.tun.ply.gg';
update public.servers set name='Morgan''s Test Server',version='1.21.1',loader='Fabric 0.20.1',machine_label='MSI GS65',controller_server_id='36ca5a76-35ed-4db4-aafa-d34923e83916' where gameplay_address='impairment-entering.tun.ply.gg';

create function private.configure_server(target uuid,operation text,configuration jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid:=target; role_name text; r uuid;
begin
 if auth.uid() is null or exists(select 1 from private.agents where user_id=auth.uid()) then raise exception 'Human owner required' using errcode='42501';end if;
 if configuration is null or jsonb_typeof(configuration)<>'object' or octet_length(configuration::text)>4096 or configuration-array['name','description','game_type','version','loader','icon','machine_label','controller_server_id']<>'{}' then raise exception 'Invalid configuration' using errcode='22023';end if;
 if operation='create' then
  -- Serialize the project-wide free-tier server cap.
  perform pg_advisory_xact_lock(747343881);
  if not exists(select 1 from public.servers s where private.allowed(s.id,'server.create')) then raise exception 'Server creation forbidden' using errcode='42501';end if;
  if (select count(*) from public.servers)>=10 then raise exception 'Project server quota reached';end if;
  insert into public.servers(name) values(coalesce(nullif(trim(configuration->>'name'),''),'New server')) returning id into result;
  foreach role_name in array array['Owner','Admin','Moderator','Member','Pending'] loop
   insert into public.roles(server_id,name) values(result,role_name) returning id into r;
   if role_name='Owner' then
    insert into public.role_permissions select r,name from public.permissions;
    insert into public.memberships values(result,auth.uid(),r,'approved');
   elsif role_name='Admin' then insert into public.role_permissions select r,name from public.permissions where name not in ('access.manage','server.create','server.configure');
   elsif role_name='Moderator' then insert into public.role_permissions select r,name from public.permissions where name in ('status.view','players.view','players.kick','players.ban','players.pardon');
   elsif role_name='Member' then insert into public.role_permissions select r,name from public.permissions where name in ('status.view','players.view');end if;
  end loop;
 else
  perform 1 from public.servers where id=target for update;
  if not private.allowed(target,'server.configure') then raise exception 'Server configuration forbidden' using errcode='42501';end if;
 end if;
 if operation in ('create','edit') then
  if configuration?'name' and (length(trim(configuration->>'name')) not between 1 and 80) then raise exception 'Invalid name';end if;
  update public.servers set name=coalesce(configuration->>'name',name),description=coalesce(configuration->>'description',description),game_type=coalesce(configuration->>'game_type',game_type),version=coalesce(configuration->>'version',version),loader=coalesce(configuration->>'loader',loader),icon=coalesce(configuration->>'icon',icon),machine_label=coalesce(configuration->>'machine_label',machine_label),controller_server_id=case when configuration?'controller_server_id' then nullif(configuration->>'controller_server_id','')::uuid else controller_server_id end where id=result;
 elsif operation in ('archive','remove','restore') then
  update public.servers set lifecycle=case operation when 'archive' then 'archived' when 'remove' then 'removed' else 'active' end where id=result;
 else raise exception 'Unknown configuration operation' using errcode='22023';end if;
 insert into public.audit_events(server_id,actor,action,details) values(result,auth.uid(),'server.'||operation,'{}');
 return result;
end $$;
create function public.configure_server(target uuid,operation text,configuration jsonb) returns uuid language sql security invoker set search_path='' as $$select private.configure_server(target,operation,configuration)$$;
create function private.configure_endpoint(target uuid,endpoint_id uuid,configuration jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid:=endpoint_id;
begin
 perform 1 from public.servers where id=target for update;
 if not private.allowed(target,'server.configure') then raise exception 'Endpoint configuration forbidden' using errcode='42501';end if;
 if configuration is null or jsonb_typeof(configuration)<>'object' or octet_length(configuration::text)>2048 or configuration-array['provider','hostname','public_port','internal_host','internal_port','remove']<>'{}' then raise exception 'Invalid endpoint' using errcode='22023';end if;
 if coalesce((configuration->>'remove')::boolean,false) then
  delete from public.server_endpoints where id=endpoint_id and server_id=target;
  if not found then raise exception 'Endpoint not found';end if;
 elsif endpoint_id is null then
  if (select count(*) from public.server_endpoints where server_id=target)>=8 then raise exception 'Endpoint quota reached';end if;
  insert into public.server_endpoints(server_id,provider,hostname,public_port,internal_host,internal_port) values(target,configuration->>'provider',configuration->>'hostname',(configuration->>'public_port')::int,coalesce(configuration->>'internal_host',''),(configuration->>'internal_port')::int) returning id into result;
 else
  update public.server_endpoints set provider=coalesce(configuration->>'provider',provider),hostname=coalesce(configuration->>'hostname',hostname),public_port=case when configuration?'public_port' then (configuration->>'public_port')::int else public_port end,internal_host=coalesce(configuration->>'internal_host',internal_host),internal_port=case when configuration?'internal_port' then (configuration->>'internal_port')::int else internal_port end where id=endpoint_id and server_id=target;
  if not found then raise exception 'Endpoint not found';end if;
 end if;
 insert into public.audit_events(server_id,actor,action,details) values(target,auth.uid(),'endpoint.changed',jsonb_build_object('endpoint_id',result));
 return result;
end $$;
create function public.configure_endpoint(target uuid,endpoint_id uuid,configuration jsonb) returns uuid language sql security invoker set search_path='' as $$select private.configure_endpoint(target,endpoint_id,configuration)$$;

-- A service identity may manage several servers; one active controller per server.
alter table private.agents drop constraint agents_pkey;
alter table private.agents add primary key(user_id,server_id);
create or replace function private.agent_server() returns uuid language sql stable security definer set search_path='' as $$
 select a.server_id from private.agents a where a.user_id=auth.uid() and a.enabled and (
 a.server_id::text=nullif(current_setting('morgan.agent_target',true),'') or
 (nullif(current_setting('morgan.agent_target',true),'') is null and (select count(*) from private.agents b where b.user_id=auth.uid() and b.enabled)=1))
$$;
create function private.agent_call(target uuid,operation text,payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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
create function public.agent_call(target uuid,operation text,payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.agent_call(target,operation,payload)$$;

create or replace function private.claim_command() returns setof public.commands language plpgsql security definer set search_path='' as $$
declare target uuid:=private.lock_agent_server(); candidate public.commands;
begin
 if target is null then raise exception 'Agent required' using errcode='42501'; end if;
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

alter table private.pairing_challenges add column server_id uuid references public.servers(id);
create index pairing_server on private.pairing_challenges(server_id);
create table public.identity_servers(server_id uuid not null references public.servers(id),minecraft_uuid uuid not null references public.mc_identities(minecraft_uuid),verified_at timestamptz not null default now(),primary key(server_id,minecraft_uuid));
create index identity_servers_player on public.identity_servers(minecraft_uuid);
alter table public.identity_servers enable row level security;
revoke all on public.identity_servers from public,anon,authenticated;
grant select on public.identity_servers to authenticated;
create policy identity_server_read on public.identity_servers for select to authenticated using(exists(select 1 from public.mc_identities i where i.minecraft_uuid=identity_servers.minecraft_uuid and i.user_id=(select auth.uid())));
create table public.identity_name_history(minecraft_uuid uuid not null references public.mc_identities(minecraft_uuid),username text not null,observed_at timestamptz not null default now(),primary key(minecraft_uuid,username));
alter table public.identity_name_history enable row level security;
revoke all on public.identity_name_history from public,anon,authenticated;
grant select on public.identity_name_history to authenticated;
create policy identity_name_read on public.identity_name_history for select to authenticated using(exists(select 1 from public.mc_identities i where i.minecraft_uuid=identity_name_history.minecraft_uuid and i.user_id=(select auth.uid())));
insert into public.identity_name_history(minecraft_uuid,username) select minecraft_uuid,username from public.mc_identities;
-- Existing server observations are evidence of association; do not duplicate Auth accounts.
insert into public.identity_servers(server_id,minecraft_uuid) select distinct s.server_id,s.minecraft_uuid from public.player_statistics s join public.mc_identities i using(minecraft_uuid) on conflict do nothing;

create function private.begin_server_link(target uuid,player_name text) returns text language plpgsql security definer set search_path='' as $$
declare code text;
begin
 if auth.uid() is null or exists(select 1 from private.agents where user_id=auth.uid()) then raise exception 'Human account required' using errcode='42501';end if;
 if not exists(select 1 from public.memberships where server_id=target and user_id=auth.uid() and state in ('pending','approved')) or not exists(select 1 from public.servers where id=target and lifecycle='active') then raise exception 'Request membership first' using errcode='42501';end if;
 if player_name is null or player_name !~ '^[A-Za-z0-9_]{3,16}$' then raise exception 'Invalid username' using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 if (select count(*) from private.pairing_challenges where user_id=auth.uid() and created_at>now()-interval '1 hour')>=5 then raise exception 'Pairing rate limit';end if;
 code:=encode(extensions.gen_random_bytes(16),'hex');
 insert into private.pairing_challenges(token_hash,user_id,expected_name,direction,server_id) values(extensions.digest(code,'sha256'),auth.uid(),player_name,'web',target);
 return code;
end $$;
create function public.begin_server_link(target uuid,player_name text) returns text language sql security invoker set search_path='' as $$select private.begin_server_link(target,player_name)$$;
create function private.claim_server_link(target uuid,code text) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or exists(select 1 from private.agents where user_id=auth.uid()) then raise exception 'Human account required' using errcode='42501';end if;
 if not exists(select 1 from private.pairing_challenges where server_id=target and token_hash=extensions.digest(code,'sha256')) then raise exception 'Wrong server or code' using errcode='22023';end if;
 perform private.claim_game_link(code);
end $$;
create function public.claim_server_link(target uuid,code text) returns void language sql security invoker set search_path='' as $$select private.claim_server_link(target,code)$$;
create or replace function private.unlink_game_identity(player_uuid uuid) returns text language plpgsql security definer set search_path='' as $$
declare target uuid:=private.lock_agent_server(); person uuid;
begin
 select user_id into person from public.mc_identities where minecraft_uuid=player_uuid;
 delete from public.identity_servers where server_id=target and minecraft_uuid=player_uuid;
 if found then insert into public.audit_events(server_id,actor,action,details) values(target,person,'identity.unlinked',jsonb_build_object('minecraft_uuid',player_uuid));end if;
 return 'Identity disconnected from this server. Other server links, website ownership, roles and inventory are preserved.';
end $$;
create or replace function private.game_profile(player_uuid uuid) returns text language plpgsql stable security definer set search_path='' as $$
declare label text; target uuid:=private.agent_server();
begin
 if target is null then raise exception 'Agent required' using errcode='42501';end if;
 select coalesce(p.display_name,'Website account')||' ['||left(i.user_id::text,8)||']' into label from public.mc_identities i join public.identity_servers x on x.minecraft_uuid=i.minecraft_uuid and x.server_id=target left join public.profiles p on p.id=i.user_id where i.minecraft_uuid=player_uuid;
 return coalesce(label,'No website identity verified on this server. Use /link.');
end $$;

create or replace function private.verify_link(code text,player_uuid uuid,player_name text,confirmed boolean) returns text
language plpgsql security definer set search_path='' as $$
declare challenge private.pairing_challenges; label text; target uuid:=private.lock_agent_server();
begin
 if target is null then raise exception 'Agent required' using errcode='42501'; end if;
 select * into challenge from private.pairing_challenges where token_hash=extensions.digest(code,'sha256') for update;
 if not found or challenge.server_id is distinct from target or challenge.expires_at<=now() or challenge.consumed_at is not null or challenge.user_id is null
 or lower(challenge.expected_name)<>lower(player_name) or player_uuid is null or player_name is null
 or (challenge.minecraft_uuid is not null and challenge.minecraft_uuid<>player_uuid) then raise exception 'Invalid or expired pairing code' using errcode='22023'; end if;
 select display_name into label from public.profiles where id=challenge.user_id;
 label:=coalesce(label,'Website account')||' ['||left(challenge.user_id::text,8)||']';
 if not coalesce(confirmed,false) then return 'Link to '||label||'? If this is your website account, run /verify '||code||' confirm'; end if;
 insert into public.mc_identities(minecraft_uuid,user_id,username) values(player_uuid,challenge.user_id,player_name)
 on conflict(minecraft_uuid) do update set username=excluded.username where public.mc_identities.user_id=excluded.user_id;
 if not found then raise exception 'Minecraft identity already linked to another account'; end if;
 insert into public.identity_name_history(minecraft_uuid,username) values(player_uuid,player_name) on conflict do nothing;
 insert into public.identity_servers(server_id,minecraft_uuid) values(target,player_uuid) on conflict do nothing;
 update private.pairing_challenges set minecraft_uuid=player_uuid,consumed_at=now() where id=challenge.id;
 insert into public.memberships(server_id,user_id) values(target,challenge.user_id) on conflict do nothing;
 insert into public.audit_events(server_id,actor,action,details) values(target,challenge.user_id,'identity.linked',jsonb_build_object('minecraft_uuid',player_uuid));
 return 'Linked to '||label||'. Membership approval is separate.';
end $$;
create or replace function private.begin_game_link(player_uuid uuid,player_name text) returns text language plpgsql security definer set search_path='' as $$
declare code text; target uuid:=private.lock_agent_server();
begin
 if private.lock_agent_server() is null then raise exception 'Agent required' using errcode='42501'; end if;
 if player_uuid is null or player_name is null or player_name !~ '^[A-Za-z0-9_]{3,16}$' then raise exception 'Invalid player'; end if;
 perform pg_advisory_xact_lock(hashtextextended(player_uuid::text,0));
 if (select count(*) from private.pairing_challenges where minecraft_uuid=player_uuid and created_at>now()-interval '1 hour')>=5 then raise exception 'Pairing rate limit'; end if;
 code:=encode(extensions.gen_random_bytes(16),'hex');
 insert into private.pairing_challenges(token_hash,minecraft_uuid,expected_name,direction,server_id) values(extensions.digest(code,'sha256'),player_uuid,player_name,'game',target);
 return code;
end $$;

-- Disable the obsolete unscoped human pairing endpoints; existing challenges fail closed.
revoke all on function public.begin_web_link(text),public.claim_game_link(text),private.begin_web_link(text),private.claim_game_link(text) from authenticated;
do $$ declare f record; begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('private','public') and p.proname in ('configure_server','configure_endpoint','agent_call','begin_server_link','claim_server_link') loop
 execute format('revoke all on function %s from public,anon',f.signature);
 execute format('grant execute on function %s to authenticated',f.signature);
 end loop;
end $$;

create function private.is_agent_for(target uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from private.agents where user_id=auth.uid() and server_id=target and enabled)$$;
revoke all on function private.is_agent_for(uuid) from public,anon;
grant execute on function private.is_agent_for(uuid) to authenticated;
alter policy commands_read on public.commands using(private.is_agent_for(server_id) or private.allowed(server_id,'audit.view') or (requested_by=(select auth.uid()) and private.allowed(server_id,'status.view')));
create or replace function private.may_view_stats(target uuid,player uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.mc_identities i join public.identity_servers x on x.minecraft_uuid=i.minecraft_uuid and x.server_id=target left join public.profiles p on p.id=i.user_id where i.minecraft_uuid=player and (i.user_id=auth.uid() or (coalesce(p.statistics_public,false) and private.allowed(target,'players.view'))))
$$;
create function private.record_identity_name() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.mc_identities where minecraft_uuid=new.minecraft_uuid) then
  insert into public.identity_name_history(minecraft_uuid,username) select minecraft_uuid,username from public.mc_identities where minecraft_uuid=new.minecraft_uuid on conflict do nothing;
  insert into public.identity_name_history(minecraft_uuid,username) values(new.minecraft_uuid,new.username) on conflict do nothing;
  update public.mc_identities set username=new.username where minecraft_uuid=new.minecraft_uuid;
 end if;
 return new;
end $$;
revoke all on function private.record_identity_name() from public,anon,authenticated;
create trigger identity_name_observation after insert or update of username on public.player_statistics for each row execute function private.record_identity_name();

create function private.agent_metrics(samples jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare sample jsonb; results jsonb:='[]'; target uuid;
begin
 if jsonb_typeof(samples)<>'array' or jsonb_array_length(samples)>10 or octet_length(samples::text)>32768 then raise exception 'Invalid metrics batch' using errcode='22023';end if;
 for sample in select value from jsonb_array_elements(samples) order by value->>'server_id' loop
  begin
   target:=(sample->>'server_id')::uuid;
   perform private.agent_call(target,'publish_snapshot',sample->'snapshot');
   results:=results||jsonb_build_array(jsonb_build_object('server_id',target,'accepted',true));
  exception when others then
   results:=results||jsonb_build_array(jsonb_build_object('server_id',sample->>'server_id','accepted',false));
  end;
 end loop;
 return results;
end $$;
create function public.agent_metrics(samples jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.agent_metrics(samples)$$;
revoke all on function private.agent_metrics(jsonb),public.agent_metrics(jsonb) from public,anon;
grant execute on function private.agent_metrics(jsonb),public.agent_metrics(jsonb) to authenticated;

create or replace function private.request_membership(target uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or exists(select 1 from private.agents where user_id=auth.uid()) then raise exception 'Human account required' using errcode='42501';end if;
 if not exists(select 1 from public.servers where id=target and lifecycle='active') then raise exception 'Server unavailable' using errcode='42501';end if;
 insert into public.memberships(server_id,user_id) values(target,auth.uid()) on conflict do nothing;
end $$;
