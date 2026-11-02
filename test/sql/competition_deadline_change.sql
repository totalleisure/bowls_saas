-- Synthetic users, membership and draw; every record is rolled back.
begin;
do $$
declare ids uuid[]:='{}'; profiles uuid[]:='{}'; u uuid; mp uuid; c uuid:=gen_random_uuid();
 a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); r uuid:=gen_random_uuid(); m uuid:=gen_random_uuid();
 club uuid; ft uuid; green uuid; f uuid; label text; settings jsonb; emails bigint; notices bigint; r2 uuid:=gen_random_uuid(); m2 uuid:=gen_random_uuid(); m3 uuid:=gen_random_uuid(); z uuid:=gen_random_uuid(); q uuid:=gen_random_uuid(); e uuid; approved uuid; claimed int;
begin
 select cc.club_id,cc.fixture_type_id,cc.settings into strict club,ft,settings
 from public.club_competitions cc where cc.name='Mens Pairs' limit 1;
 select g.id into strict green from public.green_areas g join public.venues v on v.id=g.venue_id where v.club_id=club and v.is_home_venue limit 1;
 for i in 1..8 loop
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

 update public.club_memberships set role='admin' where club_id=club and member_profile_id=profiles[6];
 update public.competition_rounds set name='Semi-final' where id=r;
 insert into public.competition_rounds(id,competition_id,round_number,name) values(r2,c,2,'Final');
 insert into public.competition_draw_matches(id,competition_id,round_id,match_number,side_a_kind,side_b_kind,side_a_source_id) values(m2,c,r2,1,'winner','winner',m);
 select id into strict approved from public.member_profiles where lower(email_address)='wayne@totalleisure.com' limit 1;
 insert into public.competition_entries(id,competition_id,name) values(z,c,'Next Pair'),(q,c,'Other Pair');
 insert into public.competition_entry_members(competition_id,entry_id,member_profile_id) values(c,z,approved),(c,z,profiles[5]),(c,q,profiles[7]),(c,q,profiles[8]);
 insert into public.competition_draw_matches(id,competition_id,round_id,match_number,side_a_kind,side_b_kind,side_a_entry_id,side_b_entry_id) values(m3,c,r,2,'entry','entry',z,q);
 update public.competition_draw_matches set side_b_source_id=m3 where id=m2;
 select count(*) into emails from public.email_queue; select count(*) into notices from public.notification_queue;
 for i in 1..4 loop
  update public.competition_draw_matches set status='to_be_arranged',score_a=null,score_b=null,proposed_winner_entry_id=null where id=m;
  perform set_config('request.jwt.claim.sub',ids[i]::text,true);
  perform public.record_competition_result(m,21,12,a,false);
  if not exists(select 1 from public.competition_draw_matches where id=m and status='result_pending' and score_a=21 and score_b=12 and proposed_winner_entry_id=a and winner_entry_id is null) then raise exception 'Player % result not pending',i; end if;
  if exists(select 1 from public.competition_draw_matches where id=m2 and side_a_entry_id is not null) then raise exception 'Submission advanced the winner'; end if;
  if not exists(select 1 from public.competition_result_events where match_id=m and actor_user_id=ids[i] and action='submitted') then raise exception 'Player submission not audited'; end if;
  begin
   perform public.record_competition_result(m,21,12,a,true);
   raise exception 'Player could confirm';
  exception when insufficient_privilege then null; end;
  begin
   perform public.record_competition_result(m,12,21,b,false);
   raise exception 'Player could overwrite a pending result';
  exception when raise_exception then if sqlerrm<>'A result is already awaiting Club Admin confirmation' then raise; end if; end;
 end loop;
 perform set_config('request.jwt.claim.sub',ids[5]::text,true);
 begin perform public.record_competition_result(m,21,12,a,false);raise exception 'Unrelated member submitted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',ids[6]::text,true);
 begin perform public.record_competition_result(m,22,12,a,true);raise exception 'Admin confirmed stale scores';exception when raise_exception then if sqlerrm<>'Review the latest submitted result before confirming' then raise;end if;end;
 perform public.record_competition_result(m,21,12,a,true);
 if not exists(select 1 from public.competition_draw_matches where id=m and status='completed' and winner_entry_id=a) then raise exception 'Admin confirmation failed'; end if;
 if not exists(select 1 from public.competition_draw_matches where id=m2 and side_a_entry_id=a) then raise exception 'Confirmed winner not advanced'; end if;

 if exists(select 1 from public.competition_round_ready_events where competition_id=c) then raise exception 'One known side sent premature mail'; end if;
 perform public.record_competition_result(m3,21,10,z,false);
 if exists(select 1 from public.competition_round_ready_events where competition_id=c) then raise exception 'Submitted score created an event'; end if;
 perform public.record_competition_result(m3,21,10,z,true);
 select id into strict e from public.competition_round_ready_events where match_id=m2;
 if not exists(select 1 from public.competition_round_ready_events where id=e and total_players=4 and eligible_count=1 and jsonb_array_length(snapshot->'matches')=1 and snapshot->>'matchId'=m2::text) then raise exception 'Wrong snapshot or counts'; end if;
 if (select count(*) from public.competition_round_ready_deliveries where event_id=e)<>1 then raise exception 'Unexpected recipients'; end if;
 if not exists(select 1 from public.competition_round_ready_deliveries where event_id=e and recipient='wayne@totalleisure.com') then raise exception 'Approved entrant missing'; end if;
 update public.competition_draw_matches set side_a_entry_id=side_a_entry_id where id=m2;
 if (select count(*) from public.competition_round_ready_events where match_id=m2)<>1 then raise exception 'Duplicate event'; end if;
 select count(*) into claimed from public.claim_competition_round_ready_deliveries(c);
 if claimed<>1 then raise exception 'First claim failed'; end if;
 select count(*) into claimed from public.claim_competition_round_ready_deliveries(c);
 if claimed<>0 then raise exception 'Claim retried'; end if;
 update public.competition_round_ready_deliveries set status='uncertain' where event_id=e;
 select count(*) into claimed from public.claim_competition_round_ready_deliveries(c);
 if claimed<>0 then raise exception 'Uncertain delivery retried'; end if;
 if has_table_privilege('authenticated','public.competition_round_ready_deliveries','SELECT') or has_function_privilege('authenticated','public.claim_competition_round_ready_deliveries(uuid)','EXECUTE') then raise exception 'Private outbox exposed'; end if;

 perform public.update_competition_round(r2,'2027-02-10','{}');
 if (select count(*) from public.competition_deadline_events where competition_id=c)<>1 then raise exception 'Published date change not queued'; end if;
 if not exists(select 1 from public.competition_deadline_events where competition_id=c and old_deadline is null and new_deadline='2027-02-10' and snapshot->>'newDeadline'='2027-02-10' and snapshot->'matches'->0->>'id'=m2::text and snapshot->'matches'->0->>'status'='to_be_arranged') then raise exception 'Wrong deadline snapshot'; end if;
 if (select count(*) from public.competition_deadline_deliveries d join public.competition_deadline_events de on de.id=d.event_id where de.competition_id=c)<>1 then raise exception 'Wrong deadline recipients';end if;
 perform public.update_competition_round(r2,'2027-02-10','{}');
 if (select count(*) from public.competition_deadline_events where competition_id=c)<>1 then raise exception 'Unchanged date notified';end if;
 begin perform public.update_competition_round(r2,'2027-02-11','{"rules":"changed"}');raise exception 'Published rules changed';exception when raise_exception then if sqlerrm<>'Only the play-by date may be changed for a published round' then raise;end if;end;
 perform set_config('request.jwt.claim.sub',ids[1]::text,true);
 begin perform public.update_competition_round(r2,'2027-02-11','{}');raise exception 'Player changed deadline';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',ids[6]::text,true);
 update public.competition_draw_matches set status='completed',winner_entry_id=a where id=m2;
 perform public.update_competition_round(r2,'2027-02-11','{}');
 if (select count(*) from public.competition_deadline_events where competition_id=c)<>1 then raise exception 'Completed match notified';end if;
 select count(*) into claimed from public.claim_competition_deadline_deliveries() where event_id in(select id from public.competition_deadline_events where competition_id=c);
 if claimed<>1 then raise exception 'Deadline claim failed';end if;
 select count(*) into claimed from public.claim_competition_deadline_deliveries() where event_id in(select id from public.competition_deadline_events where competition_id=c);
 if claimed<>0 then raise exception 'Deadline delivered twice';end if;
 if has_table_privilege('authenticated','public.competition_deadline_deliveries','SELECT') or has_function_privilege('authenticated','public.claim_competition_deadline_deliveries()','EXECUTE') then raise exception 'Deadline outbox exposed';end if;
 update public.club_memberships set is_active=false where club_id=club and member_profile_id=profiles[2];
 perform set_config('request.jwt.claim.sub',ids[2]::text,true);
 begin perform public.record_competition_result(m,21,12,a,false);raise exception 'Inactive member submitted';exception when insufficient_privilege then null;end;
 update public.club_memberships set role='guest' where club_id=club and member_profile_id=profiles[3];
 perform set_config('request.jwt.claim.sub',ids[3]::text,true);
 begin perform public.record_competition_result(m,21,12,a,false);raise exception 'Guest submitted';exception when insufficient_privilege then null;end;
 if (select count(*) from public.email_queue)<>emails or (select count(*) from public.notification_queue)<>notices then raise exception 'Unexpected messages'; end if;
end $$;
rollback;
select 'PASS: ready event, eligibility, scoped snapshot, idempotency, atomic claims and private access checked;  all four drawn players submit; pending results cannot be overwritten; unrelated/inactive/Guest players denied; only Admin confirms and advances; audit checked; all synthetic data rolled back; no messages' as result;
