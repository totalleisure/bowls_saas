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
