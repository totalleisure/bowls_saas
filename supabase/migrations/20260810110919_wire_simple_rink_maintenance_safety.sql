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

  if not exists (
    select 1
    from unnest(coalesce(p_rink_labels, array[]::text[])) as u(x)
    where nullif(btrim(x), '') is not null
  ) then
    raise exception 'At least one rink label is required.';
  end if;

  return query
  with generated_labels as (
    select
      i as rink_number,
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
  ),
  requested_labels as (
    select distinct nullif(btrim(x), '') as rink_label
    from unnest(coalesce(p_rink_labels, array[]::text[])) as u(x)
    where nullif(btrim(x), '') is not null
  ),
  requested_rinks as (
    select gl.rink_number, gl.rink_label
    from requested_labels rl
    join generated_labels gl on gl.rink_label = rl.rink_label
  ),
  invalid_requested as (
    select rl.rink_label
    from requested_labels rl
    left join generated_labels gl on gl.rink_label = rl.rink_label
    where gl.rink_label is null
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
      coalesce(bool_or(rr.rink_label is not null), false) as directly_uses_maintenance_rink,
      coalesce(
        array_agg(distinct fr.home_rink_label)
          filter (where rr.rink_label is not null),
        array[]::text[]
      ) as affected_rink_labels
    from public.fixtures f
    left join public.competition_types ct on ct.id = f.competition_type_id
    left join public.fixture_rinks fr on fr.fixture_id = f.id
    left join requested_rinks rr on rr.rink_label = fr.home_rink_label
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
  existing_maintenance as (
    select m.rink_number, m.start_at, m.end_at
    from public.green_rink_maintenance m
    where m.green_area_id = p_green_area_id
      and m.status = 'active'
      and m.time_range && tstzrange(p_start_at, p_end_at, '[)')
  ),
  boundary_points as (
    select p_start_at as point
    union select p_end_at
    union
    select greatest(c.item_start_at, p_start_at) from commitments c
    union
    select least(c.item_end_at, p_end_at) from commitments c
    union
    select greatest(m.start_at, p_start_at) from existing_maintenance m
    union
    select least(m.end_at, p_end_at) from existing_maintenance m
  ),
  ordered_boundaries as (
    select point as segment_start,
           lead(point) over (order by point) as segment_end
    from boundary_points
    where point >= p_start_at and point <= p_end_at
  ),
  segments as (
    select segment_start, segment_end
    from ordered_boundaries
    where segment_end is not null and segment_start < segment_end
  ),
  segment_loads as (
    select
      s.segment_start,
      s.segment_end,
      coalesce((
        select sum(c.rinks_required)::integer
        from commitments c
        where tstzrange(c.item_start_at, c.item_end_at, '[)')
              && tstzrange(s.segment_start, s.segment_end, '[)')
      ), 0) as committed_rinks,
      (
        select count(distinct u.rink_number)::integer
        from (
          select em.rink_number
          from existing_maintenance em
          where tstzrange(em.start_at, em.end_at, '[)')
                && tstzrange(s.segment_start, s.segment_end, '[)')
          union
          select rr.rink_number
          from requested_rinks rr
        ) u
      ) as unavailable_rinks
    from segments s
  ),
  assessed as (
    select
      c.*,
      exists (
        select 1
        from segment_loads sl
        where tstzrange(sl.segment_start, sl.segment_end, '[)')
              && tstzrange(c.item_start_at, c.item_end_at, '[)')
          and sl.committed_rinks > greatest(v_rink_count - sl.unavailable_rinks, 0)
      ) as capacity_conflict,
      coalesce((
        select min(greatest(v_rink_count - sl.unavailable_rinks, 0))::integer
        from segment_loads sl
        where tstzrange(sl.segment_start, sl.segment_end, '[)')
              && tstzrange(c.item_start_at, c.item_end_at, '[)')
      ), greatest(v_rink_count - (select count(*) from requested_rinks), 0)) as available_rinks,
      coalesce((
        select max(sl.committed_rinks)::integer
        from segment_loads sl
        where tstzrange(sl.segment_start, sl.segment_end, '[)')
              && tstzrange(c.item_start_at, c.item_end_at, '[)')
      ), 0) as peak_committed_rinks,
      coalesce((
        select max(greatest(sl.committed_rinks - greatest(v_rink_count - sl.unavailable_rinks, 0), 0))::integer
        from segment_loads sl
        where tstzrange(sl.segment_start, sl.segment_end, '[)')
              && tstzrange(c.item_start_at, c.item_end_at, '[)')
      ), 0) as capacity_shortfall
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
    a.available_rinks,
    a.peak_committed_rinks,
    a.capacity_shortfall,
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
  where not exists (select 1 from invalid_requested)
    and (a.directly_uses_maintenance_rink or a.capacity_conflict)
  order by a.item_start_at, a.source_kind, a.title;

  if exists (
    with generated_labels as (
      select case
        when ga.scheme_type = 'custom_list' then ga.custom_labels[i]
        when ga.scheme_type = 'alpha' then coalesce(ga.scheme_prefix, '') || chr(64 + i)
        else coalesce(ga.scheme_prefix, '') || case
          when coalesce(ga.scheme_padding, 0) > 0 then lpad(i::text, ga.scheme_padding, '0')
          else i::text
        end
      end as rink_label
      from public.green_areas ga
      cross join generate_series(1, ga.rink_count) i
      where ga.id = p_green_area_id
    )
    select 1
    from (
      select distinct nullif(btrim(x), '') as rink_label
      from unnest(coalesce(p_rink_labels, array[]::text[])) u(x)
      where nullif(btrim(x), '') is not null
    ) r
    left join generated_labels g on g.rink_label = r.rink_label
    where g.rink_label is null
  ) then
    raise exception 'One or more maintenance rink labels are not valid for this green.';
  end if;
end;
$$;

create or replace function public.create_green_rink_maintenance_safe(
  p_green_area_id uuid,
  p_rink_number integer,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_reason text default 'Maintenance',
  p_notes text default null
)
returns uuid
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_green public.green_areas%rowtype;
  v_rink_label text;
  v_impact_count integer;
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  select * into v_green
  from public.green_areas
  where id = p_green_area_id;

  if not found then
    raise exception 'Green area was not found.';
  end if;

  if not (
    public.is_club_admin(v_green.club_id)
    or exists (
      select 1 from public.app_superusers su where su.user_id = auth.uid()
    )
  ) then
    raise exception 'Club administrator access is required.';
  end if;

  if p_rink_number < 1 or p_rink_number > v_green.rink_count then
    raise exception 'Rink number % is not valid for this green.', p_rink_number;
  end if;

  if p_start_at is null or p_end_at is null or p_start_at >= p_end_at then
    raise exception 'A valid maintenance start/end time is required.';
  end if;

  if exists (
    select 1
    from public.green_rink_maintenance m
    where m.green_area_id = p_green_area_id
      and m.rink_number = p_rink_number
      and m.status = 'active'
      and m.time_range && tstzrange(p_start_at, p_end_at, '[)')
  ) then
    raise exception 'This rink already has maintenance during part of the selected period.';
  end if;

  v_rink_label := case
    when v_green.scheme_type = 'custom_list' then v_green.custom_labels[p_rink_number]
    when v_green.scheme_type = 'alpha' then coalesce(v_green.scheme_prefix, '') || chr(64 + p_rink_number)
    else coalesce(v_green.scheme_prefix, '') || case
      when coalesce(v_green.scheme_padding, 0) > 0
        then lpad(p_rink_number::text, v_green.scheme_padding, '0')
      else p_rink_number::text
    end
  end;

  select count(*)::integer
    into v_impact_count
  from public.get_green_maintenance_impacts(
    p_green_area_id,
    array[v_rink_label],
    p_start_at,
    p_end_at
  );

  if v_impact_count > 0 then
    raise exception 'MAINTENANCE_IMPACT:%', v_impact_count;
  end if;

  insert into public.green_rink_maintenance (
    club_id,
    green_area_id,
    rink_number,
    start_at,
    end_at,
    reason,
    notes,
    created_by_member_profile_id
  ) values (
    v_green.club_id,
    p_green_area_id,
    p_rink_number,
    p_start_at,
    p_end_at,
    coalesce(nullif(btrim(p_reason), ''), 'Maintenance'),
    nullif(btrim(coalesce(p_notes, '')), ''),
    public.my_member_profile_id()
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.create_green_rink_maintenance_safe(uuid, integer, timestamptz, timestamptz, text, text) from public;
revoke all on function public.create_green_rink_maintenance_safe(uuid, integer, timestamptz, timestamptz, text, text) from anon;
grant execute on function public.create_green_rink_maintenance_safe(uuid, integer, timestamptz, timestamptz, text, text) to authenticated;

create or replace function public.get_green_rink_availability(
  p_green_area_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
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
security invoker
set search_path = public, pg_temp
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

create or replace function public.check_green_area_rink_capacity()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_green_rink_count integer;
  v_overlapping_rinks integer;
  v_maintenance_rinks integer;
begin
  if new.green_area_id is null then
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

  select coalesce(sum(f.rinks_required), 0)
    into v_overlapping_rinks
  from public.fixtures f
  where f.green_area_id = new.green_area_id
    and f.id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid)
    and f.time_range && new.time_range;

  select count(distinct m.rink_number)::integer
    into v_maintenance_rinks
  from public.green_rink_maintenance m
  where m.green_area_id = new.green_area_id
    and m.status = 'active'
    and m.time_range && new.time_range;

  if v_overlapping_rinks + v_maintenance_rinks + new.rinks_required > v_green_rink_count then
    raise exception 'Not enough rinks available for this time slot on the selected green';
  end if;

  return new;
end;
$$;
