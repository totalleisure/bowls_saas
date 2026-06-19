CREATE OR REPLACE FUNCTION public.get_green_rink_availability(
  p_green_area_id uuid,
  p_start_at timestamp with time zone,
  p_end_at timestamp with time zone,
  p_exclude_fixture_id uuid default null
)
 RETURNS TABLE(rink_label text, is_booked boolean, booked_text text, background_hex text, foreground_hex text, total_rinks integer, physically_booked_rinks integer, capacity_booked_rinks integer, free_capacity_rinks integer, fixture_rink_id uuid, booked_fixture_id uuid)
 LANGUAGE sql
 STABLE
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
  capacity as (
    select
      g.rink_count as total_rinks,
      coalesce(sum(f.rinks_required), 0)::integer as capacity_booked_rinks
    from green g
    left join public.fixtures f
      on f.green_area_id = g.id
    and f.time_range && tstzrange(p_start_at, p_end_at, '[)')
    and (
      p_exclude_fixture_id is null
      or f.id <> p_exclude_fixture_id
    )
    group by g.id, g.rink_count
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
          'Captain: ' ||
          coalesce(
            nullif(
              trim(
                coalesce(captain.first_name, '') || ' ' ||
                coalesce(captain.last_name, '')
              ),
              ''
            ),
            'Not set'
          )
        else
          coalesce(opponent.name, 'Opponent not set')
      end,
      E'\n\n'
    ) as booked_text,
    min(cs.background_hex) as background_hex,
    min(cs.foreground_hex) as foreground_hex
  from public.fixture_rinks fr
  join public.fixtures f on f.id = fr.fixture_id
  left join public.competition_types ct on ct.id = f.competition_type_id
  left join public.fixture_colour_schemes cs on cs.id = ct.colour_scheme_id
  left join public.member_profiles captain
    on captain.id = f.captain_member_profile_id
  left join public.venues opponent
    on opponent.id = f.opponent_venue_id
  where f.green_area_id = p_green_area_id
    and fr.home_rink_label is not null
    and f.time_range && tstzrange(p_start_at, p_end_at, '[)')
    and (
      p_exclude_fixture_id is null
      or f.id <> p_exclude_fixture_id
    )
  group by fr.home_rink_label
),
  physical_count as (
    select count(*)::integer as physically_booked_rinks
    from booked
  )
select
  l.rink_label,
  b.home_rink_label is not null as is_booked,
  coalesce(b.booked_text, '') as booked_text,
  coalesce(b.background_hex, '#FEE2E2') as background_hex,
  coalesce(b.foreground_hex, '#991B1B') as foreground_hex,
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
  order by l.i;
$function$
