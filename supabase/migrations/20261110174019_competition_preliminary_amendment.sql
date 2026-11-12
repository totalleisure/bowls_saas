begin;
alter table public.competition_draw_matches add column challenger_entry_id uuid;
alter table public.competition_draw_matches add foreign key(challenger_entry_id,competition_id) references public.competition_entries(id,competition_id);
-- Immutable amendment snapshots; recipients remain subject to the environment's mail policy.
create table public.competition_amendment_events (
 id uuid primary key default gen_random_uuid(),
 match_id uuid not null references public.competition_draw_matches(id),
 competition_id uuid not null references public.club_competitions(id),
 club_id uuid not null references public.clubs(id),
 actor_user_id uuid not null references auth.users(id),
 before_match jsonb not null, snapshot jsonb not null,
 created_at timestamptz not null default now()
);
create table public.competition_amendment_deliveries (
 id uuid primary key default gen_random_uuid(),
 event_id uuid not null references public.competition_amendment_events(id),
 member_profile_id uuid not null references public.member_profiles(id),
 recipient text not null,
 status text not null default 'pending' check(status in ('pending','claimed','sent','uncertain')),
 subject text, html text, claimed_at timestamptz, sent_at timestamptz,
 last_error text, attempt_count integer not null default 0,
 next_attempt_at timestamptz not null default now(),
 unique(event_id,recipient)
);
alter table public.competition_amendment_events enable row level security;
alter table public.competition_amendment_deliveries enable row level security;
revoke all on public.competition_amendment_events,public.competition_amendment_deliveries from public,anon,authenticated;
grant all on public.competition_amendment_events,public.competition_amendment_deliveries to service_role;
create policy amendment_admin_read on public.competition_amendment_events for select to authenticated
 using(competition_private.can_manage(club_id));
grant select on public.competition_amendment_events to authenticated;
create index competition_amendment_pending on public.competition_amendment_deliveries(next_attempt_at) where status='pending';

