-- Creator identity is set by the database, never trusted from a client payload.
alter table public.fixtures add column created_by_user_id uuid;

create function audit_private.set_fixture_creator() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.created_by_user_id := auth.uid();
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Fixture creator cannot be changed';
  end if;
  return new;
end $$;
create trigger a_set_fixture_creator before insert or update on public.fixtures
for each row execute function audit_private.set_fixture_creator();
revoke all on function audit_private.set_fixture_creator() from public, anon, authenticated;

-- The returned facts are advisory for the UI. Every deletion rechecks them
-- while holding the fixture row lock.
create function public.fixture_deletion_preview(p_fixture_id uuid) returns jsonb
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
  v_has_members boolean;
  v_has_communications boolean;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  select * into f from public.fixtures where id = p_fixture_id;
  if not found then raise exception 'Fixture not found'; end if;

  select exists(select 1 from public.app_superusers s where s.user_id = v_actor)
    into v_is_super;
  select exists(
    select 1 from public.club_memberships cm
    join public.member_profiles mp on mp.id = cm.member_profile_id
    where mp.user_id = v_actor and cm.club_id = f.club_id and cm.is_active
      and cm.role::text in ('admin','selector')
  ) into v_is_manager;
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
    or exists(select 1 from public.fixture_lifecycle_events e where e.fixture_id = f.id
      and lower(e.event_type) like '%publish%')
    into v_ever_published;
  v_has_members := v_rsvps > 0 or v_selected > 0 or v_assigned > 0 or v_marker_requests > 0;
  v_has_communications := v_email_queue > 0 or v_notification_queue > 0
    or v_app_notifications > 0 or v_email_log > 0 or v_email_actions > 0
    or v_communication_audit > 0;

  return jsonb_build_object(
    'can_delete', f.archived_at is null and not v_ever_published
      and not v_has_members and not v_has_communications,
    'can_archive', f.archived_at is null and f.cancelled_at is not null
      and public.can_manage_fixture(f.id),
    'is_superuser', v_is_super,
    'is_creator', v_is_creator,
    'is_cancelled', f.cancelled_at is not null,
    'is_archived', f.archived_at is not null,
    'ever_published', v_ever_published,
    'rsvps', v_rsvps, 'selected_members', v_selected,
    'rink_assignments', v_assigned, 'marker_requests', v_marker_requests,
    'email_queue', v_email_queue, 'notification_queue', v_notification_queue,
    'app_notifications', v_app_notifications, 'fixture_email_log', v_email_log,
    'email_actions', v_email_actions, 'communication_audit', v_communication_audit,
    'diary_items', v_diary,
    'blockers', to_jsonb(array_remove(array[
      case when f.archived_at is not null then 'already archived' end,
      case when v_ever_published then 'published now or previously' end,
      case when v_has_members then 'member participation or marker requests' end,
      case when v_has_communications then 'queued or recorded communications' end
    ]::text[], null))
  );
end $$;
revoke all on function public.fixture_deletion_preview(uuid) from public, anon;
grant execute on function public.fixture_deletion_preview(uuid) to authenticated;

-- Direct Data API deletion stays blocked. Only the checked SECURITY DEFINER
-- functions below may set the transaction-local mode used by this guard.
create or replace function audit_private.guard_fixture_delete() returns trigger
language plpgsql set search_path = '' as $$
begin
  if current_user = 'postgres'
    and current_setting('app.audit_delete_mode', true) in ('ordinary','force')
    and length(trim(coalesce(current_setting('app.audit_reason', true),''))) >= 5
  then return old; end if;
  raise exception 'Use the audited fixture deletion action';
end $$;
revoke delete on public.fixtures from public, anon, authenticated, service_role;

-- Old clients cannot omit a reason.
create or replace function public.delete_fixture(p_fixture_id uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
begin raise exception 'Update the app to delete fixtures with a reason'; end $$;

create function public.delete_fixture(p_fixture_id uuid, p_reason text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_preview jsonb;
begin
  if length(trim(coalesce(p_reason,''))) < 5 then
    raise exception 'Please give a deletion reason of at least five characters';
  end if;
  perform 1 from public.fixtures where id = p_fixture_id for update;
  if not found then raise exception 'Fixture not found'; end if;
  v_preview := public.fixture_deletion_preview(p_fixture_id);
  if not (v_preview->>'can_delete')::boolean then
    raise exception 'Cancel or archive this fixture; deletion is blocked by %',
      v_preview->'blockers';
  end if;
  perform set_config('app.audit_reason', trim(p_reason), true);
  perform set_config('app.audit_delete_mode', 'ordinary', true);
  delete from public.club_schedule_items where linked_fixture_id = p_fixture_id;
  delete from public.fixtures where id = p_fixture_id;
  return true;
end $$;
revoke all on function public.delete_fixture(uuid,text) from public, anon;
grant execute on function public.delete_fixture(uuid,text) to authenticated;

-- Preserve the old force RPC signature as an explicit upgrade error.
create or replace function public.admin_force_delete_fixture(
  p_fixture_id uuid, p_confirm text default null)
returns table(item text, deleted_count integer)
language plpgsql security definer set search_path = '' as $$
begin raise exception 'Update the app to force delete with a reason'; end $$;

create function public.admin_force_delete_fixture(
  p_fixture_id uuid, p_reason text, p_confirm text)
returns table(item text, deleted_count integer)
language plpgsql security definer set search_path = '' as $$
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
  if p_confirm <> 'DELETE FIXTURE' then
    raise exception 'Type DELETE FIXTURE to confirm'; end if;
  if length(trim(coalesce(p_reason,''))) < 5 then
    raise exception 'Please give a force-deletion reason of at least five characters'; end if;
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
    f.id, 'force deletion authorized', trim(p_reason),
    audit_private.pick(to_jsonb(f), array[
      'id','club_id','team_id','team_name','start_at','end_at','venue_id',
      'opponent_venue_id','opponent_name','section','competition_type_id',
      'captain_member_profile_id','vice_captain_member_profile_id',
      'cancelled_at','cancellation_reason','archived_at','archive_reason',
      'created_by_user_id'
    ]), v_preview
  );
  perform set_config('app.audit_reason', trim(p_reason), true);
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
end $$;
revoke all on function public.admin_force_delete_fixture(uuid,text,text) from public, anon;
grant execute on function public.admin_force_delete_fixture(uuid,text,text) to authenticated;
