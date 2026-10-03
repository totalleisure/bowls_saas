do $migration$
declare
  v_definition text;
begin
  select pg_get_functiondef(p.oid) into v_definition
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'save_preselect_fixture_state'
    and pg_get_function_identity_arguments(p.oid) = 'p_fixture_id uuid, p_assignments jsonb';

  if v_definition is null then
    raise exception 'save_preselect_fixture_state(uuid, jsonb) was not found';
  end if;

  v_definition := replace(v_definition,
    '-- External names are only valid for opponents.',
    '-- External names are valid for player and opponent positions.');
  v_definition := replace(v_definition,
    $$where display_name is not null
      and role <> 'opponent'$$,
    $$where display_name is not null
      and role not in ('player', 'opponent')$$);
  v_definition := replace(v_definition,
    $$'External names may only be used for opponent positions.'$$,
    $$'External names may only be used for player or opponent positions.'$$);

  execute v_definition;
end;
$migration$;

comment on function public.save_preselect_fixture_state(uuid, jsonb)
is 'Atomically saves Pre-Select assignments, including external names in player or opponent positions, marker state and communication reconciliation.';
