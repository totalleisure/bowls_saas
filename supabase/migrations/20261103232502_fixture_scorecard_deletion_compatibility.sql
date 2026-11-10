-- Keep the new optional setup from blocking existing fixture/member deletion.
alter table scorecard_private.fixture_matches drop constraint fixture_matches_fixture_id_fkey,
 add constraint fixture_matches_fixture_id_fkey foreign key(fixture_id) references public.fixtures(id) on delete cascade;
alter table scorecard_private.fixture_matches drop constraint fixture_matches_club_id_fkey,
 add constraint fixture_matches_club_id_fkey foreign key(club_id) references public.clubs(id) on delete cascade;
alter table scorecard_private.fixture_rink_setups drop constraint fixture_rink_setups_match_id_fkey,
 add constraint fixture_rink_setups_match_id_fkey foreign key(match_id) references scorecard_private.fixture_matches(id) on delete cascade;
alter table scorecard_private.fixture_rink_setups drop constraint fixture_rink_setups_fixture_rink_id_fkey,
 add constraint fixture_rink_setups_fixture_rink_id_fkey foreign key(fixture_rink_id) references public.fixture_rinks(id) on delete cascade;
alter table scorecard_private.fixture_rink_setups alter column created_by drop not null;
alter table scorecard_private.fixture_rink_setups drop constraint fixture_rink_setups_created_by_fkey,
 add constraint fixture_rink_setups_created_by_fkey foreign key(created_by) references auth.users(id) on delete set null;