create function public.add_competition_preliminary(
 p_match_id uuid,p_entry_id uuid,p_members uuid[],p_expected_source_id uuid,p_play_by date,p_reason text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.club_competitions; m public.competition_draw_matches; src public.competition_draw_matches;
 r public.competition_rounds; target_round public.competition_rounds; new_entry uuid; event_id uuid;
 n int; member uuid; entry_name text; snap jsonb; old_match jsonb; old_source jsonb; total int; queued int;
begin
 select cc.* into c from public.club_competitions cc join public.competition_draw_matches d on d.competition_id=cc.id where d.id=p_match_id for update of cc;
 if not found or not coalesce(competition_private.can_manage(c.club_id),false) then
 raise exception 'Club administrator access required' using errcode='42501'; end if;
 if c.status<>'published' then raise exception 'This action amends a published competition'; end if;
 select * into strict m from public.competition_draw_matches where id=p_match_id for update;
 old_match:=to_jsonb(m);
 if m.status<>'to_be_arranged' or m.fixture_id is not null or m.score_a is not null or m.score_b is not null
 or m.proposed_winner_entry_id is not null or m.winner_entry_id is not null then
 raise exception 'This match has a booking or result. Resolve it before adding a preliminary'; end if;
 if p_entry_id is null or p_entry_id not in (m.side_a_entry_id,m.side_b_entry_id) then raise exception 'The selected entry has changed. Reload the draw';end if;
 if p_expected_source_id is null or p_expected_source_id is distinct from
 (case when m.side_a_entry_id=p_entry_id then m.side_a_source_id else m.side_b_source_id end) then
 raise exception 'The draw has changed. Reload before confirming';end if;
 select * into src from public.competition_draw_matches where id=p_expected_source_id and competition_id=c.id for update;
 if not found or src.status<>'bye' or src.winner_entry_id is distinct from p_entry_id or src.fixture_id is not null
 or src.side_a_source_id is not null or src.side_b_source_id is not null
 or num_nonnulls(src.side_a_entry_id,src.side_b_entry_id)<>1
 or exists(select 1 from public.competition_draw_matches d where d.id<>m.id and (d.side_a_source_id=src.id or d.side_b_source_id=src.id)) then
 raise exception 'Choose an entry advancing through an unused preliminary bye';end if;
 old_source:=to_jsonb(src);
 select * into strict r from public.competition_rounds where id=src.round_id;
 select * into strict target_round from public.competition_rounds where id=m.round_id;
 if r.round_number<>1 or target_round.round_number<>2 then raise exception 'Only an opening-round bye can become a preliminary match';end if;
 -- Avoid changing the deadline/rules of any other preliminary fixture.
 if p_play_by is distinct from r.play_by then raise exception 'Use the existing preliminary play-by date; edit the round date separately if needed';end if;
 if nullif(btrim(p_reason),'') is null or length(p_reason)>2000 then raise exception 'Give a short reason for the amendment';end if;
 n:=cardinality(p_members);
 if n is distinct from (c.settings->>'players_per_entry')::int or array_lower(p_members,1)<>1
 or n<>(select count(distinct x) from unnest(p_members) x)
 or exists(select 1 from unnest(p_members) x where x is null or not exists(
 select 1 from public.club_memberships cm where cm.club_id=c.club_id and cm.member_profile_id=x and cm.is_active and cm.role::text<>'guest')) then
 raise exception 'Select exactly one complete entry of active Club members';end if;
 if exists(select 1 from public.competition_entry_members em where em.competition_id=c.id and em.member_profile_id=any(p_members)) then
 raise exception 'One of these players is already entered in this competition';end if;
 select string_agg(btrim(concat_ws(' ',mp.first_name,mp.last_name)),' / ' order by x.ord) into entry_name
 from unnest(p_members) with ordinality x(id,ord) join public.member_profiles mp on mp.id=x.id;
 insert into public.competition_entries(competition_id,name) values(c.id,entry_name) returning id into new_entry;
 foreach member in array p_members loop
 insert into public.competition_entry_members(competition_id,entry_id,member_profile_id) values(c.id,new_entry,member);
 end loop;
 -- Side A is the challenger; retain the existing source ID/slot for print layout and progression.
 update public.competition_draw_matches set side_a_kind='entry',side_b_kind='entry',side_a_entry_id=p_entry_id,
 side_b_entry_id=new_entry,challenger_entry_id=p_entry_id,winner_entry_id=null,status='to_be_arranged' where id=src.id;
 update public.competition_draw_matches set
 side_a_entry_id=case when side_a_entry_id=p_entry_id then null else side_a_entry_id end,
 side_b_entry_id=case when side_b_entry_id=p_entry_id then null else side_b_entry_id end where id=m.id;
 select * into strict src from public.competition_draw_matches where id=src.id;
 select * into strict m from public.competition_draw_matches where id=m.id;
 select jsonb_build_object('matchId',src.id,'amendment',true,'reason',btrim(p_reason),
 'targetReference',target_round.name||' '||m.match_number,'challengerEntryId',p_entry_id,
 'clubName',(select name from public.clubs where id=c.club_id),'competitions',jsonb_build_array(to_jsonb(c)),
 'entries',(select jsonb_agg(to_jsonb(e)) from public.competition_entries e where e.id in(src.side_a_entry_id,src.side_b_entry_id,m.side_a_entry_id,m.side_b_entry_id)),
 'entryMembers',(select jsonb_agg(to_jsonb(e)) from public.competition_entry_members e where e.competition_id=c.id and e.entry_id in(src.side_a_entry_id,src.side_b_entry_id,m.side_a_entry_id,m.side_b_entry_id)),
 'rounds',jsonb_build_array(to_jsonb(r),to_jsonb(target_round)),
 'matches',jsonb_build_array(to_jsonb(src),to_jsonb(m)),
 'profiles',(select jsonb_agg(jsonb_build_object('id',mp.id,'first_name',mp.first_name,'last_name',mp.last_name,'email_address',mp.email_address,'phone',mp.phone))
 from public.member_profiles mp where exists(select 1 from public.competition_entry_members em where em.competition_id=c.id and em.member_profile_id=mp.id and em.entry_id in(src.side_a_entry_id,src.side_b_entry_id,m.side_a_entry_id,m.side_b_entry_id)))) into snap;
 insert into public.competition_amendment_events(match_id,competition_id,club_id,actor_user_id,before_match,snapshot)
 values(src.id,c.id,c.club_id,auth.uid(),jsonb_build_object('target',old_match,'source',old_source),snap) returning id into event_id;
 if competition_private.publication_enabled() then
 insert into public.competition_amendment_deliveries(event_id,member_profile_id,recipient)
 select distinct on(lower(btrim(mp.email_address))) event_id,mp.id,lower(btrim(mp.email_address))
 from public.competition_entry_members em join public.member_profiles mp on mp.id=em.member_profile_id
 where em.competition_id=c.id and em.entry_id in(src.side_a_entry_id,src.side_b_entry_id,m.side_a_entry_id,m.side_b_entry_id)
 and competition_private.email_recipient_allowed(mp.email_address)
 and exists(select 1 from public.club_memberships cm where cm.club_id=c.club_id and cm.member_profile_id=mp.id and cm.is_active and cm.role::text<>'guest')
 order by lower(btrim(mp.email_address)),mp.id;
 end if;
 get diagnostics queued=row_count;
 select count(*) into total from public.competition_entry_members em where em.competition_id=c.id and em.entry_id in(src.side_a_entry_id,src.side_b_entry_id,m.side_a_entry_id,m.side_b_entry_id);
 return jsonb_build_object('match_id',src.id,'entry_id',new_entry,'affected_players',total,'emails_queued',case when competition_private.publication_enabled() then queued else 0 end);
end $$;
revoke all on function public.add_competition_preliminary(uuid,uuid,uuid[],uuid,date,text) from public,anon,authenticated;
grant execute on function public.add_competition_preliminary(uuid,uuid,uuid[],uuid,date,text) to authenticated;
CREATE OR REPLACE FUNCTION public.claim_competition_mail_batch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record;item jsonb;items jsonb:='[]';next_time timestamptz;
begin
 if not competition_private.publication_enabled() then return items;end if;
 select next_batch_at into strict next_time from public.competition_mail_batch_control where id for update;
 if next_time>clock_timestamp() then return items;end if;
 for r in select * from (
  select 'publication' as kind,d.id,e.created_at from public.competition_publication_deliveries d join public.competition_publication_events e on e.id=d.event_id where d.status='pending' and d.next_attempt_at<=now()
  union all select 'round_ready',d.id,e.created_at from public.competition_round_ready_deliveries d join public.competition_round_ready_events e on e.id=d.event_id where d.status='pending' and d.next_attempt_at<=now()
  union all select 'deadline',d.id,e.created_at from public.competition_deadline_deliveries d join public.competition_deadline_events e on e.id=d.event_id where d.status='pending' and d.next_attempt_at<=now()
  union all select 'amendment',d.id,e.created_at from public.competition_amendment_deliveries d join public.competition_amendment_events e on e.id=d.event_id where d.status='pending' and d.next_attempt_at<=now()
 ) candidates order by created_at,id limit 20 loop
  item:=null;
  if r.kind='publication' then
   update public.competition_publication_deliveries d set status='claimed',claimed_at=clock_timestamp(),attempt_count=attempt_count+1,claimed_by=(select actor_user_id from public.competition_publication_events e where e.id=d.event_id) where d.id=r.id and d.status='pending' returning to_jsonb(d) into item;
  elsif r.kind='round_ready' then
   update public.competition_round_ready_deliveries d set status='claimed',claimed_at=clock_timestamp(),attempt_count=attempt_count+1 where d.id=r.id and d.status='pending' returning to_jsonb(d) into item;
  elsif r.kind='amendment' then
   update public.competition_amendment_deliveries d set status='claimed',claimed_at=clock_timestamp(),attempt_count=attempt_count+1 where d.id=r.id and d.status='pending' returning to_jsonb(d) into item;
  else
   update public.competition_deadline_deliveries d set status='claimed',claimed_at=clock_timestamp(),attempt_count=attempt_count+1 where d.id=r.id and d.status='pending' returning to_jsonb(d) into item;
  end if;
  if item is not null then items:=items||jsonb_build_array(jsonb_build_object('kind',r.kind,'delivery',item));end if;
 end loop;
 if jsonb_array_length(items)>0 then update public.competition_mail_batch_control set next_batch_at=clock_timestamp()+interval '60 seconds' where id;end if;
 return items;
end $function$;

commit;
