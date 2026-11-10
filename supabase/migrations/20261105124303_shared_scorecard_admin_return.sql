-- Return a pending result safely; confirmed progression is deliberately locked.
create function public.return_shared_scorecard_for_correction(p_fixture_id uuid,p_rink_id uuid,p_version bigint,p_note text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor jsonb; m public.competition_draw_matches; c scorecard_private.shared_cards;
begin
 actor:=scorecard_private.shared_actor(p_fixture_id,p_rink_id);
 if not(actor->>'admin')::boolean then raise exception 'Only Club Admin may return a submitted result' using errcode='42501'; end if;
 if length(btrim(coalesce(p_note,''))) not between 1 and 1000 then raise exception 'Enter the reason for returning the result'; end if;
 select * into strict m from public.competition_draw_matches where fixture_id=p_fixture_id;
 perform 1 from public.club_competitions where id=m.competition_id for update;
 select * into strict m from public.competition_draw_matches where id=m.id for update;
 perform 1 from scorecard_private.shared_cards where fixture_id=p_fixture_id order by id for update;
 select * into strict c from scorecard_private.shared_cards where rink_id=p_rink_id and fixture_id=p_fixture_id;
 if m.status<>'result_pending' or c.phase<>'submitted' or c.version<>p_version then raise exception 'Only the latest pending result can be returned. Confirmed progression needs separate review.'; end if;
 update public.competition_draw_matches set status='to_be_arranged',score_a=null,score_b=null,
 proposed_winner_entry_id=null,winner_entry_id=null where id=m.id;
 delete from scorecard_private.shared_agreements where card_id in(select id from scorecard_private.shared_cards where fixture_id=p_fixture_id);
 update scorecard_private.shared_cards set phase='correction_requested',submitted_at=null,version=version+1,
 correction_note='Admin: '||btrim(p_note),updated_at=clock_timestamp() where fixture_id=p_fixture_id;
 insert into scorecard_private.shared_events(card_id,actor_user_id,action,version,details)
 select id,auth.uid(),'admin_returned',version,jsonb_build_object('note',btrim(p_note)) from scorecard_private.shared_cards where fixture_id=p_fixture_id;
 return public.shared_scorecard_state(p_fixture_id,p_rink_id);
end $$;
revoke all on function public.return_shared_scorecard_for_correction(uuid,uuid,bigint,text) from public,anon;
grant execute on function public.return_shared_scorecard_for_correction(uuid,uuid,bigint,text) to authenticated;
