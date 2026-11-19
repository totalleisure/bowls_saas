begin;
do $$ begin if (select md5(replace(pg_get_functiondef(oid),chr(13),'')) from pg_proc where pronamespace='public'::regnamespace and proname='enforce_lewisham_rink_opening_hours') is distinct from '7f7dc5faeb0b8c52414fbebcfaa500f7' then raise exception 'Opening-hours definition changed; review before deployment';end if;end $$;
alter table public.competition_types
 add column lock_participation boolean not null default false,
 add column lock_rinks boolean not null default false,
 add column lock_format boolean not null default false,
 add column lock_duration boolean not null default false,
 add column booking_start_times_enabled boolean not null default false;
create table public.fixture_booking_start_rules (
 club_id uuid primary key references public.clubs(id) on delete cascade,
 windows jsonb not null default '[]'::jsonb,
 updated_at timestamptz not null default clock_timestamp()
);
alter table public.fixture_booking_start_rules enable row level security;
revoke all on public.fixture_booking_start_rules from anon;
grant select,insert,update,delete on public.fixture_booking_start_rules to authenticated,service_role;
create policy read_booking_rules on public.fixture_booking_start_rules for select to authenticated
 using (club_id in (select public.my_active_club_ids()) or public.is_app_superuser());
create policy manage_booking_rules on public.fixture_booking_start_rules for all to authenticated
 using (public.is_club_admin(club_id) or public.is_app_superuser())
 with check (public.is_club_admin(club_id) or public.is_app_superuser());

