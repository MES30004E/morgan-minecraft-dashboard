create extension if not exists pgcrypto with schema extensions;
create table public.mc_identities (
 minecraft_uuid uuid primary key, user_id uuid not null references auth.users(id),
 username text not null check(username ~ '^[A-Za-z0-9_]{3,16}$'), verified_at timestamptz not null default now(),
 online_mode boolean not null default true check(online_mode)
);
create index identities_owner on public.mc_identities(user_id);
alter table public.mc_identities enable row level security;
revoke all on public.mc_identities from anon,authenticated;
grant select on public.mc_identities to authenticated;
create policy identity_read on public.mc_identities for select to authenticated using(user_id=(select auth.uid()));
create table private.pairing_challenges (
 id uuid primary key default gen_random_uuid(), token_hash bytea unique not null, user_id uuid references auth.users(id),
 minecraft_uuid uuid, expected_name text, direction text not null check(direction in ('web','game')),
 created_at timestamptz not null default now(), expires_at timestamptz not null default now()+interval '5 minutes',
 consumed_at timestamptz
);
create index pairing_owner on private.pairing_challenges(user_id,created_at);
create index pairing_player on private.pairing_challenges(minecraft_uuid,created_at);
alter table private.pairing_challenges enable row level security;
revoke all on private.pairing_challenges from public,anon,authenticated;
create policy challenges_deny on private.pairing_challenges for all to authenticated using(false) with check(false);

create function private.begin_web_link(player_name text) returns text language plpgsql security definer set search_path='' as $$
declare code text;
begin
 if auth.uid() is null or private.agent_server() is not null then raise exception 'Human account required' using errcode='42501'; end if;
 if player_name is null or player_name !~ '^[A-Za-z0-9_]{3,16}$' then raise exception 'Invalid username'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 if (select count(*) from private.pairing_challenges where user_id=auth.uid() and created_at>now()-interval '1 hour')>=5 then raise exception 'Pairing rate limit'; end if;
 code:=encode(extensions.gen_random_bytes(16),'hex');
 insert into private.pairing_challenges(token_hash,user_id,expected_name,direction) values(extensions.digest(code,'sha256'),auth.uid(),player_name,'web');
 return code;
end $$;
create function public.begin_web_link(player_name text) returns text language sql security invoker set search_path='' as $$ select private.begin_web_link(player_name) $$;

create function private.begin_game_link(player_uuid uuid,player_name text) returns text language plpgsql security definer set search_path='' as $$
declare code text;
begin
 if private.agent_server() is null then raise exception 'Agent required' using errcode='42501'; end if;
 if player_uuid is null or player_name is null or player_name !~ '^[A-Za-z0-9_]{3,16}$' then raise exception 'Invalid player'; end if;
 perform pg_advisory_xact_lock(hashtextextended(player_uuid::text,0));
 if (select count(*) from private.pairing_challenges where minecraft_uuid=player_uuid and created_at>now()-interval '1 hour')>=5 then raise exception 'Pairing rate limit'; end if;
 code:=encode(extensions.gen_random_bytes(16),'hex');
 insert into private.pairing_challenges(token_hash,minecraft_uuid,expected_name,direction) values(extensions.digest(code,'sha256'),player_uuid,player_name,'game');
 return code;
end $$;
create function public.begin_game_link(player_uuid uuid,player_name text) returns text language sql security invoker set search_path='' as $$ select private.begin_game_link(player_uuid,player_name) $$;

create function private.claim_game_link(code text) returns void language plpgsql security definer set search_path='' as $$
declare challenge private.pairing_challenges;
begin
 if auth.uid() is null or private.agent_server() is not null then raise exception 'Human account required' using errcode='42501'; end if;
 select * into challenge from private.pairing_challenges where token_hash=extensions.digest(code,'sha256') for update;
 if not found or challenge.direction<>'game' or challenge.expires_at<=now() or challenge.consumed_at is not null or (challenge.user_id is not null and challenge.user_id<>auth.uid()) then raise exception 'Invalid or expired pairing code'; end if;
 update private.pairing_challenges set user_id=auth.uid() where id=challenge.id;
