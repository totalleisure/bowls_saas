begin;
alter table public.competition_release_controls add column environment text not null default 'staging' check(environment in ('staging','production'));
create function competition_private.email_recipient_allowed(p_email text) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce(lower(btrim(p_email)) ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' and
 ((select environment from public.competition_release_controls where id)='production' or competition_private.is_test_recipient(p_email)),false);
$$;
revoke all on function competition_private.email_recipient_allowed(text) from public,anon,authenticated;
grant usage on schema competition_private to service_role;
grant execute on function competition_private.email_recipient_allowed(text) to service_role;
do $$
declare t text;c text;
begin
 foreach t in array array['competition_publication_deliveries','competition_round_ready_deliveries','competition_deadline_deliveries'] loop
  for c in select conname from pg_constraint where conrelid=('public.'||t)::regclass and contype='c' and pg_get_constraintdef(oid) like '%recipient%' loop
   execute format('alter table public.%I drop constraint %I',t,c);
  end loop;
  execute format('alter table public.%I add constraint %I check(recipient=lower(btrim(recipient)) and competition_private.email_recipient_allowed(recipient))',t,t||'_recipient_policy');
 end loop;
end $$;
CREATE OR REPLACE FUNCTION public.competition_publication_summary(p_competition_id uuid, p_actor_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare club uuid; e public.competition_publication_events; total int; eligible int; missing int; recipients jsonb;
begin
 club:=competition_private.require_publication_admin(p_competition_id,p_actor_user_id);
 select * into e from public.competition_publication_events where competition_id=p_competition_id;
 if found then
  return jsonb_build_object('event_id',e.id,'published',(select status='published' from public.club_competitions where id=p_competition_id),
   'competitionName',(select name from public.club_competitions where id=p_competition_id),
   'total_players',e.total_players,'eligible_count',e.eligible_count,'missing_email_count',e.missing_email_count,'restricted_count',e.restricted_count,
   'pending',(select count(*) from public.competition_publication_deliveries where event_id=e.id and status='pending'),
   'claimed',(select count(*) from public.competition_publication_deliveries where event_id=e.id and status='claimed'),
   'sent',(select count(*) from public.competition_publication_deliveries where event_id=e.id and status='sent'),
   'uncertain',(select count(*) from public.competition_publication_deliveries where event_id=e.id and status='uncertain'),
   'recipients',coalesce((select jsonb_agg(jsonb_build_object('recipient',recipient,'status',status) order by recipient) from public.competition_publication_deliveries where event_id=e.id),'[]'::jsonb));
 end if;
 select count(*),count(*) filter(where nullif(btrim(mp.email_address),'') is null)
 into total,missing from public.competition_entry_members em join public.member_profiles mp on mp.id=em.member_profile_id where em.competition_id=p_competition_id;
 select count(distinct lower(btrim(mp.email_address))),jsonb_agg(distinct lower(btrim(mp.email_address))) into eligible,recipients
 from public.competition_entry_members em join public.member_profiles mp on mp.id=em.member_profile_id
 where em.competition_id=p_competition_id and competition_private.email_recipient_allowed(mp.email_address)
 and exists(select 1 from public.club_memberships cm where cm.club_id=club and cm.member_profile_id=mp.id and cm.is_active and cm.role::text<>'guest');
 return jsonb_build_object('event_id',null,'competitionName',(select name from public.club_competitions where id=p_competition_id),
 'published',(select status='published' from public.club_competitions where id=p_competition_id),
 'total_players',total,'eligible_count',eligible,'missing_email_count',missing,'restricted_count',total-missing-eligible,
 'pending',eligible,'claimed',0,'sent',0,'uncertain',0,'eligible_recipients',coalesce(recipients,'[]'::jsonb),'recipients','[]'::jsonb);
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
 count(distinct lower(btrim(mp.email_address))) filter(where competition_private.email_recipient_allowed(mp.email_address)
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
 and competition_private.email_recipient_allowed(mp.email_address)
 and exists(select 1 from public.club_memberships cm where cm.club_id=c.club_id and cm.member_profile_id=mp.id and cm.is_active and cm.role::text<>'guest')
 order by lower(btrim(mp.email_address)),mp.id;
 return new;
end $function$
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
 where em.competition_id=c.id and competition_private.email_recipient_allowed(mp.email_address)
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
 and competition_private.email_recipient_allowed(mp.email_address)
 and exists(select 1 from public.club_memberships cm where cm.club_id=c.club_id and cm.member_profile_id=mp.id and cm.is_active and cm.role::text<>'guest')
 order by lower(btrim(mp.email_address)),mp.id;
 end loop;
 return new;
end $function$
;
commit;
