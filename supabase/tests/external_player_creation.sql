begin;
do $test$
declare f public.fixtures%rowtype; actor uuid:=gen_random_uuid(); member uuid; created uuid; r text;
begin
 select fx.* into strict f from public.fixtures fx join public.competition_types ct on ct.id=fx.competition_type_id where fx.is_home and fx.green_area_id is not null and ct.is_internal and ct.selection_mode='preselect' limit 1;
 insert into auth.users(id,email) values(actor,'external-creation-test@example.invalid');
 select id into strict member from public.member_profiles where user_id=actor;
 insert into public.club_memberships(club_id,member_profile_id,role,is_active) values(f.club_id,member,'member',true);
 update public.competition_types set bookable_by_members=true,uses_rinks=true,team_selection_enabled=true,is_active=true where id=f.competition_type_id;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 foreach r in array array['member','admin'] loop
 update public.club_memberships set role=r::public.club_role where club_id=f.club_id and member_profile_id=member;
 created:=public.create_fixture_with_match_fee(p_club_id=>f.club_id,p_start_at=>now()+interval '10 years',p_end_at=>now()+interval '10 years 2 hours',p_is_home=>true,p_section=>'open',p_rinks_required=>1,p_players_per_rink=>1,p_format=>'singles',p_competition_type_id=>f.competition_type_id,p_dress_code=>'open',p_green_area_id=>f.green_area_id,p_orientation=>f.orientation::text,p_venue_id=>f.venue_id,p_requires_rsvp=>false,p_captain_member_profile_id=>member,p_create_team_selection=>true,p_team_selection_status=>'published',p_rink_assignments=>'[{"team_no":1,"position":1,"display_name":"External Player"},{"team_no":1,"position":101,"display_name":"External Opponent"}]'::jsonb);
 assert (select captain_member_profile_id=member from public.fixtures where id=created),'Captain lost';
 assert (select count(*)=2 from public.fixture_rink_assignments where fixture_id=created and member_profile_id is null and display_name is not null),'External names not saved';
 assert exists(select 1 from public.team_selections where fixture_id=created and status='published'),'Not published';
 assert not exists(select 1 from public.team_selection_members t join public.team_selections s on s.id=t.team_selection_id where s.fixture_id=created),'External names became members';
 end loop;
end $test$;
select 'PASS: member and admin create external player/opponent; booker remains captain; published; no invented members' result;
rollback;