end $$;
create function public.claim_game_link(code text) returns void language sql security invoker set search_path='' as $$ select private.claim_game_link(code) $$;

create function private.verify_link(code text,player_uuid uuid,player_name text,confirmed boolean) returns text
language plpgsql security definer set search_path='' as $$
declare challenge private.pairing_challenges; label text; target uuid:=private.agent_server();
begin
 if target is null then raise exception 'Agent required' using errcode='42501'; end if;
 select * into challenge from private.pairing_challenges where token_hash=extensions.digest(code,'sha256') for update;
 if not found or challenge.expires_at<=now() or challenge.consumed_at is not null or challenge.user_id is null
 or lower(challenge.expected_name)<>lower(player_name) or player_uuid is null or player_name is null
 or (challenge.minecraft_uuid is not null and challenge.minecraft_uuid<>player_uuid) then raise exception 'Invalid or expired pairing code'; end if;
 select display_name into label from public.profiles where id=challenge.user_id;
 label:=coalesce(label,'Website account')||' ['||left(challenge.user_id::text,8)||']';
 if not coalesce(confirmed,false) then return 'Link to '||label||'? If this is your website account, run /verify '||code||' confirm'; end if;
 insert into public.mc_identities(minecraft_uuid,user_id,username) values(player_uuid,challenge.user_id,player_name)
 on conflict(minecraft_uuid) do update set username=excluded.username where public.mc_identities.user_id=excluded.user_id;
 if not found then raise exception 'Minecraft identity already linked to another account'; end if;
 update private.pairing_challenges set minecraft_uuid=player_uuid,consumed_at=now() where id=challenge.id;
 insert into public.memberships(server_id,user_id) values(target,challenge.user_id) on conflict do nothing;
 insert into public.audit_events(server_id,actor,action,details) values(target,challenge.user_id,'identity.linked',jsonb_build_object('minecraft_uuid',player_uuid));
 return 'Linked to '||label||'. Membership approval is separate.';
end $$;
create function public.verify_link(code text,player_uuid uuid,player_name text,confirmed boolean) returns text
language sql security invoker set search_path='' as $$ select private.verify_link(code,player_uuid,player_name,confirmed) $$;

create function private.unlink_game_identity(player_uuid uuid) returns text language plpgsql security definer set search_path='' as $$
declare person uuid; target uuid:=private.agent_server();
begin
 if target is null then raise exception 'Agent required' using errcode='42501'; end if;
 delete from public.mc_identities where minecraft_uuid=player_uuid returning user_id into person;
 if found then insert into public.audit_events(server_id,actor,action,details) values(target,person,'identity.unlinked',jsonb_build_object('minecraft_uuid',player_uuid)); end if;
 return 'Identity unlinked. Website roles and Minecraft inventory are unchanged.';
end $$;
create function public.unlink_game_identity(player_uuid uuid) returns text language sql security invoker set search_path='' as $$ select private.unlink_game_identity(player_uuid) $$;

create function private.game_profile(player_uuid uuid) returns text language plpgsql stable security definer set search_path='' as $$
declare label text;
begin
 if private.agent_server() is null then raise exception 'Agent required' using errcode='42501'; end if;
 select coalesce(p.display_name,'Website account')||' ['||left(i.user_id::text,8)||']' into label from public.mc_identities i left join public.profiles p on p.id=i.user_id where minecraft_uuid=player_uuid;
 return coalesce(label,'No verified website account linked. Use /link to begin.');
end $$;
create function public.game_profile(player_uuid uuid) returns text language sql security invoker set search_path='' as $$ select private.game_profile(player_uuid) $$;
do $$ declare f record; begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('private','public')
 and p.proname in ('begin_web_link','begin_game_link','claim_game_link','verify_link','unlink_game_identity','game_profile') loop
 execute format('revoke all on function %s from public,anon',f.signature);
 execute format('grant execute on function %s to authenticated',f.signature);
 end loop;
end $$;
