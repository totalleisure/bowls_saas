begin;
do $$
declare club uuid:='8ae87bbe-cb16-4330-a5b0-e62366479f07'; ft uuid:=gen_random_uuid(); venue uuid; green uuid:=gen_random_uuid(); u uuid:=gen_random_uuid(); actor uuid; f uuid; r uuid; v record; d date; st timestamptz; en timestamptz; rejected boolean;
begin
 select id into strict venue from public.venues where club_id=club and is_home_venue limit 1;
 insert into public.green_areas(id,club_id,venue_id,name,discipline,rink_count,scheme_type,scheme_prefix,orientation_mode,allowed_orientations) values(green,club,venue,'Synthetic booking policy checks','indoor',200,'numeric','R','not_applicable','{}');
 insert into auth.users(id,email,raw_user_meta_data) values(u,'policy-'||u||'@example.invalid',jsonb_build_object('first_name','Synthetic','last_name','Booking Policy'));
 select id into actor from public.member_profiles where user_id=u;
 if actor is null then insert into public.member_profiles(user_id,display_name) values(u,'Synthetic Booking Policy') returning id into actor;end if;
 insert into public.club_memberships(club_id,member_profile_id,role,is_active) values(club,actor,'member',true);
 insert into public.competition_types(id,club_id,name,is_internal,uses_rinks,bookable_by_members,section,default_rinks_required,default_players_per_rink,default_format,default_duration_minutes,team_selection_enabled,selection_mode,lock_participation,lock_rinks,lock_format,lock_duration,booking_start_times_enabled)
 values(ft,club,'Synthetic policy type',true,true,true,'open',1,2,'pairs',150,true,'preselect',true,true,true,true,true);
 perform set_config('request.jwt.claim.sub',u::text,true);
 foreach d in array array[date '2032-01-17',date '2032-01-18',date '2032-07-17',date '2032-07-18'] loop
  for v in select * from (values(time '09:00',120,true),(time '11:30',150,true),(time '09:30',120,false),(time '11:30:30',120,false),(time '14:00',120,true),(time '14:05',120,true),(time '15:00',151,false)) x(s,mins,allowed) loop
   st:=(d+v.s) at time zone 'Europe/London';en:=st+make_interval(mins=>v.mins);
   rejected:=false;
   begin
    insert into public.fixtures(club_id,start_at,end_at,is_home,section,rinks_required,players_per_rink,competition_type_id,venue_id,green_area_id,captain_member_profile_id,requires_rsvp,team_name)
    values(club,st,en,true,'open',1,2,ft,venue,green,actor,false,'Synthetic policy') returning id into f;
   exception when raise_exception then
    if sqlerrm not like 'This start time is restricted%' and sqlerrm not like 'Booking duration cannot exceed%' then raise;end if;rejected:=true;
   end;
   if rejected=v.allowed then raise exception 'TEST FAILURE: booking boundary %, % minutes accepted=%',v.s,v.mins,not rejected;end if;
  end loop;
 end loop;
 -- Weekday 10:00 starts are accepted, while all-day duration limits remain in force.
 foreach d in array array[date '2032-01-12',date '2032-01-16',date '2032-07-12',date '2032-07-16'] loop
  st:=(d+time '10:00') at time zone 'Europe/London';
  insert into public.fixtures(club_id,start_at,end_at,is_home,section,rinks_required,players_per_rink,competition_type_id,venue_id,green_area_id,captain_member_profile_id,requires_rsvp) values(club,st,st+interval '120 minutes',true,'open',1,2,ft,venue,green,actor,false);
  begin insert into public.fixtures(club_id,start_at,end_at,is_home,section,rinks_required,players_per_rink,competition_type_id,venue_id,green_area_id,captain_member_profile_id,requires_rsvp) values(club,st,st+interval '151 minutes',true,'open',1,2,ft,venue,green,actor,false);raise exception 'TEST FAILURE: weekday duration bypass';exception when raise_exception then if sqlerrm not like 'Booking duration cannot exceed%' then raise;end if;end;
 end loop;
 -- The real creation endpoint retains creator identity through nested RPCs.
 perform public.create_fixture_with_booking_policy(jsonb_build_object('p_club_id',club,'p_start_at','2033-01-14T09:00:00Z','p_end_at','2033-01-14T11:00:00Z','p_is_home',true,'p_section','open','p_rinks_required',1,'p_players_per_rink',2,'p_format','pairs','p_competition_type_id',ft,'p_dress_code','open','p_requires_rsvp',false,'p_venue_id',venue,'p_green_area_id',green,'p_captain_member_profile_id',actor,'p_create_team_selection',true,'p_team_selection_status','published','p_home_rink_labels','[]'::jsonb,'p_rink_assignments',jsonb_build_array(jsonb_build_object('team_no',1,'member_profile_id',actor,'position',1)),'p_team_selection_members',jsonb_build_array(jsonb_build_object('member_profile_id',actor,'role','player','is_selected',true,'acceptance','accepted'))),'preselect');
 begin perform public.create_fixture_with_booking_policy(jsonb_build_object('p_club_id',club,'p_start_at','2033-01-15T10:00:00Z','p_end_at','2033-01-15T12:00:00Z','p_is_home',true,'p_section','open','p_rinks_required',1,'p_players_per_rink',2,'p_format','pairs','p_competition_type_id',ft,'p_dress_code','open','p_requires_rsvp',false,'p_venue_id',venue,'p_green_area_id',green,'p_captain_member_profile_id',actor,'p_create_team_selection',true,'p_team_selection_status','published','p_home_rink_labels','[]'::jsonb,'p_rink_assignments',jsonb_build_array(jsonb_build_object('team_no',1,'member_profile_id',actor,'position',1)),'p_team_selection_members',jsonb_build_array(jsonb_build_object('member_profile_id',actor,'role','player','is_selected',true,'acceptance','accepted'))),'preselect');
 raise exception 'TEST FAILURE: nested creation RPC bypass';exception when raise_exception then if sqlerrm not like 'This start time is restricted%' then raise;end if;end;
 -- Existing valid fixture; shorter duration remains available, structural overrides do not.
 begin update public.fixtures set rinks_required=2 where id=f;raise exception 'TEST FAILURE: locked rink override';exception when raise_exception then if sqlerrm not like 'Rinks required is locked%' then raise;end if;end;
 begin update public.fixtures set players_per_rink=3 where id=f;raise exception 'TEST FAILURE: locked player override';exception when raise_exception then if sqlerrm not like 'Format is locked%' then raise;end if;end;
 begin update public.fixtures set requires_rsvp=true where id=f;raise exception 'TEST FAILURE: locked participation override';exception when raise_exception then if sqlerrm not like 'Participation mode is locked%' then raise;end if;end;
 insert into public.fixture_rinks(fixture_id,fixture_rink_no,format,players_per_rink) values(f,1,'pairs',2) returning id into r;
 begin update public.fixture_rinks set format='aussie_pairs' where id=r;raise exception 'TEST FAILURE: same-player-count format bypass';exception when raise_exception then if sqlerrm not like 'Format is locked%' then raise;end if;end;
 begin update public.fixtures set start_at=(date '2032-07-17'+time '10:00') at time zone 'Europe/London',end_at=(date '2032-07-17'+time '12:00') at time zone 'Europe/London' where id=f;raise exception 'TEST FAILURE: bad reschedule';exception when raise_exception then if sqlerrm not like 'This start time is restricted%' then raise;end if;end;
 -- Admin overrides the Fixture Type but never the venue hours.
 update public.club_memberships set role='admin' where club_id=club and member_profile_id=actor;
 update public.fixtures set start_at=(date '2032-07-17'+time '10:00') at time zone 'Europe/London',end_at=(date '2032-07-17'+time '13:00') at time zone 'Europe/London',requires_rsvp=true where id=f;
 perform public.set_home_venue_club_hours(venue,'10:00','20:00');
 begin update public.fixtures set start_at=(date '2032-07-17'+time '09:00') at time zone 'Europe/London' where id=f;raise exception 'TEST FAILURE: opening hours bypass';exception when raise_exception then if sqlerrm not like 'Rink bookings must start at or after 10:00%' then raise;end if;end;
 -- A timetable is validated even for administrators.
 begin update public.fixture_booking_start_rules set windows='[{"from":540,"until":840,"starts":[540]},{"from":600,"until":900,"starts":[600]}]' where club_id=club;raise exception 'TEST FAILURE: overlapping windows';exception when raise_exception then if sqlerrm not like 'Booking windows must%' then raise;end if;end;
 update public.club_memberships set role='member' where club_id=club and member_profile_id=actor;
 begin perform public.set_home_venue_club_hours(venue,'08:00','23:00');raise exception 'TEST FAILURE: member can change Club hours';exception when raise_exception then if sqlerrm not like 'Only Club Admins%' then raise;end if;end;
 -- Unlocked defaults remain flexible; type rules do not retroactively block unrelated edits.
 update public.competition_types set lock_participation=false,lock_rinks=false,lock_format=false,lock_duration=false,booking_start_times_enabled=false where id=ft;
 update public.fixtures set start_at=(date '2032-07-17'+time '10:15') at time zone 'Europe/London',end_at=(date '2032-07-17'+time '14:15') at time zone 'Europe/London',players_per_rink=3,rinks_required=2 where id=f;
 update public.competition_types set lock_duration=true,booking_start_times_enabled=true where id=ft;
 update public.fixtures set notes='Unrelated edit to existing booking is allowed' where id=f;
end $$;
rollback;
select 'PASS: weekday freedom and Saturday/Sunday restrictions in winter/summer, boundaries, short/maximum duration, direct inserts and reschedules, locks, exact format, unlocked flexibility, admin overrides, editable Club hours, member denial and invalid timetable; all synthetic changes rolled back' result;
