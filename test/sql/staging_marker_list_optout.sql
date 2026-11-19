-- Synthetic users, membership and draw; every record is rolled back.
begin;
do $$
declare ids uuid[]:='{}'; profiles uuid[]:='{}'; u uuid; mp uuid; c uuid:=gen_random_uuid();
 a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); r uuid:=gen_random_uuid(); m uuid:=gen_random_uuid();
 club uuid; ft uuid; green uuid; f uuid; label text; settings jsonb; emails bigint; notices bigint; result jsonb; old_draw jsonb; v_rink uuid; setup_match uuid; old_event uuid; request_id uuid:=gen_random_uuid(); queue_id uuid; source_id uuid; forward_id uuid; code text; subject_text text; response jsonb; marker_list uuid; other_list uuid; confirm_id uuid; confirm_code text; assignments_before jsonb;
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

 for i in 1..6 loop update public.member_profiles set email_address='marker-test-'||profiles[i]::text||'@example.invalid' where id=profiles[i];end loop;
 insert into public.app_superusers(user_id) values(ids[5]);
 update public.club_competitions set status='published' where id=c;
 select rink_label into strict label from public.get_green_rink_availability(green,'2030-07-02 10:00Z','2030-07-02 12:30Z') where not is_booked and free_capacity_rinks>=1 limit 1;
 f:=public.arrange_competition_match(m,green,'2030-07-02 10:00Z','2030-07-02 12:30Z',array[label]);
 update public.member_profiles set email_address='wayne@totalleisure.com' where id=profiles[5];
 update public.member_profiles set email_address='wayne.sayers@telius.co.uk' where id=profiles[6];
 select id into strict v_rink from public.fixture_rinks where fixture_id=f limit 1;
 update public.fixture_rinks set marker_required=true where id=v_rink;
 insert into public.fixture_marker_requests(id,fixture_rink_id,status,requested_by_member_profile_id) values(request_id,v_rink,'open',profiles[5]);
 insert into public.notification_queue(event_type,member_profile_id,target_member_profile_id,fixture_id,payload,status)
 values('marker_request_opened',profiles[5],profiles[6],f,jsonb_build_object('marker_request_id',request_id,'fixture_rink_id',v_rink,'fixture_label','Synthetic marker test','start_at','2030-07-02 10:00Z'),'pending') returning id into queue_id;
 perform public.process_selected_notification_queue_rows(array[queue_id]);
 select id,payload->'action_block'->>'response_code',subject into strict source_id,code,subject_text from public.email_queue where fixture_id=f and event_type='marker_request_opened' and status='pending';
 if code !~ '^MRK-[A-F0-9]{64}$' then raise exception 'No marker response credential';end if;
 if not exists(select 1 from marker_reply_private.tokens where source_email_id=source_id) then raise exception 'Missing request correlation';end if;
 update public.email_queue set status='sent',sent_at=now() where id=source_id;
 select vt.mailing_list_id into strict marker_list from public.volunteer_tasks vt where vt.club_id=club and vt.task_code='marker' and vt.is_active limit 1;
 select id into strict other_list from public.mailing_lists where club_id=club and id<>marker_list and is_active limit 1;
 insert into public.mailing_list_members(mailing_list_id,member_profile_id,is_active,added_by_member_profile_id) values(marker_list,profiles[6],true,profiles[6]),(other_list,profiles[6],true,profiles[6]);
 perform public.set_competition_fixture_marker(f,v_rink,true,profiles[6],true,null);
 set constraints confirm_agreed_marker immediate;
 select jsonb_agg(to_jsonb(fra)) into assignments_before from public.fixture_rink_assignments fra where fixture_id=f;
 if (select payload->'action_block'->'secondary_actions'->0->>'label' from public.email_queue where id=source_id)<>'Leave the Markers List' then raise exception 'Missing separate link';end if;
 response:=public.marker_list_email_action(code,'wrong@example.test','LEAVE_MARKERS','<wrong-leave@test>',now());
 if (response->>'ok')::boolean then raise exception 'Wrong sender allowed';end if;
 response:=public.marker_list_email_action(code,'wayne.sayers@telius.co.uk','LEAVE_MARKERS','<leave@test>',now());
 if response->>'status'<>'confirmation_queued' then raise exception 'No confirmation: %',response;end if;
 select q.id,q.payload->'action_block'->>'response_code' into strict confirm_id,confirm_code from marker_reply_private.leave_challenges lc join public.email_queue q on q.id=lc.confirmation_email_id where lc.member_id=profiles[6] and lc.outcome is null;
 if not exists(select 1 from public.mailing_list_members where mailing_list_id=marker_list and member_profile_id=profiles[6]) then raise exception 'First click unsubscribed';end if;
 response:=public.marker_list_email_action(confirm_code,'wayne.sayers@telius.co.uk','CONFIRM_LEAVE_MARKERS','<not-sent@test>',now());
 if (response->>'ok')::boolean then raise exception 'Unsent confirmation accepted';end if;
 update public.email_queue set status='sent',sent_at=now() where id=confirm_id;
 response:=public.marker_list_email_action(confirm_code,'wayne.sayers@telius.co.uk','KEEP_MARKERS','<keep@test>',now());
 if response->>'status'<>'kept' then raise exception 'Keep failed';end if;
 response:=public.marker_list_email_action(confirm_code,'wayne.sayers@telius.co.uk','CONFIRM_LEAVE_MARKERS','<replay@test>',now());
 if response->>'status'<>'duplicate' then raise exception 'Confirmation reused';end if;
 if not exists(select 1 from public.mailing_list_members where mailing_list_id=marker_list and member_profile_id=profiles[6]) then raise exception 'Keep unsubscribed';end if;
 response:=public.marker_list_email_action(code,'wayne.sayers@telius.co.uk','LEAVE_MARKERS','<leave-again@test>',now());
 select q.id,q.payload->'action_block'->>'response_code' into strict confirm_id,confirm_code from marker_reply_private.leave_challenges lc join public.email_queue q on q.id=lc.confirmation_email_id where lc.member_id=profiles[6] and lc.outcome is null;
 update public.email_queue set status='sent',sent_at=now() where id=confirm_id;
 insert into public.email_queue(member_profile_id,event_type,recipient_email,subject,body,fixture_id,payload) values(profiles[6],'marker_request_opened','wayne.sayers@telius.co.uk','Test pending request','Test pending request',f,jsonb_build_object('marker_request_id',request_id));
 response:=public.marker_list_email_action(confirm_code,'wayne.sayers@telius.co.uk','CONFIRM_LEAVE_MARKERS','<confirm-leave@test>',now());
 if response->>'status'<>'left' then raise exception 'Confirmed leave failed: %',response;end if;
 if exists(select 1 from public.mailing_list_members where mailing_list_id=marker_list and member_profile_id=profiles[6]) then raise exception 'Still on marker list';end if;
 if not exists(select 1 from public.mailing_list_members where mailing_list_id=other_list and member_profile_id=profiles[6]) then raise exception 'Other list affected';end if;
 if (select jsonb_agg(to_jsonb(fra)) from public.fixture_rink_assignments fra where fixture_id=f) is distinct from assignments_before then raise exception 'Agreed assignments changed';end if;
 if not exists(select 1 from public.fixture_marker_requests where id=request_id and status='fulfilled' and fulfilled_by_member_profile_id=profiles[6]) then raise exception 'Appointment changed';end if;
 if exists(select 1 from public.email_queue where fixture_id=f and member_profile_id=profiles[6] and event_type='marker_request_opened' and status='pending') then raise exception 'Pending requests survived';end if;
 insert into public.email_queue(member_profile_id,event_type,recipient_email,subject,body,fixture_id,payload) values(profiles[6],'marker_request_opened','wayne.sayers@telius.co.uk','Test late request','Test late request',f,jsonb_build_object('marker_request_id',request_id,'test_late_marker_request',true));
 if not exists(select 1 from public.email_queue where fixture_id=f and payload->>'test_late_marker_request'='true' and status='cancelled') then raise exception 'Delayed request not suppressed';end if;
 if not exists(select 1 from public.email_queue where fixture_id=f and event_type='marker_appointment_confirmed' and status='pending') then raise exception 'Agreed appointment confirmation removed';end if;
 if not exists(select 1 from public.email_queue where event_type='marker_list_preference_receipt' and member_profile_id=profiles[6] and body like '%appointments already agreed are unchanged%') then raise exception 'Receipt warning missing';end if;
end $$;
rollback;
select 'PASS: two-step leave/keep, sender binding, sent confirmation, no first-click change, single-use, correct club/list only, pending/future requests stopped, agreed appointments preserved; ALL changes rolled back' result;

