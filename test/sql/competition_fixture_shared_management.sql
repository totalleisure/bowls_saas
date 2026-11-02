-- Synthetic users, membership and draw; every record is rolled back.
begin;
do $$
declare ids uuid[]:='{}'; profiles uuid[]:='{}'; u uuid; mp uuid; c uuid:=gen_random_uuid();
 a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); r uuid:=gen_random_uuid(); m uuid:=gen_random_uuid();
 club uuid; ft uuid; green uuid; f uuid; label text; settings jsonb; emails bigint; notices bigint; fr uuid; previous public.fixtures; ordinary uuid; state jsonb;
begin
 select cc.club_id,cc.fixture_type_id,cc.settings into strict club,ft,settings
 from public.club_competitions cc where cc.name='Mens Pairs' limit 1;
 select g.id into strict green from public.green_areas g join public.venues v on v.id=g.venue_id where v.club_id=club and v.is_home_venue limit 1;
 for i in 1..6 loop
  u:=gen_random_uuid();
  insert into auth.users(id,email,raw_user_meta_data) values(u,'competition-test-'||u||'@example.invalid',jsonb_build_object('first_name','Synthetic','last_name','Player '||i));
  select id into mp from public.member_profiles where user_id=u;
  if mp is null then insert into public.member_profiles(user_id,display_name,first_name,last_name) values(u,'Synthetic Player '||i,'Synthetic','Player '||i) returning id into mp; end if;
  insert into public.club_memberships(club_id,member_profile_id,role,is_active) values(club,mp,'member',true);
  ids:=array_append(ids,u); profiles:=array_append(profiles,mp);
 end loop;
 insert into public.club_competitions(id,club_id,name,season,status,settings,created_by,fixture_type_id) values(c,club,'Synthetic arrangement verification','test','published',settings,ids[1],ft);
 insert into public.competition_entries(id,competition_id,name) values(a,c,'Synthetic Players 1 / 2'),(b,c,'Synthetic Players 3 / 4');
 for i in 1..4 loop insert into public.competition_entry_members(competition_id,entry_id,member_profile_id) values(c,case when i<=2 then a else b end,profiles[i]); end loop;
 insert into public.competition_rounds(id,competition_id,round_number,name) values(r,c,1,'Final');
 insert into public.competition_draw_matches(id,competition_id,round_id,match_number,side_a_kind,side_b_kind,side_a_entry_id,side_b_entry_id) values(m,c,r,1,'entry','entry',a,b);
 -- Simulate only the newly created synthetic identity, never a real member.
 perform set_config('request.jwt.claim.sub',ids[4]::text,true);
 if competition_private.can_manage(club) then raise exception 'Synthetic player unexpectedly has Admin rights'; end if;
 select count(*) into emails from public.email_queue; select count(*) into notices from public.notification_queue;
 select rink_label into strict label from public.get_green_rink_availability(green,'2030-07-02 10:00Z','2030-07-02 12:30Z') where not is_booked and free_capacity_rinks>=1 limit 1;
 f:=public.arrange_competition_match(m,green,'2030-07-02 10:00Z','2030-07-02 12:30Z',array[label]);

 select * into strict previous from public.fixtures where id=f;
 select id into strict fr from public.fixture_rinks where fixture_id=f limit 1;
 -- All four newly created drawn players have the scoped controls, regardless of side.
 for i in 1..4 loop
  perform set_config('request.jwt.claim.sub',ids[i]::text,true);
  if (public.competition_fixture_access(f)->>'can_manage')::boolean is not true then raise exception 'Drawn player % denied shared controls',i; end if;
 end loop;
 -- Creator retains their normal, full Captain rights; the other entrants do not acquire them.
 perform set_config('request.jwt.claim.sub',ids[4]::text,true);
 if not public.can_manage_fixture(f) or not public.can_manage_team_selection(f) then raise exception 'Creator lost Captain rights'; end if;
 perform set_config('request.jwt.claim.sub',ids[1]::text,true);
 if public.can_manage_fixture(f) or public.can_manage_team_selection(f) then raise exception 'Shared entrant acquired broad team/fixture rights'; end if;
 begin
  perform public.save_preselect_fixture_state(f,'[]'::jsonb);
  raise exception 'Shared entrant could replace drawn players';
 exception when raise_exception then if sqlerrm not like 'You do not have permission%' then raise; end if; end;
 -- A shared player changes only the booking; Captain, type, label and players remain intact.
 perform public.change_competition_fixture_booking(f,green,'2030-07-02 13:00Z','2030-07-02 15:30Z',array[label],null,previous.start_at,previous.end_at,green,array[label]);
 if not exists(select 1 from public.fixtures where id=f and start_at='2030-07-02 13:00Z' and captain_member_profile_id=profiles[4] and created_by_user_id=ids[4] and competition_type_id=ft and team_name=previous.team_name) then raise exception 'Booking changed protected fixture data'; end if;
 if (select count(*) from public.fixture_rink_assignments where fixture_id=f)<>4 then raise exception 'Booking changed players'; end if;
 if not exists(select 1 from public.competition_fixture_management_events where fixture_id=f and action='booking_changed' and actor_user_id=ids[1]) then raise exception 'Booking actor not audited'; end if;
 begin
  perform public.change_competition_fixture_booking(f,green,'2030-07-02 16:00Z','2030-07-02 18:00Z',array[label],null,previous.start_at,previous.end_at,green,array[label]);
  raise exception 'Stale edit accepted';
 exception when serialization_failure then null; end;
 perform public.set_competition_fixture_marker(f,fr,true,profiles[5],false,null);
 if not exists(select 1 from public.fixture_rink_assignments where fixture_id=f and fixture_rink_id=fr and position=201 and member_profile_id=profiles[5]) then raise exception 'Marker not assigned'; end if;
 begin
  perform public.set_competition_fixture_marker(f,fr,true,profiles[1],true,profiles[5]);
  raise exception 'Drawn player could become a marker';
 exception when raise_exception then if sqlerrm not like 'This member already has another position%' then raise; end if; end;
 perform public.set_competition_fixture_marker(f,fr,true,null,true,profiles[5]);
 perform public.set_competition_fixture_marker(f,fr,false,null,true,null);
 if (select count(*) from public.fixture_rink_assignments where fixture_id=f)<>4 then raise exception 'Marker edits changed players'; end if;
 -- Neither an assigned marker nor an unrelated Club member gains shared rights.
 for i in 5..6 loop
  perform set_config('request.jwt.claim.sub',ids[i]::text,true);
  if (public.competition_fixture_access(f)->>'can_manage')::boolean then raise exception 'Unrelated member/marker gained rights'; end if;
  begin
   perform public.set_competition_fixture_marker(f,fr,true,null,false,null);
   raise exception 'Unrelated member changed marker';
  exception when insufficient_privilege then null; end;
 end loop;
 -- Same Fixture Type, but no draw link: existing ordinary fixture permissions are unchanged.
 perform set_config('request.jwt.claim.sub',ids[4]::text,true);
 insert into public.fixtures(club_id,start_at,end_at,is_home,section,rinks_required,players_per_rink,competition_type_id,venue_id,green_area_id,captain_member_profile_id,requires_rsvp)
 values(club,'2030-07-03 10:00Z','2030-07-03 12:30Z',true,previous.section,1,2,ft,previous.venue_id,green,profiles[4],false) returning id into ordinary;
 if not public.can_manage_fixture(ordinary) then raise exception 'Ordinary Captain lost rights'; end if;
 if (public.competition_fixture_access(ordinary)->>'is_competition')::boolean then raise exception 'Fixture Type incorrectly granted competition rights'; end if;
 perform set_config('request.jwt.claim.sub',ids[1]::text,true);
 if (public.competition_fixture_access(ordinary)->>'can_manage')::boolean or public.can_manage_fixture(ordinary) then raise exception 'Ordinary fixture permissions broadened'; end if;
 -- Cancelled means locked even for the creator in the shared controls.
 update public.fixtures set cancelled_at=now() where id=f;
 for i in 1..4 loop
  perform set_config('request.jwt.claim.sub',ids[i]::text,true);
  if (public.competition_fixture_access(f)->>'can_manage')::boolean then raise exception 'Cancelled fixture still editable'; end if;
  begin
   perform public.set_competition_fixture_marker(f,fr,true,null,false,null);
   raise exception 'Cancelled marker still editable';
  exception when insufficient_privilege then null; end;
 end loop;
 if (select count(*) from public.email_queue)<>emails or (select count(*) from public.notification_queue)<>notices then raise exception 'Shared operations unexpectedly queued communications'; end if;
 if has_function_privilege('anon','public.change_competition_fixture_booking(uuid,uuid,timestamptz,timestamptz,text[],text,timestamptz,timestamptz,uuid,text[])','execute') then raise exception 'Anonymous execute allowed'; end if;
 if has_table_privilege('authenticated','public.competition_fixture_management_events','insert') then raise exception 'Client can forge audit events'; end if;
end $$;
rollback;
select 'PASS: all four entrants have scoped controls; creator retains full Captain rights; unrelated, ordinary, cancelled and stale edits denied; markers and audit verified; no messages; synthetic test rolled back' as result;
