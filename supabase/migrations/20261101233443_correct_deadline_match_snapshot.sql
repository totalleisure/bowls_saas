begin;
CREATE OR REPLACE FUNCTION competition_private.queue_deadline_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c public.club_competitions;m public.competition_draw_matches;e uuid;s jsonb;revision uuid:=gen_random_uuid();
begin
 if old.play_by is not distinct from new.play_by then return new;end if;
 select * into strict c from public.club_competitions where id=new.competition_id;
 if c.status<>'published' then return new;end if;
 if auth.uid() is null or not competition_private.can_manage(c.club_id) then raise exception 'Club Admin access required' using errcode='42501';end if;
 for m in select * from public.competition_draw_matches where round_id=new.id and status not in ('completed','bye') and (side_a_entry_id is not null or side_b_entry_id is not null) loop
 select jsonb_build_object('matchId',m.id,'oldDeadline',old.play_by,'newDeadline',new.play_by,'clubName',(select name from public.clubs where id=c.club_id),
 'competitions',jsonb_build_array(to_jsonb(c)),
 'entries',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from public.competition_entries x where x.id in(m.side_a_entry_id,m.side_b_entry_id)),
 'entryMembers',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from public.competition_entry_members x where x.competition_id=c.id and x.entry_id in(m.side_a_entry_id,m.side_b_entry_id)),
 'rounds',jsonb_build_array((select to_jsonb(x) from public.competition_rounds x where x.id=m.round_id)),
 'matches',jsonb_build_array(to_jsonb(m)),
 'profiles',(select coalesce(jsonb_agg(jsonb_build_object('id',mp.id,'first_name',mp.first_name,'last_name',mp.last_name,'email_address',mp.email_address,'phone',mp.phone)),'[]')
 from public.member_profiles mp where exists(select 1 from public.competition_entry_members x where x.competition_id=c.id and x.entry_id in(m.side_a_entry_id,m.side_b_entry_id) and x.member_profile_id=mp.id))) into s;

 insert into public.competition_deadline_events(revision_id,round_id,match_id,competition_id,club_id,actor_user_id,old_deadline,new_deadline,snapshot)
 values(revision,new.id,m.id,c.id,c.club_id,auth.uid(),old.play_by,new.play_by,s) returning id into e;
 insert into public.competition_deadline_deliveries(event_id,member_profile_id,recipient)
 select distinct on(lower(btrim(mp.email_address))) e,mp.id,lower(btrim(mp.email_address))
 from public.competition_entry_members em join public.member_profiles mp on mp.id=em.member_profile_id
 where em.competition_id=c.id and em.entry_id in(m.side_a_entry_id,m.side_b_entry_id)
 and competition_private.is_test_recipient(mp.email_address)
 and exists(select 1 from public.club_memberships cm where cm.club_id=c.club_id and cm.member_profile_id=mp.id and cm.is_active and cm.role::text<>'guest')
 order by lower(btrim(mp.email_address)),mp.id;
 end loop;
 return new;
end $function$
;
commit;
