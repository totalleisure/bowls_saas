-- Preserve the deployed member-read authorization; add only fee metadata.
do $migration$
declare definition text;
begin
  select pg_get_functiondef(oid) into strict definition from pg_proc
  where pronamespace='public'::regnamespace and proname='get_authorized_team_sheet_data';
  if strpos(definition, '''notes'', v_fixture.notes,') = 0 then
    raise exception 'Unexpected team-sheet definition; review before applying';
  end if;
  execute replace(definition, '''notes'', v_fixture.notes,',
    '''notes'', v_fixture.notes, ''match_fee_pence'', v_fixture.match_fee_pence,');
end;
$migration$;
notify pgrst, 'reload schema';
