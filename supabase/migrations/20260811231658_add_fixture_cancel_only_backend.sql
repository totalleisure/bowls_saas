create or replace function public.cancel_fixture_safe(
  p_fixture_id uuid,
  p_reason text default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
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
      and cm.role = 'admin'
  ) into v_is_admin;

  select exists (
    select 1
    from public.app_superusers su
    where su.user_id = auth.uid()
  ) into v_is_super;

  if not (v_is_admin or v_is_super or v_is_captain_or_vice) then
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
$$;

create or replace function public.get_green_rink_availability(
  p_green_area_id uuid,
  p_start_at timestamp with time zone,
  p_end_at timestamp with time zone,
  p_exclude_fixture_id uuid default null
)
returns table(
  rink_label text,
  is_booked boolean,
  booked_text text,
  background_hex text,
  foreground_hex text,
  total_rinks integer,
  physically_booked_rinks integer,
  capacity_booked_rinks integer,
  free_capacity_rinks integer,
  fixture_rink_id uuid,
  booked_fixture_id uuid
)
language sql
stable
set search_path to public, pg_temp
as $$
  with green as (
    select *
    from public.green_areas
    where id = p_green_area_id
  ),
  labels as (
    select
      i,
      case
        when g.scheme_type = 'custom_list' then g.custom_labels[i]
        when g.scheme_type = 'alpha' then coalesce(g.scheme_prefix, '') || chr(64 + i)
        else
          coalesce(g.scheme_prefix, '') ||
          case
            when coalesce(g.scheme_padding, 0) > 0
              then lpad(i::text, g.scheme_padding, '0')
            else i::text
          end
      end as rink_label
    from green g
    cross join generate_series(1, g.rink_count) as i
  ),
  fixture_capacity as (
    select coalesce(sum(f.rinks_required), 0)::integer as booked
    from green g
    left join public.fixtures f
      on f.green_area_id = g.id
     and f.cancelled_at is null
     and f.time_range && tstzrange(p_start_at, p_end_at, '[)')
     and (p_exclude_fixture_id is null or f.id <> p_exclude_fixture_id)
  ),
  maintenance_capacity as (
    select count(distinct m.rink_number)::integer as blocked
    from public.green_rink_maintenance m
    where m.green_area_id = p_green_area_id
      and m.status = 'active'
      and m.time_range && tstzrange(p_start_at, p_end_at, '[)')
  ),
  capacity as (
    select
      g.rink_count as total_rinks,
      (fc.booked + mc.blocked)::integer as capacity_booked_rinks
    from green g
    cross join fixture_capacity fc
    cross join maintenance_capacity mc
  ),
  booked as (
    select
      fr.home_rink_label,
      (array_agg(fr.id order by f.start_at, fr.id))[1] as fixture_rink_id,
      (array_agg(fr.fixture_id order by f.start_at, fr.id))[1] as booked_fixture_id,
      string_agg(
        coalesce(ct.name, 'Fixture') || ' ' ||
        to_char(f.start_at at time zone 'Europe/London', 'HH24:MI') ||
        ' - ' ||
        to_char(f.end_at at time zone 'Europe/London', 'HH24:MI') ||
        E'\n' ||
        case
          when coalesce(ct.is_internal, false) = true then
            'Captain: ' || coalesce(
              nullif(trim(coalesce(captain.first_name, '') || ' ' || coalesce(captain.last_name, '')), ''),
              'Not set'
            )
          else coalesce(opponent.name, 'Opponent not set')
        end,
        E'\n\n'
      ) as booked_text,
      min(cs.background_hex) as background_hex,
      min(cs.foreground_hex) as foreground_hex
    from public.fixture_rinks fr
    join public.fixtures f on f.id = fr.fixture_id
    left join public.competition_types ct on ct.id = f.competition_type_id
    left join public.fixture_colour_schemes cs on cs.id = ct.colour_scheme_id
    left join public.member_profiles captain on captain.id = f.captain_member_profile_id
    left join public.venues opponent on opponent.id = f.opponent_venue_id
    where f.green_area_id = p_green_area_id
      and f.cancelled_at is null
      and fr.home_rink_label is not null
      and f.time_range && tstzrange(p_start_at, p_end_at, '[)')
      and (p_exclude_fixture_id is null or f.id <> p_exclude_fixture_id)
    group by fr.home_rink_label
  ),
  maintenance as (
    select
      l.rink_label,
      string_agg(
        coalesce(nullif(btrim(m.reason), ''), 'Maintenance') || ' ' ||
        to_char(m.start_at at time zone 'Europe/London', 'HH24:MI') || ' - ' ||
        to_char(m.end_at at time zone 'Europe/London', 'HH24:MI'),
        E'\n\n'
      ) as maintenance_text
    from public.green_rink_maintenance m
    join labels l on l.i = m.rink_number
    where m.green_area_id = p_green_area_id
      and m.status = 'active'
      and m.time_range && tstzrange(p_start_at, p_end_at, '[)')
    group by l.rink_label
  ),
  physical_count as (
    select count(distinct rink_label)::integer as physically_booked_rinks
    from (
      select home_rink_label as rink_label from booked
      union all
      select rink_label from maintenance
    ) x
  )
  select
    l.rink_label,
    (b.home_rink_label is not null or m.rink_label is not null) as is_booked,
    case
      when m.rink_label is not null then m.maintenance_text
      else coalesce(b.booked_text, '')
    end as booked_text,
    case
      when m.rink_label is not null then '#FEE2E2'
      else coalesce(b.background_hex, '#FEE2E2')
    end as background_hex,
    case
      when m.rink_label is not null then '#991B1B'
      else coalesce(b.foreground_hex, '#991B1B')
    end as foreground_hex,
    c.total_rinks,
    pc.physically_booked_rinks,
    c.capacity_booked_rinks,
    greatest(c.total_rinks - c.capacity_booked_rinks, 0)::integer as free_capacity_rinks,
    b.fixture_rink_id,
    b.booked_fixture_id
  from labels l
  cross join capacity c
  cross join physical_count pc
  left join booked b on b.home_rink_label = l.rink_label
  left join maintenance m on m.rink_label = l.rink_label
  order by l.i;
$$;
