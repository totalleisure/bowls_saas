CREATE OR REPLACE FUNCTION scorecard_private.guard_shared_result()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cards integer; rinks integer; agreed integer; a integer; b integer; locked_card scorecard_private.shared_cards; state jsonb;
begin
 if new.fixture_id is null or new.status not in ('result_pending','completed') or new.result_kind='walkover' then return new; end if;
 select count(*) into cards from scorecard_private.shared_cards where fixture_id=new.fixture_id;
 if cards=0 then return new; end if;
 for locked_card in select * from scorecard_private.shared_cards where fixture_id=new.fixture_id order by id for update loop
  state:=public.shared_scorecard_state(locked_card.fixture_id,locked_card.rink_id);
  if (state->'shared'->>'sourceChanged')::boolean then raise exception 'Fixture details changed since scorecard review'; end if;
 end loop;
 select count(*) into rinks from public.fixture_rinks where fixture_id=new.fixture_id;
 select count(*),sum(total_a),sum(total_b) into agreed,a,b from scorecard_private.shared_cards c
 where c.fixture_id=new.fixture_id and c.phase in ('review','submitted') and c.document->>'finishedAt' is not null
 and (exists(select 1 from scorecard_private.shared_agreements x join public.member_profiles mp on mp.user_id=x.user_id
 join public.fixture_rink_assignments fa on fa.member_profile_id=mp.id and fa.fixture_rink_id=c.rink_id
 join public.fixture_rinks fr on fr.id=c.rink_id join public.club_memberships cm on cm.member_profile_id=mp.id
 where x.card_id=c.id and x.side='a' and x.version=c.version and fa.position between 1 and fr.players_per_rink and cm.club_id=(select club_id from public.fixtures where id=c.fixture_id) and cm.is_active and cm.role::text<>'guest') or exists(select 1 from scorecard_private.shared_agreements x
 where x.card_id=c.id and x.side='a' and x.version=c.version
 and x.method='same_device_signature' and x.user_id=c.owner_user_id
 and x.signer_name=c.document->'signatureA'->>'name'
 and jsonb_typeof(c.document->'signatureA'->'strokes')='array'))
 and (exists(select 1 from scorecard_private.shared_agreements x join public.member_profiles mp on mp.user_id=x.user_id
 join public.fixture_rink_assignments fa on fa.member_profile_id=mp.id and fa.fixture_rink_id=c.rink_id
 join public.fixture_rinks fr on fr.id=c.rink_id join public.club_memberships cm on cm.member_profile_id=mp.id
 where x.card_id=c.id and x.side='b' and x.version=c.version and fa.position between 101 and 100+fr.players_per_rink and cm.club_id=(select club_id from public.fixtures where id=c.fixture_id) and cm.is_active and cm.role::text<>'guest') or exists(select 1 from scorecard_private.shared_agreements x
 where x.card_id=c.id and x.side='b' and x.version=c.version
 and x.method='same_device_signature' and x.user_id=c.owner_user_id
 and x.signer_name=c.document->'signatureB'->>'name'
 and jsonb_typeof(c.document->'signatureB'->'strokes')='array'));
 if agreed<>rinks or cards<>rinks then raise exception 'Both sides must agree the latest finished shared scorecard on every rink'; end if;
 if new.score_a is distinct from a or new.score_b is distinct from b then raise exception 'Submitted scores must match the agreed shared scorecard'; end if;
 if a=b then raise exception 'Resolve the tied match before submitting'; end if;
 if coalesce(new.proposed_winner_entry_id,new.winner_entry_id) is distinct from (case when a>b then new.side_a_entry_id else new.side_b_entry_id end) then raise exception 'Winner must match the agreed scores'; end if;
 update scorecard_private.shared_cards set phase='submitted',submitted_at=coalesce(submitted_at,clock_timestamp()) where fixture_id=new.fixture_id;
 return new;
end $function$
;
CREATE OR REPLACE FUNCTION public.submit_shared_scorecard(p_fixture_id uuid, p_rink_id uuid, p_version bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor jsonb; c scorecard_private.shared_cards; m public.competition_draw_matches; winner uuid;
begin
 actor:=scorecard_private.shared_actor(p_fixture_id,p_rink_id);
 -- Match/bracket lock precedes card locks, consistently with Admin confirmation.
 select * into strict m from public.competition_draw_matches where fixture_id=p_fixture_id;
 perform 1 from public.club_competitions where id=m.competition_id for update;
 perform 1 from public.competition_draw_matches where id=m.id for update;
 select * into strict c from scorecard_private.shared_cards where fixture_id=p_fixture_id and rink_id=p_rink_id for update;
 if actor->>'side' is null and not(actor->>'admin')::boolean then raise exception 'A player or Club Admin submits the agreed result' using errcode='42501'; end if;
 if c.version<>p_version or c.phase<>'review' then raise exception 'Refresh the latest finished card'; end if;
 if (select count(*) from public.fixture_rinks where fixture_id=p_fixture_id)<>1 then raise exception 'Multi-rink submission requires combined review by Club Admin'; end if;
 if (public.shared_scorecard_state(p_fixture_id,p_rink_id)->'shared'->>'sourceChanged')::boolean then raise exception 'Fixture changed; ask Club Admin to review'; end if;
 winner:=case when c.total_a>c.total_b then m.side_a_entry_id else m.side_b_entry_id end;
 perform public.record_competition_result(m.id,c.total_a,c.total_b,winner,false);
 update scorecard_private.shared_cards set phase='submitted',submitted_at=clock_timestamp(),updated_at=clock_timestamp() where id=c.id;
 insert into scorecard_private.shared_events(card_id,actor_user_id,action,version) values(c.id,auth.uid(),'submitted',c.version);
 return public.shared_scorecard_state(p_fixture_id,p_rink_id);
end $function$
;