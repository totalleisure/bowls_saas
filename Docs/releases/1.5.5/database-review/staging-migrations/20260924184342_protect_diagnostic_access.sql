-- These diagnostic endpoints have no current app callers; retain SQL/server access.
revoke all on function public.debug_member_identity_links(text,uuid) from public,anon,authenticated;
revoke all on function public.admin_find_orphaned_records() from public,anon,authenticated;
grant execute on function public.debug_member_identity_links(text,uuid) to service_role;
grant execute on function public.admin_find_orphaned_records() to service_role;
-- Legacy marker view has no app caller and an unguarded delete trigger.
revoke all on public.marker_volunteer_directory from public,anon,authenticated;
alter view public.marker_volunteer_directory set (security_invoker=true);
-- The staging login picker needs SELECT only, never profile modification.
revoke insert,update,delete,truncate,references,trigger on public.debug_login_users from public,anon,authenticated;
