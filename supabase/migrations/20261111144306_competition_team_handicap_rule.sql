begin;
alter table public.competition_entry_members add column individual_handicap integer
 check(individual_handicap between -1000 and 1000);

create function competition_private.team_handicap_total(p_entry_id uuid) returns integer
language plpgsql stable security definer set search_path='' as $$
declare total integer; supplied integer; required integer;
begin
 select (c.settings->>'players_per_entry')::int into required from public.competition_entries e join public.club_competitions c on c.id=e.competition_id where e.id=p_entry_id;
 select sum(individual_handicap),count(individual_handicap) into total,supplied from public.competition_entry_members where entry_id=p_entry_id;
 if required is null or supplied<>required then raise exception 'Set every player handicap before using this handicap entry';end if;
 return total;
end $$;
revoke all on function competition_private.team_handicap_total(uuid) from public,anon,authenticated;

create function competition_private.rink_starting_handicap(p_rink_id uuid,p_side text) returns numeric
language plpgsql stable security definer set search_path='' as $$
declare own_entry uuid; other_entry uuid; mode text; own_total integer; other_total integer;
begin
 if p_side not in ('a','b') then raise exception 'Invalid scorecard side';end if;
 select c.settings->>'handicap_mode' into mode from public.fixture_rinks fr join public.competition_draw_matches m on m.fixture_id=fr.fixture_id join public.club_competitions c on c.id=m.competition_id where fr.id=p_rink_id;
 select em.entry_id into own_entry from public.fixture_rink_assignments a join public.fixture_rinks fr on fr.id=a.fixture_rink_id
 join public.competition_draw_matches m on m.fixture_id=fr.fixture_id
 join public.competition_entry_members em on em.competition_id=m.competition_id and em.member_profile_id=a.member_profile_id
 where fr.id=p_rink_id and case when p_side='a' then a.position between 1 and fr.players_per_rink else a.position between 101 and 100+fr.players_per_rink end limit 1;
 if coalesce(mode,'entry_start')<>'team_difference' then return (select handicap from public.competition_entries where id=own_entry);end if;
 select em.entry_id into other_entry from public.fixture_rink_assignments a join public.fixture_rinks fr on fr.id=a.fixture_rink_id
 join public.competition_draw_matches m on m.fixture_id=fr.fixture_id
 join public.competition_entry_members em on em.competition_id=m.competition_id and em.member_profile_id=a.member_profile_id
 where fr.id=p_rink_id and case when p_side='b' then a.position between 1 and fr.players_per_rink else a.position between 101 and 100+fr.players_per_rink end limit 1;
 own_total:=competition_private.team_handicap_total(own_entry);
 other_total:=competition_private.team_handicap_total(other_entry);
 return greatest(other_total-own_total,0);
end $$;
revoke all on function competition_private.rink_starting_handicap(uuid,text) from public,anon,authenticated;

create function competition_private.refresh_team_handicap() returns trigger
language plpgsql security definer set search_path='' as $$
declare eid uuid:=case when tg_op='DELETE' then old.entry_id else new.entry_id end;
begin
 if exists(select 1 from public.competition_entries e join public.club_competitions c on c.id=e.competition_id where e.id=eid and c.settings->>'handicap_mode'='team_difference') then
 update public.competition_entries set handicap=(select case when count(individual_handicap)=count(*) and count(*)>0 then sum(individual_handicap) end from public.competition_entry_members where entry_id=eid) where id=eid;
 end if;
 return null;
end $$;
revoke all on function competition_private.refresh_team_handicap() from public,anon,authenticated;
create trigger refresh_competition_team_handicap after insert or delete or update of individual_handicap on public.competition_entry_members for each row execute function competition_private.refresh_team_handicap();

