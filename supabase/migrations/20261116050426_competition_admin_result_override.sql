begin;
do $$ begin if (select md5(replace(pg_get_functiondef(oid),chr(13),'')) from pg_proc where pronamespace='scorecard_private'::regnamespace and proname='guard_shared_result') <> '9267541d408b46ba00e21b6ca7e7965a' then raise exception 'Unexpected guard_shared_result definition'; end if; end $$;
do $$ begin if (select md5(replace(pg_get_functiondef(oid),chr(13),'')) from pg_proc where pronamespace='public'::regnamespace and proname='shared_scorecard_state') <> '00c0fa49558e6ad2d48d5dc5bd7e672b' then raise exception 'Unexpected shared_scorecard_state definition'; end if; end $$;
do $$ begin if (select md5(replace(pg_get_functiondef(oid),chr(13),'')) from pg_proc where pronamespace='public'::regnamespace and proname='record_competition_result') <> '9b8cf29c8e01c97058ae02b3d1ed362a' then raise exception 'Unexpected record_competition_result definition'; end if; end $$;

create table competition_private.admin_result_decisions (
 id uuid primary key default gen_random_uuid(), match_id uuid not null,
 actor_user_id uuid not null, reason text not null check(length(btrim(reason)) between 1 and 1000),
 score_a integer not null check(score_a>=0), score_b integer not null check(score_b>=0), winner_entry_id uuid not null,
 evidence jsonb not null, decided_at timestamptz not null default clock_timestamp(),
 backend_pid integer not null default pg_backend_pid(), transaction_id bigint not null default txid_current(),
 active boolean not null default true
);
alter table competition_private.admin_result_decisions enable row level security;
revoke all on competition_private.admin_result_decisions from public,anon,authenticated,service_role;
create index admin_result_decisions_match_idx on competition_private.admin_result_decisions(match_id,decided_at desc);

