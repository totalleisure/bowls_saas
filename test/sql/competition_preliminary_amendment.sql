-- Real bracket transaction, completely rolled back including all queued messages.
begin;
do $$
declare c public.club_competitions; m public.competition_draw_matches; src public.competition_draw_matches;
 a uuid; members uuid[]; existing uuid[]; reply jsonb; before_other jsonb; after_other jsonb; old_auth text;
begin
 select * into strict c from public.club_competitions where club_id='8ae87bbe-cb16-4330-a5b0-e62366479f07' and name='Ladies Pairs';
 select d.* into strict m from public.competition_draw_matches d join public.competition_rounds r on r.id=d.round_id
 where d.competition_id=c.id and r.round_number=2 and d.match_number=4;
 a:=m.side_a_entry_id;
 select * into strict src from public.competition_draw_matches where id=m.side_a_source_id;
 select array_agg(mp.id order by mp.last_name) into members from public.member_profiles mp join public.club_memberships cm on cm.member_profile_id=mp.id
 where cm.club_id=c.club_id and ((mp.first_name='Anne' and mp.last_name='Boocock') or (mp.first_name='Sandy' and mp.last_name='Woodhouse'));
 select array_agg(member_profile_id) into existing from public.competition_entry_members where entry_id=a;
 update public.club_competitions set status='published' where id=c.id;
 perform set_config('request.jwt.claim.sub',c.created_by::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',c.created_by,'role','authenticated')::text,true);
 select jsonb_agg(to_jsonb(d) order by d.id) into before_other from public.competition_draw_matches d where competition_id=c.id and id not in(m.id,src.id);
 begin
 perform public.add_competition_preliminary(m.id,a,existing,src.id,(select play_by from public.competition_rounds where id=src.round_id),'Duplicate test');
 raise exception 'TEST FAILED duplicate accepted';
 exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;
 if sqlerrm not like '%already entered%' then raise;end if;end;
 update public.competition_draw_matches set status='result_pending' where id=m.id;
 begin
 perform public.add_competition_preliminary(m.id,a,members,src.id,(select play_by from public.competition_rounds where id=src.round_id),'Pending test');
 raise exception 'TEST FAILED result accepted';
 exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;
 if sqlerrm not like '%booking or result%' then raise;end if;end;
 update public.competition_draw_matches set status='to_be_arranged' where id=m.id;
 perform set_config('request.jwt.claim.sub','',true);perform set_config('request.jwt.claims','{}',true);
 begin
 perform public.add_competition_preliminary(m.id,a,members,src.id,(select play_by from public.competition_rounds where id=src.round_id),'Unauthorized test');
 raise exception 'TEST FAILED unauthorized accepted';
 exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',c.created_by::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',c.created_by,'role','authenticated')::text,true);
 reply:=public.add_competition_preliminary(m.id,a,members,src.id,(select play_by from public.competition_rounds where id=src.round_id),'Omitted pair test');
 if (select side_a_entry_id is not null or side_b_entry_id is distinct from m.side_b_entry_id from public.competition_draw_matches where id=m.id) then raise exception 'QF4 was not preserved';end if;
 if (select challenger_entry_id is distinct from a or side_a_entry_id is distinct from a or status<>'to_be_arranged' from public.competition_draw_matches where id=src.id) then raise exception 'Preliminary challenger wrong';end if;
 select jsonb_agg(to_jsonb(d) order by d.id) into after_other from public.competition_draw_matches d where competition_id=c.id and id not in(m.id,src.id);
 if before_other is distinct from after_other then raise exception 'Other matches changed';end if;
 if not exists(select 1 from public.competition_amendment_events where match_id=src.id and before_match->'source'->>'status'='bye') then raise exception 'Missing audit';end if;
 perform public.record_competition_result(src.id,20,18,a,false);
 perform public.record_competition_result(src.id,20,18,a,true);
 if (select side_a_entry_id is distinct from a from public.competition_draw_matches where id=m.id) then raise exception 'Winner did not return to QF4';end if;
 raise notice 'PASS: permissions, duplicate/result guards, unchanged bracket, audit and winner progression; %',reply;
end $$;
rollback;
