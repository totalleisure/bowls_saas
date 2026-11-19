begin;
do $$ declare d text; begin
 select pg_get_functiondef(oid) into strict d from pg_proc where pronamespace='public'::regnamespace and proname='enforce_lewisham_rink_opening_hours';
 if position('NEW.green_area_id)' in d)=0 or position('OLD.green_area_id)' in d)=0 then raise exception 'Opening-hours guard changed; review venue amendment';end if;
 d:=replace(replace(d,'NEW.green_area_id)','NEW.green_area_id,NEW.venue_id)'),'OLD.green_area_id)','OLD.green_area_id,OLD.venue_id)');
 execute d;
end $$;
-- Preserve both existing venue-hour boundaries and the independently installed fixture checks.
drop trigger b_enforce_lewisham_rink_opening_hours on public.fixtures;
create trigger b_enforce_lewisham_rink_opening_hours before insert or update of club_id,is_home,start_at,end_at,rinks_required,competition_type_id,green_area_id,venue_id on public.fixtures for each row execute function public.enforce_lewisham_rink_opening_hours();
create function public.guard_club_hours_edit() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='UPDATE' and (new.club_start_time,new.club_end_time) is not distinct from (old.club_start_time,old.club_end_time) then return new;end if;
 if new.club_start_time is null and new.club_end_time is null then return new;end if;
 if not new.is_home_venue then raise exception 'Club opening hours belong to a home venue';end if;
 if auth.uid() is not null and not (public.is_app_superuser() or public.is_club_admin(new.club_id)) then raise exception 'Only Club Admins and superusers can edit Club hours';end if;
 return new;
end $$;
create trigger guard_club_hours_edit before insert or update of club_start_time,club_end_time,is_home_venue on public.venues for each row execute function public.guard_club_hours_edit();
commit;
