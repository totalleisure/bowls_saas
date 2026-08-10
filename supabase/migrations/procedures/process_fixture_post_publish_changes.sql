create or replace function public.process_fixture_post_publish_changes(
  p_fixture_id uuid,
  p_change_type text,
  p_changed_by_member_profile_id uuid default null,
  p_old_start_at timestamptz default null,
  p_old_end_at timestamptz default null,
  p_context jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_fixture record;
  v_team_selection record;

  v_actor_member_profile_id uuid;
  v_change_type text;
  v_workflow text;

  v_is_superuser boolean := false;
  v_has_permission boolean := false;

  v_action text := 'no_action';
  v_result jsonb := '{}'::jsonb;
  v_context jsonb := coalesce(p_context, '{}'::jsonb);

  v_queued_count integer := 0;
  v_marker_result jsonb := '{}'::jsonb;
  v_preselect_result jsonb := '{}'::jsonb;

  v_already_reconciled boolean := false;
  v_allow_incomplete boolean := false;
begin
  if p_fixture_id is null then
    raise exception 'Fixture id is required.';
  end if;

  v_change_type := lower(nullif(btrim(coalesce(p_change_type, '')), ''));

  if v_change_type is null then
    raise exception 'Change type is required.';
  end if;

  if p_changed_by_member_profile_id is not null then
    v_actor_member_profile_id := p_changed_by_member_profile_id;
  else
    select public.my_member_profile_id()
    into v_actor_member_profile_id;
  end if;

  if v_actor_member_profile_id is null then
    raise exception 'A signed-in member profile is required.';
  end if;

  select
    f.id,
    f.club_id,
    f.requires_rsvp,
    f.competition_type_id,
    f.captain_member_profile_id,
    f.vice_captain_member_profile_id,
    ct.selection_mode,
    ct.uses_rinks,
    ct.is_internal
  into v_fixture
  from public.fixtures f
  left join public.competition_types ct
    on ct.id = f.competition_type_id
  where f.id = p_fixture_id;

  if not found then
    raise exception 'Fixture % was not found.', p_fixture_id;
  end if;

  v_workflow :=
    case
      when coalesce(v_fixture.selection_mode::text, '') = 'preselect'
        then 'preselect'
      when coalesce(v_fixture.selection_mode::text, '') = 'team'
        then 'team'
      when coalesce(v_fixture.selection_mode::text, '') = 'rsvp'
           or v_fixture.requires_rsvp = true
        then 'rsvp'
      when coalesce(v_fixture.selection_mode::text, '') in ('open_session', 'practice')
        then 'open_session'
      when coalesce(v_fixture.uses_rinks, true) = false
        then 'event'
      else 'unknown'
    end;

  select
    ts.id,
    ts.status::text as status
  into v_team_selection
  from public.team_selections ts
  where ts.fixture_id = p_fixture_id
  order by ts.created_at desc nulls last
  limit 1;

  select exists (
    select 1
    from public.app_superusers su
    where su.user_id = auth.uid()
  )
  into v_is_superuser;

  v_has_permission :=
    v_is_superuser
    or v_fixture.captain_member_profile_id = v_actor_member_profile_id
    or v_fixture.vice_captain_member_profile_id = v_actor_member_profile_id
    or exists (
      select 1
      from public.club_memberships cm
      where cm.club_id = v_fixture.club_id
        and cm.member_profile_id = v_actor_member_profile_id
        and cm.is_active = true
        and lower(cm.role::text) in ('admin', 'selector')
    );

  if not v_has_permission then
    raise exception 'You do not have permission to process post-publish communications for this fixture.';
  end if;

  v_already_reconciled :=
    lower(coalesce(v_context ->> 'already_reconciled', 'false')) in ('true', 't', 'yes', 'y', '1');

  v_allow_incomplete :=
    lower(coalesce(v_context ->> 'allow_incomplete', 'false')) in ('true', 't', 'yes', 'y', '1');

  /*
    Branch 1: fixture moved.

    This should only be called when the saved fixture start/end actually changed.
    It queues notifications for affected assigned members.
  */
  if v_change_type = 'fixture_moved' then
    if p_old_start_at is null then
      v_action := 'fixture_moved_missing_old_start_at';

      v_result := jsonb_build_object(
        'ok', false,
        'fixture_id', p_fixture_id,
        'workflow', v_workflow,
        'change_type', v_change_type,
        'action', v_action,
        'message', 'Old start time is required for fixture_moved communications.'
      );
    else
      v_queued_count := public.queue_fixture_moved_notifications(
        p_fixture_id,
        p_old_start_at,
        p_old_end_at
      );

      v_action := 'fixture_moved_notifications_queued';

      v_result := jsonb_build_object(
        'ok', true,
        'fixture_id', p_fixture_id,
        'workflow', v_workflow,
        'change_type', v_change_type,
        'action', v_action,
        'queued_notifications', v_queued_count,
        'message', 'Fixture moved notifications were queued.'
      );
    end if;

  /*
    Branch 2: marker request opened.

    This sends to the marker mailing list, duplicate-safe per marker_request_id/volunteer.
  */
  elsif v_change_type = 'marker_request_opened' then
    v_marker_result := public.queue_open_marker_request_communications(p_fixture_id);

    v_action := 'marker_request_communications_queued';

    v_result := jsonb_build_object(
      'ok', true,
      'fixture_id', p_fixture_id,
      'workflow', v_workflow,
      'change_type', v_change_type,
      'action', v_action,
      'marker_result', coalesce(v_marker_result, '{}'::jsonb),
      'message', 'Marker request communications were queued.'
    );

  /*
    Branch 3: published.

    For normal team publication, queue publication communications.
    For Pre-Select, reconcile selected players/markers using the preselect communication routine.

    This is intentionally not destructive. It does not delete/rebuild sent emails.
  */
  elsif v_change_type = 'published' then
    if v_team_selection.id is null then
      v_action := 'published_no_team_selection';

      v_result := jsonb_build_object(
        'ok', true,
        'fixture_id', p_fixture_id,
        'workflow', v_workflow,
        'change_type', v_change_type,
        'action', v_action,
        'message', 'No team selection exists for this published fixture.'
      );

    elsif coalesce(v_team_selection.status, '') <> 'published' then
      v_action := 'team_selection_not_published';

      v_result := jsonb_build_object(
        'ok', true,
        'fixture_id', p_fixture_id,
        'workflow', v_workflow,
        'change_type', v_change_type,
        'team_selection_id', v_team_selection.id,
        'team_selection_status', v_team_selection.status,
        'action', v_action,
        'message', 'Team selection is not published.'
      );

    elsif v_workflow = 'preselect' then
      v_preselect_result := public.reconcile_preselect_communications(p_fixture_id);

      v_action := 'preselect_published_reconciled';

      v_result := jsonb_build_object(
        'ok', true,
        'fixture_id', p_fixture_id,
        'workflow', v_workflow,
        'change_type', v_change_type,
        'team_selection_id', v_team_selection.id,
        'action', v_action,
        'preselect_result', coalesce(v_preselect_result, '{}'::jsonb),
        'message', 'Published Pre-Select communications were reconciled.'
      );

    elsif v_workflow = 'team' then
      v_queued_count := public.queue_team_publication_communications(
        p_fixture_id,
        v_team_selection.id,
        v_allow_incomplete
      );

      v_action := 'team_publication_communications_queued';

      v_result := jsonb_build_object(
        'ok', true,
        'fixture_id', p_fixture_id,
        'workflow', v_workflow,
        'change_type', v_change_type,
        'team_selection_id', v_team_selection.id,
        'action', v_action,
        'queued_notifications', v_queued_count,
        'allow_incomplete', v_allow_incomplete,
        'message', 'Team publication communications were queued.'
      );

    else
      v_action := 'published_workflow_no_action';

      v_result := jsonb_build_object(
        'ok', true,
        'fixture_id', p_fixture_id,
        'workflow', v_workflow,
        'change_type', v_change_type,
        'action', v_action,
        'message', 'No publication communication action is configured for this workflow.'
      );
    end if;

  /*
    Branch 4: preselect changed after publication.

    Important: save_preselect_fixture_state may already do this atomically.
    So Flutter can pass:
      p_context := '{"already_reconciled": true}'::jsonb
    to prevent doing it twice.
  */
  elsif v_change_type = 'preselect_changed' then
    if v_workflow <> 'preselect' then
      v_action := 'preselect_changed_wrong_workflow';

      v_result := jsonb_build_object(
        'ok', false,
        'fixture_id', p_fixture_id,
        'workflow', v_workflow,
        'change_type', v_change_type,
        'action', v_action,
        'message', 'preselect_changed was requested for a non-Pre-Select fixture.'
      );

    elsif v_already_reconciled then
      v_action := 'preselect_changed_already_reconciled';

      v_result := jsonb_build_object(
        'ok', true,
        'fixture_id', p_fixture_id,
        'workflow', v_workflow,
        'change_type', v_change_type,
        'action', v_action,
        'message', 'Pre-Select communications were already reconciled by the save operation.'
      );

    elsif v_team_selection.id is null or coalesce(v_team_selection.status, '') <> 'published' then
      v_action := 'preselect_changed_not_published';

      v_result := jsonb_build_object(
        'ok', true,
        'fixture_id', p_fixture_id,
        'workflow', v_workflow,
        'change_type', v_change_type,
        'team_selection_id', v_team_selection.id,
        'team_selection_status', v_team_selection.status,
        'action', v_action,
        'message', 'Pre-Select fixture is not published, so no post-publish communications were queued.'
      );

    else
      v_preselect_result := public.reconcile_preselect_communications(p_fixture_id);

      v_action := 'preselect_changed_reconciled';

      v_result := jsonb_build_object(
        'ok', true,
        'fixture_id', p_fixture_id,
        'workflow', v_workflow,
        'change_type', v_change_type,
        'team_selection_id', v_team_selection.id,
        'action', v_action,
        'preselect_result', coalesce(v_preselect_result, '{}'::jsonb),
        'message', 'Published Pre-Select communications were reconciled.'
      );
    end if;

  /*
    Branch 5: team selection changed after publication.

    This is deliberately conservative for now.
    Team delta communications need a real before/after snapshot before we email
    players who have been added, removed, promoted from reserve, etc.
  */
  elsif v_change_type = 'team_selection_changed' then
    v_action := 'team_selection_changed_audit_only';

    v_result := jsonb_build_object(
      'ok', true,
      'fixture_id', p_fixture_id,
      'workflow', v_workflow,
      'change_type', v_change_type,
      'team_selection_id', v_team_selection.id,
      'action', v_action,
      'message', 'Team selection change was audited. Delta communications are not enabled yet.'
    );

  /*
    Branch 6: ordinary fixture details changed.

    We are not emailing for every changed field yet.
    Later we can use p_context.changed_fields to decide if venue/time/dress code/etc.
    needs notification.
  */
  elsif v_change_type = 'fixture_details_changed' then
    v_action := 'fixture_details_changed_audit_only';

    v_result := jsonb_build_object(
      'ok', true,
      'fixture_id', p_fixture_id,
      'workflow', v_workflow,
      'change_type', v_change_type,
      'action', v_action,
      'changed_fields', coalesce(v_context -> 'changed_fields', '[]'::jsonb),
      'message', 'Fixture detail change was audited. No communications were queued.'
    );

  /*
    Branch 7: manual sync.

    Safe, non-destructive reconciliation. This is not the same as Repair Centre.
  */
  elsif v_change_type = 'manual_sync' then
    if v_workflow = 'preselect'
       and v_team_selection.id is not null
       and coalesce(v_team_selection.status, '') = 'published' then

      v_preselect_result := public.reconcile_preselect_communications(p_fixture_id);

      v_action := 'manual_preselect_sync';

      v_result := jsonb_build_object(
        'ok', true,
        'fixture_id', p_fixture_id,
        'workflow', v_workflow,
        'change_type', v_change_type,
        'team_selection_id', v_team_selection.id,
        'action', v_action,
        'preselect_result', coalesce(v_preselect_result, '{}'::jsonb),
        'message', 'Published Pre-Select communications were manually synchronised.'
      );

    else
      v_action := 'manual_sync_no_action';

      v_result := jsonb_build_object(
        'ok', true,
        'fixture_id', p_fixture_id,
        'workflow', v_workflow,
        'change_type', v_change_type,
        'team_selection_id', v_team_selection.id,
        'team_selection_status', v_team_selection.status,
        'action', v_action,
        'message', 'No manual communication sync action is configured for this fixture state.'
      );
    end if;

  /*
    Acceptance changes are handled by the trigger queue_team_acceptance_change().
    We fixed that trigger to coalesce repeated pending changes.
  */
  elsif v_change_type = 'acceptance_changed' then
    v_action := 'acceptance_changed_handled_by_trigger';

    v_result := jsonb_build_object(
      'ok', true,
      'fixture_id', p_fixture_id,
      'workflow', v_workflow,
      'change_type', v_change_type,
      'action', v_action,
      'message', 'Acceptance changes are handled by the team acceptance trigger.'
    );

  else
    v_action := 'unknown_change_type';

    v_result := jsonb_build_object(
      'ok', false,
      'fixture_id', p_fixture_id,
      'workflow', v_workflow,
      'change_type', v_change_type,
      'action', v_action,
      'message', 'Unknown post-publish change type.'
    );
  end if;

  insert into public.fixture_communication_audit (
    fixture_id,
    club_id,
    action,
    workflow,
    changed_by_member_profile_id,
    result
  )
  values (
    p_fixture_id,
    v_fixture.club_id,
    v_action,
    v_workflow,
    v_actor_member_profile_id,
    v_result
  );

  return v_result;
end;
$function$;

grant execute on function public.process_fixture_post_publish_changes(
  uuid,
  text,
  uuid,
  timestamptz,
  timestamptz,
  jsonb
)
to authenticated;