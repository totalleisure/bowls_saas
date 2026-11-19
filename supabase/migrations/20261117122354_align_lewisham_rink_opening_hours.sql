begin;
CREATE OR REPLACE FUNCTION public.enforce_lewisham_rink_opening_hours()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE f public.fixtures%ROWTYPE; local_start timestamp; local_end timestamp; effective_end timestamptz;
BEGIN
 IF TG_TABLE_NAME = 'fixtures' THEN
  IF TG_OP = 'UPDATE' THEN
   IF (NEW.club_id,NEW.is_home,NEW.start_at,NEW.end_at,NEW.rinks_required,NEW.competition_type_id,NEW.green_area_id) IS NOT DISTINCT FROM (OLD.club_id,OLD.is_home,OLD.start_at,OLD.end_at,OLD.rinks_required,OLD.competition_type_id,OLD.green_area_id) THEN RETURN NEW; END IF;
  END IF;
  f := NEW;
 ELSE
  IF TG_OP = 'UPDATE' THEN
   IF (NEW.fixture_id,NEW.home_rink_label) IS NOT DISTINCT FROM (OLD.fixture_id,OLD.home_rink_label) THEN RETURN NEW; END IF;
  END IF;
  SELECT * INTO f FROM public.fixtures WHERE id=NEW.fixture_id;
  IF NOT FOUND THEN RETURN NEW; END IF;
 END IF;
 IF f.club_id <> '8ae87bbe-cb16-4330-a5b0-e62366479f07'::uuid OR f.is_home IS NOT TRUE THEN RETURN NEW; END IF;
 IF TG_TABLE_NAME = 'fixtures' AND coalesce(f.rinks_required,0) <= 0
  AND NOT EXISTS(SELECT 1 FROM public.competition_types t WHERE t.id=f.competition_type_id AND t.uses_rinks IS TRUE)
  AND NOT EXISTS(SELECT 1 FROM public.fixture_rinks r WHERE r.fixture_id=f.id) THEN RETURN NEW; END IF;
 effective_end := coalesce(f.end_at,f.start_at + interval '4 hours');
 local_start := f.start_at AT TIME ZONE 'Europe/London';
 local_end := effective_end AT TIME ZONE 'Europe/London';
 IF f.start_at IS NULL OR NOT isfinite(f.start_at) OR NOT isfinite(effective_end)
  OR effective_end <= f.start_at OR local_start::date <> local_end::date
  OR local_start::time < time '09:00' OR local_end::time > time '22:00' THEN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='Rink bookings must start at or after 09:00 and finish by 22:00 on the same day (UK local time). Please check the date and start/end times.', HINT='Use 24-hour times: for example, 13:00 means 1 pm and 14:00 means 2 pm.';
 END IF;
 RETURN NEW;
END;
$function$;
DROP TRIGGER IF EXISTS b_enforce_lewisham_rink_opening_hours ON public.fixtures;
DROP TRIGGER IF EXISTS b_enforce_lewisham_rink_opening_hours ON public.fixture_rinks;
CREATE TRIGGER b_enforce_lewisham_rink_opening_hours BEFORE INSERT OR UPDATE OF club_id, is_home, start_at, end_at, rinks_required, competition_type_id, green_area_id ON public.fixtures FOR EACH ROW EXECUTE FUNCTION enforce_lewisham_rink_opening_hours();
CREATE TRIGGER b_enforce_lewisham_rink_opening_hours BEFORE INSERT OR UPDATE OF fixture_id, home_rink_label ON public.fixture_rinks FOR EACH ROW EXECUTE FUNCTION enforce_lewisham_rink_opening_hours();
commit;
