begin;
create table public.competition_deadline_events(
 id uuid primary key default gen_random_uuid(),
 revision_id uuid not null, round_id uuid not null references public.competition_rounds(id),
 match_id uuid not null references public.competition_draw_matches(id),
 competition_id uuid not null references public.club_competitions(id),
 club_id uuid not null references public.clubs(id), actor_user_id uuid not null references auth.users(id),
 old_deadline date,new_deadline date,snapshot jsonb not null,
 created_at timestamptz not null default now(),unique(revision_id,match_id)
);
create table public.competition_deadline_deliveries (like public.competition_round_ready_deliveries including defaults including constraints including indexes);
alter table public.competition_deadline_deliveries add foreign key(event_id) references public.competition_deadline_events(id),add foreign key(member_profile_id) references public.member_profiles(id);
alter table public.competition_deadline_events enable row level security;
alter table public.competition_deadline_deliveries enable row level security;
revoke all on public.competition_deadline_events,public.competition_deadline_deliveries from public,anon,authenticated;
grant all on public.competition_deadline_events,public.competition_deadline_deliveries to service_role;
create function competition_private.queue_deadline_change() returns trigger
language plpgsql security definer set search_path='' as $$
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
 'matches',jsonb_build_array(to_jsonb(new)),
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
end $$;
revoke all on function competition_private.queue_deadline_change() from public,anon,authenticated;
create trigger competition_deadline_after_change after update of play_by on public.competition_rounds for each row execute function competition_private.queue_deadline_change();
create function public.claim_competition_deadline_deliveries()
returns setof public.competition_deadline_deliveries language sql security definer set search_path='' as $$
 with batch as(select id from public.competition_deadline_deliveries where status='pending' order by id for update skip locked limit 50)
 update public.competition_deadline_deliveries d set status='claimed',claimed_at=now() from batch where d.id=batch.id returning d.*;
$$;
revoke all on function public.claim_competition_deadline_deliveries() from public,anon,authenticated;
grant execute on function public.claim_competition_deadline_deliveries() to service_role;
CREATE OR REPLACE FUNCTION public.update_competition_round(p_round_id uuid, p_play_by date, p_rule_overrides jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cid uuid; club uuid;
begin
 select r.competition_id,c.club_id into cid,club from public.competition_rounds r join public.club_competitions c on c.id=r.competition_id where r.id=p_round_id;
 if not competition_private.can_manage(club) then raise exception 'Club administrator access required' using errcode='42501'; end if;
 perform 1 from public.club_competitions where id=cid for update;
 if exists(select 1 from public.club_competitions where id=cid and status='published') and p_rule_overrides is distinct from (select rule_overrides from public.competition_rounds where id=p_round_id) then raise exception 'Only the play-by date may be changed for a published round'; end if;
 if p_rule_overrides is null or jsonb_typeof(p_rule_overrides)<>'object' or length(p_rule_overrides::text)>16000 then raise exception 'Invalid round rules'; end if;
 update public.competition_rounds set play_by=p_play_by,rule_overrides=p_rule_overrides where id=p_round_id;
end $function$
;
commit;
