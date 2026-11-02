do $test$
declare a record; c uuid; ids uuid[]; n int; e record; i int; before_count int; expected_name text;
begin
 select cm.club_id,mp.user_id into strict a from public.club_memberships cm join public.member_profiles mp on mp.id=cm.member_profile_id where cm.role='admin' and cm.is_active and mp.user_id is not null and (select count(*) from public.club_memberships x where x.club_id=cm.club_id and x.is_active and x.role::text<>'guest')>=50 limit 1;
 select array_agg(x.member_profile_id order by x.member_profile_id desc) into ids from(select member_profile_id from public.club_memberships where club_id=a.club_id and is_active and role::text<>'guest' order by member_profile_id limit 50)x;
 perform set_config('request.jwt.claim.sub',a.user_id::text,true);
 c:=public.create_club_competition(a.club_id,'TEST 46 players 23 pairs','Test','{"playing_format":"pairs","section":"mens","scoring":"18 ends","players_per_entry":2,"booking_minutes":150,"time_limit_mode":"minutes","time_limit_minutes":150}');
 begin perform public.add_competition_teams(c,ids[1:45]);raise exception 'Odd batch accepted';exception when raise_exception then if sqlerrm='Odd batch accepted' then raise;end if;end;
 assert not exists(select 1 from public.competition_entries where competition_id=c),'Odd batch partly saved';
 n:=public.add_competition_teams(c,ids[1:46]);assert n=23,'46 players not saved as 23 pairs';
 assert (select count(*) from public.competition_entry_members where competition_id=c)=46,'Player links lost';
 for i in 1..23 loop
 select * into strict e from public.competition_entries where competition_id=c and entry_order=i;
 assert (select count(*) from public.competition_entry_members where entry_id=e.id and member_profile_id=any(ids[i*2-1:i*2]))=2,'Wrong partners or pair order';
 select string_agg(btrim(concat_ws(' ',nullif(btrim(mp.first_name),''),nullif(btrim(mp.last_name),''))),' / ' order by p.ord) into expected_name from unnest(ids[i*2-1:i*2]) with ordinality p(id,ord) join public.member_profiles mp on mp.id=p.id;
 assert e.name=left(expected_name,180) or (starts_with(e.name,left(expected_name,180)||' (') and right(e.name,1)=')'),'Pair display order lost';
 assert e.handicap is null and e.payment_status='not_recorded','Entry options incorrectly assumed';
 end loop;
 n:=public.add_competition_teams(c,ids[1:46]);assert n=0,'Retry duplicated pairs';
 begin perform public.add_competition_teams(c,array[ids[47],ids[48],ids[1],ids[49]]);raise exception 'Conflicting partner accepted';exception when raise_exception then if sqlerrm='Conflicting partner accepted' then raise;end if;end;
 assert (select count(*) from public.competition_entries where competition_id=c)=23,'Failed mixed batch partly saved';
 begin perform public.add_competition_teams(c,array[ids[47],ids[47]]);raise exception 'Repeated player accepted';exception when raise_exception then if sqlerrm='Repeated player accepted' then raise;end if;end;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 begin perform public.add_competition_teams(c,ids[47:48]);raise exception 'Outsider mutation accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',a.user_id::text,true);
 perform public.build_competition_draw(c,array(select id from public.competition_entries where competition_id=c order by entry_order));
 begin perform public.add_competition_teams(c,ids[47:48]);raise exception 'Post-draw entry accepted';exception when raise_exception then if sqlerrm='Post-draw entry accepted' then raise;end if;end;
 assert not has_function_privilege('anon','public.add_competition_teams(uuid,uuid[])','execute'),'Anonymous grant';
end $test$;
select 'PASS: 46 players become 23 ordered pairs; odd/conflicting/duplicate batches rejected atomically; retries and permissions protected' result;