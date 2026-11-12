-- Synthetic users, membership and draw; every record is rolled back.
begin;
do $$
declare ids uuid[]:='{}'; profiles uuid[]:='{}'; u uuid; mp uuid; c uuid:=gen_random_uuid();
 a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); r uuid:=gen_random_uuid(); m uuid:=gen_random_uuid();
 club uuid; ft uuid; green uuid; f uuid; label text; settings jsonb; emails bigint; notices bigint; state jsonb; snap jsonb; rink_id uuid; assignment_copy jsonb;
begin
 select cc.club_id,cc.fixture_type_id,cc.settings into strict club,ft,settings
 from public.club_competitions cc where cc.name='Mens Pairs' limit 1;
 settings:=settings||jsonb_build_object('handicap_mode','team_difference');
 select g.id into strict green from public.green_areas g join public.venues v on v.id=g.venue_id where v.club_id=club and v.is_home_venue limit 1;
 for i in 1..5 loop
  u:=gen_random_uuid();
  insert into auth.users(id,email,raw_user_meta_data) values(u,'competition-test-'||u||'@example.invalid',jsonb_build_object('first_name','Synthetic','last_name','Player '||i));
  select id into mp from public.member_profiles where user_id=u;
  if mp is null then insert into public.member_profiles(user_id,display_name,first_name,last_name) values(u,'Synthetic Player '||i,'Synthetic','Player '||i) returning id into mp; end if;
  insert into public.club_memberships(club_id,member_profile_id,role,is_active) values(club,mp,case when i=5 then 'admin'::public.club_role else 'member'::public.club_role end,true);
  ids:=array_append(ids,u); profiles:=array_append(profiles,mp);
 end loop;
 insert into public.club_competitions(id,club_id,name,season,status,settings,created_by,fixture_type_id) values(c,club,'Synthetic handicap verification','test','draft',settings,ids[5],ft);
 insert into public.competition_entries(id,competition_id,name) values(a,c,'Synthetic Players 1 / 2'),(b,c,'Synthetic Players 3 / 4');
 for i in 1..4 loop insert into public.competition_entry_members(competition_id,entry_id,member_profile_id) values(c,case when i<=2 then a else b end,profiles[i]); end loop;
 insert into public.competition_rounds(id,competition_id,round_number,name) values(r,c,1,'Final');
 insert into public.competition_draw_matches(id,competition_id,round_id,match_number,side_a_kind,side_b_kind,side_a_entry_id,side_b_entry_id) values(m,c,r,1,'entry','entry',a,b);

 perform set_config('request.jwt.claim.sub',ids[5]::text,true);
 perform public.set_competition_member_handicaps(a,jsonb_build_object(profiles[1],12,profiles[2],12));
 perform public.set_competition_member_handicaps(b,jsonb_build_object(profiles[3],5,profiles[4],5));
 if (select handicap from public.competition_entries where id=a)<>24 or (select handicap from public.competition_entries where id=b)<>10 then raise exception 'Totals incorrect';end if;
 begin
 perform public.set_competition_member_handicaps(a,jsonb_build_object(profiles[1],12));raise exception 'TEST FAILED missing handicap accepted';
 exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 update public.club_competitions set status='published' where id=c;
 select rink_label into strict label from public.get_green_rink_availability(green,'2030-07-05 10:00Z','2030-07-05 12:30Z') where not is_booked and free_capacity_rinks>=1 limit 1;
 f:=public.arrange_competition_match(m,green,'2030-07-05 10:00Z','2030-07-05 12:30Z',array[label]);
 state:=public.fixture_scorecard_context(f);snap:=state->'rinks'->0->'snapshot';rink_id:=(state->'rinks'->0->>'fixtureRinkId')::uuid;
 if (snap->>'handicapA')::int<>0 or (snap->>'handicapB')::int<>14 then raise exception '24 vs 10 must start 0-14: %',snap;end if;
 begin
 perform public.prepare_fixture_scorecard_setup(f,rink_id,state->'rinks'->0->>'sourceFingerprint',jsonb_build_object('handicapA',24,'handicapB',10));raise exception 'TEST FAILED manual override accepted';
 exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 -- The opponent booking orientation must reverse the starts, not the advantage.
 select jsonb_agg(to_jsonb(x)) into assignment_copy from public.fixture_rink_assignments x where fixture_id=f;
 delete from public.fixture_rink_assignments where fixture_id=f;
 insert into public.fixture_rink_assignments(fixture_id,fixture_rink_id,position,member_profile_id) select f,(x->>'fixture_rink_id')::uuid,case when (x->>'position')::int<=4 then (x->>'position')::int+100 else (x->>'position')::int-100 end,(x->>'member_profile_id')::uuid from jsonb_array_elements(assignment_copy) x;
 state:=public.fixture_scorecard_context(f);snap:=state->'rinks'->0->'snapshot';
 if (snap->>'handicapA')::int<>14 or (snap->>'handicapB')::int<>0 then raise exception 'Home/away orientation incorrect';end if;
 -- Missing is an error, never an invented zero; negative totals also work.
 update public.competition_entry_members set individual_handicap=null where entry_id=a and member_profile_id=profiles[1];
 begin perform public.fixture_scorecard_context(f);raise exception 'TEST FAILED missing handicap treated as zero';
 exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 update public.competition_entry_members set individual_handicap=-2 where entry_id=a;
 state:=public.fixture_scorecard_context(f);snap:=state->'rinks'->0->'snapshot';
 if (snap->>'handicapA')::int<>0 or (snap->>'handicapB')::int<>14 then raise exception 'Negative team total calculation incorrect';end if;
 update public.competition_entry_members set individual_handicap=5 where entry_id=a;
 snap:=public.fixture_scorecard_context(f)->'rinks'->0->'snapshot';
 if (snap->>'handicapA')::int<>0 or (snap->>'handicapB')::int<>0 then raise exception 'Equal totals must start 0-0';end if;
 begin perform public.set_competition_member_handicaps(a,jsonb_build_object(profiles[1],1,profiles[2],1));raise exception 'TEST FAILED published handicap changed';
 exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 perform set_config('request.jwt.claim.sub',ids[1]::text,true);
 begin perform public.set_competition_member_handicaps(a,jsonb_build_object(profiles[1],1,profiles[2],1));raise exception 'TEST FAILED player edited handicaps';
 exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',ids[5]::text,true);
 update public.club_competitions set status='draft' where id=c;
 update public.club_competitions cc set settings=cc.settings||jsonb_build_object('handicap_mode','entry_start') where cc.id=c;
 update public.competition_entries set handicap=case when id=a then 3 else -2 end where competition_id=c;
 snap:=public.fixture_scorecard_context(f)->'rinks'->0->'snapshot';
 if (snap->>'handicapA')::int<>-2 or (snap->>'handicapB')::int<>3 then raise exception 'Legacy starting handicap changed';end if;
end $$;
rollback;
select 'PASS: individual totals, 0-14 starts, reversed sides, equal/negative totals, missing values, fixed setup, Admin-only editing and legacy handicaps; all rows rolled back' as result;
