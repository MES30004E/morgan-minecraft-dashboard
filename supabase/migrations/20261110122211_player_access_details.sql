-- Invoker privileges preserve all identity, membership, permission and audit RLS.
-- Shared statistics never implicitly reveal website account associations.
create function public.player_access(target uuid,player uuid) returns jsonb
language sql stable security invoker set search_path='' as $$
 select jsonb_build_object(
 'role',(select r.name from public.memberships m join public.roles r on r.id=m.role_id where m.server_id=target and m.user_id=i.user_id),
 'permissions',coalesce((select jsonb_agg(p.permission order by p.permission) from public.memberships m join public.role_permissions p on p.role_id=m.role_id where m.server_id=target and m.user_id=i.user_id and m.state='approved'),'[]'::jsonb),
 'activity',coalesce((select jsonb_agg(jsonb_build_object('action',a.action,'created_at',a.created_at)) from (select action,created_at from public.audit_events where server_id=target and actor=i.user_id order by created_at desc limit 10) a),'[]'::jsonb))
 from public.mc_identities i where i.minecraft_uuid=player
$$;
revoke all on function public.player_access(uuid,uuid) from public,anon;
grant execute on function public.player_access(uuid,uuid) to authenticated;
create index archive_items_batch_fk on private.archive_items(batch_id,server_id,kind);
create index used_command_requests_actor on private.used_command_requests(requested_by);
