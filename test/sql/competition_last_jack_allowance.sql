begin;
do $$
declare settings jsonb:='{"playing_format":"pairs","section":"mixed","scoring":"18 ends","time_limit_mode":"minutes","time_limit_minutes":150,"players_per_entry":2,"booking_minutes":180}'; n numeric; c int;
begin
 perform competition_private.validate_settings(settings);
 perform competition_private.validate_settings(settings||'{"last_jack_before_end_minutes":null}');
 perform competition_private.validate_settings(settings||'{"last_jack_before_end_minutes":10}');
 perform competition_private.validate_settings(settings||'{"time_limit_mode":"none","last_jack_before_end_minutes":10}');
 foreach n in array array[0,-1,150,151,1.5]::numeric[] loop
  begin perform competition_private.validate_settings(settings||jsonb_build_object('last_jack_before_end_minutes',n));raise exception 'Invalid allowance accepted: %',n;exception when invalid_parameter_value then null;end;
 end loop;
 begin perform competition_private.validate_settings(settings||'{"last_jack_before_end_minutes":"ten"}');raise exception 'String allowance accepted';exception when invalid_parameter_value then null;end;
 select count(*) into c from public.club_competitions cc join public.clubs cl on cl.id=cc.club_id where cl.name='Lewisham and Crystal Palace Indoor Bowls Club' and cc.name in ('Mens Pairs','Mixed Pairs','Ladies Pairs') and cc.season='2026–2027' and cc.settings->>'last_jack_before_end_minutes'='10' and cc.settings->>'time_limit_minutes'='150';
 if c<>3 then raise exception 'Expected three updated competitions';end if;
end $$;
rollback;
select 'PASS: optional field, valid allowance, legacy settings, invalid values and three competition defaults' result;
