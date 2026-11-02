create function public.discard_unused_competition_draw(p_competition_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare c public.club_competitions;
begin
 select * into c from public.club_competitions where id=p_competition_id for update;
 if not found or not competition_private.can_manage(c.club_id) then raise exception 'Club administrator access required' using errcode='42501'; end if;
 if c.status<>'draft' then raise exception 'Published draws cannot be discarded'; end if;
 if exists(select 1 from public.competition_draw_matches m where m.competition_id=c.id and
   (m.fixture_id is not null or m.status not in ('bye','to_be_arranged') or m.score_a is not null or m.score_b is not null or m.proposed_winner_entry_id is not null))
 or exists(select 1 from public.competition_result_events e join public.competition_draw_matches m on m.id=e.match_id where m.competition_id=c.id)
 then raise exception 'Draws with results or linked fixtures cannot be discarded'; end if;
 update public.competition_draw_matches set side_a_source_id=null,side_b_source_id=null where competition_id=c.id;
 delete from public.competition_draw_matches where competition_id=c.id;
 delete from public.competition_rounds where competition_id=c.id;
end $$;
revoke all on function public.discard_unused_competition_draw(uuid) from public,anon,authenticated;
grant execute on function public.discard_unused_competition_draw(uuid) to authenticated;
