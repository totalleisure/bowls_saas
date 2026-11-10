begin;
do $$
declare f uuid; r uuid; u uuid; state jsonb; setup jsonb; reused jsonb; before_f jsonb; mails bigint;
begin
 select fx.id,fr.id,mp.user_id into strict f,r,u from public.fixtures fx join public.fixture_rinks fr on fr.fixture_id=fx.id
 join public.fixture_rink_assignments a on a.fixture_rink_id=fr.id join public.member_profiles mp on mp.id=a.member_profile_id
 join public.competition_types t on t.id=fx.competition_type_id
 where t.is_internal and t.bookable_by_members and t.uses_rinks and t.selection_mode='preselect'
 and a.position between 1 and fr.players_per_rink and mp.user_id is not null and fx.cancelled_at is null and fx.archived_at is null limit 1;
 select to_jsonb(x) into before_f from public.fixtures x where id=f;
 select count(*) into mails from public.email_queue;
 perform set_config('request.jwt.claim.sub',u::text,true);
 state:=public.fixture_scorecard_context(f);
 select value into state from jsonb_array_elements(state->'rinks') where value->>'fixtureRinkId'=r::text;
 if (state->>'canScore')::boolean is not true then raise exception 'Selected player cannot score'; end if;
 begin perform public.prepare_fixture_scorecard_setup(f,r,'stale','{}'); raise exception 'Accepted stale snapshot';
 exception when raise_exception then if sqlerrm<>'Fixture details changed. Refresh and review the setup again.' then raise; end if;end;
 begin perform public.prepare_fixture_scorecard_setup(f,r,state->>'sourceFingerprint','{"woods":-1}'); raise exception 'Accepted invalid woods';
 exception when raise_exception then if sqlerrm<>'Invalid playing condition: woods' then raise; end if;end;
 setup:=public.prepare_fixture_scorecard_setup(f,r,state->>'sourceFingerprint','{"woods":4,"maxEnds":18,"durationMinutes":150,"lastJackMinutes":140,"handicapA":-2,"scoring":"shots"}');
 reused:=public.prepare_fixture_scorecard_setup(f,r,'stale','{"woods":2}');
 if setup<>reused then raise exception 'Later scorer overwrote shared setup';end if;
 if setup->'conditions'->>'woods'<>'4' then raise exception 'Setup conditions missing';end if;
 if before_f is distinct from (select to_jsonb(x) from public.fixtures x where id=f) then raise exception 'Fixture changed';end if;
 if mails<>(select count(*) from public.email_queue) then raise exception 'Email queued';end if;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 begin perform public.fixture_scorecard_context(f);raise exception 'Non-member read fixture';exception when insufficient_privilege then null;end;
 if has_function_privilege('anon','public.fixture_scorecard_context(uuid)','execute') then raise exception 'Anonymous RPC privilege';end if;
 if has_table_privilege('authenticated','scorecard_private.fixture_rink_setups','select') then raise exception 'Client direct read privilege';end if;
end $$;
rollback;
select 'PASS: fixture context, first setup, copy, validation, authorization and no fixture/email changes (rolled back)' as result;
