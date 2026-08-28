do $migration$
declare
  v_def text;
  v_before text;
begin
  select pg_get_functiondef('public.process_notification_queue(integer)'::regprocedure)
  into v_def;

  v_before := v_def;

  v_def := regexp_replace(
    v_def,
    E'([[:space:]]*)elsif r\\.event_type = ''fixture_message'' then',
    E'\\1elsif r.event_type = ''fixture_cancelled'' then\n'
    || E'        v_source := ''Fixture Cancelled'';\n'
    || E'        v_title := v_source;\n\n'
    || E'        v_start_at := nullif(r.payload->>''start_at'', '''')::timestamptz;\n\n'
    || E'        v_fixture_date_text :=\n'
    || E'          case\n'
    || E'            when v_start_at is not null then\n'
    || E'              to_char(\n'
    || E'                v_start_at at time zone ''Europe/London'',\n'
    || E'                ''FMDay DD Mon YYYY "at" HH24:MI''\n'
    || E'              )\n'
    || E'            else ''''\n'
    || E'          end;\n\n'
    || E'        v_body := coalesce(nullif(r.payload->>''fixture_label'', ''''), ''Fixture'');\n\n'
    || E'        if v_fixture_date_text <> '''' then\n'
    || E'          v_body := v_body || chr(10) || v_fixture_date_text;\n'
    || E'        end if;\n\n'
    || E'        if coalesce(r.payload->>''home_away'', '''') = ''Home'' then\n'
    || E'          v_body := v_body || chr(10) || ''Home against '' || coalesce(nullif(r.payload->>''opponent_name'', ''''), ''opponent to be confirmed'');\n'
    || E'        elsif coalesce(r.payload->>''home_away'', '''') = ''Away'' then\n'
    || E'          v_body := v_body || chr(10) || ''Away at '' || coalesce(nullif(r.payload->>''venue_name'', ''''), ''venue not set'');\n'
    || E'        end if;\n\n'
    || E'        v_body := v_body || chr(10) || chr(10) || ''This fixture has been cancelled.'';\n\n'
    || E'        if coalesce(nullif(r.payload->>''reason'', ''''), '''') <> '''' then\n'
    || E'          v_body := v_body || chr(10) || chr(10) || ''Reason: '' || (r.payload->>''reason'');\n'
    || E'        end if;\n\n'
    || E'      elsif r.event_type = ''fixture_message'' then',
    1,
    1
  );

  if v_def = v_before then
    raise exception 'Could not insert fixture_cancelled processor branch';
  end if;

  v_before := v_def;

  v_def := regexp_replace(
    v_def,
    E'''fixture_opponent_changed'',([[:space:]]*)''marker_request_opened''',
    E'''fixture_opponent_changed'',\\1''fixture_cancelled'',\\1''marker_request_opened''',
    1,
    1
  );

  if v_def = v_before then
    raise exception 'Could not add fixture_cancelled to email event list';
  end if;

  execute v_def;
end;
$migration$;
