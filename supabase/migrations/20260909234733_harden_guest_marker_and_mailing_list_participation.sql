CREATE OR REPLACE FUNCTION public.queue_open_marker_request_communications(p_fixture_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_actor_member_profile_id uuid;
  v_club_id uuid;
  v_team_selection_id uuid;
  v_marker_mailing_list_id uuid;
  v_marker_mailing_list_name text;

  v_is_superuser boolean := false;
  v_has_permission boolean := false;

  v_queued_count integer := 0;
  v_open_request_count integer := 0;
  v_volunteer_count integer := 0;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  select f.club_id, ts.id
  into v_club_id, v_team_selection_id
  from public.fixtures f
  left join public.team_selections ts
    on ts.fixture_id = f.id
  where f.id = p_fixture_id;

  if not found then
    raise exception 'Fixture not found.';
  end if;

  select public.my_member_profile_id()
  into v_actor_member_profile_id;

  select exists (
    select 1
    from public.app_superusers su
    where su.user_id = auth.uid()
  )
  into v_is_superuser;

  v_has_permission :=
    v_is_superuser
    or exists (
      select 1
      from public.club_memberships cm
      where cm.club_id = v_club_id
        and cm.member_profile_id = v_actor_member_profile_id
        and cm.is_active = true
        and lower(cm.role::text) <> 'guest'
        and (
          lower(cm.role::text) in ('admin', 'selector')
          or exists (
            select 1
            from public.fixtures f
            where f.id = p_fixture_id
              and v_actor_member_profile_id in (
                f.captain_member_profile_id,
                f.vice_captain_member_profile_id
              )
          )
        )
    );

  if not v_has_permission then
    raise exception
      'You do not have permission to send marker requests for this fixture.';
  end if;

  select vt.mailing_list_id, ml.name
  into v_marker_mailing_list_id, v_marker_mailing_list_name
  from public.volunteer_tasks vt
  join public.mailing_lists ml
    on ml.id = vt.mailing_list_id
   and ml.club_id = vt.club_id
   and ml.is_active = true
  where vt.club_id = v_club_id
    and vt.task_code = 'marker'
    and vt.is_active = true
  limit 1;

  if v_marker_mailing_list_id is null then
    raise exception
      'No active Marker volunteer task with an active mailing list is configured for this club.';
  end if;

  select count(*)
  into v_open_request_count
  from public.fixture_marker_requests mr
  join public.fixture_rinks fr
    on fr.id = mr.fixture_rink_id
  where fr.fixture_id = p_fixture_id
    and mr.status = 'open';

  select count(distinct mlm.member_profile_id)
  into v_volunteer_count
  from public.mailing_list_members mlm
  join public.club_memberships cm
    on cm.club_id = v_club_id
   and cm.member_profile_id = mlm.member_profile_id
   and cm.is_active = true
   and lower(cm.role::text) <> 'guest'
  where mlm.mailing_list_id = v_marker_mailing_list_id
    and mlm.is_active = true
    and not exists (
      select 1
      from public.team_selection_members tsm
      where tsm.team_selection_id = v_team_selection_id
        and tsm.member_profile_id = mlm.member_profile_id
        and tsm.is_selected = true
    )
    and not exists (
      select 1
      from public.fixture_rink_assignments fra
      where fra.fixture_id = p_fixture_id
        and fra.member_profile_id = mlm.member_profile_id
    );

  insert into public.notification_queue (
    event_type,
    member_profile_id,
    target_member_profile_id,
    fixture_id,
    team_selection_id,
    payload,
    status
  )
  select
    'marker_request_opened',
    v_actor_member_profile_id,
    mlm.member_profile_id,
    p_fixture_id,
    v_team_selection_id,

    jsonb_build_object(
      'marker_request_id', mr.id,
      'fixture_rink_id', fr.id,
      'team_no', fr.fixture_rink_no,
      'home_rink_label', fr.home_rink_label,
      'players_per_rink', fr.players_per_rink,
      'mailing_list_id', v_marker_mailing_list_id,
      'mailing_list_name', v_marker_mailing_list_name,

      'fixture_label',
        coalesce(
          nullif(btrim(f.team_name), ''),
          nullif(btrim(ct.name), ''),
          'Pre-Select Fixture'
        ),

      'fixture_date', f.start_at,
      'start_at', f.start_at,
      'end_at', f.end_at,

      'home_away',
        case when f.is_home = true then 'Home' else 'Away' end,

      'venue_name',
        case
          when f.is_home = true
            then coalesce(home_venue.name, '')
          else coalesce(opponent_venue.name, home_venue.name, '')
        end,

      'opponent_name', coalesce(opponent_venue.name, ''),

      'message',
        'A marker is required for Team '
        || fr.fixture_rink_no::text
        || '.'
    ),

    'pending'

  from public.fixture_marker_requests mr
  join public.fixture_rinks fr
    on fr.id = mr.fixture_rink_id
  join public.fixtures f
    on f.id = fr.fixture_id
  left join public.competition_types ct
    on ct.id = f.competition_type_id
  left join public.venues home_venue
    on home_venue.id = f.venue_id
  left join public.venues opponent_venue
    on opponent_venue.id = f.opponent_venue_id
  join public.mailing_list_members mlm
    on mlm.mailing_list_id = v_marker_mailing_list_id
   and mlm.is_active = true
  join public.club_memberships cm
    on cm.club_id = f.club_id
   and cm.member_profile_id = mlm.member_profile_id
   and cm.is_active = true
   and lower(cm.role::text) <> 'guest'

  where fr.fixture_id = p_fixture_id
    and mr.status = 'open'
    and not exists (
      select 1
      from public.team_selection_members tsm
      where tsm.team_selection_id = v_team_selection_id
        and tsm.member_profile_id = mlm.member_profile_id
        and tsm.is_selected = true
    )
    and not exists (
      select 1
      from public.fixture_rink_assignments fra
      where fra.fixture_id = p_fixture_id
        and fra.member_profile_id = mlm.member_profile_id
    )
    and not exists (
      select 1
      from public.notification_queue existing
      where existing.event_type = 'marker_request_opened'
        and existing.target_member_profile_id = mlm.member_profile_id
        and existing.payload ->> 'marker_request_id' = mr.id::text
    );

  get diagnostics v_queued_count = row_count;

  return jsonb_build_object(
    'fixture_id', p_fixture_id,
    'mailing_list_id', v_marker_mailing_list_id,
    'mailing_list_name', v_marker_mailing_list_name,
    'open_request_count', v_open_request_count,
    'active_marker_volunteer_count', v_volunteer_count,
    'communications_queued', v_queued_count
  );
end;
$function$;

create or replace function public.enforce_operational_mailing_list_member_eligibility()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  if coalesce(new.is_active, false)
     and not exists (
       select 1
       from public.mailing_lists ml
       join public.club_memberships cm
         on cm.club_id = ml.club_id
        and cm.member_profile_id = new.member_profile_id
        and cm.is_active = true
        and lower(cm.role::text) <> 'guest'
       where ml.id = new.mailing_list_id
     ) then
    raise exception
      'Operational mailing-list membership requires an active non-Guest club member.'
      using errcode = '42501';
  end if;

  return new;
end;
$function$;

revoke all on function public.enforce_operational_mailing_list_member_eligibility()
from public, anon, authenticated;

drop trigger if exists enforce_operational_mailing_list_member_eligibility
on public.mailing_list_members;

create trigger enforce_operational_mailing_list_member_eligibility
before insert or update of mailing_list_id, member_profile_id, is_active
on public.mailing_list_members
for each row
execute function public.enforce_operational_mailing_list_member_eligibility();

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
       and lower(cm.role::text) <> 'guest'
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
    union
    select distinct tsm.member_profile_id
    from public.team_selection_members tsm
    where tsm.team_selection_id = v_team_selection_id
      and tsm.is_selected = true
      and tsm.role = 'player'::selection_member_role
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

create or replace function public.communications_health_detail_v2(p_fixture_id uuid)
returns table(
  member_profile_id uuid,
  member_name text,
  category text,
  app_notification text,
  email_status text,
  team_sheet text,
  email_address text
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_selection_id uuid;
  v_selection_mode text;
  v_composition_version integer;
begin
  perform public.communications_require_superuser();

  select ts.id, lower(coalesce(ct.selection_mode::text, '')),
         ts.composition_version
  into v_selection_id, v_selection_mode, v_composition_version
  from public.fixtures f
  left join public.competition_types ct on ct.id = f.competition_type_id
  join lateral (
    select x.id, x.composition_version
    from public.team_selections x
    where x.fixture_id = f.id
    order by x.created_at desc
    limit 1
  ) ts on true
  where f.id = p_fixture_id;

  if v_selection_id is null then raise exception 'Team selection not found.'; end if;

  return query
  with participants as (
    select tsm.member_profile_id
    from public.team_selection_members tsm
    where tsm.team_selection_id = v_selection_id and tsm.is_selected = true
    union
    select fra.member_profile_id
    from public.fixture_rink_assignments fra
    where fra.fixture_id = p_fixture_id and fra.member_profile_id is not null
  ),
  preselect_assignments as (
    select distinct fra.member_profile_id,
      case when fra.position = 201 then 'Named Marker'
           when fra.position between 101 and 100 + fr.players_per_rink then 'Opponent'
           else 'Player' end category,
      'fixture_selected'::text event_type,
      true team_sheet_required,
      fr.fixture_rink_no team_no,
      fra.position
    from public.fixture_rink_assignments fra
    join public.fixture_rinks fr on fr.id = fra.fixture_rink_id
    where v_selection_mode = 'preselect'
      and fra.fixture_id = p_fixture_id
      and fra.member_profile_id is not null
      and (fra.position between 1 and fr.players_per_rink
        or fra.position between 101 and 100 + fr.players_per_rink
        or fra.position = 201)
  ),
  leadership as (
    select x.member_profile_id, x.category, x.event_type,
           true team_sheet_required, null::integer team_no, null::integer position
    from public.fixtures f
    cross join lateral (values
      (f.captain_member_profile_id, 'Captain'::text, 'team_published_captain'::text),
      (f.vice_captain_member_profile_id, 'Vice Captain'::text, 'team_published_vice'::text)
    ) x(member_profile_id, category, event_type)
    where f.id = p_fixture_id and x.member_profile_id is not null
      and not exists (
        select 1 from participants p where p.member_profile_id = x.member_profile_id
      )
  ),
  marker_volunteers as (
    select distinct mlm.member_profile_id,
      'Marker Volunteer - Team ' || fr.fixture_rink_no::text category,
      'marker_request_opened'::text event_type,
      false team_sheet_required,
      fr.fixture_rink_no team_no,
      null::integer position
    from public.fixture_marker_requests mr
    join public.fixture_rinks fr on fr.id = mr.fixture_rink_id
    join public.fixtures f on f.id = fr.fixture_id
    join public.volunteer_tasks vt on vt.club_id = f.club_id
      and vt.task_code = 'marker' and vt.is_active = true
    join public.mailing_list_members mlm on mlm.mailing_list_id = vt.mailing_list_id
      and mlm.is_active = true
    join public.club_memberships cm on cm.club_id = f.club_id
      and cm.member_profile_id = mlm.member_profile_id and cm.is_active = true
      and lower(cm.role::text) <> 'guest'
    where v_selection_mode = 'preselect'
      and fr.fixture_id = p_fixture_id and mr.status = 'open'
      and not exists (
        select 1 from participants p where p.member_profile_id = mlm.member_profile_id
      )
  ),
  ordinary_players as (
    select distinct fra.member_profile_id, 'Player'::text category,
      'team_published_player'::text event_type, true team_sheet_required,
      null::integer team_no, null::integer position
    from public.fixture_rink_assignments fra
    join public.fixture_rinks fr on fr.id = fra.fixture_rink_id
    where v_selection_mode <> 'preselect' and fra.fixture_id = p_fixture_id
      and fra.member_profile_id is not null
      and fra.position between 1 and fr.players_per_rink
  ),
  ordinary_reserves as (
    select distinct tsm.member_profile_id, 'Reserve'::text category,
      'team_published_reserve'::text event_type, true team_sheet_required,
      null::integer team_no, null::integer position
    from public.team_selection_members tsm
    where v_selection_mode <> 'preselect'
      and tsm.team_selection_id = v_selection_id
      and tsm.is_selected = true and lower(tsm.role::text) = 'reserve'
      and not exists (
        select 1 from ordinary_players p where p.member_profile_id = tsm.member_profile_id
      )
  ),
  ordinary_not_selected as (
    select distinct tm.member_profile_id, 'Not Selected'::text category,
      'team_published_not_selected'::text event_type, false team_sheet_required,
      null::integer team_no, null::integer position
    from public.fixtures f
    join public.team_members tm on tm.team_id = f.team_id and tm.is_active = true
    where v_selection_mode <> 'preselect' and f.id = p_fixture_id
      and not exists (
        select 1 from participants p where p.member_profile_id = tm.member_profile_id
      )
  ),
  expected as (
    select * from preselect_assignments
    union all select * from leadership
    union all select * from marker_volunteers
    union all select * from ordinary_players
    union all select * from ordinary_reserves
    union all select * from ordinary_not_selected
  )
  select e.member_profile_id,
    coalesce(nullif(btrim(mp.display_name), ''),
      nullif(btrim(coalesce(mp.first_name, '') || ' ' || coalesce(mp.last_name, '')), ''),
      'Unknown') member_name,
    e.category,
    case when app.id is null then 'Missing' else 'Created' end app_notification,
    case when nullif(btrim(mp.email_address), '') is null then 'No Email'
         else coalesce(mail.status, 'Missing') end email_status,
    case when not e.team_sheet_required then 'Not Required'
         when mail.id is null then 'Missing'
         when case
          when jsonb_typeof(coalesce(mail.attachments, '[]'::jsonb)) = 'array'
          then jsonb_array_length(coalesce(mail.attachments, '[]'::jsonb)) = 1
          and mail.attachments->0->>'contentType' = 'application/pdf'
          and nullif(mail.attachments->0->>'contentBytes', '') is not null
          and length(mail.attachments->0->>'contentBytes') <= 2700000
          and mail.attachments->0->>'contentBytes' like 'JVBERi%'
          and nullif(mail.attachments->0->>'compositionVersion', '') is not null
          and (
            mail.status = 'sent'
            or mail.attachments->0->>'compositionVersion' = v_composition_version::text
          )
          else false
         end then 'Attached' else 'Missing' end team_sheet,
    mp.email_address
  from expected e
  left join public.member_profiles mp on mp.id = e.member_profile_id
  left join lateral (
    select an.id from public.app_notifications an
    where an.fixture_id = p_fixture_id
      and an.team_selection_id = v_selection_id
      and an.member_profile_id = e.member_profile_id
      and (an.type = e.event_type
        or (e.category = 'Player' and an.type in ('fixture_selected','reserve_promoted')))
    order by an.created_at desc limit 1
  ) app on true
  left join lateral (
    select eq.id, eq.status::text, eq.attachments
    from public.email_queue eq
    where eq.fixture_id = p_fixture_id
      and eq.team_selection_id = v_selection_id
      and eq.member_profile_id = e.member_profile_id
      and eq.status <> 'cancelled'
      and (eq.event_type = e.event_type
        or (e.category = 'Player' and eq.event_type in ('fixture_selected','reserve_promoted')))
    order by eq.created_at desc limit 1
  ) mail on true
  order by case e.category when 'Player' then 1 when 'Opponent' then 2
    when 'Named Marker' then 3 when 'Reserve' then 4 when 'Captain' then 5
    when 'Vice Captain' then 6 when 'Not Selected' then 8 else 7 end,
    member_name;
end;
$function$;

revoke all on function public.communications_health_detail_v2(uuid)
from public, anon, authenticated;
grant execute on function public.communications_health_detail_v2(uuid)
to authenticated;
