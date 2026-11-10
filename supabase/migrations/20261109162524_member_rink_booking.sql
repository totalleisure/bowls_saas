-- Separate member entry point; existing admin routines and triggers are unchanged.
create function public.create_member_rink_booking(
  p_club_id uuid, p_competition_type_id uuid, p_green_area_id uuid,
  p_start_at timestamptz, p_rink_label text
) returns uuid language plpgsql security invoker
set search_path = pg_catalog, public, pg_temp as $$
declare
  actor uuid := public.my_member_profile_id();
  ct public.competition_types%rowtype;
  green public.green_areas%rowtype;
  availability record;
  orientation_value text;
  players integer;
begin
  if auth.uid() is null or not exists (
    select 1 from public.club_memberships cm where cm.club_id=p_club_id
      and cm.member_profile_id=actor and cm.is_active and cm.role::text<>'guest'
  ) then raise exception 'An active non-guest club membership is needed to book'; end if;
  select * into ct from public.competition_types where id=p_competition_type_id
    and club_id=p_club_id and is_active and bookable_by_members and is_internal
    and uses_rinks and team_selection_enabled and selection_mode='preselect';
  if not found then raise exception 'Choose an active Member Fixture Type'; end if;
  select ga.* into green from public.green_areas ga join public.venues v on v.id=ga.venue_id
    where ga.id=p_green_area_id and ga.club_id=p_club_id and v.club_id=p_club_id and v.is_home_venue;
  if not found then raise exception 'Choose a home green for this club'; end if;
  if p_start_at is null or p_start_at<=now()
     or (p_start_at at time zone 'Europe/London')::time < time '09:00'
     or (p_start_at at time zone 'Europe/London')::date <>
        ((p_start_at+interval '150 minutes') at time zone 'Europe/London')::date
     or ((p_start_at+interval '150 minutes') at time zone 'Europe/London')::time>time '22:00'
  then raise exception 'Choose a future 2.5-hour booking between 09:00 and 22:00'; end if;
  -- Serialize this member booking route per green, then recheck the exact slot.
  perform pg_advisory_xact_lock(hashtextextended(p_green_area_id::text,0));
  select * into availability from public.get_green_rink_availability(
    p_green_area_id,p_start_at,p_start_at+interval '150 minutes',null)
    where rink_label=p_rink_label;
  if not found or availability.is_booked or availability.free_capacity_rinks<1 then
    raise exception 'That rink is no longer available. Choose another rink or time';
  end if;
  -- Retain the previous member creation default; no date/orientation schedule
  -- exists on the green record. This does not introduce a new orientation rule.
  if green.discipline::text='outdoor' and green.orientation_mode::text<>'not_applicable' then
    orientation_value:=green.allowed_orientations[1]::text;
  end if;
  players:=greatest(1,least(4,coalesce(ct.default_players_per_rink,4)));
  return public.create_fixture_with_setup_v2(
    p_club_id=>p_club_id,p_start_at=>p_start_at,p_end_at=>p_start_at+interval '150 minutes',
    p_is_home=>true,p_section=>ct.section::text,p_rinks_required=>1,p_players_per_rink=>players,
    p_format=>case players when 1 then 'singles' when 2 then 'pairs' when 3 then 'triples' else 'rinks' end,
    p_competition_type_id=>ct.id,p_dress_code=>coalesce(ct.dress_code::text,'open'),
    p_team_name=>ct.name,p_requires_rsvp=>false,p_venue_id=>green.venue_id,
    p_green_area_id=>green.id,p_orientation=>orientation_value,p_captain_member_profile_id=>actor,
    p_create_team_selection=>true,p_team_selection_status=>'published',
    p_home_rink_labels=>jsonb_build_array(jsonb_build_object('team_no',1,'home_rink_label',p_rink_label)),
    p_rink_assignments=>jsonb_build_array(jsonb_build_object('team_no',1,'position',1,'member_profile_id',actor)),
    p_team_selection_members=>jsonb_build_array(jsonb_build_object('member_profile_id',actor,'role','player','acceptance','accepted','is_selected',true)));
end $$;
revoke all on function public.create_member_rink_booking(uuid,uuid,uuid,timestamptz,text) from public,anon;
grant execute on function public.create_member_rink_booking(uuid,uuid,uuid,timestamptz,text) to authenticated;
comment on function public.create_member_rink_booking(uuid,uuid,uuid,timestamptz,text)
  is 'Member-only 150-minute physical rink booking; creates fixture and setup atomically. Admin creation unchanged.';