create function competition_private.result_review_snapshot(p_match_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('match',to_jsonb(m),
 'cards',coalesce((select jsonb_agg(to_jsonb(c)-'writer_token' order by c.id) from scorecard_private.shared_cards c where c.fixture_id=m.fixture_id),'[]'::jsonb),
 'agreements',coalesce((select jsonb_agg(to_jsonb(a) order by a.card_id,a.side) from scorecard_private.shared_agreements a join scorecard_private.shared_cards c on c.id=a.card_id where c.fixture_id=m.fixture_id),'[]'::jsonb))
 from public.competition_draw_matches m where m.id=p_match_id;
$$;
revoke all on function competition_private.result_review_snapshot(uuid) from public,anon,authenticated,service_role;

create function public.competition_admin_result_review(p_match_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s jsonb; club uuid;
begin
 select c.club_id into club from public.competition_draw_matches m join public.club_competitions c on c.id=m.competition_id where m.id=p_match_id;
 if auth.uid() is null or not coalesce(competition_private.can_manage(club),false) then raise exception 'Competition administrator access required' using errcode='42501'; end if;
 s:=competition_private.result_review_snapshot(p_match_id);
 return jsonb_build_object('token',md5(s::text),'match',s->'match','hasShared',jsonb_array_length(s->'cards')>0,
 'cardStates',(select coalesce(jsonb_agg(jsonb_build_object('phase',x->>'phase','version',x->'version','totalA',x->'total_a','totalB',x->'total_b')),'[]'::jsonb) from jsonb_array_elements(s->'cards') x));
end $$;
revoke all on function public.competition_admin_result_review(uuid) from public,anon,authenticated,service_role;
grant execute on function public.competition_admin_result_review(uuid) to authenticated;

create function public.confirm_competition_admin_result(p_match_id uuid,p_score_a integer,p_score_b integer,p_winner_entry_id uuid,p_reason text,p_review_token text) returns void
language plpgsql security definer set search_path='' as $$
declare m public.competition_draw_matches; club uuid; cid uuid; s jsonb; decision uuid;
begin
 select c.id,c.club_id into cid,club from public.competition_draw_matches d join public.club_competitions c on c.id=d.competition_id where d.id=p_match_id;
 if auth.uid() is null or not coalesce(competition_private.can_manage(club),false) then raise exception 'Competition administrator access required' using errcode='42501'; end if;
 perform 1 from public.club_competitions where id=cid for update;
 select * into strict m from public.competition_draw_matches where id=p_match_id for update;
 perform 1 from scorecard_private.shared_cards where fixture_id=m.fixture_id order by id for update;
 s:=competition_private.result_review_snapshot(p_match_id);
 if p_review_token is null or md5(s::text)<>p_review_token then raise exception 'The result or scorecard changed. Close this decision and review the latest match.'; end if;
 if m.status not in ('to_be_arranged','result_pending') or m.side_a_entry_id is null or m.side_b_entry_id is null then raise exception 'Only an unconfirmed playable match can receive an Admin decision'; end if;
 if length(btrim(coalesce(p_reason,''))) not between 1 and 1000 then raise exception 'Enter the reason for the Admin decision'; end if;
 if p_score_a is null or p_score_b is null or p_score_a<0 or p_score_b<0 or p_score_a=p_score_b
 or p_winner_entry_id is distinct from (case when p_score_a>p_score_b then m.side_a_entry_id else m.side_b_entry_id end) then raise exception 'Enter valid final scores and select the entry with the higher score'; end if;
 if exists(select 1 from public.competition_draw_matches d where (d.side_a_source_id=m.id or d.side_b_source_id=m.id) and (d.status<>'to_be_arranged' or d.fixture_id is not null)) then raise exception 'The next round already has activity. Review progression before changing this result'; end if;
 insert into competition_private.admin_result_decisions(match_id,actor_user_id,reason,score_a,score_b,winner_entry_id,evidence)
 values(m.id,auth.uid(),btrim(p_reason),p_score_a,p_score_b,p_winner_entry_id,s) returning id into decision;
 -- Use the normal result/advancement path and its existing next-round communications.
 perform public.record_competition_result(m.id,p_score_a,p_score_b,p_winner_entry_id,false);
 perform public.record_competition_result(m.id,p_score_a,p_score_b,p_winner_entry_id,true);
 -- Lock the original card as evidence; do not invent signatures or rewrite ends/totals.
 update scorecard_private.shared_cards set phase='submitted',submitted_at=coalesce(submitted_at,clock_timestamp()),updated_at=clock_timestamp() where fixture_id=m.fixture_id;
 insert into scorecard_private.shared_events(card_id,actor_user_id,action,version,details)
 select id,auth.uid(),'admin_result_decision',version,jsonb_build_object('decisionId',decision,'reason',btrim(p_reason),'drawScoreA',p_score_a,'drawScoreB',p_score_b,'winnerEntryId',p_winner_entry_id)
 from scorecard_private.shared_cards where fixture_id=m.fixture_id;
 update competition_private.admin_result_decisions set active=false where id=decision;
end $$;
revoke all on function public.confirm_competition_admin_result(uuid,integer,integer,uuid,text,text) from public,anon,authenticated,service_role;
grant execute on function public.confirm_competition_admin_result(uuid,integer,integer,uuid,text,text) to authenticated;
CREATE OR REPLACE FUNCTION scorecard_private.guard_shared_result()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cards integer; rinks integer; agreed integer; a integer; b integer; locked_card scorecard_private.shared_cards; state jsonb;
begin
 -- Only an audited Admin RPC can bypass shared agreement, for its exact result in this transaction.
 if exists(select 1 from competition_private.admin_result_decisions d
 where d.match_id=new.id and d.active and d.backend_pid=pg_backend_pid() and d.transaction_id=txid_current()
 and d.actor_user_id=auth.uid() and coalesce(competition_private.can_manage((select club_id from public.club_competitions where id=new.competition_id)),false)
 and d.score_a=new.score_a and d.score_b=new.score_b
 and d.winner_entry_id=coalesce(new.proposed_winner_entry_id,new.winner_entry_id)) then return new; end if;
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
 'adminDecision',(select jsonb_build_object('reason',d.reason,'decidedAt',d.decided_at,'scoreA',d.score_a,'scoreB',d.score_b,'winnerName',e.name,
 'sideAName',(select name from public.competition_entries where id=m.side_a_entry_id),'sideBName',(select name from public.competition_entries where id=m.side_b_entry_id))
 from competition_private.admin_result_decisions d join public.competition_draw_matches m on m.id=d.match_id
 join public.competition_entries e on e.id=d.winner_entry_id where m.fixture_id=p_fixture_id and not d.active order by d.decided_at desc limit 1),
 'competitionStatus',(select status from public.competition_draw_matches where fixture_id=p_fixture_id)));
end $function$
;
notify pgrst,'reload schema';
commit;
