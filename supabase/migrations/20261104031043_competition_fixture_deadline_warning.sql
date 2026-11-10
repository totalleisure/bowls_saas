begin;
CREATE OR REPLACE FUNCTION public.competition_fixture_access(p_fixture_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select case when auth.uid() is not null and exists(
   select 1 from public.fixtures f where f.id=p_fixture_id and (
     competition_private.can_manage(f.club_id) or exists(select 1 from public.club_memberships cm
       where cm.club_id=f.club_id and cm.member_profile_id=public.my_member_profile_id() and cm.is_active)
   )
 ) then jsonb_build_object(
   'is_competition',exists(select 1 from public.competition_draw_matches where fixture_id=p_fixture_id),
   'play_by',(select r.play_by from public.competition_draw_matches m join public.competition_rounds r on r.id=m.round_id where m.fixture_id=p_fixture_id),
   'can_manage',competition_private.can_arrange_linked_fixture(p_fixture_id),
   'is_creator',exists(select 1 from public.fixtures where id=p_fixture_id and created_by_user_id=auth.uid())
 ) else jsonb_build_object('is_competition',false,'can_manage',false,'is_creator',false) end;
$function$
;
CREATE OR REPLACE FUNCTION public.competition_fixture_management_state(p_fixture_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb;
begin
 if not competition_private.can_arrange_linked_fixture(p_fixture_id) then
 raise exception 'Only the organiser, a drawn player or Club Admin may manage this active competition fixture' using errcode='42501'; end if;
 select jsonb_build_object('fixture',jsonb_build_object('id',f.id,'club_id',f.club_id,'name',c.name,
   'play_by',r.play_by,'round',r.name||' '||m.match_number,'start_at',f.start_at,'end_at',f.end_at,
   'green_area_id',f.green_area_id,'orientation',f.orientation,'rinks_required',f.rinks_required),
   'rinks',coalesce((select jsonb_agg(jsonb_build_object('id',fr.id,'number',fr.fixture_rink_no,
      'home_rink_label',fr.home_rink_label,'marker_required',fr.marker_required,
      'marker_member_id',a.member_profile_id,'marker_name',mp.display_name)
      order by fr.fixture_rink_no)
     from public.fixture_rinks fr left join public.fixture_rink_assignments a on a.fixture_rink_id=fr.id and a.position=201
     left join public.member_profiles mp on mp.id=a.member_profile_id where fr.fixture_id=f.id),'[]'::jsonb),
   'assigned_member_ids',coalesce((select jsonb_agg(member_profile_id) from public.fixture_rink_assignments where fixture_id=f.id and member_profile_id is not null),'[]'::jsonb)) into result
 from public.fixtures f join public.competition_draw_matches m on m.fixture_id=f.id
 join public.club_competitions c on c.id=m.competition_id join public.competition_rounds r on r.id=m.round_id
 where f.id=p_fixture_id;
 return result;
end $function$
;
commit;

