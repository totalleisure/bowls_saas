do $test$
declare a record; c uuid; entries uuid[]:='{}'; e uuid; i int; m public.competition_draw_matches; dest public.competition_draw_matches; slots uuid[]:='{}'; players uuid[];
begin
 select cm.club_id,mp.user_id into strict a from public.club_memberships cm join public.member_profiles mp on mp.id=cm.member_profile_id where cm.role='admin' and cm.is_active and mp.user_id is not null limit 1;
 perform set_config('request.jwt.claim.sub',a.user_id::text,true);
 c:=public.create_club_competition(a.club_id,'TEST 45 positioned','Test','{"playing_format":"singles","section":"open","scoring":"First to 21","players_per_entry":1,"booking_minutes":150,"time_limit_mode":"none"}');
 for i in 1..45 loop
 insert into public.competition_entries(competition_id,name) values(c,'Entry '||i) returning id into e;
 entries:=array_append(entries,e);
 assert (select entry_order=i from public.competition_entries where id=e),'Insertion order lost';
 end loop;
 perform public.build_competition_draw(c,entries);
 for i in 1..13 loop
 select d.* into strict m from public.competition_draw_matches d join public.competition_rounds r on r.id=d.round_id where d.competition_id=c and r.round_number=1 and d.match_number=i;
 assert m.side_a_entry_id=entries[i*2-1] and m.side_b_entry_id=entries[i*2] and m.status='to_be_arranged','Preliminary pair misplaced';
 end loop;
 for i in 14..32 loop
 select d.* into strict m from public.competition_draw_matches d join public.competition_rounds r on r.id=d.round_id where d.competition_id=c and r.round_number=1 and d.match_number=i;
 assert m.side_a_entry_id=entries[i+13] and m.side_b_kind='bye' and m.winner_entry_id=entries[i+13],'Lower entrant not a bye';
 end loop;
 select d.* into strict dest from public.competition_draw_matches d join public.competition_rounds r on r.id=d.round_id where d.competition_id=c and r.round_number=2 and d.match_number=7;
 assert dest.side_b_entry_id=entries[27] and dest.side_a_entry_id is null,'Preliminary 13 must meet the first bye entrant';
 assert exists(select 1 from public.competition_rounds where competition_id=c and round_number=2 and name='Last 32'),'Last 32 label';
 perform public.publish_club_competition(c);
 select d.* into strict m from public.competition_draw_matches d join public.competition_rounds r on r.id=d.round_id where d.competition_id=c and r.round_number=1 and d.match_number=13;
 perform public.record_competition_result(m.id,21,10,m.side_a_entry_id);
 perform public.record_competition_result(m.id,21,10,m.side_a_entry_id,true);
 assert exists(select 1 from public.competition_draw_matches where id=dest.id and side_a_entry_id=entries[25] and side_b_entry_id=entries[27]),'Wrong progression into supplied position';
 assert not has_function_privilege('anon','public.build_positioned_competition_draw(uuid,uuid[])','execute'),'Anonymous positioned draw';
 c:=public.create_club_competition(a.club_id,'TEST bulk selection sequence','Test','{"playing_format":"singles","section":"open","scoring":"First to 21","players_per_entry":1,"booking_minutes":150,"time_limit_mode":"none"}');
 select array_agg(x.member_profile_id) into players from(select member_profile_id from public.club_memberships where club_id=a.club_id and is_active and role::text<>'guest' order by member_profile_id limit 3)x;
 players:=array[players[3],players[1],players[2]];
 perform public.add_competition_singles(c,players);
 assert (select array_agg(em.member_profile_id order by ce.entry_order) from public.competition_entries ce join public.competition_entry_members em on em.entry_id=ce.id where ce.competition_id=c)=players,'Bulk selection sequence lost on reload';
end $test$;
select 'PASS: 45 selection positions preserved; first 26 play thirteen preliminaries; lower nineteen get byes; preliminary 13 winner meets entrant 27' result;
