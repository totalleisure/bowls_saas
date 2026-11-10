-- Previous live validator; restore only if rolling back the optional field validation.
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
end $function$
;
