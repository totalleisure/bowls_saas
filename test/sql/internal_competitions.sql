-- Run after the foundation migration in the same transaction, or independently.
do $test$
declare a record; members uuid[]; c uuid; other_c uuid; entries uuid[]:='{}'; e uuid; size int; capacity int;
 m public.competition_draw_matches; final_match public.competition_draw_matches;
 r jsonb; i int; n int; ordinary uuid;
begin
 select cm.club_id,mp.user_id into strict a from public.club_memberships cm
 join public.member_profiles mp on mp.id=cm.member_profile_id
 where cm.role='admin' and cm.is_active and mp.user_id is not null
 and (select count(*) from public.club_memberships x where x.club_id=cm.club_id and x.is_active and x.role::text<>'guest')>=22 limit 1;
 select array_agg(x.member_profile_id) into members from (select member_profile_id from public.club_memberships where club_id=a.club_id and is_active and role::text<>'guest' order by member_profile_id limit 22) x;
 r:='{"playing_format":"singles","section":"open","scoring":"First to 21","players_per_entry":1,"booking_minutes":150,"time_limit_mode":"none"}';
 perform set_config('request.jwt.claim.sub','',true);
 begin perform public.create_club_competition(a.club_id,'No permission','Test',r); raise exception 'Anonymous creation allowed'; exception when insufficient_privilege then null; end;
 select mp.user_id into strict ordinary from public.club_memberships cm join public.member_profiles mp on mp.id=cm.member_profile_id where cm.club_id=a.club_id and cm.is_active and cm.role='member' and mp.user_id is not null and not exists(select 1 from public.app_superusers su where su.user_id=mp.user_id) limit 1;
 perform set_config('request.jwt.claim.sub',ordinary::text,true);
 begin perform public.create_club_competition(a.club_id,'No permission','Test',r); raise exception 'Ordinary member creation allowed'; exception when insufficient_privilege then null; end;
 perform set_config('request.jwt.claim.sub',a.user_id::text,true);
 c:=public.create_club_competition(a.club_id,'TEST rollback 22 entrants','Test',r);
 perform public.update_club_competition(c,'TEST rollback edited 22 entrants','Test',r);
 e:=public.add_competition_entry(c,'Remove me',array[members[1]]);
 perform public.remove_competition_entry(e);
 assert not exists(select 1 from public.competition_entry_members where entry_id=e),'Entry members left behind';
 for i in 1..22 loop
 e:=public.add_competition_entry(c,'Entry '||i,array[members[i]]); entries:=array_append(entries,e);
 end loop;
 begin perform public.add_competition_entry(c,'Duplicate player',array[members[1]]); raise exception 'Duplicate entrant allowed'; exception when unique_violation then null; end;
 perform public.build_competition_draw(c,entries);
 begin perform public.remove_competition_entry(entries[1]); raise exception 'Locked entry removed'; exception when raise_exception then if sqlerrm='Locked entry removed' then raise; end if; end;
 perform public.update_club_competition(c,'Changed','Test',r);
 assert (select name='Changed' from public.club_competitions where id=c),'Original rules editor failed after draw creation';
 assert (select count(*) from public.competition_rounds where competition_id=c)=5,'22 entries needs five rounds';
 assert (select count(*) from public.competition_draw_matches where competition_id=c)=31,'32-position bracket needs 31 match positions';
 assert (select count(*) from public.competition_draw_matches where competition_id=c and status='bye')=10,'22 entries needs ten byes';
 assert (select count(*) from public.competition_draw_matches d join public.competition_rounds rd on rd.id=d.round_id where d.competition_id=c and rd.round_number=1 and status='to_be_arranged')=6,'Six opening games';
 assert not exists(select 1 from public.competition_draw_matches where competition_id=c and fixture_id is not null),'Draw created fixture';
 begin perform public.build_competition_draw(c,entries); raise exception 'Redraw allowed'; exception when raise_exception then if sqlerrm='Redraw allowed' then raise; end if; end;
 select * into m from public.competition_draw_matches where competition_id=c and status='to_be_arranged' and side_a_entry_id is not null and side_b_entry_id is not null limit 1;
 perform set_config('request.jwt.claim.sub',ordinary::text,true);
 assert not competition_private.can_read(c),'Draft visible to ordinary member';
 execute 'set local role authenticated';
 select count(*) into n from public.club_competitions where id=c;
 assert n=0,'RLS draft leak';
 execute 'reset role';
 perform set_config('request.jwt.claim.sub',a.user_id::text,true);
 perform public.publish_club_competition(c);
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 assert not competition_private.can_read(c),'Published draw exposed outside the Club';
 execute 'set local role authenticated';
 select count(*) into n from public.competition_draw_matches where competition_id=c;
 assert n=0,'Cross-Club match leak';
 execute 'reset role';
 perform set_config('request.jwt.claim.sub',ordinary::text,true);
 assert competition_private.can_read(c),'Published draw hidden from Club member';
 begin perform public.record_competition_result(m.id,21,12,m.side_a_entry_id); raise exception 'Member result mutation allowed'; exception when insufficient_privilege then null; end;
 execute 'set local role authenticated';
 select count(*) into n from public.club_competitions where id=c;
 assert n=1,'RLS member read blocked';
 begin delete from public.club_competitions where id=c; raise exception 'Direct table mutation allowed'; exception when insufficient_privilege then null; end;
 execute 'reset role';
 perform set_config('request.jwt.claim.sub',a.user_id::text,true);
 perform public.record_competition_result(m.id,21,12,m.side_a_entry_id);
 assert (select winner_entry_id is null from public.competition_draw_matches where id=m.id),'Unconfirmed result advanced';
 perform public.record_competition_result(m.id,21,12,m.side_a_entry_id,true);
 assert exists(select 1 from public.competition_draw_matches where (side_a_source_id=m.id and side_a_entry_id=m.side_a_entry_id) or (side_b_source_id=m.id and side_b_entry_id=m.side_a_entry_id)),'Winner did not advance';
 assert (select count(*) from public.competition_result_events where match_id=m.id)=2,'Missing result audit';
 begin perform public.record_competition_result(m.id,12,21,m.side_b_entry_id,true); raise exception 'Confirmed result correction silently allowed'; exception when raise_exception then if sqlerrm='Confirmed result correction silently allowed' then raise; end if; end;
 -- Full bracket progression: every remaining playable match, in round order.
 for i in 1..5 loop
 for m in select d.* from public.competition_draw_matches d join public.competition_rounds rd on rd.id=d.round_id where d.competition_id=c and rd.round_number=i and d.status='to_be_arranged' loop
 assert m.side_a_entry_id is not null and m.side_b_entry_id is not null,'Unresolved entrant after preceding round';
 perform public.record_competition_result(m.id,21,10,m.side_a_entry_id);
 perform public.record_competition_result(m.id,21,10,m.side_a_entry_id,true);
 end loop; end loop;
 assert (select count(*) from public.competition_draw_matches where competition_id=c and status='completed')=21,'22 entrants requires 21 played matches';
 assert not has_function_privilege('anon','public.build_competition_draw(uuid,uuid[])','execute'),'Anonymous RPC grant';
 foreach size in array array[2,3,4,5,8,9,16,31,32,33,64,256] loop
 other_c:=public.create_club_competition(a.club_id,'TEST rollback bracket '||size,'Test',r);
 entries:='{}';capacity:=2;
 for i in 1..size loop
 insert into public.competition_entries(competition_id,name) values(other_c,'Entry '||i) returning id into e;
 entries:=array_append(entries,e);
 end loop;
 perform public.build_competition_draw(other_c,entries);
 while capacity<size loop capacity:=capacity*2; end loop;
 assert (select count(*) from public.competition_draw_matches where competition_id=other_c)=capacity-1,'Incorrect match positions';
 assert (select count(*) from public.competition_draw_matches where competition_id=other_c and status='bye')=capacity-size,'Incorrect byes';
 end loop;
 perform set_config('request.jwt.claim.sub','',true);
 assert not competition_private.can_read(c),'Anonymous read';
end $test$;
select 'PASS: Club permissions and RLS; 22-entry bracket, ten byes, six opening matches; no fixtures; confirmation, progression and audit' result;
