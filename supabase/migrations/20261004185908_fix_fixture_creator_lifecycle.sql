BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL search_path=public,extensions,pg_catalog;
DO $guard$ BEGIN
IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='cancel_fixture_safe' AND md5(pg_get_functiondef(p.oid))='e98aad5d5da9d2cc9527507451b39378') THEN RAISE EXCEPTION 'Lifecycle function drift: cancel_fixture_safe'; END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='audit_private' AND p.proname='guard_archived_fixture' AND md5(pg_get_functiondef(p.oid))='c7514187c2ecc878d8d2848716e4c005') THEN RAISE EXCEPTION 'Lifecycle function drift: guard_archived_fixture'; END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='queue_fixture_moved_notifications' AND md5(pg_get_functiondef(p.oid))='3f643299250904c4d568bc007e1950ab') THEN RAISE EXCEPTION 'Lifecycle function drift: queue_fixture_moved_notifications'; END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='reschedule_cancelled_fixture_safe' AND md5(pg_get_functiondef(p.oid))='4aaca4ec0a07e6f4d50ca17c3095083f') THEN RAISE EXCEPTION 'Lifecycle function drift: reschedule_cancelled_fixture_safe'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION public.is_active_fixture_creator(p_fixture_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM public.fixtures f JOIN public.club_memberships cm
 ON cm.club_id=f.club_id AND cm.member_profile_id=public.my_member_profile_id()
 WHERE f.id=p_fixture_id AND f.created_by_user_id=auth.uid()
 AND cm.is_active AND lower(cm.role::text)<>'guest');
