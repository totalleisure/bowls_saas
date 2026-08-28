CREATE OR REPLACE FUNCTION public.communications_health_check(p_fixture_id uuid)
 RETURNS TABLE(item text, expected integer, actual integer, status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_team_selection_id uuid;
  v_selection_mode text := '';
  v_is_rescheduled boolean := false;
  v_source_fixture_id uuid;
begin
  select
    ts.id,
    lower(coalesce(ct.selection_mode::text, '')),
    f.rescheduled_from_fixture_id is not null,
    f.rescheduled_from_fixture_id
  into
    v_team_selection_id,
    v_selection_mode,
    v_is_rescheduled,
    v_source_fixture_id
  from public.fixtures f
  left join public.competition_types ct
    on ct.id = f.competition_type_id
  left join lateral (
    select x.id
    from public.team_selections x
    where x.fixture_id = f.id
    order by x.created_at desc
    limit 1
  ) ts on true
  where f.id = p_fixture_id;

  if not found then
    raise exception 'Fixture % was not found', p_fixture_id;
  end if;

  if v_team_selection_id is null then
    raise exception 'No team selection found for fixture %', p_fixture_id;
  end if;

  if v_is_rescheduled then
    return query
    with
    managers as (
      select f.captain_member_profile_id as member_profile_id
      from public.fixtures f
      where f.id = p_fixture_id
        and f.captain_member_profile_id is not null

      union

      select f.vice_captain_member_profile_id
      from public.fixtures f
      where f.id = p_fixture_id
        and f.vice_captain_member_profile_id is not null
    ),
    selected_members as (
      select distinct tsm.member_profile_id
      from public.team_selection_members tsm
      where tsm.team_selection_id = v_team_selection_id
        and tsm.member_profile_id is not null
        and coalesce(tsm.is_selected, false) = true
        and not exists (
          select 1
          from managers m
          where m.member_profile_id = tsm.member_profile_id
        )
    ),
    eligible_team_members as (
      select distinct tm.member_profile_id
      from public.fixtures f
      join public.team_members tm
        on tm.team_id = f.team_id
       and tm.is_active = true
      where f.id = p_fixture_id
        and f.team_id is not null
    ),
    eligible_rsvp_members as (
      select distinct fr.member_profile_id
      from public.fixtures f
      join public.fixture_rsvps fr
        on fr.fixture_id = v_source_fixture_id
      join public.club_memberships cm
        on cm.club_id = f.club_id
       and cm.member_profile_id = fr.member_profile_id
       and cm.is_active = true
      where f.id = p_fixture_id
        and f.team_id is null
        and fr.status::text in ('yes', 'maybe')
    ),
    availability_members as (
      select member_profile_id from eligible_team_members
      union
      select member_profile_id from eligible_rsvp_members
    ),
    intended_recipients as (
      select
        m.member_profile_id,
        'manager'::text as precedence_kind
      from managers m

      union all

      select
        s.member_profile_id,
        'selected'::text
      from selected_members s

      union all

      select
        a.member_profile_id,
        'availability'::text
      from availability_members a
      where not exists (
        select 1 from managers m
        where m.member_profile_id = a.member_profile_id
      )
      and not exists (
        select 1 from selected_members s
        where s.member_profile_id = a.member_profile_id
      )
    ),
    classified_recipients as (
      select
        ir.member_profile_id,
        case
          when exists (
            select 1
            from public.fixture_rink_assignments fra
            where fra.fixture_id = p_fixture_id
              and fra.member_profile_id = ir.member_profile_id
              and fra.position = 201
          ) then 'marker'
          when exists (
            select 1
            from public.fixture_rink_assignments fra
            join public.fixture_rinks fr on fr.id = fra.fixture_rink_id
            where fra.fixture_id = p_fixture_id
              and fra.member_profile_id = ir.member_profile_id
              and fra.position between 101 and (100 + fr.players_per_rink)
          ) then 'opponent'
          when exists (
            select 1
            from public.fixture_rink_assignments fra
            join public.fixture_rinks fr on fr.id = fra.fixture_rink_id
            where fra.fixture_id = p_fixture_id
              and fra.member_profile_id = ir.member_profile_id
              and fra.position between 1 and fr.players_per_rink
          ) then 'player'
          when exists (
            select 1
            from public.team_selection_members tsm
            where tsm.team_selection_id = v_team_selection_id
              and tsm.member_profile_id = ir.member_profile_id
              and coalesce(tsm.is_selected, false) = true
              and lower(tsm.role::text) = 'reserve'
          ) then 'reserve'
          when ir.precedence_kind = 'manager' then 'captain'
          else 'not_selected'
        end as recipient_kind
      from intended_recipients ir
    ),
    delivery_status as (
      select
        cr.member_profile_id,
        cr.recipient_kind,
        nullif(btrim(mp.email_address), '') as email_address,
        exists (
          select 1
          from public.notification_queue nq
          where nq.fixture_id = p_fixture_id
            and nq.team_selection_id = v_team_selection_id
            and nq.target_member_profile_id = cr.member_profile_id
            and nq.status <> 'cancelled'
            and (
              nq.event_type in (
                'fixture_rescheduled_manager',
                'fixture_rescheduled_selected',
                'fixture_rescheduled_availability'
              )
              or (cr.recipient_kind in ('player', 'opponent', 'marker')
                  and nq.event_type = 'fixture_selected')
              or (cr.recipient_kind = 'player'
                  and nq.event_type = 'team_published_player')
              or (cr.recipient_kind = 'reserve'
                  and nq.event_type = 'team_published_reserve')
              or (cr.recipient_kind = 'captain'
                  and nq.event_type in ('team_published_captain', 'team_published_vice'))
              or (cr.recipient_kind = 'not_selected'
                  and nq.event_type in (
                    'team_published_not_selected',
                    'team_published_incomplete_request'
                  ))
            )
        ) as queue_exists,
        exists (
          select 1
          from public.app_notifications an
          where an.fixture_id = p_fixture_id
            and an.team_selection_id = v_team_selection_id
            and an.member_profile_id = cr.member_profile_id
            and (
              an.type in (
                'fixture_rescheduled_manager',
                'fixture_rescheduled_selected',
                'fixture_rescheduled_availability'
              )
              or (cr.recipient_kind in ('player', 'opponent', 'marker')
                  and an.type = 'fixture_selected')
              or (cr.recipient_kind = 'player'
                  and an.type = 'team_published_player')
              or (cr.recipient_kind = 'reserve'
                  and an.type = 'team_published_reserve')
              or (cr.recipient_kind = 'captain'
                  and an.type in ('team_published_captain', 'team_published_vice'))
              or (cr.recipient_kind = 'not_selected'
                  and an.type in (
                    'team_published_not_selected',
                    'team_published_incomplete_request'
                  ))
            )
        ) as app_exists,
        exists (
          select 1
          from public.email_queue eq
          where eq.fixture_id = p_fixture_id
            and eq.team_selection_id = v_team_selection_id
            and eq.member_profile_id = cr.member_profile_id
            and eq.status <> 'cancelled'
            and (
              eq.event_type in (
                'fixture_rescheduled_manager',
                'fixture_rescheduled_selected',
                'fixture_rescheduled_availability'
              )
              or (cr.recipient_kind in ('player', 'opponent', 'marker')
                  and eq.event_type = 'fixture_selected')
              or (cr.recipient_kind = 'player'
                  and eq.event_type = 'team_published_player')
              or (cr.recipient_kind = 'reserve'
                  and eq.event_type = 'team_published_reserve')
              or (cr.recipient_kind = 'captain'
                  and eq.event_type in ('team_published_captain', 'team_published_vice'))
              or (cr.recipient_kind = 'not_selected'
                  and eq.event_type in (
                    'team_published_not_selected',
                    'team_published_incomplete_request'
                  ))
            )
        ) as email_exists,
        exists (
          select 1
          from public.email_queue eq
          where eq.fixture_id = p_fixture_id
            and eq.team_selection_id = v_team_selection_id
            and eq.member_profile_id = cr.member_profile_id
            and eq.status = 'sent'
            and eq.event_type in (
              'fixture_rescheduled_manager',
              'fixture_rescheduled_selected',
              'fixture_rescheduled_availability',
              'fixture_selected',
              'team_published_player',
              'team_published_reserve',
              'team_published_captain',
              'team_published_vice',
              'team_published_not_selected',
              'team_published_incomplete_request'
            )
        ) as email_sent,
        exists (
          select 1
          from public.email_queue eq
          where eq.fixture_id = p_fixture_id
            and eq.team_selection_id = v_team_selection_id
            and eq.member_profile_id = cr.member_profile_id
            and eq.status = 'failed'
            and eq.event_type in (
              'fixture_rescheduled_manager',
              'fixture_rescheduled_selected',
              'fixture_rescheduled_availability',
              'fixture_selected',
              'team_published_player',
              'team_published_reserve',
              'team_published_captain',
              'team_published_vice',
              'team_published_not_selected',
              'team_published_incomplete_request'
            )
        ) as email_failed
      from classified_recipients cr
      join public.member_profiles mp on mp.id = cr.member_profile_id
    ),
    counts as (
      select
        count(*) filter (where recipient_kind = 'player')::integer as players_expected,
        count(*) filter (where recipient_kind = 'player' and queue_exists)::integer as players_actual,
        count(*) filter (where recipient_kind = 'opponent')::integer as opponents_expected,
        count(*) filter (where recipient_kind = 'opponent' and queue_exists)::integer as opponents_actual,
        count(*) filter (where recipient_kind = 'marker')::integer as markers_expected,
        count(*) filter (where recipient_kind = 'marker' and queue_exists)::integer as markers_actual,
        count(*) filter (where recipient_kind = 'reserve')::integer as reserves_expected,
        count(*) filter (where recipient_kind = 'reserve' and queue_exists)::integer as reserves_actual,
        count(*) filter (where recipient_kind = 'captain')::integer as captains_expected,
        count(*) filter (where recipient_kind = 'captain' and queue_exists)::integer as captains_actual,
        count(*) filter (where recipient_kind = 'not_selected')::integer as not_selected_expected,
        count(*) filter (where recipient_kind = 'not_selected' and queue_exists)::integer as not_selected_actual,
        count(*)::integer as notifications_expected,
        count(*) filter (where queue_exists)::integer as notifications_actual,
        count(*)::integer as app_expected,
        count(*) filter (where app_exists)::integer as app_actual,
        count(*) filter (where email_address is not null)::integer as emails_expected,
        count(*) filter (where email_address is not null and email_exists)::integer as emails_actual,
        count(*) filter (where email_address is not null and email_sent)::integer as emails_sent_actual,
        count(*) filter (where email_address is not null and email_failed)::integer as emails_failed_actual
      from delivery_status
    ),
    rows as (
      select 1 sort_order, 'Playing players'::text item,
        players_expected expected, players_actual actual from counts
      union all select 2, 'Opponents', opponents_expected, opponents_actual from counts
      union all select 3, 'Named markers', markers_expected, markers_actual from counts
      union all select 4, 'Marker volunteers', 0, 0
      union all select 5, 'Reserves', reserves_expected, reserves_actual from counts
      union all select 6, 'Captain/Vice copies', captains_expected, captains_actual from counts
      union all select 7, 'Not selected', not_selected_expected, not_selected_actual from counts
      union all select 8, 'Notifications queued', notifications_expected, notifications_actual from counts
      union all select 9, 'App notifications created', app_expected, app_actual from counts
      union all select 10, 'Emails queued', emails_expected, emails_actual from counts
      union all select 11, 'Emails sent', emails_expected, emails_sent_actual from counts
      union all select 12, 'Emails failed', 0, emails_failed_actual from counts
      union all select 13, 'Team sheets required', 0, 0
      union all select 14, 'Team sheets attached', 0, 0
      union all select 15, 'Team sheets sent', 0, 0
    )
    select
      rows.item,
      rows.expected,
      rows.actual,
      case
        when rows.item = 'Emails failed'
          then case when rows.actual = 0 then 'OK' else 'CHECK' end
        when rows.actual >= rows.expected then 'OK'
        else 'CHECK'
      end
    from rows
    order by rows.sort_order;

    return;
  end if;

  if v_selection_mode = 'preselect' then
    return query
    with
    current_assignments as (
      select distinct
        fra.member_profile_id,
        fr.fixture_rink_no as team_no,
        fra.position,
        case
          when fra.position = 201 then 'marker'
          when fra.position between 101 and (100 + fr.players_per_rink)
            then 'opponent'
          else 'player'
        end as recipient_kind
      from public.fixture_rink_assignments fra
      join public.fixture_rinks fr
        on fr.id = fra.fixture_rink_id
      where fra.fixture_id = p_fixture_id
        and fra.member_profile_id is not null
        and (
          fra.position between 1 and fr.players_per_rink
          or fra.position between 101 and (100 + fr.players_per_rink)
          or fra.position = 201
        )
    ),
    open_marker_requests as (
      select
        mr.id as marker_request_id,
        mr.requested_at,
        fr.fixture_rink_no as team_no,
        vt.mailing_list_id
      from public.fixture_marker_requests mr
      join public.fixture_rinks fr
        on fr.id = mr.fixture_rink_id
      join public.fixtures f
        on f.id = fr.fixture_id
      join public.volunteer_tasks vt
        on vt.club_id = f.club_id
       and vt.task_code = 'marker'
       and vt.is_active = true
      join public.mailing_lists ml
        on ml.id = vt.mailing_list_id
       and ml.club_id = vt.club_id
       and ml.is_active = true
      where fr.fixture_id = p_fixture_id
        and mr.status = 'open'
    ),
    current_marker_recipients as (
      select distinct
        omr.marker_request_id,
        omr.requested_at,
        omr.team_no,
        mlm.member_profile_id
      from open_marker_requests omr
      join public.mailing_list_members mlm
        on mlm.mailing_list_id = omr.mailing_list_id
       and mlm.is_active = true
      join public.mailing_lists ml
        on ml.id = mlm.mailing_list_id
      join public.club_memberships cm
        on cm.club_id = ml.club_id
       and cm.member_profile_id = mlm.member_profile_id
       and cm.is_active = true
    ),
    expected_deliveries as (
      select
        'fixture_selected'::text as event_type,
        ca.recipient_kind,
        ca.member_profile_id,
        ca.team_no,
        ca.position,
        null::uuid as marker_request_id,
        null::timestamptz as request_started_at
      from current_assignments ca

      union all

      select
        'marker_request_opened'::text,
        'marker_volunteer'::text,
        cmr.member_profile_id,
        cmr.team_no,
        null::integer,
        cmr.marker_request_id,
        cmr.requested_at
      from current_marker_recipients cmr
    ),
    delivery_status as (
      select
        ed.*,
        nullif(btrim(mp.email_address), '') as email_address,

        case
          when ed.event_type = 'fixture_selected' then exists (
            select 1
            from public.notification_queue nq
            where nq.fixture_id = p_fixture_id
              and nq.team_selection_id = v_team_selection_id
              and nq.event_type = 'fixture_selected'
              and nq.target_member_profile_id = ed.member_profile_id
              and nq.status <> 'cancelled'
              and (
                nullif(nq.payload ->> 'position', '') is null
                or nq.payload ->> 'position' = ed.position::text
              )
              and (
                nullif(nq.payload ->> 'team_no', '') is null
                or nq.payload ->> 'team_no' = ed.team_no::text
              )
          )
          else exists (
            select 1
            from public.notification_queue nq
            where nq.fixture_id = p_fixture_id
              and nq.event_type = 'marker_request_opened'
              and nq.target_member_profile_id = ed.member_profile_id
              and nq.status <> 'cancelled'
              and nq.payload ->> 'marker_request_id'
                    = ed.marker_request_id::text
          )
        end as queue_exists,

        case
          when ed.event_type = 'fixture_selected' then exists (
            select 1
            from public.app_notifications an
            where an.fixture_id = p_fixture_id
              and an.team_selection_id = v_team_selection_id
              and an.type = 'fixture_selected'
              and an.member_profile_id = ed.member_profile_id
          )
          else exists (
            select 1
            from public.app_notifications an
            where an.fixture_id = p_fixture_id
              and an.type = 'marker_request_opened'
              and an.member_profile_id = ed.member_profile_id
              and an.data ->> 'marker_request_id'
                    = ed.marker_request_id::text
          )
        end as app_exists,

        case
          when ed.event_type = 'fixture_selected' then exists (
            select 1
            from public.email_queue eq
            where eq.fixture_id = p_fixture_id
              and eq.team_selection_id = v_team_selection_id
              and eq.event_type = 'fixture_selected'
              and eq.member_profile_id = ed.member_profile_id
              and eq.status <> 'cancelled'
          )
          else exists (
            select 1
            from public.email_queue eq
            where eq.fixture_id = p_fixture_id
              and eq.event_type = 'marker_request_opened'
              and eq.member_profile_id = ed.member_profile_id
              and eq.status <> 'cancelled'
              and eq.created_at >= ed.request_started_at
          )
        end as email_exists,

        case
          when ed.event_type = 'fixture_selected' then exists (
            select 1
            from public.email_queue eq
            where eq.fixture_id = p_fixture_id
              and eq.team_selection_id = v_team_selection_id
              and eq.event_type = 'fixture_selected'
              and eq.member_profile_id = ed.member_profile_id
              and eq.status = 'sent'
          )
          else exists (
            select 1
            from public.email_queue eq
            where eq.fixture_id = p_fixture_id
              and eq.event_type = 'marker_request_opened'
              and eq.member_profile_id = ed.member_profile_id
              and eq.created_at >= ed.request_started_at
              and eq.status = 'sent'
          )
        end as email_sent,

        case
          when ed.event_type = 'fixture_selected' then coalesce((
            select eq.status = 'failed'
            from public.email_queue eq
            where eq.fixture_id = p_fixture_id
              and eq.team_selection_id = v_team_selection_id
              and eq.event_type = 'fixture_selected'
              and eq.member_profile_id = ed.member_profile_id
            order by eq.created_at desc
            limit 1
          ), false)
          else coalesce((
            select eq.status = 'failed'
            from public.email_queue eq
            where eq.fixture_id = p_fixture_id
              and eq.event_type = 'marker_request_opened'
              and eq.member_profile_id = ed.member_profile_id
              and eq.created_at >= ed.request_started_at
            order by eq.created_at desc
            limit 1
          ), false)
        end as latest_email_failed
      from expected_deliveries ed
      join public.member_profiles mp
        on mp.id = ed.member_profile_id
    ),
    counts as (
      select
        count(*) filter (
          where recipient_kind = 'player'
        )::integer as players_expected,
        count(*) filter (
          where recipient_kind = 'player'
            and queue_exists
        )::integer as players_actual,

        count(*) filter (
          where recipient_kind = 'opponent'
        )::integer as opponents_expected,
        count(*) filter (
          where recipient_kind = 'opponent'
            and queue_exists
        )::integer as opponents_actual,

        count(*) filter (
          where recipient_kind = 'marker'
        )::integer as named_markers_expected,
        count(*) filter (
          where recipient_kind = 'marker'
            and queue_exists
        )::integer as named_markers_actual,

        count(*) filter (
          where recipient_kind = 'marker_volunteer'
        )::integer as marker_volunteers_expected,
        count(*) filter (
          where recipient_kind = 'marker_volunteer'
            and queue_exists
        )::integer as marker_volunteers_actual,

        count(*)::integer as notifications_expected,
        count(*) filter (
          where queue_exists
        )::integer as notifications_actual,

        count(*)::integer as app_expected,
        count(*) filter (
          where app_exists
        )::integer as app_actual,

        count(*) filter (
          where email_address is not null
        )::integer as emails_expected,
        count(*) filter (
          where email_address is not null
            and email_exists
        )::integer as emails_actual,

        count(*) filter (
          where email_address is not null
            and email_sent
        )::integer as emails_sent_actual,

        count(*) filter (
          where email_address is not null
            and latest_email_failed
        )::integer as emails_failed_actual
      from delivery_status
    ),
    rows as (
      select
        1 as sort_order,
        'Playing players'::text as item,
        players_expected as expected,
        players_actual as actual
      from counts

      union all
      select 2, 'Opponents', opponents_expected, opponents_actual
      from counts

      union all
      select 3, 'Named markers', named_markers_expected, named_markers_actual
      from counts

      union all
      select 4, 'Marker volunteers',
        marker_volunteers_expected, marker_volunteers_actual
      from counts

      union all
      select 5, 'Reserves', 0, 0

      union all
      select 6, 'Captain/Vice copies', 0, 0

      union all
      select 7, 'Not selected', 0, 0

      union all
      select 8, 'Notifications queued',
        notifications_expected, notifications_actual
      from counts

      union all
      select 9, 'App notifications created',
        app_expected, app_actual
      from counts

      union all
      select 10, 'Emails queued',
        emails_expected, emails_actual
      from counts

      union all
      select 11, 'Emails sent',
        emails_expected, emails_sent_actual
      from counts

      union all
      select 12, 'Emails failed',
        0, emails_failed_actual
      from counts

      union all
      select 13, 'Team sheets required', 0, 0

      union all
      select 14, 'Team sheets attached', 0, 0

      union all
      select 15, 'Team sheets sent', 0, 0
    )
    select
      rows.item,
      rows.expected,
      rows.actual,
      case
        when rows.item = 'Emails failed'
          then case when rows.actual = 0 then 'OK' else 'CHECK' end
        when rows.actual >= rows.expected
          then 'OK'
        else 'CHECK'
      end as status
    from rows
    order by rows.sort_order;

    return;
  end if;

  -- Existing published-team behaviour for all non-Pre-Select fixtures.
  return query
  with
  assigned as (
    select distinct fra.member_profile_id
    from public.fixture_rink_assignments fra
    where fra.fixture_id = p_fixture_id
      and fra.member_profile_id is not null
  ),
  reserves as (
    select distinct tsm.member_profile_id
    from public.team_selection_members tsm
    where tsm.team_selection_id = v_team_selection_id
      and tsm.is_selected = true
      and tsm.role = 'reserve'::selection_member_role
  ),
  captains as (
    select distinct x.member_profile_id
    from public.fixtures f
    cross join lateral (
      values
        (f.captain_member_profile_id),
        (f.vice_captain_member_profile_id)
    ) x(member_profile_id)
    where f.id = p_fixture_id
      and x.member_profile_id is not null
  ),
  selected_people as (
    select member_profile_id from assigned
    union
    select member_profile_id from reserves
  ),
  team_pool as (
    select tm.member_profile_id
    from public.fixtures f
    join public.team_members tm
      on tm.team_id = f.team_id
    where f.id = p_fixture_id
      and coalesce(tm.is_active, true) = true
  ),
  not_selected as (
    select member_profile_id from team_pool
    except
    select member_profile_id from selected_people
  ),
  expected_counts as (
    select
      (select count(*) from assigned)::integer as players,
      (select count(*) from reserves)::integer as reserves,
      (select count(*) from captains)::integer as captains,
      (select count(*) from not_selected)::integer as not_selected
  ),
  totals as (
    select
      players,
      reserves,
      captains,
      not_selected,
      players + reserves + captains + not_selected as total_comms,
      players + reserves + captains as team_sheet_comms
    from expected_counts
  ),
  rows as (
    select
      1 as sort_order,
      'Playing players'::text as item,
      players as expected,
      (
        select count(*)::integer
        from public.notification_queue nq
        where nq.fixture_id = p_fixture_id
          and nq.team_selection_id = v_team_selection_id
          and nq.event_type = 'team_published_player'
          and nq.status <> 'cancelled'
      ) as actual
    from totals

    union all
    select 2, 'Reserves', reserves,
      (
        select count(*)::integer
        from public.notification_queue nq
        where nq.fixture_id = p_fixture_id
          and nq.team_selection_id = v_team_selection_id
          and nq.event_type = 'team_published_reserve'
          and nq.status <> 'cancelled'
      )
    from totals

    union all
    select 3, 'Captain/Vice copies', captains,
      (
        select count(*)::integer
        from public.notification_queue nq
        where nq.fixture_id = p_fixture_id
          and nq.team_selection_id = v_team_selection_id
          and nq.event_type in (
            'team_published_captain',
            'team_published_vice'
          )
          and nq.status <> 'cancelled'
      )
    from totals

    union all
    select 4, 'Not selected', not_selected,
      (
        select count(*)::integer
        from public.notification_queue nq
        where nq.fixture_id = p_fixture_id
          and nq.team_selection_id = v_team_selection_id
          and nq.event_type in (
            'team_published_not_selected',
            'team_published_incomplete_request'
          )
          and nq.status <> 'cancelled'
      )
    from totals

    union all
    select 5, 'Notifications queued', total_comms,
      (
        select count(*)::integer
        from public.notification_queue nq
        where nq.fixture_id = p_fixture_id
          and nq.team_selection_id = v_team_selection_id
          and nq.event_type like 'team_published%'
          and nq.status <> 'cancelled'
      )
    from totals

    union all
    select 6, 'App notifications created', total_comms,
      (
        select count(*)::integer
        from public.app_notifications an
        where an.fixture_id = p_fixture_id
          and an.team_selection_id = v_team_selection_id
          and an.type like 'team_published%'
      )
    from totals

    union all
    select 7, 'Emails queued', total_comms,
      (
        select count(*)::integer
        from public.email_queue eq
        where eq.fixture_id = p_fixture_id
          and eq.team_selection_id = v_team_selection_id
          and eq.event_type like 'team_published%'
          and eq.status <> 'cancelled'
      )
    from totals

    union all
    select 8, 'Emails sent', total_comms,
      (
        select count(*)::integer
        from public.email_queue eq
        where eq.fixture_id = p_fixture_id
          and eq.team_selection_id = v_team_selection_id
          and eq.event_type like 'team_published%'
          and eq.status = 'sent'
      )
    from totals

    union all
    select 9, 'Emails failed', 0,
      (
        select count(*)::integer
        from public.email_queue eq
        where eq.fixture_id = p_fixture_id
          and eq.team_selection_id = v_team_selection_id
          and eq.event_type like 'team_published%'
          and eq.status = 'failed'
      )
    from totals

    union all
    select 10, 'Team sheets required', team_sheet_comms,
      (
        select count(*)::integer
        from public.email_queue eq
        where eq.fixture_id = p_fixture_id
          and eq.team_selection_id = v_team_selection_id
          and eq.event_type in (
            'team_published_player',
            'team_published_reserve',
            'team_published_captain',
            'team_published_vice'
          )
          and eq.status <> 'cancelled'
      )
    from totals

    union all
    select 11, 'Team sheets attached', team_sheet_comms,
      (
        select count(*)::integer
        from public.email_queue eq
        where eq.fixture_id = p_fixture_id
          and eq.team_selection_id = v_team_selection_id
          and eq.event_type in (
            'team_published_player',
            'team_published_reserve',
            'team_published_captain',
            'team_published_vice'
          )
          and eq.status <> 'cancelled'
          and jsonb_array_length(
            coalesce(eq.attachments, '[]'::jsonb)
          ) > 0
      )
    from totals

    union all
    select 12, 'Team sheets sent', team_sheet_comms,
      (
        select count(*)::integer
        from public.email_queue eq
        where eq.fixture_id = p_fixture_id
          and eq.team_selection_id = v_team_selection_id
          and eq.event_type in (
            'team_published_player',
            'team_published_reserve',
            'team_published_captain',
            'team_published_vice'
          )
          and eq.status = 'sent'
          and jsonb_array_length(
            coalesce(eq.attachments, '[]'::jsonb)
          ) > 0
      )
    from totals
  )
  select
    rows.item,
    rows.expected,
    rows.actual,
    case
      when rows.expected = rows.actual then 'OK'
      else 'CHECK'
    end as status
  from rows
  order by rows.sort_order;
end;
$function$;

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
      );

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
$function$;
