-- Allow administrative rule edits while retaining the existing draw and entrants.
CREATE OR REPLACE FUNCTION public.update_club_competition(p_competition_id uuid, p_name text, p_season text, p_settings jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c public.club_competitions;
begin
 select * into c from public.club_competitions where id=p_competition_id for update;
 if not found or not competition_private.can_manage(c.club_id) then raise exception 'Club administrator access required' using errcode='42501'; end if;

 perform competition_private.validate_settings(p_settings);
 if (exists(select 1 from public.competition_entries where competition_id=c.id)
     or exists(select 1 from public.competition_rounds where competition_id=c.id))
 and (p_settings->>'players_per_entry' is distinct from c.settings->>'players_per_entry'
      or p_settings->>'playing_format' is distinct from c.settings->>'playing_format') then
 raise exception 'Playing format and team size cannot change while entries or a draw exist';end if;
 if nullif(btrim(p_name),'') is null or nullif(btrim(p_season),'') is null then raise exception 'Competition name and season are required';end if;
 update public.club_competitions set name=btrim(p_name),season=btrim(p_season),settings=p_settings where id=c.id;
end $function$
;
