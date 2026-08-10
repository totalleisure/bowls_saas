CREATE OR REPLACE FUNCTION public.communications_fixture_status(p_fixture_id uuid)
 RETURNS TABLE(status text, next_action text, message text, progress integer, can_repair boolean, can_prepare boolean, can_send boolean, can_retry boolean, blocking_issues jsonb, diagnostics jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_team_selection_id uuid;
  v_selection_status text;
  v_selection_mode text := '';
  v_is_internal boolean := false;
  v_required_teams integer := 0;
  v_assigned_opponents integer := 0;
  v_required_markers integer := 0;
  v_assigned_markers integer := 0;
  v_open_marker_requests integer := 0;
  v_unresolved_marker_requirements integer := 0;
  v_active_selection_without_assignment integer := 0;
  v_assignment_without_active_selection integer := 0;
  v_role_mismatches integer := 0;

  v_required_positions integer := 0;
  v_selected_players integer := 0;
  v_selected_reserves integer := 0;
  v_assigned_players integer := 0;
  v_unallocated_players integer := 0;
  v_duplicate_assignments integer := 0;

  v_players_expected integer := 0;
  v_players_actual integer := 0;
  v_reserves_expected integer := 0;
  v_reserves_actual integer := 0;
  v_captains_expected integer := 0;
  v_captains_actual integer := 0;
  v_not_selected_expected integer := 0;
  v_not_selected_actual integer := 0;
  v_notifications_expected integer := 0;
  v_notifications_actual integer := 0;
  v_app_expected integer := 0;
  v_app_actual integer := 0;
  v_emails_expected integer := 0;
  v_emails_actual integer := 0;
  v_emails_sent_expected integer := 0;
  v_emails_sent_actual integer := 0;
  v_emails_failed_actual integer := 0;
  v_sheets_expected integer := 0;
  v_sheets_actual integer := 0;
  v_sheets_sent_expected integer := 0;
  v_sheets_sent_actual integer := 0;

  v_issues jsonb := '[]'::jsonb;
begin
  select
    lower(coalesce(ct.selection_mode::text, '')),
    coalesce(ct.is_internal, false)
  into
    v_selection_mode,
    v_is_internal
  from public.fixtures f
  left join public.competition_types ct
    on ct.id = f.competition_type_id
  where f.id = p_fixture_id;

  if not found then
    raise exception 'Fixture % was not found', p_fixture_id;
  end if;

  select ts.id, ts.status::text
  into v_team_selection_id, v_selection_status
  from public.team_selections ts
  where ts.fixture_id = p_fixture_id
  order by ts.created_at desc
  limit 1;

  select
    coalesce(sum(fr.players_per_rink), 0)::integer,
    count(*)::integer
  into
    v_required_positions,
    v_required_teams
  from public.fixture_rinks fr
  where fr.fixture_id = p_fixture_id;

  if v_team_selection_id is null then
    v_issues := v_issues || jsonb_build_array(
      'No team selection exists for this fixture.'
    );
  end if;

  if v_selection_mode = 'preselect' then
    select count(*)::integer
    into v_assigned_players
    from public.fixture_rink_assignments fra
    join public.fixture_rinks fr on fr.id = fra.fixture_rink_id
    where fra.fixture_id = p_fixture_id
      and fra.position between 1 and fr.players_per_rink;

    select count(*)::integer
    into v_assigned_opponents
    from public.fixture_rink_assignments fra
    join public.fixture_rinks fr on fr.id = fra.fixture_rink_id
    where fra.fixture_id = p_fixture_id
      and fra.position between 101 and (100 + fr.players_per_rink);

    select
      count(*) filter (
        where fr.marker_required = true
      )::integer,
      count(*) filter (
        where fr.marker_required = true
          and exists (
            select 1
            from public.fixture_rink_assignments fra
            where fra.fixture_rink_id = fr.id
              and fra.position = 201
              and fra.member_profile_id is not null
          )
      )::integer,
      count(*) filter (
        where fr.marker_required = true
          and not exists (
            select 1
            from public.fixture_rink_assignments fra
            where fra.fixture_rink_id = fr.id
              and fra.position = 201
              and fra.member_profile_id is not null
          )
          and exists (
            select 1
            from public.fixture_marker_requests fmr
            where fmr.fixture_rink_id = fr.id
              and fmr.status = 'open'
          )
      )::integer,
      count(*) filter (
        where fr.marker_required = true
          and not exists (
            select 1
            from public.fixture_rink_assignments fra
            where fra.fixture_rink_id = fr.id
              and fra.position = 201
              and fra.member_profile_id is not null
          )
          and not exists (
            select 1
            from public.fixture_marker_requests fmr
            where fmr.fixture_rink_id = fr.id
              and fmr.status = 'open'
          )
      )::integer
    into
      v_required_markers,
      v_assigned_markers,
      v_open_marker_requests,
      v_unresolved_marker_requirements
    from public.fixture_rinks fr
    where fr.fixture_id = p_fixture_id;

    select count(*)::integer
    into v_duplicate_assignments
    from (
      select fra.member_profile_id
      from public.fixture_rink_assignments fra
      where fra.fixture_id = p_fixture_id
        and fra.member_profile_id is not null
      group by fra.member_profile_id
      having count(*) > 1
    ) d;

    if v_team_selection_id is not null then
      select count(*)::integer
      into v_active_selection_without_assignment
      from public.team_selection_members tsm
      where tsm.team_selection_id = v_team_selection_id
        and tsm.is_selected = true
        and not exists (
          select 1
          from public.fixture_rink_assignments fra
          where fra.fixture_id = p_fixture_id
            and fra.member_profile_id = tsm.member_profile_id
        );

      select count(*)::integer
      into v_assignment_without_active_selection
      from public.fixture_rink_assignments fra
      where fra.fixture_id = p_fixture_id
        and fra.member_profile_id is not null
        and not exists (
          select 1
          from public.team_selection_members tsm
          where tsm.team_selection_id = v_team_selection_id
            and tsm.member_profile_id = fra.member_profile_id
            and tsm.is_selected = true
        );

      select count(*)::integer
      into v_role_mismatches
      from public.fixture_rink_assignments fra
      join public.fixture_rinks fr on fr.id = fra.fixture_rink_id
      join public.team_selection_members tsm
        on tsm.team_selection_id = v_team_selection_id
       and tsm.member_profile_id = fra.member_profile_id
       and tsm.is_selected = true
      where fra.fixture_id = p_fixture_id
        and lower(tsm.role::text) <>
          case
            when fra.position = 201 then 'marker'
            when fra.position between 101 and (100 + fr.players_per_rink)
              then 'opponent'
            else 'player'
          end;
    end if;

    if v_required_positions > 0 and v_assigned_players < v_required_positions then
      v_issues := v_issues || jsonb_build_array(
        format(
          '%s player position(s) are required, but only %s are filled.',
          v_required_positions,
          v_assigned_players
        )
      );
    end if;

    if v_unresolved_marker_requirements > 0 then
      v_issues := v_issues || jsonb_build_array(
        format(
          '%s rink marker requirement(s) have neither an assigned marker nor an open volunteer request.',
          v_unresolved_marker_requirements
        )
      );
    end if;

    if v_duplicate_assignments > 0 then
      v_issues := v_issues || jsonb_build_array(
        format(
          '%s member(s) have been assigned to more than one pre-select position.',
          v_duplicate_assignments
        )
      );
    end if;

    if v_active_selection_without_assignment > 0 then
      v_issues := v_issues || jsonb_build_array(
        format(
          '%s selected member record(s) are not attached to a current player, opponent or marker position.',
          v_active_selection_without_assignment
        )
      );
    end if;

    if v_assignment_without_active_selection > 0 then
      v_issues := v_issues || jsonb_build_array(
        format(
          '%s current fixture assignment(s) have no active selection record.',
          v_assignment_without_active_selection
        )
      );
    end if;

    if v_role_mismatches > 0 then
      v_issues := v_issues || jsonb_build_array(
        format(
          '%s active selection record(s) have a role that does not match the current pre-select position.',
          v_role_mismatches
        )
      );
    end if;

  else
    if v_team_selection_id is not null then
      select
        count(*) filter (
          where tsm.is_selected = true
            and lower(tsm.role::text) = 'player'
        )::integer,
        count(*) filter (
          where tsm.is_selected = true
            and lower(tsm.role::text) = 'reserve'
        )::integer
      into v_selected_players, v_selected_reserves
      from public.team_selection_members tsm
      where tsm.team_selection_id = v_team_selection_id;

      select count(distinct fra.member_profile_id)::integer
      into v_assigned_players
      from public.fixture_rink_assignments fra
      join public.fixture_rinks fr on fr.id = fra.fixture_rink_id
      where fra.fixture_id = p_fixture_id
        and fra.position between 1 and fr.players_per_rink;

      select count(*)::integer
      into v_unallocated_players
      from public.team_selection_members tsm
      where tsm.team_selection_id = v_team_selection_id
        and tsm.is_selected = true
        and lower(tsm.role::text) = 'player'
        and not exists (
          select 1
          from public.fixture_rink_assignments fra
          join public.fixture_rinks fr on fr.id = fra.fixture_rink_id
          where fra.fixture_id = p_fixture_id
            and fra.member_profile_id = tsm.member_profile_id
            and fra.position between 1 and fr.players_per_rink
        );

      select count(*)::integer
      into v_duplicate_assignments
      from (
        select fra.member_profile_id
        from public.fixture_rink_assignments fra
        join public.fixture_rinks fr on fr.id = fra.fixture_rink_id
        where fra.fixture_id = p_fixture_id
          and fra.position between 1 and fr.players_per_rink
        group by fra.member_profile_id
        having count(*) > 1
      ) d;
    end if;

    if v_required_positions > 0 and v_selected_players < v_required_positions then
      v_issues := v_issues || jsonb_build_array(
        format(
          '%s player position(s) are required, but only %s player(s) are selected.',
          v_required_positions,
          v_selected_players
        )
      );
    end if;

    if v_required_positions > 0 and v_selected_players > v_required_positions then
      v_issues := v_issues || jsonb_build_array(
        format(
          'Too many players have been selected. %s player position(s) are required, but %s player(s) are selected. Return the unallocated player(s) to the available pool.',
          v_required_positions,
          v_selected_players
        )
      );
    end if;

    if v_required_positions > 0 and v_assigned_players < v_required_positions then
      v_issues := v_issues || jsonb_build_array(
        format(
          '%s player position(s) are required, but only %s are allocated.',
          v_required_positions,
          v_assigned_players
        )
      );
    end if;

    if v_unallocated_players > 0 then
      v_issues := v_issues || jsonb_build_array(
        format(
          '%s selected player(s) have not been allocated to a team position.',
          v_unallocated_players
        )
      );
    end if;

    if v_duplicate_assignments > 0 then
      v_issues := v_issues || jsonb_build_array(
        format(
          '%s player(s) have been allocated more than once.',
          v_duplicate_assignments
        )
      );
    end if;
  end if;

  if coalesce(v_selection_status, 'draft') <> 'published' then
    if jsonb_array_length(v_issues) > 0 then
      return query
      select
        'draft_incomplete'::text,
        'open_fixture'::text,
        'This fixture is still being prepared. Complete the team details before publication.'::text,
        20,
        false,
        false,
        false,
        false,
        v_issues,
        jsonb_build_object(
          'team_selection_id', v_team_selection_id,
          'selection_status', coalesce(v_selection_status, 'missing'),
          'selection_mode', v_selection_mode,
          'is_internal', v_is_internal,
          'required_teams', v_required_teams,
          'assigned_opponents', v_assigned_opponents,
          'required_markers', v_required_markers,
          'assigned_markers', v_assigned_markers,
          'open_marker_requests', v_open_marker_requests,
          'unresolved_marker_requirements', v_unresolved_marker_requirements,
          'active_selection_without_assignment', v_active_selection_without_assignment,
          'assignment_without_active_selection', v_assignment_without_active_selection,
          'role_mismatches', v_role_mismatches,
          'required_positions', v_required_positions,
          'selected_players', v_selected_players,
          'selected_reserves', v_selected_reserves,
          'assigned_players', v_assigned_players,
          'unallocated_players', v_unallocated_players,
          'duplicate_assignments', v_duplicate_assignments
        );
    else
      return query
      select
        'ready_to_publish'::text,
        'none'::text,
        'The fixture setup is complete. Communications will be prepared when it is published.'::text,
        40,
        false,
        false,
        false,
        false,
        '[]'::jsonb,
        jsonb_build_object(
          'team_selection_id', v_team_selection_id,
          'selection_status', coalesce(v_selection_status, 'draft'),
          'selection_mode', v_selection_mode,
          'is_internal', v_is_internal,
          'required_teams', v_required_teams,
          'assigned_opponents', v_assigned_opponents,
          'required_markers', v_required_markers,
          'assigned_markers', v_assigned_markers,
          'open_marker_requests', v_open_marker_requests,
          'unresolved_marker_requirements', v_unresolved_marker_requirements,
          'required_positions', v_required_positions,
          'selected_players', v_selected_players,
          'selected_reserves', v_selected_reserves,
          'assigned_players', v_assigned_players,
          'unallocated_players', v_unallocated_players,
          'duplicate_assignments', v_duplicate_assignments
        );
    end if;
    return;
  end if;

  -- A published fixture may be incomplete and still have valid current
  -- recipients. Do not stop here: communications health must be checked
  -- independently so missing queue rows can still be repaired.

  select
    coalesce(max(h.expected) filter (where h.item = 'Playing players'), 0),
    coalesce(max(h.actual) filter (where h.item = 'Playing players'), 0),
    coalesce(max(h.expected) filter (where h.item = 'Reserves'), 0),
    coalesce(max(h.actual) filter (where h.item = 'Reserves'), 0),
    coalesce(max(h.expected) filter (where h.item = 'Captain/Vice copies'), 0),
    coalesce(max(h.actual) filter (where h.item = 'Captain/Vice copies'), 0),
    coalesce(max(h.expected) filter (where h.item = 'Not selected'), 0),
    coalesce(max(h.actual) filter (where h.item = 'Not selected'), 0),
    coalesce(max(h.expected) filter (where h.item = 'Notifications queued'), 0),
    coalesce(max(h.actual) filter (where h.item = 'Notifications queued'), 0),
    coalesce(max(h.expected) filter (where h.item = 'App notifications created'), 0),
    coalesce(max(h.actual) filter (where h.item = 'App notifications created'), 0),
    coalesce(max(h.expected) filter (where h.item = 'Emails queued'), 0),
    coalesce(max(h.actual) filter (where h.item = 'Emails queued'), 0),
    coalesce(max(h.expected) filter (where h.item = 'Emails sent'), 0),
    coalesce(max(h.actual) filter (where h.item = 'Emails sent'), 0),
    coalesce(max(h.actual) filter (where h.item = 'Emails failed'), 0),
    coalesce(max(h.expected) filter (where h.item = 'Team sheets attached'), 0),
    coalesce(max(h.actual) filter (where h.item = 'Team sheets attached'), 0),
    coalesce(max(h.expected) filter (where h.item = 'Team sheets sent'), 0),
    coalesce(max(h.actual) filter (where h.item = 'Team sheets sent'), 0)
  into
    v_players_expected,
    v_players_actual,
    v_reserves_expected,
    v_reserves_actual,
    v_captains_expected,
    v_captains_actual,
    v_not_selected_expected,
    v_not_selected_actual,
    v_notifications_expected,
    v_notifications_actual,
    v_app_expected,
    v_app_actual,
    v_emails_expected,
    v_emails_actual,
    v_emails_sent_expected,
    v_emails_sent_actual,
    v_emails_failed_actual,
    v_sheets_expected,
    v_sheets_actual,
    v_sheets_sent_expected,
    v_sheets_sent_actual
  from public.communications_health_check(p_fixture_id) h;

  if v_players_actual < v_players_expected
     or v_reserves_actual < v_reserves_expected
     or v_captains_actual < v_captains_expected
     or v_not_selected_actual < v_not_selected_expected
     or v_notifications_actual < v_notifications_expected then
    return query
    select
      'communications_repair_required'::text,
      'repair_communications'::text,
      'Some fixture communication records need attention.'::text,
      55,
      true,
      false,
      false,
      false,
      v_issues,
      jsonb_build_object(
        'team_selection_id', v_team_selection_id,
        'selection_mode', v_selection_mode,
        'is_internal', v_is_internal,
        'notifications_expected', v_notifications_expected,
        'notifications_actual', v_notifications_actual,
        'emails_expected', v_emails_expected,
        'emails_actual', v_emails_actual,
        'team_sheets_expected', v_sheets_expected,
        'team_sheets_actual', v_sheets_actual
      )
    return;
  end if;

  if v_app_actual < v_app_expected or v_emails_actual < v_emails_expected then
    return query
    select
      'preparation_required'::text,
      'prepare_messages'::text,
      'Fixture messages are being prepared.'::text,
      65,
      false,
      true,
      false,
      false,
      v_issues,
      jsonb_build_object(
        'team_selection_id', v_team_selection_id,
        'selection_mode', v_selection_mode,
        'is_internal', v_is_internal,        
        'app_notifications_expected', v_app_expected,
        'app_notifications_actual', v_app_actual,
        'emails_expected', v_emails_expected,
        'emails_actual', v_emails_actual
      );
    return;
  end if;

  if v_sheets_actual < v_sheets_expected then
    return query
    select
      'team_sheets_required'::text,
      'prepare_team_sheets'::text,
      'Fixture messages are being prepared.'::text,
      75,
      false,
      true,
      false,
      false,
      v_issues,
      jsonb_build_object(
        'team_selection_id', v_team_selection_id,
        'selection_mode', v_selection_mode,
        'is_internal', v_is_internal,        
        'team_sheets_expected', v_sheets_expected,
        'team_sheets_actual', v_sheets_actual
      );
    return;
  end if;

  if v_emails_failed_actual > 0 then
    return query
    select
      'email_failures'::text,
      'retry_failed_emails'::text,
      format(
        '%s fixture email(s) could not be sent.',
        v_emails_failed_actual
      ),
      85,
      false,
      false,
      false,
      true,
      v_issues,
      jsonb_build_object(
        'team_selection_id', v_team_selection_id,
        'selection_mode', v_selection_mode,
        'is_internal', v_is_internal,        
        'emails_failed', v_emails_failed_actual
      );
    return;
  end if;

  if v_emails_sent_actual < v_emails_sent_expected
     or v_sheets_sent_actual < v_sheets_sent_expected then
    return query
    select
      'ready_to_send'::text,
      'send_emails'::text,
      'Fixture messages have been prepared. Emails will be sent shortly.'::text,
      90,
      false,
      false,
      true,
      false,
      v_issues,
      jsonb_build_object(
        'team_selection_id', v_team_selection_id,
        'selection_mode', v_selection_mode,
        'is_internal', v_is_internal,        
        'emails_expected', v_emails_sent_expected,
        'emails_sent', v_emails_sent_actual,
        'team_sheets_expected', v_sheets_sent_expected,
        'team_sheets_sent', v_sheets_sent_actual
      );
    return;
  end if;

  if jsonb_array_length(v_issues) > 0 then
    return query
    select
      'fixture_correction_required'::text,
      'open_fixture'::text,
      'Communications are complete, but the fixture setup still needs attention.'::text,
      95,
      false,
      false,
      false,
      false,
      v_issues,
      jsonb_build_object(
        'team_selection_id', v_team_selection_id,
        'selection_status', v_selection_status,
        'selection_mode', v_selection_mode,
        'communications_complete', true
      );
    return;
  end if;

  return query
  select
    'communications_complete'::text,
    'complete'::text,
    'All expected notifications, emails and team sheets have been completed.'::text,
    100,
    false,
    false,
    false,
    false,
    '[]'::jsonb,
    jsonb_build_object(
      'team_selection_id', v_team_selection_id,
      'selection_mode', v_selection_mode,
      'is_internal', v_is_internal,
      'emails_sent', v_emails_sent_actual,
      'team_sheets_sent', v_sheets_sent_actual
    );
end;
$function$