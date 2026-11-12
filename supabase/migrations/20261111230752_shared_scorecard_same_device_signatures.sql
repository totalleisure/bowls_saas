-- Additive signature acknowledgement; result submission and Admin confirmation remain separate.
alter table scorecard_private.shared_agreements add column method text not null default 'account_agreement'
 check(method in ('account_agreement','same_device_signature'));
alter table scorecard_private.shared_agreements add column signer_name text;

create function scorecard_private.checked_signature(p_signature jsonb,p_revision integer) returns jsonb
language plpgsql set search_path='' as $$
declare stroke jsonb; point jsonb; coordinate text; points integer:=0; drawn boolean:=false;
begin
 if jsonb_typeof(p_signature) is distinct from 'object'
 or jsonb_typeof(p_signature->'name') is distinct from 'string'
 or length(btrim(p_signature->>'name')) not between 1 and 150
 or jsonb_typeof(p_signature->'strokes') is distinct from 'array'
 or octet_length(p_signature::text)>500000
 then raise exception 'Enter a representative name and draw a signature for each side'; end if;
 for stroke in select value from jsonb_array_elements(p_signature->'strokes') loop
  if jsonb_typeof(stroke)<>'array' then raise exception 'Invalid signature stroke'; end if;
  if jsonb_array_length(stroke)>1 then drawn:=true; end if;
  for point in select value from jsonb_array_elements(stroke) loop
   points:=points+1;
   if points>10000 then raise exception 'Signature has too many points'; end if;
   foreach coordinate in array array['x','y'] loop
    if jsonb_typeof(point->coordinate) is distinct from 'number'
     or (point->>coordinate)::numeric not between 0 and 1 then raise exception 'Invalid signature coordinates'; end if;
   end loop;
  end loop;
 end loop;
 if not drawn then raise exception 'Draw a signature for each side'; end if;
 return jsonb_build_object('name',btrim(p_signature->>'name'),'at',clock_timestamp(),'revision',p_revision,'strokes',p_signature->'strokes');
end $$;
revoke all on function scorecard_private.checked_signature(jsonb,integer) from public,anon,authenticated;

