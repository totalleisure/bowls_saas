begin;
-- Card side A/B follows fixture positions. Draw side A/B follows fixed competition entries.
create function scorecard_private.fixture_a_is_draw_a(p_fixture uuid,p_rink uuid) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare m public.competition_draw_matches; card scorecard_private.shared_cards; ppr integer;
 members_a uuid[]; members_b uuid[]; entries_a uuid[]; entries_b uuid[]; matched_a integer; matched_b integer;
 frozen_a uuid[]; frozen_b uuid[];
begin
 select * into strict m from public.competition_draw_matches where fixture_id=p_fixture;
 select * into strict card from scorecard_private.shared_cards where fixture_id=p_fixture and rink_id=p_rink;
 select players_per_rink into strict ppr from public.fixture_rinks where id=p_rink and fixture_id=p_fixture;
 select array_agg(fa.member_profile_id order by fa.position),array_agg(distinct em.entry_id),count(em.entry_id)
 into members_a,entries_a,matched_a from public.fixture_rink_assignments fa
 left join public.competition_entry_members em on em.competition_id=m.competition_id and em.member_profile_id=fa.member_profile_id and em.entry_id in(m.side_a_entry_id,m.side_b_entry_id)
 where fa.fixture_id=p_fixture and fa.fixture_rink_id=p_rink and fa.position between 1 and ppr;
 select array_agg(fa.member_profile_id order by fa.position),array_agg(distinct em.entry_id),count(em.entry_id)
 into members_b,entries_b,matched_b from public.fixture_rink_assignments fa
 left join public.competition_entry_members em on em.competition_id=m.competition_id and em.member_profile_id=fa.member_profile_id and em.entry_id in(m.side_a_entry_id,m.side_b_entry_id)
 where fa.fixture_id=p_fixture and fa.fixture_rink_id=p_rink and fa.position between 101 and 100+ppr;
 if matched_a<>ppr or matched_b<>ppr or cardinality(members_a) is distinct from ppr or cardinality(members_b) is distinct from ppr
 or cardinality(entries_a) is distinct from 1 or cardinality(entries_b) is distinct from 1 or entries_a[1] is null or entries_b[1] is null or entries_a[1]=entries_b[1] then
 raise exception 'Cannot map the shared scorecard players to the two competition entries. Ask the Competition Secretary to review the fixture.';end if;
 select array_agg((p->>'memberId')::uuid order by (p->>'position')::int) into frozen_a
 from jsonb_array_elements(coalesce(card.document->'fixtureLink'->'players','[]')) p where (p->>'position')::int between 1 and ppr;
 select array_agg((p->>'memberId')::uuid order by (p->>'position')::int) into frozen_b
 from jsonb_array_elements(coalesce(card.document->'fixtureLink'->'players','[]')) p where (p->>'position')::int between 101 and 100+ppr;
 if frozen_a is distinct from members_a or frozen_b is distinct from members_b then
 raise exception 'Shared scorecard player identities differ from the fixture. Review the card before submitting a competition result.';end if;
 return entries_a[1]=m.side_a_entry_id;
end $$;
revoke all on function scorecard_private.fixture_a_is_draw_a(uuid,uuid) from public,anon,authenticated;

do $$ declare definition text; patched text; begin
 select pg_get_functiondef(oid) into strict definition from pg_proc where pronamespace='scorecard_private'::regnamespace and proname='guard_shared_result';
 if md5(replace(definition,chr(13),''))<>'927b6d2ef7ee5f8dc4310a9450d3ef66' then raise exception 'Shared result guard changed since review';end if;
 patched:=replace(definition,'sum(total_a),sum(total_b)',
 'sum(case when scorecard_private.fixture_a_is_draw_a(c.fixture_id,c.rink_id) then c.total_a else c.total_b end),sum(case when scorecard_private.fixture_a_is_draw_a(c.fixture_id,c.rink_id) then c.total_b else c.total_a end)');
 if patched=definition then raise exception 'Guard mapping anchor missing';end if;
 execute patched;
 select pg_get_functiondef(oid) into strict definition from pg_proc where pronamespace='public'::regnamespace and proname='submit_shared_scorecard';
 if md5(replace(definition,chr(13),''))<>'651147ba353f2f253a741d5b6df25129' then raise exception 'Shared submission changed since review';end if;
 patched:=replace(definition,'winner:=case when c.total_a>c.total_b then m.side_a_entry_id else m.side_b_entry_id end;',
 'winner:=case when (case when scorecard_private.fixture_a_is_draw_a(c.fixture_id,c.rink_id) then c.total_a>c.total_b else c.total_b>c.total_a end) then m.side_a_entry_id else m.side_b_entry_id end;');
 if patched=definition then raise exception 'Winner mapping anchor missing';end if;
 definition:=patched;
 patched:=replace(definition,'perform public.record_competition_result(m.id,c.total_a,c.total_b,winner,false);',
 'perform public.record_competition_result(m.id,case when scorecard_private.fixture_a_is_draw_a(c.fixture_id,c.rink_id) then c.total_a else c.total_b end,case when scorecard_private.fixture_a_is_draw_a(c.fixture_id,c.rink_id) then c.total_b else c.total_a end,winner,false);');
 if patched=definition then raise exception 'Score mapping anchor missing';end if;
 execute patched;
end $$;
notify pgrst,'reload schema';
commit;
