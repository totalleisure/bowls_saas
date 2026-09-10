create or replace function public.can_manage_fixture(p_fixture_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, auth
as $function$
  select
    coalesce(auth.jwt() ->> 'role', '') = 'service_role'
    or exists (
      select 1
      from public.app_superusers su
      where su.user_id = auth.uid()
    )
    or exists (
      select 1
      from public.fixtures f
      join public.club_memberships cm
        on cm.club_id = f.club_id
       and cm.member_profile_id = public.my_member_profile_id()
       and cm.is_active = true
       and lower(cm.role::text) <> 'guest'
      where f.id = p_fixture_id
        and (
          lower(cm.role::text) in ('admin', 'selector')
          or f.captain_member_profile_id = cm.member_profile_id
          or f.vice_captain_member_profile_id = cm.member_profile_id
        )
    );
$function$;

revoke all on function public.can_manage_fixture(uuid)
from public, anon;
grant execute on function public.can_manage_fixture(uuid)
to authenticated, service_role;

create or replace function public.can_manage_team_selection(p_fixture_id uuid)
returns boolean
language sql
stable
set search_path = pg_catalog, public, auth
as $function$
  select public.can_manage_fixture(p_fixture_id)
      or exists (
        select 1
          from public.fixtures f
          join public.club_memberships cm
            on cm.club_id = f.club_id
           and cm.member_profile_id = public.my_member_profile_id()
         where f.id = p_fixture_id
           and cm.is_active = true
           and lower(cm.role::text) = 'captain'
      );
$function$;

revoke all on function public.can_manage_team_selection(uuid)
from public, anon;
grant execute on function public.can_manage_team_selection(uuid)
to authenticated, service_role;

alter table public.fixture_rinks enable row level security;

drop policy if exists "fixture_rinks select (club members)"
on public.fixture_rinks;
create policy "fixture_rinks select (club members)"
on public.fixture_rinks
for select
to authenticated
using (
  exists (
    select 1
    from public.fixtures f
    join public.club_memberships cm
      on cm.club_id = f.club_id
     and cm.member_profile_id = public.my_member_profile_id()
     and cm.is_active = true
    where f.id = fixture_rinks.fixture_id
  )
  or exists (
    select 1 from public.app_superusers su where su.user_id = auth.uid()
  )
);

drop policy if exists "fixture_rinks insert (fixture managers)"
on public.fixture_rinks;
create policy "fixture_rinks insert (fixture managers)"
on public.fixture_rinks
for insert
to authenticated
with check (public.can_manage_fixture(fixture_id));

drop policy if exists "fixture_rinks update (fixture managers)"
on public.fixture_rinks;
create policy "fixture_rinks update (fixture managers)"
on public.fixture_rinks
for update
to authenticated
using (public.can_manage_fixture(fixture_id))
with check (public.can_manage_fixture(fixture_id));

drop policy if exists "fixture_rinks delete (fixture managers)"
on public.fixture_rinks;
create policy "fixture_rinks delete (fixture managers)"
on public.fixture_rinks
for delete
to authenticated
using (public.can_manage_fixture(fixture_id));

create or replace function public.swap_fixture_rink_labels(
  p_a_fixture_rink_id uuid,
  p_b_fixture_rink_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  a_label text;
  b_label text;
  a_fixture_id uuid;
  b_fixture_id uuid;
begin
  select fr.home_rink_label, fr.fixture_id
  into a_label, a_fixture_id
  from public.fixture_rinks fr
  where fr.id = p_a_fixture_rink_id;

  select fr.home_rink_label, fr.fixture_id
  into b_label, b_fixture_id
  from public.fixture_rinks fr
  where fr.id = p_b_fixture_rink_id;

  if a_fixture_id is null or b_fixture_id is null then
    raise exception 'Both fixture rinks must exist.';
  end if;

  if not public.can_manage_fixture(a_fixture_id)
     or not public.can_manage_fixture(b_fixture_id) then
    raise exception 'You do not have permission to move these rink bookings.';
  end if;

  if a_label is null or b_label is null then
    raise exception 'Both fixture rinks must have a home_rink_label before swapping.';
  end if;

  update public.fixture_rinks
  set home_rink_label = null
  where id = p_a_fixture_rink_id;

  update public.fixture_rinks
  set home_rink_label = a_label
  where id = p_b_fixture_rink_id;

  update public.fixture_rinks
  set home_rink_label = b_label
  where id = p_a_fixture_rink_id;
end;
$function$;

revoke all on function public.swap_fixture_rink_labels(uuid, uuid)
from public, anon;
grant execute on function public.swap_fixture_rink_labels(uuid, uuid)
to authenticated, service_role;

drop policy if exists "member captain can create preselect team selections"
on public.team_selections;
create policy "member captain can create preselect team selections"
on public.team_selections
for insert
to authenticated
with check (
  public.can_manage_fixture(fixture_id)
  and exists (
    select 1
    from public.fixtures f
    join public.competition_types ct on ct.id = f.competition_type_id
    where f.id = team_selections.fixture_id
      and ct.selection_mode = 'preselect'
      and ct.bookable_by_members = true
  )
);

drop policy if exists "member captain can insert preselect team selection members"
on public.team_selection_members;
create policy "member captain can insert preselect team selection members"
on public.team_selection_members
for insert
to authenticated
with check (
  exists (
    select 1
    from public.team_selections ts
    join public.fixtures f on f.id = ts.fixture_id
    join public.competition_types ct on ct.id = f.competition_type_id
    where ts.id = team_selection_members.team_selection_id
      and public.can_manage_fixture(f.id)
      and ct.selection_mode = 'preselect'
      and ct.bookable_by_members = true
  )
);

drop policy if exists "team_selection_members confirm own"
on public.team_selection_members;
create policy "team_selection_members confirm own"
on public.team_selection_members
for update
to authenticated
using (
  member_profile_id = public.my_member_profile_id()
  and exists (
    select 1
    from public.team_selections ts
    join public.fixtures f on f.id = ts.fixture_id
    join public.club_memberships cm
      on cm.club_id = f.club_id
     and cm.member_profile_id = team_selection_members.member_profile_id
     and cm.is_active = true
     and lower(cm.role::text) <> 'guest'
    where ts.id = team_selection_members.team_selection_id
      and ts.status = 'published'::public.selection_status
  )
)
with check (
  member_profile_id = public.my_member_profile_id()
  and exists (
    select 1
    from public.team_selections ts
    join public.fixtures f on f.id = ts.fixture_id
    join public.club_memberships cm
      on cm.club_id = f.club_id
     and cm.member_profile_id = team_selection_members.member_profile_id
     and cm.is_active = true
     and lower(cm.role::text) <> 'guest'
    where ts.id = team_selection_members.team_selection_id
      and ts.status = 'published'::public.selection_status
  )
);

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

  if not public.can_manage_fixture(p_fixture_id) then
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
$function$;

create or replace function public.queue_fixture_moved_notifications(
  p_fixture_id uuid,
  p_old_start_at timestamptz,
  p_old_end_at timestamptz default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_count int := 0;
begin
  if not public.can_manage_fixture(p_fixture_id) then
    raise exception 'You do not have permission to queue fixture-move notifications.';
  end if;

  insert into public.notification_queue (
    target_member_profile_id,
    event_type,
    fixture_id,
    payload,
    status,
    created_at
  )
  select distinct
    fra.member_profile_id,
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
  join public.fixture_rink_assignments fra
    on fra.fixture_id = f.id
  left join public.competition_types ct
    on ct.id = f.competition_type_id
  left join public.venues venue
    on venue.id = f.venue_id
  left join public.venues opponent
    on opponent.id = f.opponent_venue_id
  where f.id = p_fixture_id
    and fra.member_profile_id is not null
    and not exists (
      select 1
      from public.notification_queue existing
      where existing.fixture_id = f.id
        and existing.event_type = 'fixture_moved'
        and existing.target_member_profile_id = fra.member_profile_id
        and existing.payload ->> 'old_start_at' = p_old_start_at::text
        and coalesce(existing.payload ->> 'old_end_at', '') =
            coalesce(p_old_end_at::text, '')
        and existing.payload ->> 'new_start_at' = f.start_at::text
        and coalesce(existing.payload ->> 'new_end_at', '') =
            coalesce(f.end_at::text, '')
        and existing.status in ('pending', 'processing', 'sent')
    );

  get diagnostics v_count = row_count;

  return v_count;
end;
$function$;

revoke all on function public.queue_fixture_moved_notifications(
  uuid,
  timestamptz,
  timestamptz
)
from public, anon;
grant execute on function public.queue_fixture_moved_notifications(
  uuid,
  timestamptz,
  timestamptz
)
to authenticated, service_role;

create or replace function public.queue_fixture_opponent_changed_notifications(
  p_fixture_id uuid,
  p_old_opponent_venue_id uuid,
  p_new_opponent_venue_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_changed_by_member_profile_id uuid;
  v_team_selection_id uuid;

  v_old_opponent_name text;
  v_new_opponent_name text;

  v_start_at timestamptz;
  v_fixture_name text;
  v_team_name text;
  v_selection_mode text;
  v_is_published boolean := false;

  v_queued_count integer := 0;
begin
  /*
   * Who made the change?
   */
  select public.my_member_profile_id()
  into v_changed_by_member_profile_id;

  /*
   * Current fixture details.
   */
  select
    f.start_at,
    coalesce(nullif(ct.name, ''), 'Fixture'),
    nullif(
      trim(
        coalesce(t.name, f.team_name, '')
      ),
      ''
    ),
    lower(coalesce(ct.selection_mode, ''))
  into
    v_start_at,
    v_fixture_name,
    v_team_name,
    v_selection_mode
  from public.fixtures f
  left join public.competition_types ct
    on ct.id = f.competition_type_id
  left join public.teams t
    on t.id = f.team_id
  where f.id = p_fixture_id;

  if not found then
    raise exception 'Fixture % was not found', p_fixture_id;
  end if;

  if not public.can_manage_fixture(p_fixture_id) then
    raise exception 'You do not have permission to queue opponent-change notifications.';
  end if;

  /*
   * Venue names before and after the change.
   */
  select name
  into v_old_opponent_name
  from public.venues
  where id = p_old_opponent_venue_id;

  select name
  into v_new_opponent_name
  from public.venues
  where id = p_new_opponent_venue_id;

  v_old_opponent_name :=
    coalesce(nullif(v_old_opponent_name, ''), 'To be confirmed');

  v_new_opponent_name :=
    coalesce(nullif(v_new_opponent_name, ''), 'To be confirmed');

  /*
   * Current team selection, if one exists.
   */
  select
  id,
  status = 'published'
  into
  v_team_selection_id,
  v_is_published
  from public.team_selections
  where fixture_id = p_fixture_id
  order by created_at desc nulls last
  limit 1;

  /*
 * Before publication, opponent changes are still part of fixture preparation.
 * Do not notify selected members until the fixture has been published.
 */
  if coalesce(v_is_published, false) = false then
  return 0;
  end if;

  /*
   * Build one deduplicated recipient set.
   *
   * Recipients:
   *   - fixture captain
   *   - fixture vice-captain
   *   - selected team-selection members
   *   - RSVP Yes / Maybe members
   *
   * The person making the change is excluded.
   */
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
    join public.team_selections ts
      on ts.id = tsm.team_selection_id
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
      'fixture_opponent_changed',
      v_changed_by_member_profile_id,
      r.member_profile_id,
      p_fixture_id,
      v_team_selection_id,
      jsonb_build_object(
        'old_opponent_venue_id', p_old_opponent_venue_id,
        'new_opponent_venue_id', p_new_opponent_venue_id,
        'old_opponent_name', v_old_opponent_name,
        'new_opponent_name', v_new_opponent_name,
        'start_at', v_start_at,
        'fixture_name', v_fixture_name,
        'team_name', v_team_name,
        'selection_mode', v_selection_mode
      ),
      'pending'
    from recipients r
    where r.member_profile_id is not null
      and (
        v_changed_by_member_profile_id is null
        or r.member_profile_id <> v_changed_by_member_profile_id
      )
    returning 1
  )
  select count(*)
  into v_queued_count
  from inserted;

  return v_queued_count;
end;
$$;

create or replace function public.publish_team_selection_safe(
  p_fixture_id uuid,
  p_team_selection_id uuid,
  p_allow_incomplete boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_current_member uuid := public.my_member_profile_id();
  v_required integer;
  v_assigned integer;
begin
  if v_current_member is null then
    raise exception 'Not signed in.';
  end if;

  if not public.can_manage_team_selection(p_fixture_id) then
    raise exception 'You do not have permission to publish this team.';
  end if;

  select coalesce(sum(players_per_rink), 0)
  into v_required
  from public.fixture_rinks
  where fixture_id = p_fixture_id;

  select count(*)
  into v_assigned
  from public.fixture_rink_assignments fra
  join public.fixture_rinks fr on fr.id = fra.fixture_rink_id
  where fra.fixture_id = p_fixture_id
    and fra.position between 1 and fr.players_per_rink;

  if v_required > 0 and v_assigned < v_required and p_allow_incomplete = false then
    raise exception 'INCOMPLETE_TEAM:%:%', v_required, v_assigned;
  end if;

  update public.team_selections
  set
    status = 'published'::selection_status,
    published_by_member_profile_id = v_current_member
  where id = p_team_selection_id
    and fixture_id = p_fixture_id;

  if not found then
    raise exception 'Team selection not found for this fixture.';
  end if;

  perform public.queue_team_publication_communications(
    p_fixture_id,
    p_team_selection_id,
    p_allow_incomplete
  ); 
end;
$$;

CREATE OR REPLACE FUNCTION public.queue_team_publication_communications(p_fixture_id uuid, p_team_selection_id uuid, p_allow_incomplete boolean DEFAULT false)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_current_member uuid := public.my_member_profile_id();
  v_fixture_label text;
  v_start_at timestamptz;
  v_home_away text;
  v_venue_name text;
  v_team_id uuid;
  v_captain uuid;
  v_vice uuid;
  v_required integer;
  v_assigned integer;
  v_missing integer;
  v_count integer := 0;
begin
  if v_current_member is null then
    raise exception 'Not signed in.';
  end if;

  if not public.can_manage_team_selection(p_fixture_id) then
    raise exception 'You do not have permission to queue team communications.';
  end if;

  select
    coalesce(nullif(f.team_name, ''), 'Fixture'),
    f.start_at,
    case when f.is_home then 'Home' else 'Away' end,
    coalesce(v.name, ov.name, ''),
    f.team_id,
    f.captain_member_profile_id,
    f.vice_captain_member_profile_id
  into
    v_fixture_label,
    v_start_at,
    v_home_away,
    v_venue_name,
    v_team_id,
    v_captain,
    v_vice
  from public.fixtures f
  left join public.venues v on v.id = f.venue_id
  left join public.venues ov on ov.id = f.opponent_venue_id
  where f.id = p_fixture_id;

  select coalesce(sum(players_per_rink), 0)
  into v_required
  from public.fixture_rinks
  where fixture_id = p_fixture_id;

  select count(*)
  into v_assigned
  from public.fixture_rink_assignments fra
  join public.fixture_rinks fr
    on fr.id = fra.fixture_rink_id
  where fra.fixture_id = p_fixture_id
    and fra.member_profile_id is not null
    and fra.position between 1 and fr.players_per_rink;

  v_missing := greatest(v_required - v_assigned, 0);

  -- Assigned players
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
    'team_published_player',
    v_current_member,
    fra.member_profile_id,
    p_fixture_id,
    p_team_selection_id,
    jsonb_build_object(
      'fixture_label', v_fixture_label,
      'fixture_date', v_start_at,
      'home_away', v_home_away,
      'venue_name', v_venue_name,
      'missing_players', v_missing,
      'team_sheet_required', true
    ),
    'pending'
  from public.fixture_rink_assignments fra
  join public.fixture_rinks fr
    on fr.id = fra.fixture_rink_id
  where fra.fixture_id = p_fixture_id

    -- Only real club members can receive a player notification.
    and fra.member_profile_id is not null

    -- Only actual player positions, not opponents/markers/request rows.
    and fra.position between 1 and fr.players_per_rink

    and not exists (
      select 1
      from public.notification_queue nq
      where nq.fixture_id = p_fixture_id
        and nq.team_selection_id = p_team_selection_id
        and nq.target_member_profile_id = fra.member_profile_id
        and nq.event_type = 'team_published_player'
    );

  get diagnostics v_count = row_count;

  -- Reserves
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
    'team_published_reserve',
    v_current_member,
    tsm.member_profile_id,
    p_fixture_id,
    p_team_selection_id,
    jsonb_build_object(
      'fixture_label', v_fixture_label,
      'fixture_date', v_start_at,
      'home_away', v_home_away,
      'venue_name', v_venue_name,
      'missing_players', v_missing,
      'team_sheet_required', true
    ),
    'pending'
  from public.team_selection_members tsm
  where tsm.team_selection_id = p_team_selection_id
    and tsm.is_selected = true
    and tsm.role = 'reserve'::selection_member_role
    and not exists (
      select 1
      from public.notification_queue nq
      where nq.fixture_id = p_fixture_id
        and nq.team_selection_id = p_team_selection_id
        and nq.target_member_profile_id = tsm.member_profile_id
        and nq.event_type = 'team_published_reserve'
    );

  -- Captain copy
  if v_captain is not null then
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
      'team_published_captain',
      v_current_member,
      v_captain,
      p_fixture_id,
      p_team_selection_id,
      jsonb_build_object(
        'fixture_label', v_fixture_label,
        'fixture_date', v_start_at,
        'home_away', v_home_away,
        'venue_name', v_venue_name,
        'missing_players', v_missing,
        'team_sheet_required', true
      ),
      'pending'
    where not exists (
      select 1
      from public.notification_queue nq
      where nq.fixture_id = p_fixture_id
        and nq.team_selection_id = p_team_selection_id
        and nq.target_member_profile_id = v_captain
        and nq.event_type = 'team_published_captain'
    );
  end if;

  -- Vice captain copy
  if v_vice is not null and v_vice is distinct from v_captain then
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
      'team_published_vice',
      v_current_member,
      v_vice,
      p_fixture_id,
      p_team_selection_id,
      jsonb_build_object(
        'fixture_label', v_fixture_label,
        'fixture_date', v_start_at,
        'home_away', v_home_away,
        'venue_name', v_venue_name,
        'missing_players', v_missing,
        'team_sheet_required', true
      ),
      'pending'
    where not exists (
      select 1
      from public.notification_queue nq
      where nq.fixture_id = p_fixture_id
        and nq.team_selection_id = p_team_selection_id
        and nq.target_member_profile_id = v_vice
        and nq.event_type = 'team_published_vice'
    );
  end if;

  -- Available but not selected: notification/email, no team sheet.
  -- Assumes team_members has team_id/member_profile_id/is_active.
  if v_team_id is not null then
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
      case
        when p_allow_incomplete = true and v_missing > 0
          then 'team_published_incomplete_request'
        else 'team_published_not_selected'
      end,
      v_current_member,
      tm.member_profile_id,
      p_fixture_id,
      p_team_selection_id,
      jsonb_build_object(
        'fixture_label', v_fixture_label,
        'fixture_date', v_start_at,
        'home_away', v_home_away,
        'venue_name', v_venue_name,
        'missing_players', v_missing,
        'team_sheet_required', false
      ),
      'pending'
    from public.team_members tm
    where tm.team_id = v_team_id
      and tm.member_profile_id is not null
      and coalesce(tm.is_active, true) = true
      and not exists (
        select 1
        from public.team_selection_members tsm
        where tsm.team_selection_id = p_team_selection_id
          and tsm.member_profile_id = tm.member_profile_id
          and tsm.is_selected = true
      )
      and not exists (
        select 1
        from public.notification_queue nq
        where nq.fixture_id = p_fixture_id
          and nq.team_selection_id = p_team_selection_id
          and nq.target_member_profile_id = tm.member_profile_id
          and nq.event_type in (
            'team_published_not_selected',
            'team_published_incomplete_request'
          )
      );
  end if;

  return v_count;
end;
$function$;

revoke all on function
  public.queue_team_publication_communications(uuid, uuid, boolean)
from public, anon;

grant execute on function
  public.queue_team_publication_communications(uuid, uuid, boolean)
to authenticated;

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

  v_has_permission := public.can_manage_fixture(p_fixture_id);

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

CREATE OR REPLACE FUNCTION public.reconcile_preselect_communications(p_fixture_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_actor_member_profile_id uuid;
  v_club_id uuid;
  v_team_selection_id uuid;
  v_selection_mode text := '';
  v_is_superuser boolean := false;
  v_has_permission boolean := false;
  v_fixture_selected_queued integer := 0;
  v_leadership_queued integer := 0;
  v_fixture_label text;
  v_start_at timestamptz;
  v_is_home boolean;
  v_venue_name text;
  v_captain uuid;
  v_vice uuid;
  v_marker_result jsonb := '{}'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  select
    f.club_id,
    ts.id,
    lower(coalesce(ct.selection_mode::text, '')),
    coalesce(nullif(btrim(f.team_name), ''), nullif(btrim(ct.name), ''), 'Pre-Select Fixture'),
    f.start_at,
    f.is_home,
    coalesce(v.name, ov.name, ''),
    f.captain_member_profile_id,
    f.vice_captain_member_profile_id
  into
    v_club_id,
    v_team_selection_id,
    v_selection_mode,
    v_fixture_label,
    v_start_at,
    v_is_home,
    v_venue_name,
    v_captain,
    v_vice
  from public.fixtures f
  left join public.competition_types ct
    on ct.id = f.competition_type_id
  left join public.venues v on v.id = f.venue_id
  left join public.venues ov on ov.id = f.opponent_venue_id
  left join lateral (
    select x.id
    from public.team_selections x
    where x.fixture_id = f.id
    order by x.created_at desc
    limit 1
  ) ts on true
  where f.id = p_fixture_id;

  if not found then
    raise exception 'Fixture not found.';
  end if;

  if v_team_selection_id is null then
    raise exception 'No team selection exists for this fixture.';
  end if;

  if v_selection_mode <> 'preselect' then
    raise exception 'This repair routine is only for Pre-Select fixtures.';
  end if;

  select public.my_member_profile_id()
  into v_actor_member_profile_id;

  select exists (
    select 1
    from public.app_superusers su
    where su.user_id = auth.uid()
  )
  into v_is_superuser;

  v_has_permission := public.can_manage_fixture(p_fixture_id);

  if not v_has_permission then
    raise exception
      'You do not have permission to repair this fixture''s communications.';
  end if;

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
    'fixture_selected',
    v_actor_member_profile_id,
    fra.member_profile_id,
    p_fixture_id,
    v_team_selection_id,
    jsonb_build_object(
      'fixture_label',
        coalesce(
          nullif(btrim(f.team_name), ''),
          nullif(btrim(ct.name), ''),
          'Pre-Select Fixture'
        ),
      'start_at', f.start_at,
      'fixture_date', f.start_at,
      'fixture_rink_id', fr.id,
      'team_no', fr.fixture_rink_no,
      'home_rink_label', fr.home_rink_label,
      'players_per_rink', fr.players_per_rink,
      'position', fra.position,
      'role',
        case
          when fra.position = 201 then 'marker'
          when fra.position between 101 and (100 + fr.players_per_rink)
            then 'opponent'
          else 'player'
        end,
      'team_sheet_required', true
    ),
    'pending'
  from public.fixture_rink_assignments fra
  join public.fixture_rinks fr
    on fr.id = fra.fixture_rink_id
  join public.fixtures f
    on f.id = fr.fixture_id
  left join public.competition_types ct
    on ct.id = f.competition_type_id
  where fra.fixture_id = p_fixture_id
    and fra.member_profile_id is not null
    and (
      fra.position between 1 and fr.players_per_rink
      or fra.position between 101 and (100 + fr.players_per_rink)
      or fra.position = 201
    )
    and (
      fra.member_profile_id = any(
        coalesce(
          string_to_array(
            nullif(
              current_setting('app.preselect_reselected_member_ids', true),
              ''
            ),
            ','
          )::uuid[],
          array[]::uuid[]
        )
      )
      or not exists (
        select 1
        from public.notification_queue nq
        where nq.fixture_id = p_fixture_id
          and nq.team_selection_id = v_team_selection_id
          and nq.event_type = 'fixture_selected'
          and nq.target_member_profile_id = fra.member_profile_id
          and (
            nullif(nq.payload ->> 'position', '') is null
            or nq.payload ->> 'position' = fra.position::text
          )
          and (
            nullif(nq.payload ->> 'team_no', '') is null
            or nq.payload ->> 'team_no' = fr.fixture_rink_no::text
          )
      )
    );

  get diagnostics v_fixture_selected_queued = row_count;

  -- Leadership who are not already receiving an assignment-specific message
  -- receive one informational publication copy of the same Team Sheet.
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
    leadership.event_type,
    v_actor_member_profile_id,
    leadership.member_profile_id,
    p_fixture_id,
    v_team_selection_id,
    jsonb_build_object(
      'fixture_label', v_fixture_label,
      'fixture_date', v_start_at,
      'start_at', v_start_at,
      'home_away', case when v_is_home then 'Home' else 'Away' end,
      'venue_name', v_venue_name,
      'team_sheet_required', true
    ),
    'pending'
  from (
    values
      ('team_published_captain'::text, v_captain),
      ('team_published_vice'::text, v_vice)
  ) as leadership(event_type, member_profile_id)
  where leadership.member_profile_id is not null
    and not exists (
      select 1
      from public.notification_queue existing
      where existing.fixture_id = p_fixture_id
        and existing.team_selection_id = v_team_selection_id
        and existing.target_member_profile_id = leadership.member_profile_id
        and existing.status in ('pending', 'sent')
        and existing.event_type in (
          'fixture_selected',
          'team_published_captain',
          'team_published_vice'
        )
    );

  get diagnostics v_leadership_queued = row_count;

  -- Reuses the existing duplicate-safe marker routine.
  select public.queue_open_marker_request_communications(p_fixture_id)
  into v_marker_result;

  return jsonb_build_object(
    'fixture_id', p_fixture_id,
    'fixture_selected_queued', v_fixture_selected_queued,
    'leadership_queued', v_leadership_queued,
    'marker_communications',
      coalesce(v_marker_result, '{}'::jsonb),
    'total_communications_queued',
      v_fixture_selected_queued
      + v_leadership_queued
      + coalesce(
          (v_marker_result ->> 'communications_queued')::integer,
          0
        )
  );
end;
$function$;


revoke all on function public.reconcile_preselect_communications(uuid) from public;
revoke all on function public.reconcile_preselect_communications(uuid) from anon;
revoke all on function public.reconcile_preselect_communications(uuid) from authenticated;

create or replace function public.enforce_non_guest_fixture_notification_actor()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
begin
  if auth.uid() is not null
     and new.fixture_id is not null
     and coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
     and not exists (
       select 1
       from public.app_superusers su
       where su.user_id = auth.uid()
     )
     and not exists (
       select 1
       from public.fixtures f
       join public.club_memberships cm
         on cm.club_id = f.club_id
        and cm.member_profile_id = public.my_member_profile_id()
        and cm.is_active = true
        and lower(cm.role::text) <> 'guest'
       where f.id = new.fixture_id
     ) then
    raise exception 'Guest members cannot create fixture communications.'
      using errcode = '42501';
  end if;

  return new;
end;
$function$;

revoke all on function public.enforce_non_guest_fixture_notification_actor()
from public, anon, authenticated;

drop trigger if exists enforce_non_guest_fixture_notification_actor
on public.notification_queue;
create trigger enforce_non_guest_fixture_notification_actor
before insert
on public.notification_queue
for each row
execute function public.enforce_non_guest_fixture_notification_actor();
