begin;
create table public.competition_round_ready_events (
 id uuid primary key default gen_random_uuid(),
 match_id uuid not null unique references public.competition_draw_matches(id),
 competition_id uuid not null references public.club_competitions(id),
 club_id uuid not null references public.clubs(id),
 actor_user_id uuid not null references auth.users(id),
 snapshot jsonb not null,
 total_players int not null, eligible_count int not null,
 missing_email_count int not null, restricted_count int not null,
 created_at timestamptz not null default now()
);
create table public.competition_round_ready_deliveries (
 id uuid primary key default gen_random_uuid(),
 event_id uuid not null references public.competition_round_ready_events(id),
 member_profile_id uuid not null references public.member_profiles(id),
 recipient text not null check(recipient in ('wayne@totalleisure.com','wayne.s.sayers@gmail.com','wayne.streem@gmail.com','wayne.sayers@telius.co.uk','wayne.sayers@icloud.com','wayne.sayers@me.com','suesayers9@gmail.com')),
 status text not null default 'pending' check(status in ('pending','claimed','sent','uncertain')),
 subject text,html text,claimed_at timestamptz,sent_at timestamptz,
 unique(event_id,recipient)
);
alter table public.competition_round_ready_events enable row level security;
alter table public.competition_round_ready_deliveries enable row level security;
revoke all on public.competition_round_ready_events,public.competition_round_ready_deliveries from public,anon,authenticated;
grant all on public.competition_round_ready_events,public.competition_round_ready_deliveries to service_role;
create index competition_round_ready_pending on public.competition_round_ready_deliveries(event_id) where status='pending';
-- Exactly one immutable event as confirmation fills the final empty side. No historical backfill.
create function competition_private.queue_round_ready() returns trigger
language plpgsql security definer set search_path='' as $$
declare c public.club_competitions; e uuid; s jsonb; total int; missing int; eligible int;
begin
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
end $$;
revoke all on function competition_private.queue_round_ready() from public,anon,authenticated;
create trigger competition_round_ready_after_advancement after update of side_a_entry_id,side_b_entry_id
 on public.competition_draw_matches for each row execute function competition_private.queue_round_ready();
create function public.claim_competition_round_ready_deliveries(p_competition_id uuid default null)
returns setof public.competition_round_ready_deliveries language sql security definer set search_path='' as $$
 with batch as (select d.id from public.competition_round_ready_deliveries d
 join public.competition_round_ready_events e on e.id=d.event_id
 where d.status='pending' and (p_competition_id is null or e.competition_id=p_competition_id)
 order by e.created_at,d.id for update of d skip locked limit 50)
 update public.competition_round_ready_deliveries d set status='claimed',claimed_at=now()
 from batch where d.id=batch.id returning d.*;
$$;
revoke all on function public.claim_competition_round_ready_deliveries(uuid) from public,anon,authenticated;
grant execute on function public.claim_competition_round_ready_deliveries(uuid) to service_role;
commit;
