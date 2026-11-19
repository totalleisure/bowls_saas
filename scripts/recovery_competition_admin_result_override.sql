begin;
-- Restore function definitions before removing the new override functions/tables.
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
 select count(*),sum(case when scorecard_private.fixture_a_is_draw_a(c.fixture_id,c.rink_id) then c.total_a else c.total_b end),sum(case when scorecard_private.fixture_a_is_draw_a(c.fixture_id,c.rink_id) then c.total_b else c.total_a end) into agreed,a,b from scorecard_private.shared_cards c
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
CREATE OR REPLACE FUNCTION public.shared_scorecard_state(p_fixture_id uuid, p_rink_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor jsonb; c scorecard_private.shared_cards; context jsonb; rink jsonb; a boolean; b boolean;
begin
 actor:=scorecard_private.shared_actor(p_fixture_id,p_rink_id);
 context:=public.fixture_scorecard_context(p_fixture_id);
 select value into rink from jsonb_array_elements(context->'rinks') where value->>'fixtureRinkId'=p_rink_id::text;
 select * into c from scorecard_private.shared_cards where rink_id=p_rink_id;
 if c.id is null then return jsonb_build_object('actor',actor,'snapshot',rink->'snapshot','fingerprint',rink->>'sourceFingerprint','shared',null); end if;
 select exists(select 1 from scorecard_private.shared_agreements where card_id=c.id and side='a' and version=c.version),
 exists(select 1 from scorecard_private.shared_agreements where card_id=c.id and side='b' and version=c.version) into a,b;
 return jsonb_build_object('actor',actor,'snapshot',rink->'snapshot','fingerprint',rink->>'sourceFingerprint',
 'shared',jsonb_build_object('id',c.id,'ownerUserId',c.owner_user_id,
 'ownerName',(select coalesce(nullif(btrim(first_name||' '||last_name),''),display_name,'Scorer') from public.member_profiles where user_id=c.owner_user_id limit 1),
 'document',c.document,'version',c.version,'sequence',c.sequence,'phase',c.phase,'totalA',c.total_a,'totalB',c.total_b,
 'agreedA',a,'agreedB',b,'signedOnOneDevice',a and b and exists(select 1 from scorecard_private.shared_agreements where card_id=c.id and version=c.version and method='same_device_signature'),'updatedAt',c.updated_at,'submittedAt',c.submitted_at,'correctionNote',c.correction_note,
 'sourceChanged',c.source_fingerprint is distinct from rink->>'sourceFingerprint','isOwner',c.owner_user_id=auth.uid(),
 'competitionStatus',(select status from public.competition_draw_matches where fixture_id=p_fixture_id)));
end $function$
;

revoke execute on function public.confirm_competition_admin_result(uuid,integer,integer,uuid,text,text), public.competition_admin_result_review(uuid) from authenticated;
commit;
-- Audit evidence deliberately retained in competition_private.admin_result_decisions.