create function public.validate_fixture_booking_start_rules() returns trigger
language plpgsql set search_path='' as $$
declare w jsonb; s jsonb; previous_end integer:=0; a integer; b integer;
begin
 if jsonb_typeof(new.windows)<>'array' or jsonb_array_length(new.windows)>24 then raise exception 'Use an array of up to 24 booking windows';end if;
 for w in select value from jsonb_array_elements(new.windows) order by (value->>'from')::integer loop
  a:=(w->>'from')::integer;b:=(w->>'until')::integer;
  if a is null or b is null or a<0 or b>1440 or a>=b or a<previous_end then raise exception 'Booking windows must be valid, non-overlapping times within one day';end if;
  if jsonb_typeof(w->'starts') is distinct from 'array' or jsonb_array_length(w->'starts')=0 then raise exception 'Each window needs at least one allowed start time';end if;
  for s in select value from jsonb_array_elements(w->'starts') loop
   if jsonb_typeof(s)<>'number' or (s#>>'{}')::numeric<>trunc((s#>>'{}')::numeric) or (s#>>'{}')::integer<a or (s#>>'{}')::integer>=b then raise exception 'Allowed start times must lie within their booking window';end if;
  end loop;
  previous_end:=b;
 end loop;
 new.updated_at:=clock_timestamp();return new;
end $$;
create trigger validate_booking_start_rules before insert or update on public.fixture_booking_start_rules
 for each row execute function public.validate_fixture_booking_start_rules();

alter table public.fixtures add column participation_mode text check (participation_mode in ('team','rsvp','preselect','open'));

create function public.enforce_fixture_type_booking_rules() returns trigger
language plpgsql security definer set search_path='' as $$
declare f public.fixtures%rowtype;t public.competition_types%rowtype;w jsonb; minute_of_day numeric; check_times boolean; check_type boolean; check_rinks boolean; check_format boolean; check_participation boolean; expected_players integer;
begin
 if tg_table_name='fixtures' then
  f:=new;
  check_type:=tg_op='INSERT';check_times:=true;check_rinks:=true;check_format:=true;check_participation:=true;
  if tg_op='UPDATE' then
   check_type:=(new.competition_type_id,new.club_id) is distinct from (old.competition_type_id,old.club_id);
   check_times:=check_type or (new.start_at,new.end_at,new.is_home) is distinct from (old.start_at,old.end_at,old.is_home);
   check_rinks:=check_type or new.rinks_required is distinct from old.rinks_required;
   check_format:=check_type or new.players_per_rink is distinct from old.players_per_rink;
   check_participation:=check_type or (new.requires_rsvp,new.participation_mode) is distinct from (old.requires_rsvp,old.participation_mode);
  end if;
 else
  select * into f from public.fixtures where id=coalesce(new.fixture_id,old.fixture_id);
  check_times:=false;check_rinks:=false;check_participation:=false;check_format:=true;
  if tg_op='UPDATE' and (new.fixture_id,new.format,new.players_per_rink) is not distinct from (old.fixture_id,old.format,old.players_per_rink) then return new;end if;
 end if;
 select * into t from public.competition_types where id=f.competition_type_id;
 if not found then return new;end if;
 -- System jobs have no member identity; signed-in users are checked even inside SECURITY DEFINER booking RPCs.
 if auth.uid() is null or public.is_app_superuser() or public.is_club_admin(f.club_id) then return new;end if;
 if check_rinks and t.lock_rinks and f.rinks_required is distinct from t.default_rinks_required then raise exception 'Rinks required is locked by the Fixture Type. Please contact a Club Admin.';end if;
 expected_players:=coalesce(t.default_players_per_rink,case t.default_format when 'singles' then 1 when 'pairs' then 2 when 'aussie_pairs' then 2 when 'triples' then 3 when 'rinks' then 4 when 'fours' then 4 end);
 if check_format and t.lock_format then
  if tg_table_name='fixtures' then
   if f.players_per_rink is distinct from expected_players then raise exception 'Format is locked by the Fixture Type. Please contact a Club Admin.';end if;
  elsif new.players_per_rink is distinct from expected_players or new.format is distinct from (case when t.default_format='fours' then 'rinks' else t.default_format end) then
   raise exception 'Format is locked by the Fixture Type. Please contact a Club Admin.';
  end if;
 end if;
 if check_participation and t.lock_participation and (f.requires_rsvp is distinct from (coalesce(t.selection_mode,'') not in ('team','preselect')) or (f.participation_mode is not null and f.participation_mode is distinct from t.selection_mode)) then
  raise exception 'Participation mode is locked by the Fixture Type. Please contact a Club Admin.';
 end if;
 if check_times and t.lock_duration and (f.end_at is null or f.end_at<=f.start_at or f.end_at-f.start_at>make_interval(mins=>t.default_duration_minutes)) then
  raise exception 'Booking duration cannot exceed the Fixture Type maximum of % minutes.',t.default_duration_minutes;
 end if;
 if check_times and f.is_home and t.bookable_by_members and t.booking_start_times_enabled then
  minute_of_day:=extract(hour from f.start_at at time zone 'Europe/London')*60+extract(minute from f.start_at at time zone 'Europe/London')+extract(second from f.start_at at time zone 'Europe/London')/60;
  for w in select value from public.fixture_booking_start_rules r cross join lateral jsonb_array_elements(r.windows) where r.club_id=f.club_id loop
   if minute_of_day>=(w->>'from')::integer and minute_of_day<(w->>'until')::integer and not exists(select 1 from jsonb_array_elements_text(w->'starts') s where s::numeric=minute_of_day) then
    raise exception 'This start time is restricted by the Fixture Type. Choose one of the allowed Fixture Booking Start Times.';
   end if;
  end loop;
 end if;
 return new;
end $$;
revoke all on function public.enforce_fixture_type_booking_rules() from public,anon,authenticated;
create trigger c_fixture_type_booking_rules before insert or update on public.fixtures for each row execute function public.enforce_fixture_type_booking_rules();
create trigger c_fixture_type_booking_rules before insert or update on public.fixture_rinks for each row execute function public.enforce_fixture_type_booking_rules();

-- Initial timetable only for the requested Club and two named member booking types.
insert into public.fixture_booking_start_rules(club_id,windows)
 select id,'[{"from":540,"until":840,"starts":[540,690]}]'::jsonb from public.clubs where id='8ae87bbe-cb16-4330-a5b0-e62366479f07';
update public.competition_types set booking_start_times_enabled=true,lock_duration=true,default_duration_minutes=150
 where club_id='8ae87bbe-cb16-4330-a5b0-e62366479f07' and name in ('Member Rink Booking','Club Competition');


alter table public.venues add column club_start_time time, add column club_end_time time;
alter table public.venues add constraint club_hours_same_day check ((club_start_time is null and club_end_time is null) or (club_start_time is not null and club_end_time is not null and club_start_time<club_end_time));
update public.venues set club_start_time='09:00',club_end_time='22:00' where club_id='8ae87bbe-cb16-4330-a5b0-e62366479f07' and is_home_venue;
create function public.set_home_venue_club_hours(p_venue_id uuid,p_start time,p_end time) returns void
language plpgsql security definer set search_path='' as $$
declare v public.venues%rowtype;
begin
 select * into strict v from public.venues where id=p_venue_id for update;
 if auth.uid() is null or not (public.is_app_superuser() or public.is_club_admin(v.club_id)) then raise exception 'Only Club Admins and superusers can edit Club hours';end if;
 if not v.is_home_venue then raise exception 'Club hours can be set only on a home venue';end if;
 if p_start is null or p_end is null or p_start>=p_end then raise exception 'Club End Time must be after Club Start Time on the same day';end if;
 update public.venues set club_start_time=p_start,club_end_time=p_end where id=p_venue_id;
end $$;
revoke all on function public.set_home_venue_club_hours(uuid,time,time) from public,anon;
grant execute on function public.set_home_venue_club_hours(uuid,time,time) to authenticated;
CREATE OR REPLACE FUNCTION public.enforce_lewisham_rink_opening_hours()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE f public.fixtures%ROWTYPE; local_start timestamp; local_end timestamp; effective_end timestamptz; opens time; closes time;
BEGIN
 IF TG_TABLE_NAME = 'fixtures' THEN
  IF TG_OP = 'UPDATE' THEN
   IF (NEW.club_id,NEW.is_home,NEW.start_at,NEW.end_at,NEW.rinks_required,NEW.competition_type_id,NEW.green_area_id) IS NOT DISTINCT FROM (OLD.club_id,OLD.is_home,OLD.start_at,OLD.end_at,OLD.rinks_required,OLD.competition_type_id,OLD.green_area_id) THEN RETURN NEW; END IF;
  END IF;
  f := NEW;
 ELSE
  IF TG_OP = 'UPDATE' THEN
   IF (NEW.fixture_id,NEW.home_rink_label) IS NOT DISTINCT FROM (OLD.fixture_id,OLD.home_rink_label) THEN RETURN NEW; END IF;
  END IF;
  SELECT * INTO f FROM public.fixtures WHERE id=NEW.fixture_id;
  IF NOT FOUND THEN RETURN NEW; END IF;
 END IF;
 IF f.is_home IS NOT TRUE THEN RETURN NEW; END IF;
 SELECT club_start_time,club_end_time INTO opens,closes FROM public.venues WHERE id=f.venue_id AND club_id=f.club_id AND is_home_venue;
 IF opens IS NULL OR closes IS NULL THEN
  IF f.club_id='8ae87bbe-cb16-4330-a5b0-e62366479f07'::uuid THEN opens:='09:00';closes:='22:00'; ELSE RETURN NEW;END IF;
 END IF;
 IF TG_TABLE_NAME = 'fixtures' AND coalesce(f.rinks_required,0) <= 0
  AND NOT EXISTS(SELECT 1 FROM public.competition_types t WHERE t.id=f.competition_type_id AND t.uses_rinks IS TRUE)
  AND NOT EXISTS(SELECT 1 FROM public.fixture_rinks r WHERE r.fixture_id=f.id) THEN RETURN NEW; END IF;
 effective_end := coalesce(f.end_at,f.start_at + interval '4 hours');
 local_start := f.start_at AT TIME ZONE 'Europe/London';
 local_end := effective_end AT TIME ZONE 'Europe/London';
 IF f.start_at IS NULL OR NOT isfinite(f.start_at) OR NOT isfinite(effective_end)
  OR effective_end <= f.start_at OR local_start::date <> local_end::date
  OR local_start::time < opens OR local_end::time > closes THEN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE=format('Rink bookings must start at or after %s and finish by %s on the same day (UK local time). Please check the date and start/end times.',to_char(opens,'HH24:MI'),to_char(closes,'HH24:MI')), HINT='Use 24-hour times: for example, 13:00 means 1 pm and 14:00 means 2 pm.';
 END IF;
 RETURN NEW;
END;
$function$
;
create function public.validate_fixture_type_locks() returns trigger language plpgsql set search_path='' as $$
begin
 if new.lock_duration and coalesce(new.default_duration_minutes,0)<=0 then raise exception 'A locked duration needs a positive maximum in minutes';end if;
 if new.lock_rinks and new.uses_rinks and coalesce(new.default_rinks_required,0)<=0 then raise exception 'Locked rinks need a positive default';end if;
 if new.lock_format and new.uses_rinks and (new.default_format is null or new.default_players_per_rink is null) then raise exception 'A locked format needs a default format and players per rink';end if;
 return new;
end $$;
create trigger validate_fixture_type_locks before insert or update on public.competition_types for each row execute function public.validate_fixture_type_locks();
create function public.create_fixture_with_booking_policy(p_booking jsonb,p_participation_mode text) returns uuid
language plpgsql security definer set search_path='' as $$
declare f uuid;
begin
 if auth.uid() is null then raise exception 'Sign in to create a fixture';end if;
 if p_participation_mode not in ('team','rsvp','preselect','open') or p_participation_mode is null then raise exception 'Choose a participation mode';end if;
 f:=public.create_fixture_with_match_fee(
p_club_id=>(p_booking->>'p_club_id')::uuid,
p_start_at=>(p_booking->>'p_start_at')::timestamptz,
p_end_at=>(p_booking->>'p_end_at')::timestamptz,
p_is_home=>(p_booking->>'p_is_home')::boolean,
p_section=>(p_booking->>'p_section')::text,
p_rinks_required=>(p_booking->>'p_rinks_required')::integer,
p_players_per_rink=>(p_booking->>'p_players_per_rink')::integer,
p_format=>(p_booking->>'p_format')::text,
p_competition_type_id=>(p_booking->>'p_competition_type_id')::uuid,
p_dress_code=>(p_booking->>'p_dress_code')::text,
p_team_id=>(p_booking->>'p_team_id')::uuid,
p_team_name=>(p_booking->>'p_team_name')::text,
p_requires_rsvp=>(p_booking->>'p_requires_rsvp')::boolean,
p_venue_id=>(p_booking->>'p_venue_id')::uuid,
p_opponent_venue_id=>(p_booking->>'p_opponent_venue_id')::uuid,
p_green_area_id=>(p_booking->>'p_green_area_id')::uuid,
p_orientation=>(p_booking->>'p_orientation')::text,
p_captain_member_profile_id=>(p_booking->>'p_captain_member_profile_id')::uuid,
p_vice_captain_member_profile_id=>(p_booking->>'p_vice_captain_member_profile_id')::uuid,
p_notes=>(p_booking->>'p_notes')::text,
p_create_team_selection=>(p_booking->>'p_create_team_selection')::boolean,
p_team_selection_status=>(p_booking->>'p_team_selection_status')::text,
p_home_rink_labels=>p_booking->'p_home_rink_labels',
p_rink_assignments=>p_booking->'p_rink_assignments',
p_team_selection_members=>p_booking->'p_team_selection_members',
p_match_fee_pence=>(p_booking->>'p_match_fee_pence')::integer);
 update public.fixtures set participation_mode=p_participation_mode where id=f;
 return f;
end $$;
revoke all on function public.create_fixture_with_booking_policy(jsonb,text) from public,anon;
grant execute on function public.create_fixture_with_booking_policy(jsonb,text) to authenticated;
notify pgrst,'reload schema';
commit;
