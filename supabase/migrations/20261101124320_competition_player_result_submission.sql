begin;
-- Drawn players may submit; confirmation and winner advancement remain Admin-only.
CREATE OR REPLACE FUNCTION public.record_competition_result(p_match_id uuid, p_score_a integer, p_score_b integer, p_winner_entry_id uuid, p_confirm boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare m public.competition_draw_matches; club uuid; cid uuid; is_admin boolean; actor_member uuid;
begin
 select d.competition_id,c.club_id into cid,club from public.competition_draw_matches d join public.club_competitions c on c.id=d.competition_id where d.id=p_match_id;
 if auth.uid() is null or cid is null then raise exception 'Sign in and select a valid competition match' using errcode='42501'; end if;
 -- Serialize all changes to one bracket, including simultaneous upstream results.
 perform 1 from public.club_competitions where id=cid for update;
 select * into m from public.competition_draw_matches where id=p_match_id for update;
 is_admin:=coalesce(competition_private.can_manage(club),false);
 actor_member:=public.my_member_profile_id();
 if p_confirm and not is_admin then raise exception 'Only a Club Admin may confirm competition results' using errcode='42501'; end if;
 if not is_admin and not exists(
  select 1 from public.competition_entry_members em join public.club_memberships cm on cm.member_profile_id=em.member_profile_id and cm.club_id=club
  where em.competition_id=cid and em.entry_id in (m.side_a_entry_id,m.side_b_entry_id)
    and em.member_profile_id=actor_member and cm.is_active and cm.role::text<>'guest'
 ) then raise exception 'Only a drawn player or Club Admin may submit this match result' using errcode='42501'; end if;
 if not is_admin and m.status='result_pending' then raise exception 'A result is already awaiting Club Admin confirmation'; end if;
 if m.status in ('bye','completed') or m.side_a_entry_id is null or m.side_b_entry_id is null
 or p_score_a is null or p_score_b is null or p_score_a<0 or p_score_b<0 or p_winner_entry_id is null
 or p_winner_entry_id not in (m.side_a_entry_id,m.side_b_entry_id) then raise exception 'A playable match and valid result are required'; end if;
 if not exists(select 1 from public.club_competitions where id=cid and status='published') then raise exception 'Publish the competition before recording results'; end if;
 if p_confirm then
 if m.status<>'result_pending' or m.score_a is distinct from p_score_a or m.score_b is distinct from p_score_b or m.proposed_winner_entry_id is distinct from p_winner_entry_id then
 raise exception 'Review the latest submitted result before confirming'; end if;
 update public.competition_draw_matches set status='completed',winner_entry_id=p_winner_entry_id where id=m.id;
 update public.competition_draw_matches set side_a_entry_id=p_winner_entry_id where side_a_source_id=m.id;
 update public.competition_draw_matches set side_b_entry_id=p_winner_entry_id where side_b_source_id=m.id;
 else
 update public.competition_draw_matches set status='result_pending',score_a=p_score_a,score_b=p_score_b,proposed_winner_entry_id=p_winner_entry_id where id=m.id;
 end if;
 insert into public.competition_result_events(match_id,actor_user_id,action,score_a,score_b,winner_entry_id)
 values(m.id,auth.uid(),case when p_confirm then 'confirmed' else 'submitted' end,p_score_a,p_score_b,p_winner_entry_id);
end $function$
;
commit;
