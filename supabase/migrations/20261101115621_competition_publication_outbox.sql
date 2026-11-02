begin;
-- A frozen first-publication event, distinct from ad-hoc preview/test copies.
create function competition_private.is_test_recipient(p_email text) returns boolean
language sql immutable set search_path='' as $$
 select coalesce(lower(btrim(p_email)) in ('wayne@totalleisure.com','wayne.s.sayers@gmail.com','wayne.streem@gmail.com','wayne.sayers@telius.co.uk','wayne.sayers@icloud.com','wayne.sayers@me.com','suesayers9@gmail.com'),false);
$$;
revoke all on function competition_private.is_test_recipient(text) from public,anon,authenticated;
create table public.competition_publication_events(
 id uuid primary key default gen_random_uuid(),
 competition_id uuid not null unique references public.club_competitions(id),
 club_id uuid not null references public.clubs(id),
 actor_user_id uuid not null references auth.users(id),
 snapshot jsonb not null,
 total_players integer not null,
 eligible_count integer not null,
 missing_email_count integer not null,
 restricted_count integer not null,
 created_at timestamptz not null default now()
);
create table public.competition_publication_deliveries(
 id uuid primary key default gen_random_uuid(),
 event_id uuid not null references public.competition_publication_events(id),
 member_profile_id uuid not null references public.member_profiles(id),
 recipient text not null check(recipient in ('wayne@totalleisure.com','wayne.s.sayers@gmail.com','wayne.streem@gmail.com','wayne.sayers@telius.co.uk','wayne.sayers@icloud.com','wayne.sayers@me.com','suesayers9@gmail.com')),
 status text not null default 'pending' check(status in ('pending','claimed','sent','uncertain')),
 subject text, html text,
 claimed_by uuid references auth.users(id),
 claimed_at timestamptz, sent_at timestamptz,
 unique(event_id,recipient)
);
alter table public.competition_publication_events enable row level security;
alter table public.competition_publication_deliveries enable row level security;
revoke all on public.competition_publication_events,public.competition_publication_deliveries from public,anon,authenticated;
grant all on public.competition_publication_events,public.competition_publication_deliveries to service_role;

-- Privileged server boundary: actor is supplied only by the authenticated Edge handler.
create function competition_private.require_publication_admin(p_competition_id uuid,p_actor uuid) returns uuid
language plpgsql stable security definer set search_path='' as $$
declare club uuid;
begin
 select club_id into club from public.club_competitions where id=p_competition_id;
 if club is null or p_actor is null or not (
 exists(select 1 from public.app_superusers where user_id=p_actor) or exists(
 select 1 from public.club_memberships cm join public.member_profiles mp on mp.id=cm.member_profile_id
 where cm.club_id=club and cm.is_active and cm.role::text='admin' and mp.user_id=p_actor)
 ) then raise exception 'Club Admin access required' using errcode='42501'; end if;
 return club;
end $$;
revoke all on function competition_private.require_publication_admin(uuid,uuid) from public,anon,authenticated;

create function public.competition_publication_summary(p_competition_id uuid,p_actor_user_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
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
 where em.competition_id=p_competition_id and competition_private.is_test_recipient(mp.email_address)
 and exists(select 1 from public.club_memberships cm where cm.club_id=club and cm.member_profile_id=mp.id and cm.is_active and cm.role::text<>'guest');
 return jsonb_build_object('event_id',null,'competitionName',(select name from public.club_competitions where id=p_competition_id),
 'published',(select status='published' from public.club_competitions where id=p_competition_id),
 'total_players',total,'eligible_count',eligible,'missing_email_count',missing,'restricted_count',total-missing-eligible,
 'pending',eligible,'claimed',0,'sent',0,'uncertain',0,'eligible_recipients',coalesce(recipients,'[]'::jsonb),'recipients','[]'::jsonb);
end $$;

create function competition_private.prepare_publication(p_competition_id uuid,p_actor uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare c public.club_competitions; event uuid; s jsonb; summary jsonb;
begin
 perform competition_private.require_publication_admin(p_competition_id,p_actor);
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
end $$;
revoke all on function competition_private.prepare_publication(uuid,uuid) from public,anon,authenticated;

create function public.prepare_competition_publication(p_competition_id uuid,p_actor_user_id uuid) returns uuid
language sql security definer set search_path='' as $$ select competition_private.prepare_publication(p_competition_id,p_actor_user_id); $$;
create function public.claim_competition_publication_deliveries(p_event_id uuid,p_actor_user_id uuid)
returns setof public.competition_publication_deliveries language plpgsql security definer set search_path='' as $$
begin
 perform competition_private.require_publication_admin((select competition_id from public.competition_publication_events where id=p_event_id),p_actor_user_id);
 return query update public.competition_publication_deliveries set status='claimed',claimed_by=p_actor_user_id,claimed_at=now()
 where event_id=p_event_id and status='pending' returning *;
end $$;
-- Existing clients publishing a draw still create the same durable event. Transport is Edge-only.
create or replace function public.publish_club_competition(p_competition_id uuid) returns void
language plpgsql security definer set search_path='' as $$
begin perform competition_private.prepare_publication(p_competition_id,auth.uid()); end $$;
revoke all on function public.competition_publication_summary(uuid,uuid),public.prepare_competition_publication(uuid,uuid),public.claim_competition_publication_deliveries(uuid,uuid) from public,anon,authenticated;
grant execute on function public.competition_publication_summary(uuid,uuid),public.prepare_competition_publication(uuid,uuid),public.claim_competition_publication_deliveries(uuid,uuid) to service_role;
commit;
