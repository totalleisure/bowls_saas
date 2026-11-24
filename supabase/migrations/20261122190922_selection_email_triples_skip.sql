-- Correct triples position labels in selection introductions and roster lines.
-- Read and amend the deployed definition so unrelated live fixes and grants survive.
DO $migration$
DECLARE original text; revised text;
BEGIN
 original := pg_get_functiondef('public.process_notification_queue(integer)'::regprocedure);
 revised := regexp_replace(original,
  'when v_selected_position = 3 then([[:space:]]*)''Third''',
  'when v_selected_position = 3 and v_players_per_rink = 3 then ''Skip'' WHEN v_selected_position = 3 then\1''Third''');
 IF revised = original THEN RAISE EXCEPTION 'Expected selected-position branch not found'; END IF;
 original := revised;
 revised := regexp_replace(original,
  'when fra.position = 3 then([[:space:]]*)''Third: ''',
  'when fra.position = 3 and fr.players_per_rink = 3 then ''Skip: '' WHEN fra.position = 3 then\1''Third: ''');
 IF revised = original THEN RAISE EXCEPTION 'Expected roster-position branch not found'; END IF;
 EXECUTE revised;
END;
$migration$;


