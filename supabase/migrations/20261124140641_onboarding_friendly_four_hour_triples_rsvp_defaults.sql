-- New clubs only: preserve every other reviewed onboarding amendment.
do $migration$
declare definition text; anchor text := 'perform club_setup_private.apply_onboarding_participation_defaults(v_club);';
begin
 select pg_get_functiondef('club_setup_private.create_staging_club(uuid,jsonb)'::regprocedure) into definition;
 if (length(definition)-length(replace(definition,anchor,'')))/length(anchor) <> 1 then
  raise exception 'Unexpected onboarding definition; review before amending';
 end if;
 definition := replace(definition,anchor,anchor || E'\n  update public.competition_types set default_duration_minutes=240, lock_duration=true\n  where club_id=v_club and name=''Friendly matches'';');
 execute definition;
end $migration$;

-- New clubs only; retain four-hour duration limit and all other reviewed settings.
do $migration$
declare definition text; anchor text := 'set default_duration_minutes=240, lock_duration=true';
begin
 select pg_get_functiondef('club_setup_private.create_staging_club(uuid,jsonb)'::regprocedure) into definition;
 if (length(definition)-length(replace(definition,anchor,'')))/length(anchor) <> 1 then
  raise exception 'Unexpected onboarding definition; review before amending';
 end if;
 execute replace(definition,anchor,anchor || ', default_format=''triples'', default_players_per_rink=3, default_rinks_required=4');
end $migration$;

-- Only the Friendly template for newly onboarded clubs changes.
do $migration$
declare definition text; anchor text := 'default_format=''triples'', default_players_per_rink=3, default_rinks_required=4';
begin
 select pg_get_functiondef('club_setup_private.create_staging_club(uuid,jsonb)'::regprocedure) into definition;
 if (length(definition)-length(replace(definition,anchor,'')))/length(anchor) <> 1 then
  raise exception 'Unexpected onboarding definition; review before amending';
 end if;
 execute replace(definition,anchor,anchor || ', lock_participation=true');
end $migration$;