create function public.set_competition_member_handicaps(p_entry_id uuid,p_handicaps jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare c public.club_competitions; required integer; member record;
begin
 select cc.* into c from public.club_competitions cc join public.competition_entries e on e.competition_id=cc.id where e.id=p_entry_id for update of cc;
 if not found or not coalesce(competition_private.can_manage(c.club_id),false) then raise exception 'Club Admin access required' using errcode='42501';end if;
 if c.status<>'draft' or exists(select 1 from public.competition_draw_matches where competition_id=c.id and (fixture_id is not null or status in ('result_pending','completed'))) then raise exception 'Individual handicaps are fixed when the competition is published or play has started';end if;
 if c.settings->>'handicap_mode' is distinct from 'team_difference' then raise exception 'Choose the team handicap difference rule first';end if;
 required:=(c.settings->>'players_per_entry')::int;
 if jsonb_typeof(p_handicaps) is distinct from 'object' then raise exception 'Supply every player handicap';end if;
 if (select count(*) from jsonb_object_keys(p_handicaps))<>required or (select count(*) from public.competition_entry_members where entry_id=p_entry_id)<>required then raise exception 'Supply exactly one handicap for every entry member';end if;
 for member in select member_profile_id from public.competition_entry_members where entry_id=p_entry_id loop
 if jsonb_typeof(p_handicaps->member.member_profile_id::text) is distinct from 'number' then raise exception 'Every player needs a numeric handicap';end if;
 if (p_handicaps->>member.member_profile_id::text)::numeric<>trunc((p_handicaps->>member.member_profile_id::text)::numeric) or abs((p_handicaps->>member.member_profile_id::text)::numeric)>1000 then raise exception 'Handicaps must be whole numbers between -1000 and 1000';end if;
 update public.competition_entry_members set individual_handicap=(p_handicaps->>member.member_profile_id::text)::integer where entry_id=p_entry_id and member_profile_id=member.member_profile_id;
 end loop;
end $$;
revoke all on function public.set_competition_member_handicaps(uuid,jsonb) from public,anon;
grant execute on function public.set_competition_member_handicaps(uuid,jsonb) to authenticated;

create function competition_private.guard_handicap_rule() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if coalesce(new.settings->>'handicap_mode','entry_start') not in ('entry_start','team_difference') then raise exception 'Unknown handicap calculation rule';end if;
 if new.settings->>'handicap_mode'='team_difference' and coalesce((new.settings->>'rinks_required')::int,1)<>1 then raise exception 'Team difference handicaps currently require one rink per match';end if;
 if tg_op='UPDATE' and old.status='published' and coalesce(old.settings->>'handicap_mode','entry_start') is distinct from coalesce(new.settings->>'handicap_mode','entry_start') then raise exception 'The handicap calculation cannot change after publication';end if;
 if new.status='published' and new.settings->>'handicap_mode'='team_difference' then
 perform competition_private.team_handicap_total(id) from public.competition_entries where competition_id=new.id;
 end if;
 return new;
end $$;
revoke all on function competition_private.guard_handicap_rule() from public,anon,authenticated;
create trigger guard_competition_handicap_rule before insert or update of status,settings on public.club_competitions for each row execute function competition_private.guard_handicap_rule();
CREATE OR REPLACE FUNCTION public.fixture_scorecard_context(p_fixture_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f public.fixtures; actor uuid; admin boolean; result jsonb; rules jsonb; match_record record;
begin
 f:=scorecard_private.require_member_fixture(p_fixture_id);
 actor:=public.my_member_profile_id();
 admin:=public.is_app_superuser() or public.is_club_admin(f.club_id);
 select m.id,m.competition_id,m.round_id,c.name competition_name,r.name round_name,r.play_by,c.settings||r.rule_overrides settings
 into match_record from public.competition_draw_matches m
 join public.club_competitions c on c.id=m.competition_id
 join public.competition_rounds r on r.id=m.round_id where m.fixture_id=f.id;
 rules:=coalesce(match_record.settings,'{}'::jsonb);
 with rinks as (
  select fr.*,coalesce((
    select jsonb_agg(jsonb_build_object('memberId',a.member_profile_id,'position',a.position,
      'name',coalesce(nullif(btrim(a.display_name),''),nullif(btrim(mp.first_name||' '||mp.last_name),''),mp.display_name,'Unnamed player')) order by a.position)
    from public.fixture_rink_assignments a left join public.member_profiles mp on mp.id=a.member_profile_id
    where a.fixture_rink_id=fr.id and a.fixture_id=f.id
  ),'[]'::jsonb) players
  from public.fixture_rinks fr where fr.fixture_id=f.id
 ), snapshots as (
  select r.id,r.fixture_rink_no,
  jsonb_build_object('fixtureId',f.id,'clubId',f.club_id,'fixtureRinkId',r.id,
   'title',coalesce(nullif(f.team_name,''),(select name from public.competition_types where id=f.competition_type_id),'Member fixture'),
   'startAt',f.start_at,'endAt',f.end_at,'venue',coalesce((select name from public.venues where id=f.venue_id),''),
   'green',coalesce((select name from public.green_areas where id=f.green_area_id),''),'rink',coalesce(r.home_rink_label,r.fixture_rink_no::text),
   'format',r.format,'playersPerSide',r.players_per_rink,'players',r.players,'notes',coalesce(f.notes,''),
   'competitionId',match_record.competition_id,'competitionMatchId',match_record.id,'competitionName',match_record.competition_name,
   'roundName',match_record.round_name,'playBy',match_record.play_by,'rules',rules,
   'handicapA',competition_private.rink_starting_handicap(r.id,'a'),
   'handicapB',competition_private.rink_starting_handicap(r.id,'b')
  ) snapshot,
  f.cancelled_at is null and f.archived_at is null and (admin or exists(
   select 1 from public.fixture_rink_assignments a where a.fixture_id=f.id and a.fixture_rink_id=r.id and a.member_profile_id=actor
   and (a.position between 1 and r.players_per_rink or a.position between 101 and 100+r.players_per_rink or a.position=201)
  )) can_score
  from rinks r
 ) select jsonb_agg(jsonb_build_object('fixtureRinkId',s.id,'snapshot',s.snapshot,'sourceFingerprint',md5(s.snapshot::text),'canScore',s.can_score,
    'setup',case when stored.id is null then null else jsonb_build_object('id',stored.id,'matchId',stored.match_id,'snapshot',stored.source_snapshot,'conditions',stored.conditions,'createdAt',stored.created_at) end) order by s.fixture_rink_no)
 into result from snapshots s left join scorecard_private.fixture_rink_setups stored on stored.fixture_rink_id=s.id;
 return jsonb_build_object('fixtureId',f.id,'actorUserId',auth.uid(),'sharedWorkflow',true,'rinks',coalesce(result,'[]'::jsonb));
end $function$;
CREATE OR REPLACE FUNCTION public.update_competition_entry_options(p_entry_id uuid, p_paid boolean DEFAULT NULL::boolean, p_handicap numeric DEFAULT NULL::numeric, p_set_handicap boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cid uuid; club uuid;
begin
 select e.competition_id,c.club_id into cid,club from public.competition_entries e join public.club_competitions c on c.id=e.competition_id where e.id=p_entry_id;
 if cid is null or not competition_private.can_manage(club) then raise exception 'Club administrator access required' using errcode='42501'; end if;
 perform 1 from public.club_competitions where id=cid for update;
 if p_set_handicap then
 if exists(select 1 from public.club_competitions where id=cid and settings->>'handicap_mode'='team_difference') then raise exception 'Edit the individual player handicaps for this competition';end if;
 if exists(select 1 from public.competition_rounds where competition_id=cid) then raise exception 'Handicaps are locked after creating the draw'; end if;
 if p_handicap is not null and (p_handicap::text in ('NaN','Infinity','-Infinity') or p_handicap not between -100000 and 100000) then raise exception 'Enter a finite handicap between -100000 and 100000'; end if;
 update public.competition_entries set handicap=p_handicap where id=p_entry_id;
 end if;
 if p_paid is not null then
 update public.competition_entries set payment_status=case when p_paid then 'paid' else 'unpaid' end where id=p_entry_id;
 end if;
end $function$;
CREATE OR REPLACE FUNCTION public.prepare_fixture_scorecard_setup(p_fixture_id uuid, p_fixture_rink_id uuid, p_source_fingerprint text, p_conditions jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare state jsonb; rink jsonb; mid uuid; conditions jsonb; k text; n numeric;
begin
 perform pg_advisory_xact_lock(hashtextextended(p_fixture_id::text,9121));
 state:=public.fixture_scorecard_context(p_fixture_id);
 select value into rink from jsonb_array_elements(state->'rinks') where value->>'fixtureRinkId'=p_fixture_rink_id::text;
 if rink is null or not coalesce((rink->>'canScore')::boolean,false) then raise exception 'Only a selected player, opponent or Club Admin can prepare this rink scorecard' using errcode='42501'; end if;
 -- First setup wins; later independent scorers copy it, without copying scores.
 if rink->'setup' <> 'null'::jsonb then return rink->'setup'; end if;
 if p_source_fingerprint is distinct from rink->>'sourceFingerprint' then raise exception 'Fixture details changed. Refresh and review the setup again.'; end if;
 if jsonb_typeof(p_conditions) is distinct from 'object' then raise exception 'Invalid playing conditions'; end if;
 conditions:='{}'::jsonb;
 for k in select unnest(array['woods','target','maxEnds','durationMinutes','lastJackMinutes','handicapA','handicapB']) loop
  if p_conditions->k is not null and p_conditions->k<>'null'::jsonb then
   if jsonb_typeof(p_conditions->k)<>'number' then raise exception 'Invalid numeric playing condition: %',k; end if;
   n:=(p_conditions->>k)::numeric;
   if n<>trunc(n) or abs(n)>10000 or (k not in ('handicapA','handicapB') and n<=0) then raise exception 'Invalid playing condition: %',k; end if;
   conditions:=conditions||jsonb_build_object(k,n::int);
  end if;
 end loop;
 if rink->'snapshot'->'rules'->>'handicap_mode'='team_difference' then
  if (conditions->>'handicapA')::numeric is distinct from (rink->'snapshot'->>'handicapA')::numeric
   or (conditions->>'handicapB')::numeric is distinct from (rink->'snapshot'->>'handicapB')::numeric then
   raise exception 'Starting handicaps are calculated from the competition rule; refresh the scorecard setup';
  end if;
 end if;
 if coalesce(p_conditions->>'scoring','shots') not in ('shots','100up') then raise exception 'Unsupported scoring method'; end if;
 if length(coalesce(p_conditions->>'notes',''))>10000 then raise exception 'Playing notes are too long'; end if;
 if (conditions->>'lastJackMinutes')::int>(conditions->>'durationMinutes')::int then raise exception 'Last-jack deadline exceeds match duration'; end if;
 conditions:=conditions||jsonb_build_object('scoring',coalesce(p_conditions->>'scoring','shots'),'notes',coalesce(p_conditions->>'notes',''));
 insert into scorecard_private.fixture_matches(fixture_id,club_id) values(p_fixture_id,(rink->'snapshot'->>'clubId')::uuid)
 on conflict(fixture_id) do nothing;
 select id into mid from scorecard_private.fixture_matches where fixture_id=p_fixture_id;
 insert into scorecard_private.fixture_rink_setups(match_id,fixture_rink_id,source_snapshot,conditions,created_by)
 values(mid,p_fixture_rink_id,rink->'snapshot',conditions,auth.uid());
 return (select jsonb_build_object('id',s.id,'matchId',s.match_id,'snapshot',s.source_snapshot,'conditions',s.conditions,'createdAt',s.created_at)
 from scorecard_private.fixture_rink_setups s where s.fixture_rink_id=p_fixture_rink_id);
end $function$;
commit;
