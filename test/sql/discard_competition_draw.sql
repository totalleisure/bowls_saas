do $test$
declare a record; c uuid; ids uuid[]; entries uuid[]; e uuid;
begin
 select cm.club_id,mp.user_id into strict a from public.club_memberships cm join public.member_profiles mp on mp.id=cm.member_profile_id where cm.role='admin' and cm.is_active and mp.user_id is not null limit 1;
 select array_agg(x.member_profile_id) into ids from (select member_profile_id from public.club_memberships where club_id=a.club_id and is_active and role::text<>'guest' order by member_profile_id limit 3) x;
 perform set_config('request.jwt.claim.sub',a.user_id::text,true);
 c:=public.create_club_competition(a.club_id,'TEST discard draw','Test','{"playing_format":"singles","section":"open","scoring":"First to 21","players_per_entry":1,"booking_minutes":150,"time_limit_mode":"none"}');
 perform public.add_competition_singles(c,ids[1:2]);
 select array_agg(id order by id) into entries from public.competition_entries where competition_id=c;
 perform public.update_competition_entry_options(entries[1],true,-2,true);
 perform public.build_competition_draw(c,entries);
 perform set_config('request.jwt.claim.sub','',true);
 begin perform public.discard_unused_competition_draw(c);raise exception 'Anonymous discard allowed';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',a.user_id::text,true);
 perform public.discard_unused_competition_draw(c);
 assert not exists(select 1 from public.competition_rounds where competition_id=c),'Rounds remain';
 assert (select count(*) from public.competition_entries where competition_id=c)=2,'Entries lost';
 assert exists(select 1 from public.competition_entries where id=entries[1] and payment_status='paid' and handicap=-2),'Entry settings lost';
 perform public.add_competition_singles(c,ids[3:3]);
 select array_agg(id order by id) into entries from public.competition_entries where competition_id=c;
 perform public.build_competition_draw(c,entries);
 update public.competition_draw_matches set score_a=0 where competition_id=c and status='to_be_arranged';
 begin perform public.discard_unused_competition_draw(c);raise exception 'Scored draw discarded';exception when raise_exception then if sqlerrm='Scored draw discarded' then raise;end if;end;
 update public.competition_draw_matches set score_a=null where competition_id=c;
 perform public.publish_club_competition(c);
 begin perform public.discard_unused_competition_draw(c);raise exception 'Published draw discarded';exception when raise_exception then if sqlerrm='Published draw discarded' then raise;end if;end;
 assert not has_function_privilege('anon','public.discard_unused_competition_draw(uuid)','execute'),'Anonymous grant';
end $test$;
select 'PASS: unused draw reset preserves players and entry settings, unlocks entry, protects scored/published draws' result;
