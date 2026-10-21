do $migration$
declare d text; old_clause text := $old$if v_display_name is not null
       and not (
         v_position between 101 and (100 + p_players_per_rink)
       ) then$old$;
begin
 select replace(pg_get_functiondef(oid),chr(13),'') into strict d from pg_proc where pronamespace='public'::regnamespace and proname='create_fixture_with_setup_v2';
 if position(old_clause in d)=0 then raise exception 'Expected external-name validation not found'; end if;
 d := replace(d,old_clause,$new$if v_display_name is not null
       and not (
         v_position between 1 and p_players_per_rink
         or v_position between 101 and (100 + p_players_per_rink)
       ) then$new$);
 d := replace(d,'External names can only be used in opponent positions.','External names can only be used in player or opponent positions.');
 execute d;
end $migration$;
