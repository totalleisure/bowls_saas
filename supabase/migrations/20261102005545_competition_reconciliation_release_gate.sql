begin;
create table public.competition_release_controls(id boolean primary key default true check(id),publication_enabled boolean not null default false);
insert into public.competition_release_controls(id,publication_enabled) values(true,false);
alter table public.competition_release_controls enable row level security;
revoke all on public.competition_release_controls from public,anon,authenticated;
grant all on public.competition_release_controls to service_role;
create function competition_private.publication_enabled() returns boolean language sql stable security definer set search_path='' as $$select coalesce((select publication_enabled from public.competition_release_controls where id),false);$$;
revoke all on function competition_private.publication_enabled() from public,anon,authenticated;
create function public.competition_release_status(p_club_id uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not coalesce(competition_private.can_manage(p_club_id),false) then raise exception 'Club Admin access required' using errcode='42501';end if;
 return competition_private.publication_enabled();
end $$;
revoke all on function public.competition_release_status(uuid) from public,anon;
grant execute on function public.competition_release_status(uuid) to authenticated;
CREATE OR REPLACE FUNCTION public.claim_competition_deadline_deliveries()
 RETURNS SETOF competition_deadline_deliveries
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
 with batch as(select id from public.competition_deadline_deliveries where competition_private.publication_enabled() and status='pending' order by id for update skip locked limit 50)
 update public.competition_deadline_deliveries d set status='claimed',claimed_at=now() from batch where d.id=batch.id returning d.*;
$function$
;
CREATE OR REPLACE FUNCTION public.claim_competition_round_ready_deliveries(p_competition_id uuid DEFAULT NULL::uuid)
 RETURNS SETOF competition_round_ready_deliveries
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
 with batch as (select d.id from public.competition_round_ready_deliveries d
 join public.competition_round_ready_events e on e.id=d.event_id
 where competition_private.publication_enabled() and d.status='pending' and (p_competition_id is null or e.competition_id=p_competition_id)
 order by e.created_at,d.id for update of d skip locked limit 50)
 update public.competition_round_ready_deliveries d set status='claimed',claimed_at=now()
 from batch where d.id=batch.id returning d.*;
$function$
;
CREATE OR REPLACE FUNCTION competition_private.prepare_publication(p_competition_id uuid, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c public.club_competitions; event uuid; s jsonb; summary jsonb;
begin
 perform competition_private.require_publication_admin(p_competition_id,p_actor);
 if not competition_private.publication_enabled() then raise exception 'Competition publication and emails are disabled while production records are checked';end if;
 select * into strict c from public.club_competitions where id=p_competition_id for update;
 select id into event from public.competition_publication_events where competition_id=c.id;
 if event is not null then return event; end if;
 if not exists(select 1 from public.competition_rounds where competition_id=c.id)
 or not exists(select 1 from public.competition_draw_matches where competition_id=c.id)
 then raise exception 'Create and review the draw first'; end if;
 if c.fixture_type_id is null then raise exception 'Select a Fixture Type first'; end if;
 summary:=public.competition_publication_summary(c.id,p_actor);
 select jsonb_build_object('clubName',(select name from public.clubs where id=c.club_id),
   'competitions',jsonb_build_array(to_jsonb(c)||jsonb_build_object('status','published')),
   'entries',coalesce((select jsonb_agg(to_jsonb(e) order by e.entry_order) from public.competition_entries e where e.competition_id=c.id),'[]'::jsonb),
   'entryMembers',coalesce((select jsonb_agg(to_jsonb(em)) from public.competition_entry_members em where em.competition_id=c.id),'[]'::jsonb),
   'rounds',coalesce((select jsonb_agg(to_jsonb(r) order by r.round_number) from public.competition_rounds r where r.competition_id=c.id),'[]'::jsonb),
   'matches',coalesce((select jsonb_agg(to_jsonb(m)) from public.competition_draw_matches m where m.competition_id=c.id),'[]'::jsonb),
   'profiles',coalesce((select jsonb_agg(jsonb_build_object('id',mp.id,'first_name',mp.first_name,'last_name',mp.last_name,'email_address',mp.email_address,'phone',mp.phone)) from public.member_profiles mp where exists(select 1 from public.competition_entry_members em where em.competition_id=c.id and em.member_profile_id=mp.id)),'[]'::jsonb)) into s;
 insert into public.competition_publication_events(competition_id,club_id,actor_user_id,snapshot,total_players,eligible_count,missing_email_count,restricted_count)
 values(c.id,c.club_id,p_actor,s,(summary->>'total_players')::int,(summary->>'eligible_count')::int,(summary->>'missing_email_count')::int,(summary->>'restricted_count')::int) returning id into event;
 insert into public.competition_publication_deliveries(event_id,member_profile_id,recipient)
 select distinct on (lower(btrim(mp.email_address))) event,mp.id,lower(btrim(mp.email_address))
 from public.competition_entry_members em join public.member_profiles mp on mp.id=em.member_profile_id
 where em.competition_id=c.id and competition_private.is_test_recipient(mp.email_address)
 and exists(select 1 from public.club_memberships cm where cm.club_id=c.club_id and cm.member_profile_id=mp.id and cm.is_active and cm.role::text<>'guest')
 order by lower(btrim(mp.email_address)),mp.id;
 update public.club_competitions set status='published' where id=c.id;
 return event;
end $function$
;
CREATE OR REPLACE FUNCTION competition_private.queue_deadline_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c public.club_competitions;m public.competition_draw_matches;e uuid;s jsonb;revision uuid:=gen_random_uuid();
begin
 if not competition_private.publication_enabled() then return new;end if;
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
CREATE OR REPLACE FUNCTION competition_private.queue_round_ready()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c public.club_competitions; e uuid; s jsonb; total int; missing int; eligible int;
begin
 if not competition_private.publication_enabled() then return new;end if;
 if new.side_a_entry_id is null or new.side_b_entry_id is null
 or (old.side_a_entry_id is not null and old.side_b_entry_id is not null)
 or new.status<>'to_be_arranged' or new.fixture_id is not null
 or (new.side_a_source_id is null and new.side_b_source_id is null) then return new; end if;
 select * into strict c from public.club_competitions where id=new.competition_id;
 if c.status<>'published' or auth.uid() is null or not competition_private.can_manage(c.club_id) then return new; end if;
 if exists(select 1 from public.competition_draw_matches src
 where src.id in(new.side_a_source_id,new.side_b_source_id) and
 (src.status not in ('completed','bye') or src.winner_entry_id is distinct from
 case when src.id=new.side_a_source_id then new.side_a_entry_id else new.side_b_entry_id end)) then return new; end if;
 select count(*),count(*) filter(where nullif(btrim(mp.email_address),'') is null),
 count(distinct lower(btrim(mp.email_address))) filter(where competition_private.is_test_recipient(mp.email_address)
 and exists(select 1 from public.club_memberships cm where cm.club_id=c.club_id and cm.member_profile_id=mp.id and cm.is_active and cm.role::text<>'guest'))
 into total,missing,eligible from public.competition_entry_members em join public.member_profiles mp on mp.id=em.member_profile_id
 where em.competition_id=c.id and em.entry_id in(new.side_a_entry_id,new.side_b_entry_id);
 select jsonb_build_object('matchId',new.id,'clubName',(select name from public.clubs where id=c.club_id),
 'competitions',jsonb_build_array(to_jsonb(c)),
 'entries',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from public.competition_entries x where x.id in(new.side_a_entry_id,new.side_b_entry_id)),
 'entryMembers',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from public.competition_entry_members x where x.competition_id=c.id and x.entry_id in(new.side_a_entry_id,new.side_b_entry_id)),
 'rounds',jsonb_build_array((select to_jsonb(x) from public.competition_rounds x where x.id=new.round_id)),
 'matches',jsonb_build_array(to_jsonb(new)),
 'profiles',(select coalesce(jsonb_agg(jsonb_build_object('id',mp.id,'first_name',mp.first_name,'last_name',mp.last_name,'email_address',mp.email_address,'phone',mp.phone)),'[]')
 from public.member_profiles mp where exists(select 1 from public.competition_entry_members x where x.competition_id=c.id and x.entry_id in(new.side_a_entry_id,new.side_b_entry_id) and x.member_profile_id=mp.id))) into s;
 insert into public.competition_round_ready_events(match_id,competition_id,club_id,actor_user_id,snapshot,total_players,eligible_count,missing_email_count,restricted_count)
 values(new.id,c.id,c.club_id,auth.uid(),s,total,eligible,missing,total-missing-eligible)
 on conflict(match_id) do nothing returning id into e;
 if e is null then return new; end if;
 insert into public.competition_round_ready_deliveries(event_id,member_profile_id,recipient)
 select distinct on(lower(btrim(mp.email_address))) e,mp.id,lower(btrim(mp.email_address))
 from public.competition_entry_members em join public.member_profiles mp on mp.id=em.member_profile_id
 where em.competition_id=c.id and em.entry_id in(new.side_a_entry_id,new.side_b_entry_id)
 and competition_private.is_test_recipient(mp.email_address)
 and exists(select 1 from public.club_memberships cm where cm.club_id=c.club_id and cm.member_profile_id=mp.id and cm.is_active and cm.role::text<>'guest')
 order by lower(btrim(mp.email_address)),mp.id;
 return new;
end $function$
;
commit;
