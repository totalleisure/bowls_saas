-- Require the exact explicit force-deletion confirmation, including rejecting null.
CREATE OR REPLACE FUNCTION public.admin_force_delete_fixture(p_fixture_id uuid, p_reason text, p_confirm text)
 RETURNS TABLE(item text, deleted_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  f public.fixtures;
  v_actor uuid := auth.uid();
  v_actor_name text;
  v_club_name text;
  v_preview jsonb;
  v_count integer;
begin
  if v_actor is null or not exists(
    select 1 from public.app_superusers s where s.user_id = v_actor
  ) then raise exception 'Superuser access required'; end if;
  if p_confirm is distinct from 'DELETE FIXTURE' then
    raise exception 'Type DELETE FIXTURE to confirm'; end if;
  select * into f from public.fixtures where id = p_fixture_id for update;
  if not found then raise exception 'Fixture not found'; end if;
  v_preview := public.fixture_deletion_preview(p_fixture_id);
  select nullif(trim(concat_ws(' ',m.first_name,m.last_name)), '')
    into v_actor_name from public.member_profiles m where m.user_id = v_actor limit 1;
  select c.name into v_club_name from public.clubs c where c.id = f.club_id;

  -- This entry and the automatic DELETE entry share one transaction.
  insert into public.audit_journal(
    actor_user_id, actor_name, origin, club_id, club_name,
    record_type, record_id, record_label, fixture_id, action,
    reason, before_values, after_values)
  values(
    v_actor, coalesce(v_actor_name,v_actor::text), 'app', f.club_id, v_club_name,
    'fixtures', f.id::text,
    coalesce(nullif(f.team_name,''),nullif(f.opponent_name,''),'Fixture') || ' / ' || f.start_at::text,
    f.id, 'force deletion authorized', nullif(trim(coalesce(p_reason,'')),''),
    audit_private.pick(to_jsonb(f), array[
      'id','club_id','team_id','team_name','start_at','end_at','venue_id',
      'opponent_venue_id','opponent_name','section','competition_type_id',
      'captain_member_profile_id','vice_captain_member_profile_id',
      'cancelled_at','cancellation_reason','archived_at','archive_reason',
      'created_by_user_id'
    ]), v_preview
  );
  perform set_config('app.audit_reason', coalesce(trim(p_reason),''), true);
  perform set_config('app.audit_delete_mode', 'force', true);

  delete from public.club_schedule_items where linked_fixture_id = f.id;
  get diagnostics v_count = row_count;
  item := 'club_schedule_items'; deleted_count := v_count; return next;
  delete from public.fixture_email_log where fixture_id = f.id;
  get diagnostics v_count = row_count;
  item := 'fixture_email_log'; deleted_count := v_count; return next;
  delete from public.notification_queue where fixture_id = f.id;
  get diagnostics v_count = row_count;
  item := 'notification_queue'; deleted_count := v_count; return next;
  delete from public.email_queue where fixture_id = f.id;
  get diagnostics v_count = row_count;
  item := 'email_queue'; deleted_count := v_count; return next;
  delete from public.app_notifications where fixture_id = f.id;
  get diagnostics v_count = row_count;
  item := 'app_notifications'; deleted_count := v_count; return next;
  -- Remaining fixture-linked rows have database-managed ON DELETE actions.
  delete from public.fixtures where id = f.id;
  get diagnostics v_count = row_count;
  item := 'fixtures'; deleted_count := v_count; return next;
end $function$
;

