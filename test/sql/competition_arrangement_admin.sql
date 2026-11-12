-- Synthetic users, membership and draw; every record is rolled back.
begin;
do $$
declare ids uuid[]:='{}'; profiles uuid[]:='{}'; u uuid; mp uuid; c uuid:=gen_random_uuid();
 a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); r uuid:=gen_random_uuid(); m uuid:=gen_random_uuid();
 club uuid; ft uuid; green uuid; f uuid; label text; settings jsonb; emails bigint; notices bigint;
begin
 select cc.club_id,cc.fixture_type_id,cc.settings into strict club,ft,settings
 from public.club_competitions cc where cc.name='Mens Pairs' limit 1;
 select g.id into strict green from public.green_areas g join public.venues v on v.id=g.venue_id where v.club_id=club and v.is_home_venue limit 1;
 for i in 1..5 loop
  u:=gen_random_uuid();
  insert into auth.users(id,email,raw_user_meta_data) values(u,'competition-test-'||u||'@example.invalid',jsonb_build_object('first_name','Synthetic','last_name','Player '||i));
  select id into mp from public.member_profiles where user_id=u;
  if mp is null then insert into public.member_profiles(user_id,display_name,first_name,last_name) values(u,'Synthetic Player '||i,'Synthetic','Player '||i) returning id into mp; end if;
  insert into public.club_memberships(club_id,member_profile_id,role,is_active) values(club,mp,case when i=5 then 'admin'::public.club_role else 'member'::public.club_role end,true);
  ids:=array_append(ids,u); profiles:=array_append(profiles,mp);
 end loop;
 insert into public.club_competitions(id,club_id,name,season,status,settings,created_by,fixture_type_id) values(c,club,'Synthetic Admin arrangement verification','test','published',settings,ids[5],ft);
 insert into public.competition_entries(id,competition_id,name) values(a,c,'Synthetic Players 1 / 2'),(b,c,'Synthetic Players 3 / 4');
 for i in 1..4 loop insert into public.competition_entry_members(competition_id,entry_id,member_profile_id) values(c,case when i<=2 then a else b end,profiles[i]); end loop;
 insert into public.competition_rounds(id,competition_id,round_number,name) values(r,c,1,'Final');
 insert into public.competition_draw_matches(id,competition_id,round_id,match_number,side_a_kind,side_b_kind,side_a_entry_id,side_b_entry_id) values(m,c,r,1,'entry','entry',a,b);
 -- Simulate only the newly created synthetic identity, never a real member.
 perform set_config('request.jwt.claim.sub',ids[5]::text,true);
 if not competition_private.can_manage(club) then raise exception 'Synthetic organiser requires Admin rights'; end if;
 select count(*) into emails from public.email_queue; select count(*) into notices from public.notification_queue;
 select rink_label into strict label from public.get_green_rink_availability(green,'2030-07-02 10:00Z','2030-07-02 12:30Z') where not is_booked and free_capacity_rinks>=1 limit 1;
 f:=public.arrange_competition_match(m,green,'2030-07-02 10:00Z','2030-07-02 12:30Z',array[label]);
 if exists(select 1 from public.fixture_rink_assignments where fixture_id=f and member_profile_id=profiles[5]) then raise exception 'Admin was added as a player';end if;
 if not exists(select 1 from public.fixtures where id=f and captain_member_profile_id=profiles[5]) then raise exception 'Admin not recorded as organiser';end if;
 if public.arrange_competition_match(m,green,'2030-07-02 10:00Z','2030-07-02 12:30Z',array[label]) is distinct from f then raise exception 'Duplicate booking created';end if;
 if (select count(*) from public.fixture_rink_assignments where fixture_id=f)<>4 then raise exception 'Missing players'; end if;
 if (select count(*) from public.email_queue)<>emails or (select count(*) from public.notification_queue)<>notices+(select count(*) from public.notification_queue where fixture_id=f and payload ? 'competition_booking_key') then raise exception 'Booking unexpectedly queued communications'; end if;
end $$;
rollback;
select 'PASS: synthetic non-playing Admin can arrange; organiser retained; four real entrants copied; duplicate booking prevented; standard competition booking notices expected; no direct email dispatch; all records rolled back' as result;
