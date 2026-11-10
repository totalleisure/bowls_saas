begin;
do $$
declare fid uuid; uid uuid; deadline date; value jsonb; mid uuid;
begin
 select f.id,f.created_by_user_id,r.play_by into fid,uid,deadline from public.fixtures f
 join public.competition_draw_matches m on m.fixture_id=f.id join public.competition_rounds r on r.id=m.round_id
 where f.created_by_user_id is not null and r.play_by is not null limit 1;
 if fid is null then
  -- Production has no linked fixture yet. Borrow a fixture and draw slot only
  -- inside this rollback-only transaction; neither record is saved or published.
  select f.id,f.created_by_user_id,r.play_by,m.id into fid,uid,deadline,mid
  from public.fixtures f join public.club_competitions c on c.club_id=f.club_id
  join public.competition_draw_matches m on m.competition_id=c.id
  join public.competition_rounds r on r.id=m.round_id
  join public.member_profiles mp on mp.user_id=f.created_by_user_id
  join public.club_memberships cm on cm.member_profile_id=mp.id and cm.club_id=f.club_id and cm.is_active
  where m.fixture_id is null and r.play_by is not null and f.cancelled_at is null limit 1;
  if fid is null then raise exception 'No fixture available for rollback-only verification';end if;
  update public.competition_draw_matches set fixture_id=fid where id=mid;
 end if;
 perform set_config('request.jwt.claim.sub',uid::text,true);
 value:=public.competition_fixture_access(fid);
 if (value->>'is_competition')::boolean is not true or value->>'play_by' is distinct from deadline::text then raise exception 'Deadline response incorrect';end if;
 if (value->>'can_manage')::boolean then
  value:=public.competition_fixture_management_state(fid);
  if value->'fixture'->>'play_by' is distinct from deadline::text then raise exception 'Management deadline incorrect';end if;
 end if;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 value:=public.competition_fixture_access(fid);
 if value ? 'play_by' or (value->>'is_competition')::boolean then raise exception 'Unauthorized deadline disclosed';end if;
end $$;
rollback;
select 'PASS: linked fixture deadline and unchanged access restrictions (rolled back)' result;
