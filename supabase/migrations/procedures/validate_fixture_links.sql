CREATE OR REPLACE FUNCTION public.validate_fixture_links()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare
  v record;
  ga record;
  v_uses_rinks boolean := true;
begin
  select coalesce(ct.uses_rinks, true)
    into v_uses_rinks
  from public.competition_types ct
  where ct.id = new.competition_type_id;

  -- Venue must exist and belong to the same club as the fixture record
  select * into v from public.venues where id = new.venue_id;
  if v is null then
    raise exception 'Invalid venue_id';
  end if;

  if v.club_id <> new.club_id then
    raise exception 'Venue does not belong to club';
  end if;

  if v_uses_rinks then
    -- HOME rink-using fixture: green_area is required and must match venue/club
    if new.is_home then
      if new.green_area_id is null then
        raise exception 'green_area_id is required for home fixtures that use rinks';
      end if;

      select * into ga from public.green_areas where id = new.green_area_id;
      if ga is null then
        raise exception 'Invalid green_area_id';
      end if;

      if ga.venue_id <> new.venue_id then
        raise exception 'Green area does not belong to venue';
      end if;

      if ga.club_id <> new.club_id then
        raise exception 'Green area does not belong to club';
      end if;

      if ga.discipline = 'outdoor' then
        if ga.orientation_mode = 'required' and new.orientation is null then
          raise exception 'Orientation is required for this outdoor green';
        end if;

        if ga.orientation_mode <> 'not_applicable'
           and array_length(ga.allowed_orientations, 1) > 0
           and new.orientation is not null
           and not (new.orientation = any (ga.allowed_orientations)) then
          raise exception 'Orientation not allowed for this green area';
        end if;
      else
        if new.orientation is not null then
          raise exception 'Orientation must be null for indoor green';
        end if;
      end if;

    else
      -- AWAY rink-using fixture: green_area and orientation should be NULL
      if new.green_area_id is not null then
        raise exception 'green_area_id must be null for away fixtures';
      end if;

      if new.orientation is not null then
        raise exception 'orientation must be null for away fixtures';
      end if;
    end if;

  else
    -- Non-rink event/meeting/party: no green/orientation allowed
    if new.green_area_id is not null then
      raise exception 'green_area_id must be null for fixtures that do not use rinks';
    end if;

    if new.orientation is not null then
      raise exception 'orientation must be null for fixtures that do not use rinks';
    end if;
  end if;

  return new;
end;
$function$
