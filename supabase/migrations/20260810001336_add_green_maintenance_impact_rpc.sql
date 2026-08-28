create or replace function public.get_green_maintenance_impacts(
  p_green_area_id uuid,
  p_rink_labels text[],
  p_start_at timestamptz,
  p_end_at timestamptz
)
returns table (
  source_kind text,
  source_id uuid,
  linked_fixture_id uuid,
  title text,
  item_start_at timestamptz,
  item_end_at timestamptz,
  rinks_required integer,
  allocated_rinks integer,
  directly_uses_maintenance_rink boolean,
  capacity_conflict boolean,
  affected_rink_labels text[],
  available_rinks integer,
  peak_committed_rinks integer,
  capacity_shortfall integer,
  impact_reason text
)
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_rink_count integer;
  v_unavailable_count integer;
begin
  if p_green_area_id is null then
    raise exception 'Green area id is required.';
  end if;

  if p_start_at is null or p_end_at is null or p_start_at >= p_end_at then
    raise exception 'A valid maintenance start/end time is required.';
  end if;

  select ga.rink_count
    into v_rink_count
  from public.green_areas ga
  where ga.id = p_green_area_id;

  if v_rink_count is null then
    raise exception 'Green area was not found.';
  end if;

  select count(distinct nullif(btrim(x), ''))::integer
    into v_unavailable_count
  from unnest(coalesce(p_rink_labels, array[]::text[])) as u(x)
  where nullif(btrim(x), '') is not null;

  if coalesce(v_unavailable_count, 0) < 1 then
    raise exception 'At least one rink label is required.';
  end if;

  if exists (
    with generated_labels as (
      select
        case
          when ga.scheme_type = 'custom_list' then ga.custom_labels[i]
          when ga.scheme_type = 'alpha' then coalesce(ga.scheme_prefix, '') || chr(64 + i)
          else
            coalesce(ga.scheme_prefix, '') ||
            case
              when coalesce(ga.scheme_padding, 0) > 0
                then lpad(i::text, ga.scheme_padding, '0')
              else i::text
            end
        end as rink_label
      from public.green_areas ga
      cross join generate_series(1, ga.rink_count) as i
      where ga.id = p_green_area_id
    )
    select 1
    from (
      select distinct nullif(btrim(x), '') as rink_label
      from unnest(coalesce(p_rink_labels, array[]::text[])) as u(x)
      where nullif(btrim(x), '') is not null
    ) requested
    left join generated_labels gl
      on gl.rink_label = requested.rink_label
    where gl.rink_label is null
  ) then
    raise exception 'One or more maintenance rink labels are not valid for this green.';
  end if;

  return query
  with requested_rinks as (
    select distinct nullif(btrim(x), '') as rink_label
    from unnest(coalesce(p_rink_labels, array[]::text[])) as u(x)
    where nullif(btrim(x), '') is not null
  ),
  fixture_items as (
    select
      'fixture'::text as source_kind,
      f.id as source_id,
      f.id as linked_fixture_id,
      case
        when nullif(btrim(f.team_name), '') is not null
             and nullif(btrim(f.opponent_name), '') is not null
          then btrim(f.team_name) || ' v ' || btrim(f.opponent_name)
        when nullif(btrim(f.opponent_name), '') is not null
          then 'v ' || btrim(f.opponent_name)
        when nullif(btrim(f.team_name), '') is not null
          then btrim(f.team_name)
        else coalesce(nullif(btrim(ct.name), ''), 'Fixture')
      end as title,
      f.start_at as item_start_at,
      coalesce(f.end_at, upper(f.time_range), f.start_at + interval '3 hours') as item_end_at,
      greatest(coalesce(f.rinks_required, 0), 0)::integer as rinks_required,
      count(fr.id) filter (where fr.home_rink_label is not null)::integer as allocated_rinks,
      coalesce(
        bool_or(rr.rink_label is not null),
        false
      ) as directly_uses_maintenance_rink,
      coalesce(
        array_agg(distinct fr.home_rink_label)
          filter (where rr.rink_label is not null),
        array[]::text[]
      ) as affected_rink_labels
    from public.fixtures f
    left join public.competition_types ct
      on ct.id = f.competition_type_id
    left join public.fixture_rinks fr
      on fr.fixture_id = f.id
    left join requested_rinks rr
      on rr.rink_label = fr.home_rink_label
    where f.green_area_id = p_green_area_id
      and f.is_home = true
      and tstzrange(
            f.start_at,
            coalesce(f.end_at, upper(f.time_range), f.start_at + interval '3 hours'),
            '[)'
          ) && tstzrange(p_start_at, p_end_at, '[)')
    group by
      f.id,
      f.team_name,
      f.opponent_name,
      ct.name,
      f.start_at,
      f.end_at,
      f.time_range,
      f.rinks_required
  ),
  schedule_items as (
    select
      'schedule_item'::text as source_kind,
      csi.id as source_id,
      csi.linked_fixture_id,
      coalesce(nullif(btrim(csi.title), ''), 'Schedule item') as title,
      csi.start_at as item_start_at,
      csi.end_at as item_end_at,
      greatest(coalesce(csi.rinks_required, 0), 0)::integer as rinks_required,
      0::integer as allocated_rinks,
      false as directly_uses_maintenance_rink,
      array[]::text[] as affected_rink_labels
    from public.club_schedule_items csi
    where csi.green_area_id = p_green_area_id
      and csi.is_home = true
      and csi.needs_rinks = true
      and coalesce(csi.rinks_required, 0) > 0
      and csi.linked_fixture_id is null
      and tstzrange(csi.start_at, csi.end_at, '[)')
          && tstzrange(p_start_at, p_end_at, '[)')
  ),
  commitments as (
    select * from fixture_items
    union all
    select * from schedule_items
  ),
  boundary_points as (
    select p_start_at as point
    union
    select p_end_at
    union
    select greatest(c.item_start_at, p_start_at)
    from commitments c
    union
    select least(c.item_end_at, p_end_at)
    from commitments c
  ),
  ordered_boundaries as (
    select
      point as segment_start,
      lead(point) over (order by point) as segment_end
    from boundary_points
    where point >= p_start_at
      and point <= p_end_at
  ),
  segments as (
    select segment_start, segment_end
    from ordered_boundaries
    where segment_end is not null
      and segment_start < segment_end
  ),
  segment_loads as (
    select
      s.segment_start,
      s.segment_end,
      coalesce(sum(c.rinks_required), 0)::integer as committed_rinks
    from segments s
    left join commitments c
      on tstzrange(c.item_start_at, c.item_end_at, '[)')
         && tstzrange(s.segment_start, s.segment_end, '[)')
    group by s.segment_start, s.segment_end
  ),
  assessed as (
    select
      c.*,
      exists (
        select 1
        from segment_loads sl
        where sl.committed_rinks > greatest(v_rink_count - v_unavailable_count, 0)
          and tstzrange(sl.segment_start, sl.segment_end, '[)')
              && tstzrange(c.item_start_at, c.item_end_at, '[)')
      ) as capacity_conflict,
      coalesce((
        select max(sl.committed_rinks)::integer
        from segment_loads sl
        where tstzrange(sl.segment_start, sl.segment_end, '[)')
              && tstzrange(c.item_start_at, c.item_end_at, '[)')
      ), 0) as peak_committed_rinks
    from commitments c
  )
  select
    a.source_kind,
    a.source_id,
    a.linked_fixture_id,
    a.title,
    a.item_start_at,
    a.item_end_at,
    a.rinks_required,
    a.allocated_rinks,
    a.directly_uses_maintenance_rink,
    a.capacity_conflict,
    a.affected_rink_labels,
    greatest(v_rink_count - v_unavailable_count, 0)::integer as available_rinks,
    a.peak_committed_rinks,
    greatest(
      a.peak_committed_rinks - greatest(v_rink_count - v_unavailable_count, 0),
      0
    )::integer as capacity_shortfall,
    case
      when a.directly_uses_maintenance_rink and a.capacity_conflict
        then 'Uses a rink being maintained and the remaining green capacity is insufficient.'
      when a.directly_uses_maintenance_rink
        then 'Uses a rink being maintained and requires rink reassignment.'
      when a.capacity_conflict
        then 'Maintenance reduces the remaining green capacity below the committed rink demand.'
      else ''
    end as impact_reason
  from assessed a
  where a.directly_uses_maintenance_rink
     or a.capacity_conflict
  order by a.item_start_at, a.source_kind, a.title;
end;
$$;

revoke all on function public.get_green_maintenance_impacts(uuid, text[], timestamptz, timestamptz) from public;
revoke all on function public.get_green_maintenance_impacts(uuid, text[], timestamptz, timestamptz) from anon;
grant execute on function public.get_green_maintenance_impacts(uuid, text[], timestamptz, timestamptz) to authenticated;
