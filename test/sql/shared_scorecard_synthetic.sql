-- Run inside a caller-owned transaction; every real fixture change is rolled back.
do $$
declare f uuid; r uuid; ua uuid; ub uuid; um uuid; admin_user uuid; mid uuid; winner uuid;
 club uuid; ft uuid; settings jsonb; venue uuid; test_green uuid:=gen_random_uuid(); comp uuid:=gen_random_uuid();
 round_one uuid:=gen_random_uuid(); round_two uuid:=gen_random_uuid(); side_b uuid:=gen_random_uuid(); final_opponent uuid:=gen_random_uuid();
 users uuid[]:='{}'; profiles uuid[]:='{}'; u uuid; mp uuid;
 token uuid:=gen_random_uuid(); doc jsonb; state jsonb; fingerprint text; version bigint; old_fixture jsonb;
begin
 -- All users, match records and the green below are synthetic and rolled back.
 select cc.club_id,cc.fixture_type_id,cc.settings into strict club,ft,settings
 from public.club_competitions cc where cc.name='Mens Pairs' limit 1;
 select id into strict venue from public.venues where club_id=club and is_home_venue limit 1;
 insert into public.green_areas(id,club_id,venue_id,name,discipline,rink_count,scheme_type,scheme_prefix,orientation_mode,allowed_orientations)
 values(test_green,club,venue,'Synthetic shared-card verification','indoor',1,'numeric','R','not_applicable','{}');
 for i in 1..6 loop
  u:=gen_random_uuid();
  insert into auth.users(id,email,raw_user_meta_data) values(u,'shared-test-'||u||'@example.invalid',jsonb_build_object('first_name','Synthetic','last_name','Shared Player '||i));
  select id into mp from public.member_profiles where user_id=u;
  if mp is null then insert into public.member_profiles(user_id,display_name,first_name,last_name)
    values(u,'Synthetic Shared Player '||i,'Synthetic','Shared Player '||i) returning id into mp; end if;
  insert into public.club_memberships(club_id,member_profile_id,role,is_active) values(club,mp,case when i=6 then 'admin'::public.club_role else 'member'::public.club_role end,true);
  users:=array_append(users,u); profiles:=array_append(profiles,mp);
 end loop;
 ua:=users[1]; ub:=users[3]; um:=users[5]; admin_user:=users[6];
 perform set_config('request.jwt.claim.sub',ua::text,true);
 winner:=gen_random_uuid(); mid:=gen_random_uuid(); f:=gen_random_uuid(); r:=gen_random_uuid();
 insert into public.club_competitions(id,club_id,name,season,status,settings,created_by,fixture_type_id)
 values(comp,club,'Synthetic shared-card verification','test','published',settings,admin_user,ft);
 insert into public.competition_entries(id,competition_id,name) values(winner,comp,'Synthetic side A'),(side_b,comp,'Synthetic side B'),(final_opponent,comp,'Synthetic finalist');
 for i in 1..4 loop insert into public.competition_entry_members(competition_id,entry_id,member_profile_id)
 values(comp,case when i<=2 then winner else side_b end,profiles[i]); end loop;
 insert into public.competition_rounds(id,competition_id,round_number,name) values(round_one,comp,1,'Semi-final'),(round_two,comp,2,'Final');
 insert into public.fixtures(id,club_id,start_at,end_at,is_home,section,rinks_required,players_per_rink,competition_type_id,
   venue_id,green_area_id,team_name,requires_rsvp,captain_member_profile_id)
 values(f,club,((now() at time zone 'Europe/London')::date+time '10:00') at time zone 'Europe/London',
   ((now() at time zone 'Europe/London')::date+time '12:30') at time zone 'Europe/London',true,'mixed',1,2,ft,venue,test_green,'Synthetic shared-card verification',false,profiles[1]);
 insert into public.fixture_rinks(id,fixture_id,fixture_rink_no,format,players_per_rink,home_rink_label,marker_required) values(r,f,1,'pairs',2,'R1',true);
 for i in 1..5 loop insert into public.fixture_rink_assignments(fixture_id,fixture_rink_id,member_profile_id,position)
 values(f,r,profiles[i],case i when 1 then 1 when 2 then 2 when 3 then 101 when 4 then 102 else 201 end);end loop;
 insert into public.competition_draw_matches(id,competition_id,round_id,match_number,side_a_kind,side_b_kind,side_a_entry_id,side_b_entry_id,fixture_id)
 values(mid,comp,round_one,1,'entry','entry',winner,side_b,f);
 insert into public.competition_draw_matches(id,competition_id,round_id,match_number,side_a_kind,side_a_source_id,side_b_kind,side_b_entry_id)
 values(gen_random_uuid(),comp,round_two,1,'winner',mid,'entry',final_opponent);
 perform set_config('request.jwt.claim.sub',um::text,true);
 select to_jsonb(fx) into old_fixture from public.fixtures fx where id=f;
 state:=public.shared_scorecard_state(f,r); fingerprint:=state->>'fingerprint';
 if (state->'actor'->>'canKeep')::boolean is not true or state->'actor'->>'side' is not null then raise exception 'Marker role incorrect'; end if;
 doc:=jsonb_build_object('schema',1,'id',gen_random_uuid(),'title','Rollback shared test','date',(now() at time zone 'Europe/London')::date,'venue','','rink','R1','format','Pairs','sideA','A','sideB','B','playersA','A players','playersB','B players','marker','Test marker','notes','','woods',4,'handicapA',0,'handicapB',0,'scoring','shots','target',null,'maxEnds',3,'durationMinutes',150,'lastJackMinutes',140,'startedAt',null,'finishedAt',null,'revision',0,'saveVersion',0,'ends','[]'::jsonb,'history','[]'::jsonb,'signatureA',null,'signatureB',null,'fixtureLink',state->'snapshot');
 state:=public.claim_shared_scorecard(f,r,fingerprint,token,doc);
 if state->'shared' is null then raise exception 'Marker claim failed'; end if;
 if state->'shared'->'document'->'fixtureLink' ? 'sharedWriterToken' then raise exception 'Writer token leaked'; end if;
 perform set_config('request.jwt.claim.sub',ub::text,true);
 begin perform public.claim_shared_scorecard(f,r,fingerprint,gen_random_uuid(),doc); raise exception 'Second scorer accepted';
 exception when raise_exception then if sqlerrm not like 'This match already has%' then raise; end if; end;
 begin perform public.sync_shared_scorecard(f,r,token,1,doc); raise exception 'Opponent uploaded'; exception when insufficient_privilege then null; end;
 perform set_config('request.jwt.claim.sub',um::text,true);
 begin perform public.sync_shared_scorecard(f,r,gen_random_uuid(),1,doc); raise exception 'Wrong-device upload accepted'; exception when insufficient_privilege then null; end;
 doc:=doc||jsonb_build_object('startedAt',now()-interval '5 minutes','revision',3,'ends',jsonb_build_array(jsonb_build_object('jackAt',now()-interval '4 minutes','a',3,'b',0,'automatic',false)),'finishedAt',now());
 state:=public.sync_shared_scorecard(f,r,token,2,doc); version:=(state->'shared'->>'version')::bigint;
 if state->'shared'->>'totalA'<>'3' or state->'shared'->>'phase'<>'review' then raise exception 'Finished upload totals incorrect'; end if;
 begin perform public.agree_shared_scorecard(f,r,version); raise exception 'Marker agreed for a side'; exception when insufficient_privilege then null; end;
 perform set_config('request.jwt.claim.sub',ua::text,true);
 begin perform public.record_competition_result(mid,3,0,winner,false); raise exception 'Bypassed missing agreements';
 exception when raise_exception then if sqlerrm not like 'Both sides must agree%' then raise; end if; end;
 state:=public.agree_shared_scorecard(f,r,version);
 if (state->'shared'->>'agreedA')::boolean is not true then raise exception 'A agreement missing'; end if;
 perform set_config('request.jwt.claim.sub',ub::text,true);
 begin perform public.agree_shared_scorecard(f,r,version-1); raise exception 'Stale version accepted';
 exception when raise_exception then if sqlerrm not like 'Review the latest%' then raise; end if; end;
 state:=public.request_shared_scorecard_correction(f,r,version,'Check end 1');
 if (state->'shared'->>'agreedA')::boolean or state->'shared'->>'phase'<>'correction_requested' then raise exception 'Correction did not clear agreement'; end if;
 perform set_config('request.jwt.claim.sub',um::text,true);
 perform public.reopen_shared_scorecard(f,r,token);
 doc:=doc||jsonb_build_object('revision',5,'ends',jsonb_build_array(jsonb_build_object('jackAt',now()-interval '4 minutes','a',4,'b',0,'automatic',false)));
 state:=public.sync_shared_scorecard(f,r,token,3,doc); version:=(state->'shared'->>'version')::bigint;
 -- A delayed older upload must not roll back scores or review version.
 state:=public.sync_shared_scorecard(f,r,token,2,doc||'{"revision":1}');
 if state->'shared'->>'totalA'<>'4' or (state->'shared'->>'version')::bigint<>version then raise exception 'Stale upload rolled back card'; end if;
 perform set_config('request.jwt.claim.sub',ua::text,true);
 perform public.agree_shared_scorecard(f,r,version);
 perform set_config('request.jwt.claim.sub',ub::text,true);
 state:=public.agree_shared_scorecard(f,r,version);
 if not(state->'shared'->>'agreedA')::boolean or not(state->'shared'->>'agreedB')::boolean then raise exception 'Both sides not agreed'; end if;
 begin perform public.record_competition_result(mid,9,0,winner,false); raise exception 'Mismatched result accepted';
 exception when raise_exception then if sqlerrm not like 'Submitted scores must match%' then raise; end if; end;
 state:=public.submit_shared_scorecard(f,r,version);
 if state->'shared'->>'phase'<>'submitted' then raise exception 'Submission failed'; end if;
 if not exists(select 1 from public.competition_draw_matches where id=mid and status='result_pending' and score_a=4 and score_b=0 and winner_entry_id is null) then raise exception 'Submission advanced prematurely'; end if;
 begin perform public.record_competition_result(mid,4,0,winner,true); raise exception 'Player confirmed result'; exception when insufficient_privilege then null; end;
 perform set_config('request.jwt.claim.sub',um::text,true);
 begin perform public.sync_shared_scorecard(f,r,token,4,doc); raise exception 'Submitted card overwritten';
 exception when raise_exception then if sqlerrm<>'Submitted scorecard is locked' then raise; end if; end;
 perform set_config('request.jwt.claim.sub',admin_user::text,true);
 state:=public.return_shared_scorecard_for_correction(f,r,version,'Check before confirmation');
 if state->'shared'->>'phase'<>'correction_requested' or (state->'shared'->>'agreedA')::boolean then raise exception 'Admin return did not clear review'; end if;
 if not exists(select 1 from public.competition_draw_matches where id=mid and status='to_be_arranged' and score_a is null and score_b is null) then raise exception 'Admin return did not clear pending result'; end if;
 perform set_config('request.jwt.claim.sub',um::text,true);
 perform public.reopen_shared_scorecard(f,r,token);
 state:=public.sync_shared_scorecard(f,r,token,4,doc||'{"revision":6}'); version:=(state->'shared'->>'version')::bigint;
 perform set_config('request.jwt.claim.sub',ua::text,true);
 perform public.agree_shared_scorecard(f,r,version);
 perform set_config('request.jwt.claim.sub',ub::text,true);
 perform public.agree_shared_scorecard(f,r,version);
 perform public.submit_shared_scorecard(f,r,version);
 perform set_config('request.jwt.claim.sub',admin_user::text,true);
 perform public.record_competition_result(mid,4,0,winner,true);
 if not exists(select 1 from public.competition_draw_matches where id=mid and status='completed' and winner_entry_id=winner) then raise exception 'Admin confirmation failed'; end if;
 if exists(select 1 from public.competition_draw_matches where side_a_source_id=mid and side_a_entry_id is distinct from winner) or exists(select 1 from public.competition_draw_matches where side_b_source_id=mid and side_b_entry_id is distinct from winner) then raise exception 'Winner did not progress'; end if;
 if old_fixture is distinct from (select to_jsonb(fx) from public.fixtures fx where id=f) then raise exception 'Fixture booking changed'; end if;
 if has_function_privilege('anon','public.shared_scorecard_state(uuid,uuid)','execute') or has_table_privilege('authenticated','scorecard_private.shared_cards','select') then raise exception 'Public access leaked'; end if;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 begin perform public.shared_scorecard_state(f,r); raise exception 'Nonmember read shared card'; exception when insufficient_privilege then null; end;
end $$;
select 'PASS: marker claim, one writer/device, scores, agreement, stale revisions, corrections, submission guard, Admin confirmation/progression, privileges (caller rolls back)' result;
