create index audit_actor on public.audit_events(actor);
create index commands_actor on public.commands(requested_by);
create index commands_claimant on public.commands(claimed_by);
create index memberships_role on public.memberships(server_id,role_id);
create index role_permissions_capability on public.role_permissions(permission);
drop policy agent_command_read on public.commands;
alter policy commands_read on public.commands using(server_id=private.agent_server() or private.allowed(server_id,'audit.view') or (requested_by=(select auth.uid()) and private.allowed(server_id,'status.view')));

create or replace function private.finish_command(command_id uuid,token uuid,outcome text,summary text) returns void
language plpgsql security definer set search_path='' as $$
declare target uuid:=private.agent_server(); command public.commands;
begin
 if target is null or outcome not in ('completed','failed','uncertain') or outcome is null then raise exception 'Forbidden' using errcode='42501'; end if;
 select * into command from public.commands where id=command_id and server_id=target and claimed_by=auth.uid() and claim_token=token for update;
 if not found then raise exception 'Invalid claim'; end if;
 if command.state=outcome then return; end if;
 if command.state not in ('claimed','uncertain') then raise exception 'Claim already finalized'; end if;
 update public.commands set state=outcome,result=left(summary,1000),finished_at=now() where id=command.id;
 insert into public.audit_events(server_id,actor,action,details) values(target,auth.uid(),'command.'||outcome,jsonb_build_object('command_id',command_id));
end $$;
create function private.resolve_uncertain(command_id uuid,outcome text,note text) returns void
language plpgsql security definer set search_path='' as $$
declare command public.commands;
begin
 select * into command from public.commands where id=command_id for update;
 if not found or not private.allowed(command.server_id,'access.manage') then raise exception 'Forbidden' using errcode='42501'; end if;
 if command.state<>'uncertain' or outcome not in ('completed','failed') or outcome is null or length(note)<10 or note is null then raise exception 'Reconciliation note and terminal outcome required'; end if;
 update public.commands set state=outcome,result=left(note,1000),finished_at=now() where id=command_id;
 insert into public.audit_events(server_id,actor,action,details) values(command.server_id,auth.uid(),'command.reconciled',jsonb_build_object('command_id',command_id,'outcome',outcome,'note',left(note,1000)));
end $$;
create function public.resolve_uncertain(command_id uuid,outcome text,note text) returns void
language sql security invoker set search_path='' as $$ select private.resolve_uncertain(command_id,outcome,note) $$;
create function private.publish_console(log_lines jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare target uuid:=private.agent_server();
begin
 if target is null then raise exception 'Agent required' using errcode='42501'; end if;
 if exists(select 1 from public.console_tail where server_id=target and updated_at>now()-interval '60 seconds') then return; end if;
 insert into public.console_tail values(target,now(),log_lines) on conflict(server_id) do update set updated_at=excluded.updated_at,lines=excluded.lines;
end $$;
create function public.publish_console(log_lines jsonb) returns void
language sql security invoker set search_path='' as $$ select private.publish_console(log_lines) $$;
do $$ declare f record; begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in ('private','public') and p.proname in ('resolve_uncertain','publish_console') loop
 execute format('revoke all on function %s from public,anon',f.signature);
 execute format('grant execute on function %s to authenticated',f.signature);
 end loop;
end $$;
