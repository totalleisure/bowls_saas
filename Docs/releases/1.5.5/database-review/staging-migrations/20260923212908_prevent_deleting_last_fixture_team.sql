do $migration$
declare v_definition text;
begin
  select pg_get_functiondef(p.oid) into v_definition
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='manage_fixture_team_structure';
  v_definition := replace(v_definition,
    $$if v_action='delete' then
      delete from public.fixture_rinks where id=v_rink.id;$$,
    $$if v_action='delete' then
      if (select count(*) from public.fixture_rinks fr where fr.fixture_id=p_fixture_id) <= 1 then
        raise exception 'A rink-based fixture must retain at least one team.';
      end if;
      delete from public.fixture_rinks where id=v_rink.id;$$);
  execute v_definition;
end;
$migration$;
