-- Preserve legacy draft selection members as well as published teams.
DO $migration$
DECLARE
  definition text := pg_get_functiondef('open_fixture_private.set_rinks_required(uuid,integer,integer,jsonb)'::regprocedure);
  anchor text := 'OR EXISTS (SELECT 1 FROM public.fixture_rink_assignments a';
BEGIN
  IF position(anchor IN definition)=0 THEN RAISE EXCEPTION 'Open fixture rink function has drifted'; END IF;
  definition := replace(definition,anchor,
    'OR EXISTS (SELECT 1 FROM public.team_selection_members m JOIN public.team_selections s ON s.id=m.team_selection_id WHERE s.fixture_id=p_fixture_id)'
    || E'\n     ' || anchor);
  EXECUTE definition;
END;
$migration$;
