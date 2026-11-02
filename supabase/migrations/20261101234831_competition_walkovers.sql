begin;
alter table public.competition_draw_matches add column result_kind text not null default 'played' check(result_kind in ('played','walkover'));
create table public.competition_walkover_events(
 id uuid primary key default gen_random_uuid(),match_id uuid not null unique references public.competition_draw_matches(id),
 club_id uuid not null references public.clubs(id),actor_user_id uuid not null references auth.users(id),
 winner_entry_id uuid not null references public.competition_entries(id),
 reason text not null check(reason in ('pulled_out','injured_unwell','deadline','no_show','ineligible','other')),
 note text check(length(note)<=2000),recorded_at timestamptz not null default clock_timestamp()
);
alter table public.competition_walkover_events enable row level security;
revoke all on public.competition_walkover_events from public,anon,authenticated;
grant select on public.competition_walkover_events to authenticated;
create policy competition_walkover_admin_read on public.competition_walkover_events for select to authenticated using(competition_private.can_manage(club_id));
create function public.award_competition_walkover(p_match_id uuid,p_winner_entry_id uuid,p_reason text,p_note text,p_expected_side_a uuid,p_expected_side_b uuid)
returns void language plpgsql security definer set search_path='' as $$
declare m public.competition_draw_matches;cid uuid;club uuid;
begin
 select d.competition_id,c.club_id into cid,club from public.competition_draw_matches d join public.club_competitions c on c.id=d.competition_id where d.id=p_match_id;
 if cid is null or auth.uid() is null or not coalesce(competition_private.can_manage(club),false) then raise exception 'Only a Club Admin may award a walkover' using errcode='42501';end if;
 perform 1 from public.club_competitions where id=cid for update;
 select * into strict m from public.competition_draw_matches where id=p_match_id for update;
 if not exists(select 1 from public.club_competitions where id=cid and status='published') then raise exception 'Publish the competition before awarding a walkover';end if;
 if m.status not in ('to_be_arranged','result_pending') or m.side_a_entry_id is null or m.side_b_entry_id is null or p_winner_entry_id is null or p_winner_entry_id not in(m.side_a_entry_id,m.side_b_entry_id) then raise exception 'Select an unfinished playable match and its winning entry';end if;
 if m.side_a_entry_id is distinct from p_expected_side_a or m.side_b_entry_id is distinct from p_expected_side_b then raise exception 'The draw has changed; reopen the match';end if;
 if p_reason is null or p_reason not in ('pulled_out','injured_unwell','deadline','no_show','ineligible','other') or length(coalesce(p_note,''))>2000 or (p_reason='other' and nullif(btrim(p_note),'') is null) then raise exception 'Select a valid reason; Other requires an explanation';end if;
 insert into public.competition_walkover_events(match_id,club_id,actor_user_id,winner_entry_id,reason,note) values(m.id,club,auth.uid(),p_winner_entry_id,p_reason,nullif(btrim(p_note),''));
 update public.competition_draw_matches set status='completed',result_kind='walkover',score_a=null,score_b=null,proposed_winner_entry_id=null,winner_entry_id=p_winner_entry_id where id=m.id;
 update public.competition_draw_matches set side_a_entry_id=p_winner_entry_id where side_a_source_id=m.id;
 update public.competition_draw_matches set side_b_entry_id=p_winner_entry_id where side_b_source_id=m.id;
end $$;
revoke all on function public.award_competition_walkover(uuid,uuid,text,text,uuid,uuid) from public,anon;
grant execute on function public.award_competition_walkover(uuid,uuid,text,text,uuid,uuid) to authenticated;
commit;