create function public.sign_shared_scorecard_on_device(p_fixture_id uuid,p_rink_id uuid,p_version bigint,p_signature_a jsonb,p_signature_b jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor jsonb; c scorecard_private.shared_cards; state jsonb; sa jsonb; sb jsonb;
begin
 actor:=scorecard_private.shared_actor(p_fixture_id,p_rink_id);
 select * into strict c from scorecard_private.shared_cards where fixture_id=p_fixture_id and rink_id=p_rink_id for update;
 if auth.uid() is null or c.owner_user_id<>auth.uid() or not coalesce((actor->>'canKeep')::boolean,false)
 then raise exception 'Only the designated scorer may collect both signatures' using errcode='42501'; end if;
 state:=public.shared_scorecard_state(p_fixture_id,p_rink_id);
 if p_version is null or c.version<>p_version or c.phase<>'review' or c.submitted_at is not null
 or c.document->>'finishedAt' is null or (state->'shared'->>'sourceChanged')::boolean
 or exists(select 1 from public.competition_draw_matches where fixture_id=p_fixture_id and status in ('result_pending','completed'))
 then raise exception 'Refresh and review the latest finished card before signing'; end if;
 sa:=scorecard_private.checked_signature(p_signature_a,coalesce((c.document->>'revision')::integer,0));
 sb:=scorecard_private.checked_signature(p_signature_b,coalesce((c.document->>'revision')::integer,0));
 if lower(sa->>'name')=lower(sb->>'name') then raise exception 'A different representative must sign for each side'; end if;
 update scorecard_private.shared_cards set document=document||jsonb_build_object('signatureA',sa,'signatureB',sb),
 version=version+1,updated_at=clock_timestamp() where id=c.id returning * into c;
 insert into scorecard_private.shared_agreements(card_id,side,version,user_id,method,signer_name)
 values(c.id,'a',c.version,auth.uid(),'same_device_signature',sa->>'name'),
       (c.id,'b',c.version,auth.uid(),'same_device_signature',sb->>'name')
 on conflict(card_id,side) do update set version=excluded.version,user_id=excluded.user_id,
 agreed_at=clock_timestamp(),method=excluded.method,signer_name=excluded.signer_name;
 insert into scorecard_private.shared_events(card_id,actor_user_id,action,version,details)
 values(c.id,auth.uid(),'signed_on_one_device',c.version,jsonb_build_object('signatureA',sa,'signatureB',sb,
 'totalA',c.total_a,'totalB',c.total_b,'documentHash',md5(c.document::text)));
 return public.shared_scorecard_state(p_fixture_id,p_rink_id);
end $$;
revoke all on function public.sign_shared_scorecard_on_device(uuid,uuid,bigint,jsonb,jsonb) from public,anon;
grant execute on function public.sign_shared_scorecard_on_device(uuid,uuid,bigint,jsonb,jsonb) to authenticated;
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
end $function$;

CREATE OR REPLACE FUNCTION public.sync_shared_scorecard(p_fixture_id uuid, p_rink_id uuid, p_writer_token uuid, p_sequence bigint, p_document jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c scorecard_private.shared_cards; state jsonb; totals integer[]; doc jsonb; k text;
begin
 perform scorecard_private.shared_actor(p_fixture_id,p_rink_id);
 select * into strict c from scorecard_private.shared_cards where fixture_id=p_fixture_id and rink_id=p_rink_id for update;
 if c.owner_user_id<>auth.uid() or c.writer_token is distinct from p_writer_token then raise exception 'Only the designated scorer on the claiming device may upload' using errcode='42501'; end if;
 if p_sequence<=c.sequence then return public.shared_scorecard_state(p_fixture_id,p_rink_id); end if;
 if c.phase='submitted' or c.submitted_at is not null or exists(select 1 from public.competition_draw_matches where fixture_id=p_fixture_id and status in ('result_pending','completed')) then raise exception 'Submitted scorecard is locked'; end if;
 state:=public.shared_scorecard_state(p_fixture_id,p_rink_id);
 if (state->'shared'->>'sourceChanged')::boolean then raise exception 'Fixture details changed. Ask Club Admin to review before continuing'; end if;
 doc:=jsonb_set(p_document-'saveVersion','{fixtureLink}',c.document->'fixtureLink');
 for k in select unnest(array['id','title','date','venue','rink','format','sideA','sideB','playersA','playersB','marker']) loop
  if doc->k is distinct from c.document->k then raise exception 'Shared card identity cannot change: %',k; end if;
 end loop;
 if c.document->>'startedAt' is not null then
  for k in select unnest(array['startedAt','scoring','woods','handicapA','handicapB','target','maxEnds','durationMinutes','lastJackMinutes']) loop
   if doc->k is distinct from c.document->k then raise exception 'Started match conditions cannot change: %',k; end if;
  end loop;
 end if;
 if c.document->>'finishedAt' is not null and doc->>'finishedAt' is null then raise exception 'Reopen online before editing an agreed card'; end if;
 if c.phase='correction_requested' then raise exception 'Reopen the card online to address the correction request'; end if;
 totals:=scorecard_private.validate_shared_document(doc);
 -- Uploaded documents cannot manufacture agreements or replace server-captured signatures.
 doc:=doc||jsonb_build_object('signatureA',null,'signatureB',null);
 if (doc-'signatureA'-'signatureB') is distinct from (c.document-'signatureA'-'signatureB') then
  delete from scorecard_private.shared_agreements where card_id=c.id;
  update scorecard_private.shared_cards set document=doc,sequence=p_sequence,version=version+1,
  total_a=totals[1],total_b=totals[2],phase=case when doc->>'finishedAt' is null then 'playing' else 'review' end,
  updated_at=clock_timestamp(),correction_note=null where id=c.id;
  insert into scorecard_private.shared_events(card_id,actor_user_id,action,version,details)
  select id,auth.uid(),'uploaded',version,jsonb_build_object('sequence',p_sequence,'totalA',total_a,'totalB',total_b,'phase',phase) from scorecard_private.shared_cards where id=c.id;
 else
  update scorecard_private.shared_cards set sequence=p_sequence where id=c.id;
 end if;
 return public.shared_scorecard_state(p_fixture_id,p_rink_id);
end $function$;

CREATE OR REPLACE FUNCTION public.reopen_shared_scorecard(p_fixture_id uuid, p_rink_id uuid, p_writer_token uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c scorecard_private.shared_cards;
begin
 perform scorecard_private.shared_actor(p_fixture_id,p_rink_id);
 select * into strict c from scorecard_private.shared_cards where fixture_id=p_fixture_id and rink_id=p_rink_id for update;
 if c.owner_user_id<>auth.uid() or c.writer_token is distinct from p_writer_token then raise exception 'Only the designated scorer may reopen' using errcode='42501'; end if;
 if c.submitted_at is not null then raise exception 'Result already submitted. Ask Club Admin to resolve it'; end if;
 delete from scorecard_private.shared_agreements where card_id=c.id;
 update scorecard_private.shared_cards set document=jsonb_set(document,'{finishedAt}','null'::jsonb)||jsonb_build_object('signatureA',null,'signatureB',null),
 phase='playing',correction_note=null,version=version+1,updated_at=clock_timestamp() where id=c.id;
 insert into scorecard_private.shared_events(card_id,actor_user_id,action,version) values(c.id,auth.uid(),'reopened',c.version+1);
 return public.shared_scorecard_state(p_fixture_id,p_rink_id);
end $function$;

CREATE OR REPLACE FUNCTION public.request_shared_scorecard_correction(p_fixture_id uuid, p_rink_id uuid, p_version bigint, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor jsonb; c scorecard_private.shared_cards;
begin
 actor:=scorecard_private.shared_actor(p_fixture_id,p_rink_id);
 if actor->>'side' is null then raise exception 'Only a player may request a correction' using errcode='42501'; end if;
 if length(btrim(coalesce(p_note,''))) not between 1 and 1000 then raise exception 'Enter a correction explanation (up to 1000 characters)'; end if;
 select * into strict c from scorecard_private.shared_cards where fixture_id=p_fixture_id and rink_id=p_rink_id for update;
 if c.version<>p_version or c.phase not in ('review','correction_requested') then raise exception 'Refresh the latest finished card'; end if;
 delete from scorecard_private.shared_agreements where card_id=c.id;
 update scorecard_private.shared_cards set document=document||jsonb_build_object('signatureA',null,'signatureB',null),phase='correction_requested',correction_note=btrim(p_note),version=version+1,updated_at=clock_timestamp() where id=c.id;
 insert into scorecard_private.shared_events(card_id,actor_user_id,action,version,details) values(c.id,auth.uid(),'correction_requested',c.version+1,jsonb_build_object('note',btrim(p_note)));
 return public.shared_scorecard_state(p_fixture_id,p_rink_id);
end $function$;

CREATE OR REPLACE FUNCTION public.return_shared_scorecard_for_correction(p_fixture_id uuid, p_rink_id uuid, p_version bigint, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 update scorecard_private.shared_cards set document=document||jsonb_build_object('signatureA',null,'signatureB',null),phase='correction_requested',submitted_at=null,version=version+1,
 correction_note='Admin: '||btrim(p_note),updated_at=clock_timestamp() where fixture_id=p_fixture_id;
 insert into scorecard_private.shared_events(card_id,actor_user_id,action,version,details)
 select id,auth.uid(),'admin_returned',version,jsonb_build_object('note',btrim(p_note)) from scorecard_private.shared_cards where fixture_id=p_fixture_id;
 return public.shared_scorecard_state(p_fixture_id,p_rink_id);
end $function$;
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
end $function$;

