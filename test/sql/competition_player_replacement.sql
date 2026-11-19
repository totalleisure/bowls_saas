-- Synthetic users, membership and draw; every record is rolled back.
begin;
do $$
declare ids uuid[]:='{}'; profiles uuid[]:='{}'; u uuid; mp uuid; c uuid:=gen_random_uuid();
 a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); r uuid:=gen_random_uuid(); m uuid:=gen_random_uuid();
 club uuid; ft uuid; green uuid; f uuid; label text; settings jsonb; emails bigint; notices bigint; result jsonb; old_draw jsonb; v_rink uuid; setup_match uuid; old_event uuid;
begin
 select cc.club_id,cc.fixture_type_id,cc.settings into strict club,ft,settings
 from public.club_competitions cc where cc.name='Mens Pairs' limit 1;
 select g.id into strict green from public.green_areas g join public.venues v on v.id=g.venue_id where v.club_id=club and v.is_home_venue limit 1;
 for i in 1..6 loop
  u:=gen_random_uuid();
  insert into auth.users(id,email,raw_user_meta_data) values(u,'competition-test-'||u||'@example.invalid',jsonb_build_object('first_name','Synthetic','last_name','Player '||i));
  select id into mp from public.member_profiles where user_id=u;
  if mp is null then insert into public.member_profiles(user_id,display_name,first_name,last_name) values(u,'Synthetic Player '||i,'Synthetic','Player '||i) returning id into mp; end if;
  update public.member_profiles set first_name='Synthetic',last_name='Player '||i where id=mp;
  insert into public.club_memberships(club_id,member_profile_id,role,is_active) values(club,mp,case when i=5 then 'admin'::public.club_role else 'member'::public.club_role end,true);
  ids:=array_append(ids,u); profiles:=array_append(profiles,mp);
 end loop;
 insert into public.club_competitions(id,club_id,name,season,status,settings,created_by,fixture_type_id) values(c,club,'Synthetic Admin arrangement verification','test','draft',settings||'{"handicap_mode":"team_difference"}',ids[5],ft);
 insert into public.competition_entries(id,competition_id,name) values(a,c,'Synthetic Player 1 / Synthetic Player 2'),(b,c,'Synthetic Player 3 / Synthetic Player 4');
 for i in 1..4 loop insert into public.competition_entry_members(competition_id,entry_id,member_profile_id) values(c,case when i<=2 then a else b end,profiles[i]); end loop;
 update public.competition_entry_members set individual_handicap=case when entry_id=a then 12 else 5 end where competition_id=c;
 update public.competition_entries set payment_status='paid',entry_order=7 where id=a;
 insert into public.competition_rounds(id,competition_id,round_number,name) values(r,c,1,'Final');
 insert into public.competition_draw_matches(id,competition_id,round_id,match_number,side_a_kind,side_b_kind,side_a_entry_id,side_b_entry_id) values(m,c,r,1,'entry','entry',a,b);
 -- Simulate only the newly created synthetic identity, never a real member.
 perform set_config('request.jwt.claim.sub',ids[5]::text,true);
 if not competition_private.can_manage(club) then raise exception 'Synthetic organiser requires Admin rights'; end if;

 select to_jsonb(d) into old_draw from public.competition_draw_matches d where id=m;
 perform set_config('request.jwt.claim.sub',ids[3]::text,true);
 begin perform public.replace_competition_entry_player(a,profiles[1],profiles[6],array[profiles[1],profiles[2]],'Synthetic Player 1 / Synthetic Player 2',24,2,'Wrong member'); raise exception 'Player replacement allowed to nonadmin'; exception when insufficient_privilege then null; end;
 perform set_config('request.jwt.claim.sub',ids[5]::text,true);
 begin perform public.replace_competition_entry_player(a,profiles[1],profiles[3],array[profiles[1],profiles[2]],'Synthetic Player 1 / Synthetic Player 2',24,2,'Wrong member'); raise exception 'Duplicate entrant accepted'; exception when raise_exception then if sqlerrm not like 'This player is already%' then raise; end if; end;
 begin perform public.replace_competition_entry_player(a,profiles[1],profiles[6],array[profiles[1],profiles[2]],'Old name',24,2,'Wrong member'); raise exception 'Stale entry accepted'; exception when raise_exception then if sqlerrm not like 'This entry has changed%' then raise; end if; end;
 begin perform public.replace_competition_entry_player(a,profiles[1],profiles[6],array[profiles[1],profiles[2]],'Synthetic Player 1 / Synthetic Player 2',24,null,'Wrong member'); raise exception 'Missing handicap accepted'; exception when raise_exception then if sqlerrm not like 'Enter the replacement%' then raise; end if; end;
 result:=public.replace_competition_entry_player(a,profiles[1],profiles[6],array[profiles[1],profiles[2]],'Synthetic Player 1 / Synthetic Player 2',24,2,'Wrong member');
 if (result->>'emails_queued')::int<>0 then raise exception 'Draft queued emails';end if;
 if not exists(select 1 from public.competition_entries where id=a and payment_status='paid' and entry_order=7 and handicap=14 and name='Synthetic Player 6 / Synthetic Player 2') then raise exception 'Entry/order/payment/handicap not preserved'; end if;
 if old_draw is distinct from (select to_jsonb(d) from public.competition_draw_matches d where id=m) then raise exception 'Draw rebuilt'; end if;
 perform public.replace_competition_entry_player(a,profiles[6],profiles[1],array[profiles[6],profiles[2]],'Synthetic Player 6 / Synthetic Player 2',14,12,'Restore synthetic entry');
 update public.club_competitions set status='published' where id=c;
 update public.competition_draw_matches set status='result_pending',score_a=2,score_b=1,proposed_winner_entry_id=a where id=m;
 begin perform public.replace_competition_entry_player(a,profiles[1],profiles[6],array[profiles[1],profiles[2]],'Synthetic Player 1 / Synthetic Player 2',24,2,'Wrong member'); raise exception 'Played entry changed'; exception when raise_exception then if sqlerrm not like 'This entry has a played%' then raise; end if; end;
 update public.competition_draw_matches set status='to_be_arranged',score_a=null,score_b=null,proposed_winner_entry_id=null where id=m;
 result:=public.replace_competition_entry_player(a,profiles[1],profiles[6],array[profiles[1],profiles[2]],'Synthetic Player 1 / Synthetic Player 2',24,2,'Published correction');
 if not exists(select 1 from public.competition_amendment_events where competition_id=c and snapshot ? 'playerReplacement') then raise exception 'No amendment event'; end if;
 perform public.replace_competition_entry_player(a,profiles[6],profiles[1],array[profiles[6],profiles[2]],'Synthetic Player 6 / Synthetic Player 2',14,12,'Restore synthetic entry');
 select count(*) into emails from public.email_queue; select count(*) into notices from public.notification_queue;
 select rink_label into strict label from public.get_green_rink_availability(green,'2030-07-02 10:00Z','2030-07-02 12:30Z') where not is_booked and free_capacity_rinks>=1 limit 1;
 f:=public.arrange_competition_match(m,green,'2030-07-02 10:00Z','2030-07-02 12:30Z',array[label]);

 select id into v_rink from public.fixture_rinks where fixture_id=f limit 1;
 begin
  insert into scorecard_private.fixture_matches(fixture_id,club_id) values(f,club) returning id into setup_match;
  insert into scorecard_private.fixture_rink_setups(match_id,fixture_rink_id,source_snapshot,conditions,created_by) values(setup_match,v_rink,'{}','{}',ids[5]);
  perform public.replace_competition_entry_player(a,profiles[1],profiles[6],array[profiles[1],profiles[2]],'Synthetic Player 1 / Synthetic Player 2',24,2,'Wrong member'); raise exception 'Scoring setup changed';
 exception when raise_exception then if sqlerrm not like 'A linked fixture already has%' then raise; end if; end;
 insert into public.competition_amendment_events(match_id,competition_id,club_id,actor_user_id,before_match,snapshot)
 values(m,c,club,ids[5],'{}','{}') returning id into old_event;
 insert into public.competition_amendment_deliveries(event_id,member_profile_id,recipient) values(old_event,profiles[1],'wayne@totalleisure.com');
 update public.competition_amendment_deliveries set status='claimed' where event_id=old_event;
 begin perform public.replace_competition_entry_player(a,profiles[1],profiles[6],array[profiles[1],profiles[2]],'Synthetic Player 1 / Synthetic Player 2',24,2,'Correction while sending'); raise exception 'In-flight email changed'; exception when raise_exception then if sqlerrm not like 'An affected email is being sent%' then raise; end if; end;
 update public.competition_amendment_deliveries set status='pending' where event_id=old_event;
 result:=public.replace_competition_entry_player(a,profiles[1],profiles[6],array[profiles[1],profiles[2]],'Synthetic Player 1 / Synthetic Player 2',24,2,'Correct booked fixture player');
 if (result->>'fixtures_updated')::int<>1 then raise exception 'Booked fixture not updated';end if;
 if exists(select 1 from public.fixture_rink_assignments where fixture_id=f and member_profile_id=profiles[1])
 or not exists(select 1 from public.fixture_rink_assignments where fixture_id=f and member_profile_id=profiles[6]) then raise exception 'Fixture players wrong';end if;
 if not exists(select 1 from public.team_selection_members sm join public.team_selections ts on ts.id=sm.team_selection_id where ts.fixture_id=f and sm.member_profile_id=profiles[6] and sm.acceptance='pending') then raise exception 'Replacement RSVP not pending';end if;
 if not exists(select 1 from public.fixtures where id=f and start_at='2030-07-02 10:00Z' and captain_member_profile_id=profiles[5]) then raise exception 'Fixture date or Admin organiser changed';end if;
 if not exists(select 1 from public.competition_amendment_deliveries where event_id=old_event and status='cancelled') then raise exception 'Stale message not cancelled';end if;
 if (select count(*) from public.competition_player_replacements where competition_id=c)<>5 then raise exception 'Replacement audit incomplete';end if;
 if competition_private.rink_starting_handicap(v_rink,'a')<>0 or competition_private.rink_starting_handicap(v_rink,'b')<>4 then raise exception 'Starting scores wrong';end if;
 if has_function_privilege('anon','public.replace_competition_entry_player(uuid,uuid,uuid,uuid[],text,numeric,integer,text)','execute') or has_table_privilege('authenticated','public.competition_player_replacements','insert') then raise exception 'Replacement permissions leaked'; end if;
end $$;
rollback;
select 'PASS: Admin replacement, stale/duplicate/played/scoring guards, draft/published entries, payment/order/handicaps, same draw, linked booking/RSVP, audit, stale message cancellation and privileges; all synthetic records rolled back' result;
