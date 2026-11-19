-- Synthetic users, membership and draw; every record is rolled back.
begin;
do $$
declare ids uuid[]:='{}'; profiles uuid[]:='{}'; u uuid; mp uuid; c uuid:=gen_random_uuid();
 a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); r uuid:=gen_random_uuid(); m uuid:=gen_random_uuid();
 club uuid; ft uuid; green uuid; f uuid; label text; settings jsonb; emails bigint; notices bigint; result jsonb; old_draw jsonb; v_rink uuid; setup_match uuid; old_event uuid;
begin
 select cc.club_id,cc.fixture_type_id,cc.settings into strict club,ft,settings
 from public.club_competitions cc where cc.name='Mens Pairs' limit 1;
 select g.id into strict green from public.green_areas g join public.venues v on v.id=g.venue_id where v.club_id=club and v.is_home_venue limit 1;
 for i in 1..6 loop
  u:=gen_random_uuid();
  insert into auth.users(id,email,raw_user_meta_data) values(u,'competition-test-'||u||'@example.invalid',jsonb_build_object('first_name','Synthetic','last_name','Player '||i));
  select id into mp from public.member_profiles where user_id=u;
  if mp is null then insert into public.member_profiles(user_id,display_name,first_name,last_name) values(u,'Synthetic Player '||i,'Synthetic','Player '||i) returning id into mp; end if;
  update public.member_profiles set first_name='Synthetic',last_name='Player '||i where id=mp;
  insert into public.club_memberships(club_id,member_profile_id,role,is_active) values(club,mp,case when i=5 then 'admin'::public.club_role else 'member'::public.club_role end,true);
  ids:=array_append(ids,u); profiles:=array_append(profiles,mp);
 end loop;
 insert into public.club_competitions(id,club_id,name,season,status,settings,created_by,fixture_type_id) values(c,club,'Synthetic Admin arrangement verification','test','draft',settings||'{"handicap_mode":"team_difference"}',ids[5],ft);
 insert into public.competition_entries(id,competition_id,name) values(a,c,'Synthetic Player 1 / Synthetic Player 2'),(b,c,'Synthetic Player 3 / Synthetic Player 4');
 for i in 1..4 loop insert into public.competition_entry_members(competition_id,entry_id,member_profile_id) values(c,case when i<=2 then a else b end,profiles[i]); end loop;
 update public.competition_entry_members set individual_handicap=case when entry_id=a then 12 else 5 end where competition_id=c;
 update public.competition_entries set payment_status='paid',entry_order=7 where id=a;
 insert into public.competition_rounds(id,competition_id,round_number,name) values(r,c,1,'Final');
 insert into public.competition_draw_matches(id,competition_id,round_id,match_number,side_a_kind,side_b_kind,side_a_entry_id,side_b_entry_id) values(m,c,r,1,'entry','entry',a,b);
 -- Simulate only the newly created synthetic identity, never a real member.
 perform set_config('request.jwt.claim.sub',ids[5]::text,true);
 if not competition_private.can_manage(club) then raise exception 'Synthetic organiser requires Admin rights'; end if;

 for i in 1..4 loop update public.member_profiles set email_address='removal-'||profiles[i]::text||'@example.invalid' where id=profiles[i];end loop;
 insert into public.app_superusers(user_id) values(ids[5]);
 update public.club_competitions set status='published' where id=c;
 select rink_label into strict label from public.get_green_rink_availability(green,'2030-07-02 10:00Z','2030-07-02 12:30Z') where not is_booked and free_capacity_rinks>=1 limit 1;
 f:=public.arrange_competition_match(m,green,'2030-07-02 10:00Z','2030-07-02 12:30Z',array[label]);
 insert into public.competition_fixture_management_events(club_id,fixture_id,match_id,actor_user_id,action,details)
 values(club,f,m,ids[5],'booking_changed','{}') returning id into old_event;
 select to_jsonb(d) into old_draw from public.competition_draw_matches d where id=m;
 -- A pending result must block even Superuser deletion, atomically.
 update public.competition_draw_matches set status='result_pending',score_a=10,score_b=8,proposed_winner_entry_id=a where id=m;
 begin
 perform public.admin_force_delete_fixture(f,'Synthetic regression','DELETE FIXTURE');
 raise exception 'Recorded result deleted';
 exception when raise_exception then if sqlerrm not like 'This competition match has a recorded result%' then raise;end if;end;
 update public.competition_draw_matches set status='to_be_arranged',score_a=null,score_b=null,proposed_winner_entry_id=null where id=m;
 select id into v_rink from public.fixture_rinks where fixture_id=f limit 1;
 insert into scorecard_private.fixture_matches(fixture_id,club_id) values(f,club) returning id into setup_match;
 insert into scorecard_private.fixture_rink_setups(match_id,fixture_rink_id,source_snapshot,conditions,created_by) values(setup_match,v_rink,'{}','{}',ids[5]);
 begin
 perform public.admin_force_delete_fixture(f,'Synthetic regression','DELETE FIXTURE');
 raise exception 'Prepared scorecard deleted';
 exception when raise_exception then if sqlerrm not like 'A scorecard has already been prepared%' then raise;end if;end;
 delete from scorecard_private.fixture_matches where id=setup_match;
 if exists(select 1 from public.email_queue where event_type='competition_booking_removed' and payload->>'deleted_fixture_id'=f::text) then raise exception 'Blocked deletion queued removal mail';end if;
 -- Exercise the staging restriction without retaining any control/config changes.
 update public.competition_release_controls set environment='staging';
 if competition_private.queue_booking_removal(m,f)<>0 then raise exception 'Staging allowed a non-test recipient';end if;
 update public.competition_release_controls set environment='production';
 if competition_private.queue_booking_removal(m,f)<>4 then raise exception 'Expected all four drawn players';end if;
 if competition_private.queue_booking_removal(m,f)<>0 then raise exception 'Duplicate removal emails';end if;
 delete from public.email_queue where event_type='competition_booking_removed' and payload->>'deleted_fixture_id'=f::text;
 update public.member_profiles set email_address=(select email_address from public.member_profiles where id=profiles[1]) where id=profiles[2];
 update public.member_profiles set email_address=null where id=profiles[3];
 if competition_private.queue_booking_removal(m,f)<>2 then raise exception 'Shared/missing email handling failed';end if;
 delete from public.email_queue where event_type='competition_booking_removed' and payload->>'deleted_fixture_id'=f::text;
 for i in 1..4 loop update public.member_profiles set email_address='removal-'||profiles[i]::text||'@example.invalid' where id=profiles[i];end loop;
 perform public.admin_force_delete_fixture(f,'Synthetic regression','DELETE FIXTURE');
 if (select count(*) from public.email_queue where event_type='competition_booking_removed' and payload->>'deleted_fixture_id'=f::text
   and fixture_id is null and team_selection_id is null and status='pending'
   and body like '%NOT been cancelled%' and body like '%To be arranged%' and body like '%Removed booking:%')<>4 then raise exception 'Removal mail did not survive deletion for all players';end if;
 if exists(select 1 from public.fixtures where id=f) or exists(select 1 from public.fixture_rinks where fixture_id=f) then raise exception 'Booking/rink survived deletion';end if;
 if not exists(select 1 from public.competition_draw_matches d where id=m and fixture_id is null and (to_jsonb(d)-'fixture_id')=(old_draw-'fixture_id')) then raise exception 'Draw not preserved';end if;
 if not exists(select 1 from public.competition_fixture_management_events where id=old_event and fixture_id is null and details->>'deleted_fixture_id'=f::text) then raise exception 'Booking history lost';end if;
 if not exists(select 1 from public.audit_journal where record_id=m::text and action='booking removed') then raise exception 'Removal audit missing';end if;
end $$;
rollback;
select 'PASS: synthetic booking deletion preserves draw and history, releases rink; results/scorecards protected; all-four-player removal emails, shared/missing email handling, staging restriction, deduplication; ALL changes rolled back' result;
