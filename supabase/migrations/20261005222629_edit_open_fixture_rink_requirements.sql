-- Open fixtures only. Physical unassignment remains a separate operation.
CREATE SCHEMA IF NOT EXISTS open_fixture_private;
REVOKE ALL ON SCHEMA open_fixture_private FROM PUBLIC;
GRANT USAGE ON SCHEMA open_fixture_private TO authenticated;

CREATE OR REPLACE FUNCTION open_fixture_private.set_rinks_required(
  p_fixture_id uuid, p_rinks_required integer,
  p_expected_rinks_required integer, p_expected_rinks jsonb
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_fixture public.fixtures%rowtype;
  v_mode text;
  v_uses_rinks boolean;
  v_snapshot jsonb;
  v_expected jsonb;
  v_count integer;
  v_assigned integer;
  v_remove uuid[];
  v_next_no integer;
  v_format text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'You must be signed in.' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_fixture FROM public.fixtures WHERE id=p_fixture_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Fixture not found.'; END IF;
  IF NOT (public.can_manage_fixture(p_fixture_id) OR public.is_active_fixture_creator(p_fixture_id)) THEN
    RAISE EXCEPTION 'You do not have permission to manage this fixture.' USING ERRCODE='42501';
  END IF;
  SELECT lower(btrim(selection_mode)), coalesce(uses_rinks,true)
    INTO v_mode,v_uses_rinks FROM public.competition_types WHERE id=v_fixture.competition_type_id;
  IF v_mode IS DISTINCT FROM 'open' OR NOT coalesce(v_uses_rinks,false) THEN
    RAISE EXCEPTION 'Rink requirements can only be edited here for Open fixtures.';
  END IF;
  IF v_fixture.cancelled_at IS NOT NULL OR v_fixture.archived_at IS NOT NULL THEN
    RAISE EXCEPTION 'Cancelled or archived fixtures cannot be changed.';
  END IF;
  IF p_rinks_required IS NULL OR p_rinks_required < 1 OR p_rinks_required > 99 THEN
    RAISE EXCEPTION 'Choose between 1 and 99 rinks.';
  END IF;
  -- Lock the slots before checking dependent players/markers. Their FK inserts
  -- must wait, so a slot cannot acquire an assignment while it is being removed.
  PERFORM id FROM public.fixture_rinks WHERE fixture_id=p_fixture_id ORDER BY id FOR UPDATE;
  SELECT count(*),count(*) FILTER (WHERE nullif(btrim(home_rink_label),'') IS NOT NULL),
         coalesce(jsonb_agg(jsonb_build_object('id',id,'home_rink_label',home_rink_label) ORDER BY id),'[]'::jsonb)
    INTO v_count,v_assigned,v_snapshot FROM public.fixture_rinks WHERE fixture_id=p_fixture_id;
  IF p_expected_rinks IS NULL OR jsonb_typeof(p_expected_rinks) <> 'array' THEN
    RAISE EXCEPTION 'Reload the fixture before editing its rinks.';
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',x.id,'home_rink_label',x.home_rink_label) ORDER BY x.id),'[]'::jsonb)
    INTO v_expected FROM jsonb_to_recordset(p_expected_rinks) AS x(id uuid,home_rink_label text);
  IF v_fixture.rinks_required IS DISTINCT FROM p_expected_rinks_required OR v_snapshot IS DISTINCT FROM v_expected THEN
    RAISE EXCEPTION 'The rink requirements or assignments have changed. Reload the fixture and try again.';
  END IF;
  IF v_count <> v_fixture.rinks_required THEN
    RAISE EXCEPTION 'The fixture rink records need checking before their number can be changed.';
  END IF;
  IF p_rinks_required=v_fixture.rinks_required THEN RETURN; END IF;
  -- Open fixtures should have no selected players or published teams. Preserve
  -- any legacy selection rather than cascading through it or rewriting history.
  PERFORM id FROM public.team_selections WHERE fixture_id=p_fixture_id ORDER BY id FOR UPDATE;
  IF EXISTS (SELECT 1 FROM public.team_selections WHERE fixture_id=p_fixture_id AND (status::text='published' OR published_at IS NOT NULL))
     OR EXISTS (SELECT 1 FROM public.fixture_rink_assignments a JOIN public.fixture_rinks r ON r.id=a.fixture_rink_id WHERE r.fixture_id=p_fixture_id)
     OR EXISTS (SELECT 1 FROM public.fixture_marker_requests m JOIN public.fixture_rinks r ON r.id=m.fixture_rink_id WHERE r.fixture_id=p_fixture_id)
     OR EXISTS (SELECT 1 FROM public.fixture_rinks WHERE fixture_id=p_fixture_id AND marker_required) THEN
    RAISE EXCEPTION 'This Open fixture has team or marker records. Review these before changing its rink requirements.';
  END IF;
  IF p_rinks_required < v_assigned THEN
    RAISE EXCEPTION 'Unassign a physical rink first. % rinks are still assigned to this fixture.',v_assigned;
  END IF;
  IF p_rinks_required < v_count THEN
    SELECT array_agg(id) INTO v_remove FROM (
      SELECT id FROM public.fixture_rinks WHERE fixture_id=p_fixture_id
      AND nullif(btrim(home_rink_label),'') IS NULL ORDER BY fixture_rink_no DESC,id
      LIMIT (v_count-p_rinks_required)
    ) r;
    DELETE FROM public.fixture_rinks WHERE id=ANY(v_remove);
  ELSE
    SELECT coalesce(max(fixture_rink_no),0)+1 INTO v_next_no FROM public.fixture_rinks WHERE fixture_id=p_fixture_id;
    SELECT format INTO v_format FROM public.fixture_rinks WHERE fixture_id=p_fixture_id ORDER BY fixture_rink_no LIMIT 1;
    INSERT INTO public.fixture_rinks(fixture_id,fixture_rink_no,format,players_per_rink)
      SELECT p_fixture_id,v_next_no+i,v_format,v_fixture.players_per_rink
      FROM generate_series(0,p_rinks_required-v_count-1) i;
  END IF;
  -- Existing capacity validation and durable audit run on this update. Any
  -- failure rolls back both the slot changes and the capacity change together.
  UPDATE public.fixtures SET rinks_required=p_rinks_required WHERE id=p_fixture_id;
END;
$$;
REVOKE ALL ON FUNCTION open_fixture_private.set_rinks_required(uuid,integer,integer,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION open_fixture_private.set_rinks_required(uuid,integer,integer,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_open_fixture_rinks_required(
  p_fixture_id uuid, p_rinks_required integer,
  p_expected_rinks_required integer, p_expected_rinks jsonb
) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path = '' AS $$
  SELECT open_fixture_private.set_rinks_required(p_fixture_id,p_rinks_required,p_expected_rinks_required,p_expected_rinks);
$$;
REVOKE ALL ON FUNCTION public.set_open_fixture_rinks_required(uuid,integer,integer,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_open_fixture_rinks_required(uuid,integer,integer,jsonb) TO authenticated;
NOTIFY pgrst, 'reload schema';