$$;
REVOKE ALL ON FUNCTION public.is_active_fixture_creator(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.is_active_fixture_creator(uuid) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.cancel_fixture_safe(p_fixture_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_current_member uuid := public.my_member_profile_id();
  v_club_id uuid;
  v_start_at timestamptz;
  v_end_at timestamptz;
  v_fixture_label text;
  v_home_away text;
  v_venue_name text;
  v_opponent_name text;
  v_team_selection_id uuid;
  v_is_admin boolean := false;
  v_is_super boolean := false;
  v_is_captain_or_vice boolean := false;
  v_count integer := 0;
begin
  if v_current_member is null then
    raise exception 'Not signed in.';
  end if;

  select
    f.club_id,
    f.start_at,
    f.end_at,
    coalesce(nullif(f.team_name, ''), nullif(ct.name, ''), 'Fixture'),
    case when f.is_home then 'Home' else 'Away' end,
    coalesce(v.name, ''),
    coalesce(ov.name, ''),
    (f.captain_member_profile_id = v_current_member
      or f.vice_captain_member_profile_id = v_current_member)
  into
    v_club_id,
    v_start_at,
    v_end_at,
    v_fixture_label,
    v_home_away,
    v_venue_name,
    v_opponent_name,
    v_is_captain_or_vice
  from public.fixtures f
  left join public.competition_types ct on ct.id = f.competition_type_id
  left join public.venues v on v.id = f.venue_id
  left join public.venues ov on ov.id = f.opponent_venue_id
  where f.id = p_fixture_id;

  if not found then
    raise exception 'Fixture not found.';
  end if;

  select exists (
    select 1
    from public.club_memberships cm
    where cm.club_id = v_club_id
      and cm.member_profile_id = v_current_member
      and cm.is_active = true
      and cm.role in ('admin', 'selector')
  ) into v_is_admin;

  select exists (
    select 1
    from public.app_superusers su
    where su.user_id = auth.uid()
  ) into v_is_super;

  if not (public.can_manage_fixture(p_fixture_id) or public.is_active_fixture_creator(p_fixture_id)) then
    raise exception 'You do not have permission to cancel this fixture.';
  end if;

  if exists (
    select 1
    from public.fixtures f
    where f.id = p_fixture_id
      and f.cancelled_at is not null
  ) then
    raise exception 'Fixture is already cancelled.';
  end if;

  select ts.id
  into v_team_selection_id
  from public.team_selections ts
  where ts.fixture_id = p_fixture_id
  order by ts.created_at desc nulls last
  limit 1;

  --------------------------------------------------------------------
  -- Suppress undelivered operational communications for this fixture.
  -- Cancellation is a lifecycle event and is deliberately preserved.
  --------------------------------------------------------------------

  update public.email_queue eq
  set status = 'cancelled'
  where eq.fixture_id = p_fixture_id
    and eq.event_type in (
      'acceptance_reminder',
      'fixture_message',
      'fixture_moved',
      'fixture_opponent_changed',
      'fixture_rescheduled_availability',
      'fixture_rescheduled_manager',
      'fixture_rescheduled_selected',
      'fixture_selected',
      'marker_request_opened',
      'reserve_promoted',
      'team_acceptance_changed',
      'team_published_captain',
      'team_published_incomplete_request',
      'team_published_not_selected',
      'team_published_player',
      'team_published_reserve',
      'team_published_vice'
    )
    and eq.status in ('pending', 'failed')
    and eq.sent_at is null;

  update public.notification_queue nq
  set status = 'cancelled'
  where nq.fixture_id = p_fixture_id
    and nq.event_type in (
      'acceptance_reminder',
      'fixture_message',
      'fixture_moved',
      'fixture_opponent_changed',
      'fixture_rescheduled_availability',
      'fixture_rescheduled_manager',
      'fixture_rescheduled_selected',
      'fixture_selected',
      'marker_request_opened',
      'reserve_promoted',
      'team_acceptance_changed',
      'team_published_captain',
      'team_published_incomplete_request',
      'team_published_not_selected',
      'team_published_player',
      'team_published_reserve',
      'team_published_vice'
    )
    and nq.status = 'pending';

  update public.fixtures
  set
    cancelled_at = now(),
    cancelled_by_member_profile_id = v_current_member,
    cancellation_reason = nullif(btrim(p_reason), '')
  where id = p_fixture_id;

  insert into public.fixture_lifecycle_events (
    fixture_id,
    event_type,
    old_start_at,
    old_end_at,
    reason,
    created_by_member_profile_id
  )
  values (
    p_fixture_id,
    'cancelled',
    v_start_at,
    v_end_at,
    nullif(btrim(p_reason), ''),
    v_current_member
  );

  with recipients as (
    select f.captain_member_profile_id as member_profile_id
    from public.fixtures f
    where f.id = p_fixture_id
      and f.captain_member_profile_id is not null

    union

    select f.vice_captain_member_profile_id
    from public.fixtures f
    where f.id = p_fixture_id
      and f.vice_captain_member_profile_id is not null

    union

    select tsm.member_profile_id
    from public.team_selection_members tsm
    join public.team_selections ts on ts.id = tsm.team_selection_id
    where ts.fixture_id = p_fixture_id
      and tsm.member_profile_id is not null
      and coalesce(tsm.is_selected, false) = true

    union

    select frsvp.member_profile_id
    from public.fixture_rsvps frsvp
    where frsvp.fixture_id = p_fixture_id
      and frsvp.member_profile_id is not null
      and lower(coalesce(frsvp.status::text, '')) in ('yes', 'maybe')
  ),
  inserted as (
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
      'fixture_cancelled',
      v_current_member,
      r.member_profile_id,
      p_fixture_id,
      v_team_selection_id,
      jsonb_strip_nulls(
        jsonb_build_object(
          'fixture_label', v_fixture_label,
          'start_at', v_start_at,
          'end_at', v_end_at,
          'home_away', v_home_away,
          'venue_name', nullif(v_venue_name, ''),
          'opponent_name', nullif(v_opponent_name, ''),
          'reason', nullif(btrim(p_reason), '')
        )
      ),
      'pending'
    from recipients r
    where r.member_profile_id is not null
      and r.member_profile_id <> v_current_member
      and not exists (
        select 1
        from public.notification_queue nq
        where nq.fixture_id = p_fixture_id
          and nq.target_member_profile_id = r.member_profile_id
          and nq.event_type = 'fixture_cancelled'
          and nq.status in ('pending', 'sent')
      )
    returning 1
  )
  select count(*) into v_count from inserted;

  return v_count;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.queue_fixture_moved_notifications(p_fixture_id uuid, p_old_start_at timestamp with time zone, p_old_end_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_count int := 0;
begin
  if not (public.can_manage_fixture(p_fixture_id) or public.is_active_fixture_creator(p_fixture_id)) then
    raise exception 'You do not have permission to queue fixture-move notifications.';
  end if;

  -- Serialize retries for this fixture without locking other clubs' fixtures.
  perform 1 from public.fixtures where id = p_fixture_id for update;

  with recipients as (
    -- Includes assigned markers (position 201), as well as playing positions.
    select fra.member_profile_id
    from public.fixture_rink_assignments fra
    where fra.fixture_id = p_fixture_id

    union

    select tsm.member_profile_id
    from public.team_selections ts
    join public.team_selection_members tsm on tsm.team_selection_id = ts.id
    where ts.fixture_id = p_fixture_id
      and ts.status = 'published'
      and tsm.is_selected = true

    union

    select f.captain_member_profile_id
    from public.fixtures f where f.id = p_fixture_id

    union

    select f.vice_captain_member_profile_id
    from public.fixtures f where f.id = p_fixture_id
  )
  insert into public.notification_queue (
    target_member_profile_id,
    event_type,
    fixture_id,
    payload,
    status,
    created_at
  )
  select distinct
    recipient.member_profile_id,
    'fixture_moved',
    f.id,
    jsonb_build_object(
      'fixture_id', f.id,
      'fixture_name', coalesce(ct.name, 'Fixture'),
      'old_start_at', p_old_start_at,
      'old_end_at', p_old_end_at,
      'new_start_at', f.start_at,
      'new_end_at', f.end_at,
      'is_home', f.is_home,
      'venue_name', venue.name,
      'opponent_name', opponent.name
    ),
    'pending',
    now()
  from public.fixtures f
  cross join recipients recipient
  left join public.competition_types ct
    on ct.id = f.competition_type_id
  left join public.venues venue
    on venue.id = f.venue_id
  left join public.venues opponent
    on opponent.id = f.opponent_venue_id
  where f.id = p_fixture_id
    and recipient.member_profile_id is not null
    and not exists (
      select 1
      from public.notification_queue existing
      where existing.fixture_id = f.id
        and existing.event_type = 'fixture_moved'
        and existing.target_member_profile_id = recipient.member_profile_id
        and (existing.payload ->> 'old_start_at')::timestamptz is not distinct from p_old_start_at
        and nullif(existing.payload ->> 'old_end_at', '')::timestamptz is not distinct from p_old_end_at
        and (existing.payload ->> 'new_start_at')::timestamptz is not distinct from f.start_at
        and nullif(existing.payload ->> 'new_end_at', '')::timestamptz is not distinct from f.end_at
        and existing.status in ('pending', 'processing', 'sent')
    );

  get diagnostics v_count = row_count;

  return v_count;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.reschedule_cancelled_fixture_safe(p_fixture_id uuid, p_new_start_at timestamp with time zone, p_new_end_at timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_current_member uuid := public.my_member_profile_id();
  v_source public.fixtures%rowtype;

  v_new_fixture_id uuid;
  v_old_team_selection_id uuid;
  v_new_team_selection_id uuid;

  v_is_admin boolean := false;
  v_is_super boolean := false;

  v_free_rinks integer;

  v_old_selection_status selection_status;

  v_fixture_label text;
  v_recipient record;
begin
  --------------------------------------------------------------------
  -- Basic validation
  --------------------------------------------------------------------

  if v_current_member is null then
    raise exception 'Not signed in.';
  end if;

  if p_new_start_at is null
     or p_new_end_at is null
     or p_new_start_at >= p_new_end_at then
    raise exception 'Invalid new fixture start/end time.';
  end if;

  select *
  into v_source
  from public.fixtures
  where id = p_fixture_id
  for update;

  if not found then
    raise exception 'Fixture not found.';
  end if;

  if v_source.cancelled_at is null then
    raise exception
      'Only a cancelled fixture can be rescheduled by this procedure.';
  end if;

  if v_source.rescheduled_to_fixture_id is not null then
    raise exception
      'This cancelled fixture has already been rescheduled.';
  end if;

  --------------------------------------------------------------------
  -- Fixture label for notifications
  --------------------------------------------------------------------

  select coalesce(
    nullif(btrim(v_source.team_name), ''),
    nullif(btrim(ct.name), ''),
    'Fixture'
  )
  into v_fixture_label
  from public.competition_types ct
  where ct.id = v_source.competition_type_id;

  if v_fixture_label is null then
    v_fixture_label := coalesce(
      nullif(btrim(v_source.team_name), ''),
      'Fixture'
    );
  end if;

  --------------------------------------------------------------------
  -- Permission
  --------------------------------------------------------------------

  select exists (
    select 1
    from public.club_memberships cm
    where cm.club_id = v_source.club_id
      and cm.member_profile_id = v_current_member
      and cm.is_active = true
      and cm.role = 'admin'
  )
  into v_is_admin;

  select exists (
    select 1
    from public.app_superusers su
    where su.user_id = auth.uid()
  )
  into v_is_super;

  if not (v_is_admin or v_is_super or public.is_active_fixture_creator(p_fixture_id)) then
    raise exception
      'You do not have permission to reschedule this fixture.';
  end if;

  --------------------------------------------------------------------
  -- Defensively suppress legacy undelivered operational communications
  -- for the cancelled fixture. Its lifecycle cancellation is preserved.
  --------------------------------------------------------------------

  update public.email_queue eq
  set status = 'cancelled'
  where eq.fixture_id = p_fixture_id
    and eq.event_type in (
      'acceptance_reminder',
      'fixture_message',
      'fixture_moved',
      'fixture_opponent_changed',
      'fixture_rescheduled_availability',
      'fixture_rescheduled_manager',
      'fixture_rescheduled_selected',
      'fixture_selected',
      'marker_request_opened',
      'reserve_promoted',
      'team_acceptance_changed',
      'team_published_captain',
      'team_published_incomplete_request',
      'team_published_not_selected',
      'team_published_player',
      'team_published_reserve',
      'team_published_vice'
    )
    and eq.status in ('pending', 'failed')
    and eq.sent_at is null;

  update public.notification_queue nq
  set status = 'cancelled'
  where nq.fixture_id = p_fixture_id
    and nq.event_type in (
      'acceptance_reminder',
      'fixture_message',
      'fixture_moved',
      'fixture_opponent_changed',
      'fixture_rescheduled_availability',
      'fixture_rescheduled_manager',
      'fixture_rescheduled_selected',
      'fixture_selected',
      'marker_request_opened',
      'reserve_promoted',
      'team_acceptance_changed',
      'team_published_captain',
      'team_published_incomplete_request',
      'team_published_not_selected',
      'team_published_player',
      'team_published_reserve',
      'team_published_vice'
    )
    and nq.status = 'pending';

  --------------------------------------------------------------------
  -- Final capacity check for a HOME fixture using rinks
  --------------------------------------------------------------------

  if v_source.is_home = true
     and v_source.green_area_id is not null
     and v_source.rinks_required > 0 then

    select free_capacity_rinks
    into v_free_rinks
    from public.get_green_rink_availability(
      v_source.green_area_id,
      p_new_start_at,
      p_new_end_at
    )
    limit 1;

    if v_free_rinks is null then
      raise exception
        'No rink availability returned for the selected green.';
    end if;

    if v_free_rinks < v_source.rinks_required then
      raise exception
        'Not enough rinks available on the new date: % free, % required.',
        v_free_rinks,
        v_source.rinks_required;
    end if;

  end if;

  --------------------------------------------------------------------
  -- Create the new LIVE fixture
  --------------------------------------------------------------------

  insert into public.fixtures (
    club_id,
    start_at,
    end_at,
    is_home,
    venue_id,
    green_area_id,
    opponent_name,
    opponent_contact,
    notes,
    fixture_type,
    section,
    dress_code,
    rinks_required,
    players_per_rink,
    orientation,
    time_range,
    captain_member_profile_id,
    opponent_venue_id,
    vice_captain_member_profile_id,
    team_name,
    team_id,
    requires_rsvp,
    competition_type_id,
    rescheduled_from_fixture_id,
    rescheduled_at,
    rescheduled_by_member_profile_id
  )
  values (
    v_source.club_id,
    p_new_start_at,
    p_new_end_at,
    v_source.is_home,
    v_source.venue_id,
    v_source.green_area_id,
    v_source.opponent_name,
    v_source.opponent_contact,
    v_source.notes,
    v_source.fixture_type,
    v_source.section,
    v_source.dress_code,
    v_source.rinks_required,
    v_source.players_per_rink,
    v_source.orientation,
    tstzrange(p_new_start_at, p_new_end_at, '[)'),
    v_source.captain_member_profile_id,
    v_source.opponent_venue_id,
    v_source.vice_captain_member_profile_id,
    v_source.team_name,
    v_source.team_id,
    v_source.requires_rsvp,
    v_source.competition_type_id,
    p_fixture_id,
    now(),
    v_current_member
  )
  returning id into v_new_fixture_id;

  --------------------------------------------------------------------
  -- Link OLD cancelled fixture to NEW fixture
  --------------------------------------------------------------------

  update public.fixtures
  set
    rescheduled_to_fixture_id = v_new_fixture_id,
    rescheduled_at = now(),
    rescheduled_by_member_profile_id = v_current_member
  where id = p_fixture_id;

  --------------------------------------------------------------------
  -- Copy logical rink/team structure
  --
  -- Physical rink labels are deliberately NOT carried forward.
  --------------------------------------------------------------------

  insert into public.fixture_rinks (
    fixture_id,
    fixture_rink_no,
    format,
    players_per_rink,
    home_rink_label,
    marker_required
  )
  select
    v_new_fixture_id,
    fr.fixture_rink_no,
    fr.format,
    fr.players_per_rink,
    null,
    fr.marker_required
  from public.fixture_rinks fr
  where fr.fixture_id = p_fixture_id
  order by fr.fixture_rink_no;

  --------------------------------------------------------------------
  -- Carry picked players into same logical team/rink positions
  --------------------------------------------------------------------

  insert into public.fixture_rink_assignments (
    fixture_id,
    fixture_rink_id,
    member_profile_id,
    position,
    display_name
  )
  select
    v_new_fixture_id,
    new_fr.id,
    fra.member_profile_id,
    fra.position,
    fra.display_name
  from public.fixture_rink_assignments fra
  join public.fixture_rinks old_fr
    on old_fr.id = fra.fixture_rink_id
  join public.fixture_rinks new_fr
    on new_fr.fixture_id = v_new_fixture_id
   and new_fr.fixture_rink_no = old_fr.fixture_rink_no
  where fra.fixture_id = p_fixture_id;

  --------------------------------------------------------------------
  -- Find latest team selection on original fixture
  --------------------------------------------------------------------

  select
    ts.id,
    ts.status
  into
    v_old_team_selection_id,
    v_old_selection_status
  from public.team_selections ts
  where ts.fixture_id = p_fixture_id
  order by ts.created_at desc
  limit 1;

  --------------------------------------------------------------------
  -- Recreate team selection on replacement fixture
  --------------------------------------------------------------------

  if v_old_team_selection_id is not null then

    insert into public.team_selections (
      fixture_id,
      status,
      published_at,
      published_by_member_profile_id,
      captain_member_profile_id,
      vice_captain_member_profile_id
    )
    values (
      v_new_fixture_id,
      v_old_selection_status,

      case
        when v_old_selection_status::text = 'published'
          then now()
        else null
      end,

      case
        when v_old_selection_status::text = 'published'
          then v_current_member
        else null
      end,

      v_source.captain_member_profile_id,
      v_source.vice_captain_member_profile_id
    )
    returning id into v_new_team_selection_id;

    ------------------------------------------------------------------
    -- Carry players/reserves but reset ALL acceptance responses
    ------------------------------------------------------------------

    insert into public.team_selection_members (
      team_selection_id,
      member_profile_id,
      role,
      acceptance,
      responded_at,
      is_selected,
      acceptance_by
    )
    select
      v_new_team_selection_id,
      tsm.member_profile_id,
      tsm.role,
      'pending'::acceptance_status,
      null,
      tsm.is_selected,
      null
    from public.team_selection_members tsm
    where tsm.team_selection_id = v_old_team_selection_id;

  end if;

  --------------------------------------------------------------------
  -- Deliberately DO NOT copy fixture_rsvps.
  --
  -- Availability belongs to the old date.
  --------------------------------------------------------------------

  --------------------------------------------------------------------
  -- Queue reschedule communications
  --
  -- Precedence:
  --   1. Captain / Vice            -> manager
  --   2. Selected player/reserve   -> selected
  --   3. Other eligible member     -> availability
  --------------------------------------------------------------------

  for v_recipient in
  with managers as (
    select v_source.captain_member_profile_id as member_profile_id
    where v_source.captain_member_profile_id is not null

    union

    select v_source.vice_captain_member_profile_id
    where v_source.vice_captain_member_profile_id is not null
  ),

  selected_members as (
    select distinct tsm.member_profile_id
    from public.team_selection_members tsm
    where tsm.team_selection_id = v_new_team_selection_id
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
    from public.team_members tm
    where v_source.team_id is not null
      and tm.team_id = v_source.team_id
      and tm.is_active = true
  ),

  eligible_rsvp_members as (
    select distinct fr.member_profile_id
    from public.fixture_rsvps fr
    join public.club_memberships cm
      on cm.club_id = v_source.club_id
    and cm.member_profile_id = fr.member_profile_id
    and cm.is_active = true
    where v_source.team_id is null
      and fr.fixture_id = p_fixture_id
      and fr.status::text in ('yes', 'maybe')
  ),

  availability_members as (
    select member_profile_id
    from eligible_team_members

    union

    select member_profile_id
    from eligible_rsvp_members
  ),

  recipients as (
    ------------------------------------------------------------------
    -- Managers have highest precedence
    ------------------------------------------------------------------
    select
      m.member_profile_id,
      'fixture_rescheduled_manager'::text as event_type
    from managers m

    union all

    ------------------------------------------------------------------
    -- Selected players/reserves who are not managers
    ------------------------------------------------------------------
    select
      s.member_profile_id,
      'fixture_rescheduled_selected'::text
    from selected_members s

    union all

    ------------------------------------------------------------------
    -- Remaining eligible members can submit fresh availability
    ------------------------------------------------------------------
    select
      a.member_profile_id,
      'fixture_rescheduled_availability'::text
    from availability_members a
    where not exists (
      select 1
      from managers m
      where m.member_profile_id = a.member_profile_id
    )
    and not exists (
      select 1
      from selected_members s
      where s.member_profile_id = a.member_profile_id
    )
  )
  select
    r.member_profile_id,
    r.event_type,
    case
      when r.event_type = 'fixture_rescheduled_selected'
       and exists (
         select 1
         from public.fixture_rink_assignments fra
         join public.team_selection_members tsm
           on tsm.team_selection_id = v_new_team_selection_id
          and tsm.member_profile_id = fra.member_profile_id
          and coalesce(tsm.is_selected, false) = true
          and lower(tsm.role::text) = 'marker'
         where fra.fixture_id = v_new_fixture_id
           and fra.member_profile_id = r.member_profile_id
           and fra.position = 201
       )
        then 'marker'::text
      else null::text
    end as recipient_role
  from recipients r
  where r.member_profile_id is not null
  loop
    -- Replace only this recipient's undelivered cancellation with the
    -- rescheduling event. Sent cancellations remain part of the audit trail.
    delete from public.notification_queue nq
    where nq.fixture_id = p_fixture_id
      and nq.target_member_profile_id = v_recipient.member_profile_id
      and nq.event_type = 'fixture_cancelled'
      and nq.status = 'pending';

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
      v_recipient.event_type,
      v_current_member,
      v_recipient.member_profile_id,
      v_new_fixture_id,
      v_new_team_selection_id,
      jsonb_strip_nulls(
        jsonb_build_object(
          'fixture_label', v_fixture_label,
          'old_fixture_id', p_fixture_id,
          'new_fixture_id', v_new_fixture_id,
          'old_start_at', v_source.start_at,
          'old_end_at', v_source.end_at,
          'new_start_at', p_new_start_at,
          'new_end_at', p_new_end_at,
          'recipient_role', v_recipient.recipient_role
        )
      ),
      'pending'
    where not exists (
      select 1
      from public.notification_queue nq
      where nq.fixture_id = v_new_fixture_id
        and nq.target_member_profile_id = v_recipient.member_profile_id
        and nq.event_type = v_recipient.event_type
        and nq.status in ('pending', 'sent')
    );
  end loop;

  --------------------------------------------------------------------
  -- Lifecycle audit
  --------------------------------------------------------------------

  insert into public.fixture_lifecycle_events (
    fixture_id,
    event_type,
    old_start_at,
    old_end_at,
    new_start_at,
    new_end_at,
    reason,
    created_by_member_profile_id
  )
  values (
    p_fixture_id,
    'rescheduled',
    v_source.start_at,
    v_source.end_at,
    p_new_start_at,
    p_new_end_at,
    v_source.cancellation_reason,
    v_current_member
  );

  return v_new_fixture_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION audit_private.guard_archived_fixture()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 -- Cancellation reasons are optional; supplied reasons remain in the audit.
 RETURN NEW;
END $$;
CREATE OR REPLACE FUNCTION public.change_fixture_time_safe(
 p_fixture_id uuid,p_new_start_at timestamptz,p_new_end_at timestamptz,
 p_expected_start_at timestamptz,p_expected_end_at timestamptz)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE f public.fixtures%rowtype;
BEGIN
 SELECT * INTO f FROM public.fixtures WHERE id=p_fixture_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Fixture not found.'; END IF;
 IF NOT (public.can_manage_fixture(p_fixture_id) OR public.is_active_fixture_creator(p_fixture_id)) THEN
  RAISE EXCEPTION 'You do not have permission to change this fixture time.';
 END IF;
 IF f.cancelled_at IS NOT NULL OR f.archived_at IS NOT NULL THEN
  RAISE EXCEPTION 'Use reschedule for a cancelled fixture.';
 END IF;
 IF f.start_at IS DISTINCT FROM p_expected_start_at OR f.end_at IS DISTINCT FROM p_expected_end_at THEN
  RAISE EXCEPTION 'Fixture time has changed. Reopen the fixture and try again.';
 END IF;
 IF p_new_start_at IS NULL OR p_new_end_at IS NULL OR p_new_start_at>=p_new_end_at THEN
  RAISE EXCEPTION 'Invalid fixture start/end time.';
 END IF;
 IF p_new_start_at < now() THEN RAISE EXCEPTION 'A fixture cannot be moved into the past.'; END IF;
 IF f.start_at=p_new_start_at AND f.end_at=p_new_end_at THEN RETURN; END IF;
 -- Release physical labels in the same transaction as the time and notifications.
 -- Capacity/maintenance triggers still validate the new booking; failure rolls back all changes.
 UPDATE public.fixture_rinks SET home_rink_label=NULL WHERE fixture_id=p_fixture_id;
 UPDATE public.fixtures SET start_at=p_new_start_at,end_at=p_new_end_at WHERE id=p_fixture_id;
 PERFORM public.queue_fixture_moved_notifications(p_fixture_id,f.start_at,f.end_at);
END $$;
REVOKE ALL ON FUNCTION public.change_fixture_time_safe(uuid,timestamptz,timestamptz,timestamptz,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.change_fixture_time_safe(uuid,timestamptz,timestamptz,timestamptz,timestamptz) TO authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
