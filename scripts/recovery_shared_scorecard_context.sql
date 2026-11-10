create or replace function public.fixture_scorecard_context(p_fixture_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
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
   and (a.position between 1 and r.players_per_rink or a.position between 101 and 100+r.players_per_rink)
  )) can_score
  from rinks r
 ) select jsonb_agg(jsonb_build_object('fixtureRinkId',s.id,'snapshot',s.snapshot,'sourceFingerprint',md5(s.snapshot::text),'canScore',s.can_score,
    'setup',case when stored.id is null then null else jsonb_build_object('id',stored.id,'matchId',stored.match_id,'snapshot',stored.source_snapshot,'conditions',stored.conditions,'createdAt',stored.created_at) end) order by s.fixture_rink_no)
 into result from snapshots s left join scorecard_private.fixture_rink_setups stored on stored.fixture_rink_id=s.id;
 return jsonb_build_object('fixtureId',f.id,'actorUserId',auth.uid(),'rinks',coalesce(result,'[]'::jsonb));
end $$;
