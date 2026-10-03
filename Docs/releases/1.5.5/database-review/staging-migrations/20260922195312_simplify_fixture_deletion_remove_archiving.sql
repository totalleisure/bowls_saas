-- Return fixture handling to the simple model agreed during staging review:
-- ordinary deletion is allowed only when no players are attached; only a
-- superuser can force-delete a fixture with player attachments. Cancellation
-- and rescheduling remain the preservation paths.

drop policy if exists hide_archived_fixtures on public.fixtures;
drop function if exists public.archive_fixture(uuid,text);
drop function if exists public.restore_archived_fixture(uuid,text);
drop function if exists public.list_archived_fixtures(uuid);

create or replace function audit_private.guard_archived_fixture() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE'
    and old.cancelled_at is null
    and new.cancelled_at is not null
    and length(trim(coalesce(new.cancellation_reason,''))) < 5
  then
    raise exception 'A cancellation reason of at least five characters is required';
  end if;
  return new;
end $$;

create or replace function public.fixture_deletion_preview(p_fixture_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  f public.fixtures;
  v_actor uuid := auth.uid();
  v_is_super boolean;
  v_is_manager boolean;
  v_is_creator boolean;
  v_rsvps integer;
  v_selected integer;
  v_assigned integer;
  v_marker_requests integer;
  v_email_queue integer;
  v_notification_queue integer;
  v_app_notifications integer;
  v_email_log integer;
  v_email_actions integer;
  v_communication_audit integer;
  v_diary integer;
  v_ever_published boolean;
  v_has_players boolean;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  select * into f from public.fixtures where id = p_fixture_id;
  if not found then raise exception 'Fixture not found'; end if;

  select exists(select 1 from public.app_superusers s where s.user_id = v_actor)
    into v_is_super;
  select public.can_manage_fixture(f.id) into v_is_manager;
  select f.created_by_user_id = v_actor and exists(
    select 1 from public.club_memberships cm
    join public.member_profiles mp on mp.id = cm.member_profile_id
    where mp.user_id = v_actor and cm.club_id = f.club_id and cm.is_active
      and cm.role::text <> 'guest'
  ) into v_is_creator;
  v_is_creator := coalesce(v_is_creator, false);
  if not (v_is_super or v_is_manager or v_is_creator) then
    raise exception 'Not authorized to delete this fixture';
  end if;

  select count(*) into v_rsvps from public.fixture_rsvps where fixture_id = f.id;
  select count(*) into v_selected from public.team_selection_members m
    join public.team_selections s on s.id = m.team_selection_id
    where s.fixture_id = f.id;
  select count(*) into v_assigned from public.fixture_rink_assignments
    where fixture_id = f.id and member_profile_id is not null;
  select count(*) into v_marker_requests from public.fixture_marker_requests mr
    join public.fixture_rinks fr on fr.id = mr.fixture_rink_id
    where fr.fixture_id = f.id;
  select count(*) into v_email_queue from public.email_queue where fixture_id = f.id;
  select count(*) into v_notification_queue from public.notification_queue where fixture_id = f.id;
  select count(*) into v_app_notifications from public.app_notifications where fixture_id = f.id;
  select count(*) into v_email_log from public.fixture_email_log where fixture_id = f.id;
  select count(*) into v_email_actions from public.email_action_requests where fixture_id = f.id;
  select count(*) into v_communication_audit from public.fixture_communication_audit where fixture_id = f.id;
  select count(*) into v_diary from public.club_schedule_items where linked_fixture_id = f.id;
  select
    exists(select 1 from public.team_selections s where s.fixture_id = f.id
      and (s.status::text = 'published' or s.published_at is not null))
    or exists(select 1 from public.audit_journal j where j.fixture_id = f.id
      and j.record_type = 'team_selections' and j.action = 'published')
    into v_ever_published;

  v_has_players := v_rsvps > 0 or v_selected > 0
    or v_assigned > 0 or v_marker_requests > 0;

  return jsonb_build_object(
    'can_delete', not v_has_players,
    'can_force_delete', v_is_super and v_has_players,
    'is_superuser', v_is_super,
    'is_creator', v_is_creator,
    'has_players', v_has_players,
    'ever_published', v_ever_published,
    'rsvps', v_rsvps, 'selected_members', v_selected,
    'rink_assignments', v_assigned, 'marker_requests', v_marker_requests,
    'email_queue', v_email_queue, 'notification_queue', v_notification_queue,
    'app_notifications', v_app_notifications, 'fixture_email_log', v_email_log,
    'email_actions', v_email_actions, 'communication_audit', v_communication_audit,
    'diary_items', v_diary,
    'blockers', to_jsonb(array_remove(array[
      case when v_has_players then 'players are attached' end
    ]::text[], null))
  );
end $$;
revoke all on function public.fixture_deletion_preview(uuid) from public, anon;
grant execute on function public.fixture_deletion_preview(uuid) to authenticated;
