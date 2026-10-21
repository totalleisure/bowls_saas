do $migration$
declare d text; old_clause text := $old$and (a.item->>'position')::integer
          between 1 and p_players_per_rink
    ) then
      raise exception
        'The booking member must occupy a player position.';$old$;
begin
 select replace(pg_get_functiondef(oid),chr(13),'') into strict d from pg_proc where pronamespace='public'::regnamespace and proname='create_fixture_with_setup_v2';
 if position(old_clause in d)=0 then raise exception 'Expected booker validation not found'; end if;
 d:=replace(d,old_clause,$new$and (a.item->>'position')::integer
          between 1 and p_players_per_rink
    ) and not exists (
      select 1 from jsonb_array_elements(coalesce(p_rink_assignments,'[]'::jsonb)) as a(item)
      where nullif(btrim(a.item->>'display_name'),'') is not null
        and nullif(a.item->>'member_profile_id','') is null
        and (a.item->>'position')::integer between 1 and p_players_per_rink
    ) then
      raise exception
        'The booking member must occupy a player position or book an external player.';$new$);
 d:=replace(d,'-- The booking member must occupy a player slot. This prevents nomination','-- A member may book an external player; the captain must still be the booking member. Prevent nomination');
 execute d;
end $migration$;
