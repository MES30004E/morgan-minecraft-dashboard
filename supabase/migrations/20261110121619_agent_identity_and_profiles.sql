-- Read-only preflight: no registry rows, credentials or human permissions exposed.
create function public.agent_identity() returns uuid language sql stable security invoker set search_path='' as $$
 select private.agent_server()
$$;
revoke all on function public.agent_identity() from public,anon;
grant execute on function public.agent_identity() to authenticated;
