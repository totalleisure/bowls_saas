-- Correct peak concurrent rink capacity. No tables, data, policies or triggers are changed.
BEGIN;
CREATE OR REPLACE FUNCTION public.get_green_rink_availability(p_green_area_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_exclude_fixture_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(rink_label text, is_booked boolean, booked_text text, background_hex text, foreground_hex text, total_rinks integer, physically_booked_rinks integer, capacity_booked_rinks integer, free_capacity_rinks integer, fixture_rink_id uuid, booked_fixture_id uuid)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  overlapping_fixtures as (
    select f.time_range, f.rinks_required
    from public.fixtures f
    where f.green_area_id = p_green_area_id
      and f.cancelled_at is null
      and f.time_range && tstzrange(p_start_at, p_end_at, '[)')
      and (p_exclude_fixture_id is null or f.id <> p_exclude_fixture_id)
  ),
  overlapping_maintenance as (
    select m.time_range, m.rink_number
    from public.green_rink_maintenance m
    where m.green_area_id = p_green_area_id
      and m.status = 'active'
      and m.time_range && tstzrange(p_start_at, p_end_at, '[)')
  ),
  -- Occupancy can increase only at the requested start or an interval start.
  -- [start,end) excludes bookings ending exactly when the next one starts.
  capacity_points as (
    select p_start_at as at_time where p_start_at < p_end_at
    union
    select greatest(lower(time_range), p_start_at) from overlapping_fixtures
    union
    select greatest(lower(time_range), p_start_at) from overlapping_maintenance
  ),
  capacity as (
    select g.rink_count as total_rinks,
      coalesce((select max(
        coalesce((select sum(f.rinks_required) from overlapping_fixtures f
                  where f.time_range @> p.at_time), 0)
        + (select count(distinct m.rink_number) from overlapping_maintenance m
           where m.time_range @> p.at_time)
      ) from capacity_points p), 0)::integer as capacity_booked_rinks
    from green g
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
$function$;

CREATE OR REPLACE FUNCTION public.check_green_area_rink_capacity()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_green_rink_count integer;
  v_overlapping_rinks integer;
begin
  if new.green_area_id is null or new.cancelled_at is not null then
    return new;
  end if;

  if new.rinks_required is null or new.rinks_required < 1 then
    raise exception 'Rinks required must be at least 1 when a green area is selected';
  end if;

  select ga.rink_count into v_green_rink_count
  from public.green_areas ga
  where ga.id = new.green_area_id;

  if v_green_rink_count is null then
    raise exception 'Selected green area was not found';
  end if;

  -- fixtures_set_time_range runs before this trigger, preserving its 4-hour fallback.
  select coalesce(max(a.capacity_booked_rinks), 0)
    into v_overlapping_rinks
  from public.get_green_rink_availability(
    new.green_area_id, lower(new.time_range), upper(new.time_range), new.id
  ) a;

  if v_overlapping_rinks + new.rinks_required > v_green_rink_count then
    raise exception 'Not enough rinks available for this time slot on the selected green';
  end if;

  return new;
end;
$function$;

COMMIT;
