-- Disable new individual handicap editing and restore the prior scorecard context.
-- Preserve all imported entry/member handicaps and existing competition records.
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
 if exists(select 1 from public.competition_rounds where competition_id=cid) then raise exception 'Handicaps are locked after creating the draw'; end if;
 if p_handicap is not null and (p_handicap::text in ('NaN','Infinity','-Infinity') or p_handicap not between -100000 and 100000) then raise exception 'Enter a finite handicap between -100000 and 100000'; end if;
 update public.competition_entries set handicap=p_handicap where id=p_entry_id;
 end if;
 if p_paid is not null then
 update public.competition_entries set payment_status=case when p_paid then 'paid' else 'unpaid' end where id=p_entry_id;
 end if;
end $function$;
revoke execute on function public.set_competition_member_handicaps(uuid,jsonb) from authenticated;
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
   'handicapA',(select e.handicap from public.competition_entries e join public.competition_entry_members em on em.entry_id=e.id
      join public.fixture_rink_assignments a on a.member_profile_id=em.member_profile_id and a.fixture_rink_id=r.id and a.position between 1 and r.players_per_rink
      where em.competition_id=match_record.competition_id limit 1),
   'handicapB',(select e.handicap from public.competition_entries e join public.competition_entry_members em on em.entry_id=e.id
      join public.fixture_rink_assignments a on a.member_profile_id=em.member_profile_id and a.fixture_rink_id=r.id and a.position between 101 and 100+r.players_per_rink
      where em.competition_id=match_record.competition_id limit 1)
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
