begin;
CREATE OR REPLACE FUNCTION competition_private.validate_settings(p_settings jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
 if p_settings is null or jsonb_typeof(p_settings)<>'object' or length(p_settings::text)>16000
 or coalesce(p_settings->>'playing_format','')='' or coalesce(p_settings->>'section','')=''
 or coalesce(p_settings->>'scoring','')=''
 or coalesce(p_settings->>'time_limit_mode','') not in ('unknown','none','minutes')
 or (p_settings->>'players_per_entry')::int not between 1 and 12
 or (p_settings->>'booking_minutes')::int not between 1 and 1440
 or (p_settings->>'time_limit_mode'='minutes' and coalesce((p_settings->>'time_limit_minutes')::int,0) not between 1 and 1440)
 then raise exception 'Invalid competition playing conditions' using errcode='22023'; end if;
 if p_settings->>'players_per_entry' is null or p_settings->>'booking_minutes' is null then
 raise exception 'Players and booking duration required'; end if;
 if p_settings->'last_jack_before_end_minutes' is not null and p_settings->'last_jack_before_end_minutes'<>'null'::jsonb then
  if jsonb_typeof(p_settings->'last_jack_before_end_minutes')<>'number' then
   raise exception 'Last-jack allowance must be a whole number of minutes' using errcode='22023';
  end if;
  if (p_settings->>'last_jack_before_end_minutes')::numeric <> trunc((p_settings->>'last_jack_before_end_minutes')::numeric)
   or (p_settings->>'last_jack_before_end_minutes')::numeric not between 1 and 1439
   or (p_settings->>'time_limit_mode'='minutes' and (p_settings->>'last_jack_before_end_minutes')::numeric >= (p_settings->>'time_limit_minutes')::int)
  then raise exception 'Last-jack allowance must be positive and less than the playing time limit' using errcode='22023'; end if;
 end if;
end $function$
;

-- Update only the three reviewed Lewisham pairs competitions.
do $$
declare c record; found_count int:=0;
begin
 for c in select cc.* from public.club_competitions cc join public.clubs cl on cl.id=cc.club_id
 where cl.name='Lewisham and Crystal Palace Indoor Bowls Club' and cc.name in ('Mens Pairs','Mixed Pairs','Ladies Pairs')
 and cc.season='2026–2027' loop
  if c.settings->>'time_limit_mode'<>'minutes' or (c.settings->>'time_limit_minutes')::int<>150 then raise exception 'Review timing before setting last-jack allowance for %',c.name;end if;
  update public.club_competitions set settings=settings||'{"last_jack_before_end_minutes":10}'::jsonb where id=c.id;
  found_count:=found_count+1;
 end loop;
 if found_count<>3 then raise exception 'Expected three reviewed pairs competitions, found %',found_count;end if;
end $$;
-- Correct the reviewed, shared setup template, never local scores or started timers.
-- Round overrides (including no time limit in finals) remain in effect.
with effective as (
 select s.id,c.settings||coalesce(r.rule_overrides,'{}'::jsonb) rules
 from scorecard_private.fixture_rink_setups s
 join public.competition_draw_matches m on m.id=(s.source_snapshot->>'competitionMatchId')::uuid
 join public.club_competitions c on c.id=m.competition_id
 join public.clubs cl on cl.id=c.club_id
 join public.competition_rounds r on r.id=m.round_id
 where cl.name='Lewisham and Crystal Palace Indoor Bowls Club' and c.name in ('Mens Pairs','Mixed Pairs','Ladies Pairs') and c.season='2026–2027'
)
update scorecard_private.fixture_rink_setups s
set source_snapshot=jsonb_set(s.source_snapshot,'{rules}',e.rules),
 conditions=case when e.rules->>'time_limit_mode'='minutes'
   and s.conditions->>'durationMinutes'=e.rules->>'time_limit_minutes'
   then jsonb_set(s.conditions,'{lastJackMinutes}',to_jsonb((e.rules->>'time_limit_minutes')::int-10))
   else s.conditions end
from effective e where s.id=e.id;


commit;
