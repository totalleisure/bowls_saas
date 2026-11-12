-- All identities, settings, bookings, messages and action requests roll back.
begin;
do $$
declare users uuid[]:='{}'; profiles uuid[]:='{}'; u uuid; mp uuid; club uuid; ft uuid; green uuid;
 settings jsonb; cid uuid; ea uuid; eb uuid; rid uuid; mid uuid; fid uuid; label text; label2 text;
 f public.fixtures; ids text; n int; total int; env text; before_count int; actor int;
begin
 select cc.club_id,cc.fixture_type_id,cc.settings into strict club,ft,settings from public.club_competitions cc where cc.name='Mens Pairs' limit 1;
 select g.id into strict green from public.green_areas g join public.venues v on v.id=g.venue_id where v.club_id=club and v.is_home_venue limit 1;
 select environment into env from public.competition_release_controls where id;
 for i in 1..5 loop
 u:=gen_random_uuid();
 insert into auth.users(id,email,raw_user_meta_data) values(u,'booking-comms-'||u||'@example.invalid',jsonb_build_object('first_name','Synthetic','last_name','Scorer '||i));
 select id into mp from public.member_profiles where user_id=u;
 if mp is null then insert into public.member_profiles(user_id,display_name,first_name,last_name) values(u,'Synthetic Scorer '||i,'Synthetic','Scorer '||i) returning id into mp;end if;
 update public.member_profiles set email_address='booking-comms-'||u||'@example.invalid' where id=mp;
 insert into public.club_memberships(club_id,member_profile_id,role,is_active) values(club,mp,case when i=5 then 'admin'::public.club_role else 'member'::public.club_role end,true);
 users:=array_append(users,u);profiles:=array_append(profiles,mp);
 end loop;
 -- Test production recipient semantics in isolation, even on staging; nobody can see uncommitted rows.
 update public.competition_release_controls set environment='production' where id;
 foreach actor in array array[1,5] loop
 cid:=gen_random_uuid();ea:=gen_random_uuid();eb:=gen_random_uuid();rid:=gen_random_uuid();mid:=gen_random_uuid();
 insert into public.club_competitions(id,club_id,name,season,status,settings,created_by,fixture_type_id)
 values(cid,club,'Synthetic booking communications '||cid,'test','published',settings,users[5],ft);
 insert into public.competition_entries(id,competition_id,name) values(ea,cid,'Synthetic Pair One'),(eb,cid,'Synthetic Pair Two');
 for i in 1..4 loop insert into public.competition_entry_members(competition_id,entry_id,member_profile_id) values(cid,case when i<3 then ea else eb end,profiles[i]);end loop;
 insert into public.competition_rounds(id,competition_id,round_number,name,play_by) values(rid,cid,1,'Preliminary','2030-08-01');
 insert into public.competition_draw_matches(id,competition_id,round_id,match_number,side_a_kind,side_b_kind,side_a_entry_id,side_b_entry_id) values(mid,cid,rid,1,'entry','entry',ea,eb);
 perform set_config('request.jwt.claim.sub',users[actor]::text,true);
 select rink_label into strict label from public.get_green_rink_availability(green,'2030-07-02 10:00Z','2030-07-02 12:30Z') where not is_booked and free_capacity_rinks>=1 limit 1;
 fid:=public.arrange_competition_match(mid,green,'2030-07-02 10:00Z','2030-07-02 12:30Z',array[label]);
 select count(*) into n from public.notification_queue where fixture_id=fid and payload ? 'competition_booking_key';
 if n<>4 then raise exception 'Expected four booking notifications, got % (actor %)',n,actor;end if;
 if exists(select 1 from public.notification_queue where fixture_id=fid and target_member_profile_id=profiles[5]) then raise exception 'Non-playing Admin got a player message';end if;
 perform public.arrange_competition_match(mid,green,'2030-07-02 10:00Z','2030-07-02 12:30Z',array[label]);
 if (select count(*) from public.notification_queue where fixture_id=fid)<>4 then raise exception 'Retry duplicated booking notices';end if;
 select string_agg(id::text,',') into ids from public.notification_queue where fixture_id=fid;
 perform set_config('app.notification_queue_ids',ids,true);
 perform public.process_notification_queue(20);
 if exists(select 1 from public.notification_queue where fixture_id=fid and status<>'sent') then
 raise exception 'Notification processing failed: %',(select string_agg(last_error,';') from public.notification_queue where fixture_id=fid and status<>'sent');end if;
 if (select count(*) from public.email_queue where fixture_id=fid)<>4 then raise exception 'Four emails required for both entries';end if;
 if exists(select 1 from public.email_queue where fixture_id=fid and (body not like '%Competition: Synthetic booking communications%' or body not like '%Round: Preliminary 1%' or body not like '%11:00 to 13:30%' or body not like '%Rink: '||label||'%' or body not like '%Green:%')) then raise exception 'Missing booking details';end if;
 if exists(select 1 from public.email_queue where fixture_id=fid and not(payload ? 'action_block')) then raise exception 'Standard fixture email action pipeline was bypassed';end if;
 -- Opponent and Admin use the same change route, regardless of initial organiser.
 perform set_config('request.jwt.claim.sub',users[case when actor=1 then 5 else 3 end]::text,true);
 select * into strict f from public.fixtures where id=fid;
 select rink_label into strict label2 from public.get_green_rink_availability(green,'2030-07-03 11:00Z','2030-07-03 13:30Z',fid) where not is_booked and free_capacity_rinks>=1 limit 1;
 perform public.change_competition_fixture_booking(fid,green,'2030-07-03 11:00Z','2030-07-03 13:30Z',array[label2],f.orientation::text,f.start_at,f.end_at,f.green_area_id,array[label]);
 if (select count(*) from public.notification_queue where fixture_id=fid and event_type='fixture_moved')<>4 then raise exception 'Update did not cover both entries';end if;
 if exists(select 1 from public.email_queue where fixture_id=fid and event_type='competition_fixture_booked' and status<>'cancelled') then raise exception 'An obsolete unsent confirmation survived rescheduling';end if;
 if exists(select 1 from public.email_action_requests ar join public.email_queue q on q.id=ar.source_email_queue_id where q.fixture_id=fid and q.event_type='competition_fixture_booked' and ar.status<>'cancelled') then raise exception 'Obsolete confirmation action survived';end if;
 select * into strict f from public.fixtures where id=fid;
 perform public.change_competition_fixture_booking(fid,green,f.start_at,f.end_at,array[label2],f.orientation::text,f.start_at,f.end_at,f.green_area_id,array[label2]);
 if (select count(*) from public.notification_queue where fixture_id=fid and event_type='fixture_moved')<>4 then raise exception 'No-op update generated duplicate notices';end if;
 select string_agg(id::text,',') into ids from public.notification_queue where fixture_id=fid and status='pending';
 perform set_config('app.notification_queue_ids',ids,true);perform public.process_notification_queue(20);
 if (select count(*) from public.email_queue where fixture_id=fid and event_type='fixture_moved')<>4 then raise exception 'Four update emails required';end if;
 if exists(select 1 from public.email_queue where fixture_id=fid and event_type='fixture_moved' and (body not like '%12:00 to 14:30%' or body not like '%03 Jul 2030%' or body not like '%Rink: '||label2||'%')) then raise exception 'Missing updated booking details';end if;
 -- An ordinary time-edit route also uses the same competition message helper.
 perform set_config('request.jwt.claim.sub',users[5]::text,true);
 perform public.change_fixture_time_safe(fid,'2030-07-04 09:00Z','2030-07-04 11:30Z',f.start_at,f.end_at);
 if (select count(*) from public.notification_queue where fixture_id=fid and event_type='fixture_moved')<>8 then raise exception 'Normal fixture time edit did not notify both entries';end if;
 -- No copied production recipient is allowed when staging restrictions apply.
 update public.competition_release_controls set environment='staging' where id;
 before_count:=(select count(*) from public.notification_queue where fixture_id=fid);
 perform competition_private.queue_booking_communications(fid,'updated','restricted-test',f.start_at,f.end_at);
 if (select count(*) from public.notification_queue where fixture_id=fid)<>before_count then raise exception 'Staging recipient restriction bypassed';end if;
 update public.member_profiles set email_address='wayne.s.sayers@gmail.com' where id=profiles[1];
 perform competition_private.queue_booking_communications(fid,'updated','allowlist-test',f.start_at,f.end_at);
 if (select count(*) from public.notification_queue where fixture_id=fid and payload->>'competition_booking_key'=fid::text||':allowlist-test')<>1 then raise exception 'Approved staging test recipient not queued';end if;
 update public.member_profiles set email_address='booking-comms-'||users[1]||'@example.invalid' where id=profiles[1];
 select string_agg(id::text,',') into ids from public.notification_queue where fixture_id=fid and status='pending';
 perform set_config('app.notification_queue_ids',ids,true);perform public.process_notification_queue(20);
 if exists(select 1 from public.notification_queue where fixture_id=fid and payload->>'competition_booking_key'=fid::text||':allowlist-test' and status<>'cancelled') then raise exception 'Changed staging address not blocked at processing time';end if;
 update public.competition_release_controls set environment='production' where id;
 end loop;
 update public.competition_release_controls set environment=env where id;
end $$;
rollback;
select 'PASS: player/Admin booking parity; both entries emailed with standard actions; updates by Admin/opponent; ordinary time edits; retries/no-ops; staging restrictions; all test data rolled back' as result;

