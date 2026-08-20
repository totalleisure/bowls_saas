CREATE OR REPLACE FUNCTION public.check_green_area_rink_capacity()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
$function$
