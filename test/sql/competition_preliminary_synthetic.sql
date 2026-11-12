-- Synthetic bracket only; all test rows and queued messages roll back.
begin;
do $$
declare c public.club_competitions; m public.competition_draw_matches; src public.competition_draw_matches;
 a uuid; members uuid[]; existing uuid[]; reply jsonb; before_other jsonb; after_other jsonb; old_auth text; ids uuid[]; e1 uuid:=gen_random_uuid(); e2 uuid:=gen_random_uuid(); r1 uuid:=gen_random_uuid(); r2 uuid:=gen_random_uuid(); cid uuid:=gen_random_uuid();
begin
 select * into strict c from public.club_competitions where club_id='8ae87bbe-cb16-4330-a5b0-e62366479f07' and name='Ladies Pairs';
 insert into public.club_competitions(id,club_id,name,season,status,settings,created_by,fixture_type_id)
 values(cid,c.club_id,'Synthetic preliminary amendment '||cid,c.season,'published',c.settings,c.created_by,c.fixture_type_id);
 select * into strict c from public.club_competitions where id=cid;
 select array_agg(x.member_profile_id order by x.member_profile_id) into ids from (
 select cm.member_profile_id from public.club_memberships cm join public.member_profiles mp on mp.id=cm.member_profile_id
 where cm.club_id=c.club_id and cm.is_active and cm.role::text<>'guest' and nullif(btrim(concat_ws(' ',mp.first_name,mp.last_name)),'') is not null order by cm.member_profile_id limit 6) x;
 if cardinality(ids)<>6 then raise exception 'Six test member references required';end if;
 insert into public.competition_entries(id,competition_id,name) values(e1,c.id,'Synthetic challengers'),(e2,c.id,'Synthetic waiting pair');
 insert into public.competition_entry_members(competition_id,entry_id,member_profile_id)
 values(c.id,e1,ids[1]),(c.id,e1,ids[2]),(c.id,e2,ids[3]),(c.id,e2,ids[4]);
 insert into public.competition_rounds(id,competition_id,round_number,name,play_by) values(r1,c.id,1,'Preliminary','2026-12-13'),(r2,c.id,2,'Quarter-final','2027-01-24');
 insert into public.competition_draw_matches(competition_id,round_id,match_number,side_a_kind,side_b_kind,side_a_entry_id,status,winner_entry_id)
 values(c.id,r1,7,'entry','bye',e1,'bye',e1) returning * into src;
 insert into public.competition_draw_matches(competition_id,round_id,match_number,side_a_kind,side_b_kind,side_a_entry_id,status,winner_entry_id)
 values(c.id,r1,8,'entry','bye',e2,'bye',e2);
 insert into public.competition_draw_matches(competition_id,round_id,match_number,side_a_kind,side_b_kind,side_a_entry_id,side_b_entry_id,side_a_source_id,side_b_source_id)
 values(c.id,r2,4,'winner','winner',e1,e2,src.id,(select id from public.competition_draw_matches where round_id=r1 and match_number=8)) returning * into m;
 a:=e1;members:=ids[5:6];
 select array_agg(member_profile_id) into existing from public.competition_entry_members where entry_id=a;
 update public.club_competitions set status='published' where id=c.id;
 perform set_config('request.jwt.claim.sub',c.created_by::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',c.created_by,'role','authenticated')::text,true);
 select jsonb_agg(to_jsonb(d) order by d.id) into before_other from public.competition_draw_matches d where competition_id=c.id and id not in(m.id,src.id);
 begin
 perform public.add_competition_preliminary(m.id,a,existing,src.id,(select play_by from public.competition_rounds where id=src.round_id),'Duplicate test');
 raise exception 'TEST FAILED duplicate accepted';
 exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;
 if sqlerrm not like '%already entered%' then raise;end if;end;
 update public.competition_draw_matches set status='result_pending' where id=m.id;
 begin
 perform public.add_competition_preliminary(m.id,a,members,src.id,(select play_by from public.competition_rounds where id=src.round_id),'Pending test');
 raise exception 'TEST FAILED result accepted';
 exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;
 if sqlerrm not like '%booking or result%' then raise;end if;end;
 update public.competition_draw_matches set status='to_be_arranged' where id=m.id;
 perform set_config('request.jwt.claim.sub','',true);perform set_config('request.jwt.claims','{}',true);
 begin
 perform public.add_competition_preliminary(m.id,a,members,src.id,(select play_by from public.competition_rounds where id=src.round_id),'Unauthorized test');
 raise exception 'TEST FAILED unauthorized accepted';
 exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',c.created_by::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',c.created_by,'role','authenticated')::text,true);
 reply:=public.add_competition_preliminary(m.id,a,members,src.id,(select play_by from public.competition_rounds where id=src.round_id),'Omitted pair test');
 if (select side_a_entry_id is not null or side_b_entry_id is distinct from m.side_b_entry_id from public.competition_draw_matches where id=m.id) then raise exception 'QF4 was not preserved';end if;
 if (select challenger_entry_id is distinct from a or side_a_entry_id is distinct from a or status<>'to_be_arranged' from public.competition_draw_matches where id=src.id) then raise exception 'Preliminary challenger wrong';end if;
 select jsonb_agg(to_jsonb(d) order by d.id) into after_other from public.competition_draw_matches d where competition_id=c.id and id not in(m.id,src.id);
 if before_other is distinct from after_other then raise exception 'Other matches changed';end if;
 if not exists(select 1 from public.competition_amendment_events where match_id=src.id and before_match->'source'->>'status'='bye') then raise exception 'Missing audit';end if;
 perform public.record_competition_result(src.id,20,18,a,false);
 perform public.record_competition_result(src.id,20,18,a,true);
 if (select side_a_entry_id is distinct from a from public.competition_draw_matches where id=m.id) then raise exception 'Winner did not return to QF4';end if;
 raise notice 'PASS: permissions, duplicate/result guards, unchanged bracket, audit and winner progression; %',reply;
end $$;
rollback;
