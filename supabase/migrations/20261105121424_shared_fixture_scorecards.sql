-- Additive official shared cards. Legacy local cards and setup RPCs remain intact.
create table scorecard_private.shared_cards (
 id uuid primary key default gen_random_uuid(),
 fixture_id uuid not null references public.fixtures(id) on delete cascade,
 rink_id uuid not null unique references public.fixture_rinks(id) on delete cascade,
 owner_user_id uuid not null references auth.users(id),
 writer_token uuid not null,
 source_fingerprint text not null,
 document jsonb not null,
 sequence bigint not null default 0,
 version bigint not null default 1,
 total_a integer not null default 0,
 total_b integer not null default 0,
 phase text not null default 'playing' check(phase in ('playing','review','correction_requested','submitted')),
 correction_note text,
 updated_at timestamptz not null default clock_timestamp(),
 submitted_at timestamptz
);
create table scorecard_private.shared_agreements (
 card_id uuid not null references scorecard_private.shared_cards(id) on delete cascade,
 side text not null check(side in ('a','b')),
 version bigint not null,
 user_id uuid not null references auth.users(id),
 agreed_at timestamptz not null default clock_timestamp(),
 primary key(card_id,side)
);
create table scorecard_private.shared_events (
 id bigint generated always as identity primary key,
 card_id uuid not null references scorecard_private.shared_cards(id) on delete cascade,
 actor_user_id uuid not null,
 action text not null,
 version bigint not null,
 recorded_at timestamptz not null default clock_timestamp(),
 details jsonb not null default '{}'
);
alter table scorecard_private.shared_cards enable row level security;
alter table scorecard_private.shared_agreements enable row level security;
alter table scorecard_private.shared_events enable row level security;
revoke all on scorecard_private.shared_cards,scorecard_private.shared_agreements,scorecard_private.shared_events from public,anon,authenticated;

create function scorecard_private.shared_actor(p_fixture uuid,p_rink uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare f public.fixtures; r public.fixture_rinks; member uuid; side_a boolean; side_b boolean; marker boolean; admin boolean;
begin
 f:=scorecard_private.require_member_fixture(p_fixture);
 select * into strict r from public.fixture_rinks where id=p_rink and fixture_id=f.id;
 member:=public.my_member_profile_id();
 select coalesce(bool_or(position between 1 and r.players_per_rink),false),
 coalesce(bool_or(position between 101 and 100+r.players_per_rink),false),
 coalesce(bool_or(position=201),false) into side_a,side_b,marker
 from public.fixture_rink_assignments where fixture_id=f.id and fixture_rink_id=r.id and member_profile_id=member;
 admin:=coalesce(public.is_app_superuser() or public.is_club_admin(f.club_id),false);
 if not(side_a or side_b or marker or admin) then raise exception 'Only this rink''s players, marker or Club Admin may open its shared card' using errcode='42501'; end if;
 if f.cancelled_at is not null or f.archived_at is not null then raise exception 'This fixture is cancelled or archived'; end if;
 return jsonb_build_object('userId',auth.uid(),'side',case when side_a and not side_b then 'a' when side_b and not side_a then 'b' else null end,
 'marker',marker,'admin',admin,'canKeep',side_a or side_b or marker,
 'available',(now() at time zone 'Europe/London')::date >= (f.start_at at time zone 'Europe/London')::date);
end $$;

create function scorecard_private.validate_shared_document(p_doc jsonb) returns integer[]
language plpgsql set search_path='' as $$
declare a integer; b integer; e jsonb; k text; n numeric; v integer; count_ends integer:=0; incomplete boolean:=false;
begin
 if jsonb_typeof(p_doc) is distinct from 'object' or p_doc->>'schema' is distinct from '1'
 or jsonb_typeof(p_doc->'ends') is distinct from 'array' or octet_length(p_doc::text)>2000000
 or coalesce(p_doc->>'scoring','') not in ('shots','100up') then raise exception 'Invalid shared scorecard'; end if;
 for k in select unnest(array['handicapA','handicapB','woods','maxEnds','target','durationMinutes','lastJackMinutes']) loop
  if p_doc->k is not null and p_doc->k<>'null'::jsonb then
   if jsonb_typeof(p_doc->k)<>'number' then raise exception 'Invalid numeric condition: %',k; end if;
   n:=(p_doc->>k)::numeric;
   if n<>trunc(n) or abs(n)>10000 or (k not in ('handicapA','handicapB') and n<=0) then raise exception 'Invalid condition: %',k; end if;
  end if;
 end loop;
 if (p_doc->>'lastJackMinutes')::integer>(p_doc->>'durationMinutes')::integer then raise exception 'Last jack exceeds match duration'; end if;
 a:=coalesce((p_doc->>'handicapA')::integer,0); b:=coalesce((p_doc->>'handicapB')::integer,0);
 for e in select value from jsonb_array_elements(p_doc->'ends') loop
  count_ends:=count_ends+1;
  if incomplete then raise exception 'An unscored end must be last'; end if;
  if e->>'a' is null or e->>'b' is null then
   if e->>'a' is not null or e->>'b' is not null then raise exception 'Incomplete end scores'; end if;
   incomplete:=true;
  else
   for k in select unnest(array['a','b']) loop
    if jsonb_typeof(e->k)<>'number' then raise exception 'Invalid end score'; end if;
    n:=(e->>k)::numeric;
    if n<>trunc(n) or n<0 or n>1000 then raise exception 'Invalid end score'; end if;
   end loop;
   if p_doc->>'scoring'='shots' and (e->>'a')::int>0 and (e->>'b')::int>0 then raise exception 'Only one side scores normal shots'; end if;
   if p_doc->>'scoring'='100up' and (e->>'a')::int+(e->>'b')::int<>10 then raise exception '100 Up must total ten'; end if;
   a:=a+(e->>'a')::integer; b:=b+(e->>'b')::integer;
  end if;
 end loop;
 if count_ends>1000 then raise exception 'Too many ends'; end if;
 if p_doc->>'finishedAt' is not null and (incomplete or count_ends=0 or p_doc->>'startedAt' is null) then raise exception 'Finish requires scored ends'; end if;
 return array[a,b];
end $$;

create function public.shared_scorecard_state(p_fixture_id uuid,p_rink_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
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
 'agreedA',a,'agreedB',b,'updatedAt',c.updated_at,'submittedAt',c.submitted_at,'correctionNote',c.correction_note,
 'sourceChanged',c.source_fingerprint is distinct from rink->>'sourceFingerprint','isOwner',c.owner_user_id=auth.uid(),
 'competitionStatus',(select status from public.competition_draw_matches where fixture_id=p_fixture_id)));
end $$;

create function public.claim_shared_scorecard(p_fixture_id uuid,p_rink_id uuid,p_fingerprint text,p_writer_token uuid,p_document jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor jsonb; state jsonb; c scorecard_private.shared_cards; doc jsonb; totals integer[];
begin
 perform pg_advisory_xact_lock(hashtextextended(p_rink_id::text,75205));
 actor:=scorecard_private.shared_actor(p_fixture_id,p_rink_id);
 if not (actor->>'canKeep')::boolean or not(actor->>'available')::boolean then raise exception 'A selected player or marker may claim the card from fixture day' using errcode='42501'; end if;
 if exists(select 1 from public.competition_draw_matches where fixture_id=p_fixture_id and status in ('result_pending','completed','bye')) then raise exception 'This competition match already has a submitted or completed result'; end if;
 select * into c from scorecard_private.shared_cards where rink_id=p_rink_id for update;
 if c.id is not null then
  if c.owner_user_id=auth.uid() and c.writer_token=p_writer_token then return public.shared_scorecard_state(p_fixture_id,p_rink_id); end if;
  raise exception 'This match already has a designated scorer. Open the shared card to review it.';
 end if;
 state:=public.shared_scorecard_state(p_fixture_id,p_rink_id);
 if p_fingerprint is distinct from state->>'fingerprint' then raise exception 'Fixture changed. Refresh and review again'; end if;
 if p_writer_token is null or jsonb_array_length(p_document->'ends')<>0 or p_document->>'startedAt' is not null or p_document->>'finishedAt' is not null then raise exception 'Claim with a fresh unstarted card'; end if;
 doc:=jsonb_set(p_document-'saveVersion','{fixtureLink}',state->'snapshot');
 totals:=scorecard_private.validate_shared_document(doc);
 insert into scorecard_private.shared_cards(fixture_id,rink_id,owner_user_id,writer_token,source_fingerprint,document,total_a,total_b)
 values(p_fixture_id,p_rink_id,auth.uid(),p_writer_token,p_fingerprint,doc,totals[1],totals[2]) returning * into c;
 insert into scorecard_private.shared_events(card_id,actor_user_id,action,version) values(c.id,auth.uid(),'claimed',c.version);
 return public.shared_scorecard_state(p_fixture_id,p_rink_id);
end $$;

create function public.sync_shared_scorecard(p_fixture_id uuid,p_rink_id uuid,p_writer_token uuid,p_sequence bigint,p_document jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
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
 if doc is distinct from c.document then
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
end $$;

create function public.agree_shared_scorecard(p_fixture_id uuid,p_rink_id uuid,p_version bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor jsonb; c scorecard_private.shared_cards; actor_side text; state jsonb;
begin
 actor:=scorecard_private.shared_actor(p_fixture_id,p_rink_id); actor_side:=actor->>'side';
 if actor_side is null then raise exception 'Only a player may agree for their own side; markers and Admins cannot substitute' using errcode='42501'; end if;
 select * into strict c from scorecard_private.shared_cards where fixture_id=p_fixture_id and rink_id=p_rink_id for update;
 state:=public.shared_scorecard_state(p_fixture_id,p_rink_id);
 if c.version<>p_version or c.phase<>'review' or (state->'shared'->>'sourceChanged')::boolean then raise exception 'Review the latest finished card before agreeing'; end if;
 if exists(select 1 from scorecard_private.shared_agreements where card_id=c.id and side<>actor_side and user_id=auth.uid()) then raise exception 'Different representatives must agree for the two sides'; end if;
 insert into scorecard_private.shared_agreements(card_id,side,version,user_id) values(c.id,actor_side,c.version,auth.uid())
 on conflict(card_id,side) do update set version=excluded.version,user_id=excluded.user_id,agreed_at=clock_timestamp();
 insert into scorecard_private.shared_events(card_id,actor_user_id,action,version,details) values(c.id,auth.uid(),'agreed',c.version,jsonb_build_object('side',actor_side));
 return public.shared_scorecard_state(p_fixture_id,p_rink_id);
end $$;

create function public.request_shared_scorecard_correction(p_fixture_id uuid,p_rink_id uuid,p_version bigint,p_note text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor jsonb; c scorecard_private.shared_cards;
begin
 actor:=scorecard_private.shared_actor(p_fixture_id,p_rink_id);
 if actor->>'side' is null then raise exception 'Only a player may request a correction' using errcode='42501'; end if;
 if length(btrim(coalesce(p_note,''))) not between 1 and 1000 then raise exception 'Enter a correction explanation (up to 1000 characters)'; end if;
 select * into strict c from scorecard_private.shared_cards where fixture_id=p_fixture_id and rink_id=p_rink_id for update;
 if c.version<>p_version or c.phase not in ('review','correction_requested') then raise exception 'Refresh the latest finished card'; end if;
 delete from scorecard_private.shared_agreements where card_id=c.id;
 update scorecard_private.shared_cards set phase='correction_requested',correction_note=btrim(p_note),version=version+1,updated_at=clock_timestamp() where id=c.id;
 insert into scorecard_private.shared_events(card_id,actor_user_id,action,version,details) values(c.id,auth.uid(),'correction_requested',c.version+1,jsonb_build_object('note',btrim(p_note)));
 return public.shared_scorecard_state(p_fixture_id,p_rink_id);
end $$;

create function public.reopen_shared_scorecard(p_fixture_id uuid,p_rink_id uuid,p_writer_token uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c scorecard_private.shared_cards;
begin
 perform scorecard_private.shared_actor(p_fixture_id,p_rink_id);
 select * into strict c from scorecard_private.shared_cards where fixture_id=p_fixture_id and rink_id=p_rink_id for update;
 if c.owner_user_id<>auth.uid() or c.writer_token is distinct from p_writer_token then raise exception 'Only the designated scorer may reopen' using errcode='42501'; end if;
 if c.submitted_at is not null then raise exception 'Result already submitted. Ask Club Admin to resolve it'; end if;
 delete from scorecard_private.shared_agreements where card_id=c.id;
 update scorecard_private.shared_cards set document=jsonb_set(document,'{finishedAt}','null'::jsonb),
 phase='playing',correction_note=null,version=version+1,updated_at=clock_timestamp() where id=c.id;
 insert into scorecard_private.shared_events(card_id,actor_user_id,action,version) values(c.id,auth.uid(),'reopened',c.version+1);
 return public.shared_scorecard_state(p_fixture_id,p_rink_id);
end $$;

-- Guard the existing submission/confirmation path, including older clients.
create function scorecard_private.guard_shared_result() returns trigger
language plpgsql security definer set search_path='' as $$
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
 and exists(select 1 from scorecard_private.shared_agreements x join public.member_profiles mp on mp.user_id=x.user_id
 join public.fixture_rink_assignments fa on fa.member_profile_id=mp.id and fa.fixture_rink_id=c.rink_id
 join public.fixture_rinks fr on fr.id=c.rink_id join public.club_memberships cm on cm.member_profile_id=mp.id
 where x.card_id=c.id and x.side='a' and x.version=c.version and fa.position between 1 and fr.players_per_rink and cm.club_id=(select club_id from public.fixtures where id=c.fixture_id) and cm.is_active and cm.role::text<>'guest')
 and exists(select 1 from scorecard_private.shared_agreements x join public.member_profiles mp on mp.user_id=x.user_id
 join public.fixture_rink_assignments fa on fa.member_profile_id=mp.id and fa.fixture_rink_id=c.rink_id
 join public.fixture_rinks fr on fr.id=c.rink_id join public.club_memberships cm on cm.member_profile_id=mp.id
 where x.card_id=c.id and x.side='b' and x.version=c.version and fa.position between 101 and 100+fr.players_per_rink and cm.club_id=(select club_id from public.fixtures where id=c.fixture_id) and cm.is_active and cm.role::text<>'guest');
 if agreed<>rinks or cards<>rinks then raise exception 'Both sides must agree the latest finished shared scorecard on every rink'; end if;
 if new.score_a is distinct from a or new.score_b is distinct from b then raise exception 'Submitted scores must match the agreed shared scorecard'; end if;
 if a=b then raise exception 'Resolve the tied match before submitting'; end if;
 if coalesce(new.proposed_winner_entry_id,new.winner_entry_id) is distinct from (case when a>b then new.side_a_entry_id else new.side_b_entry_id end) then raise exception 'Winner must match the agreed scores'; end if;
 update scorecard_private.shared_cards set phase='submitted',submitted_at=coalesce(submitted_at,clock_timestamp()) where fixture_id=new.fixture_id;
 return new;
end $$;
create trigger shared_scorecard_result_guard before insert or update on public.competition_draw_matches
for each row execute function scorecard_private.guard_shared_result();

create function public.submit_shared_scorecard(p_fixture_id uuid,p_rink_id uuid,p_version bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
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
end $$;

revoke all on all functions in schema scorecard_private from public,anon,authenticated;
revoke all on function public.shared_scorecard_state(uuid,uuid),public.claim_shared_scorecard(uuid,uuid,text,uuid,jsonb),
public.sync_shared_scorecard(uuid,uuid,uuid,bigint,jsonb),public.agree_shared_scorecard(uuid,uuid,bigint),
public.request_shared_scorecard_correction(uuid,uuid,bigint,text),public.reopen_shared_scorecard(uuid,uuid,uuid),
public.submit_shared_scorecard(uuid,uuid,bigint) from public,anon;
grant execute on function public.shared_scorecard_state(uuid,uuid),public.claim_shared_scorecard(uuid,uuid,text,uuid,jsonb),
public.sync_shared_scorecard(uuid,uuid,uuid,bigint,jsonb),public.agree_shared_scorecard(uuid,uuid,bigint),
public.request_shared_scorecard_correction(uuid,uuid,bigint,text),public.reopen_shared_scorecard(uuid,uuid,uuid),
public.submit_shared_scorecard(uuid,uuid,bigint) to authenticated;

-- Expose the shared workflow and include assigned markers.
create or replace function public.fixture_scorecard_context(p_fixture_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare f public.fixtures; actor uuid; admin boolean; result jsonb; rules jsonb; match_record record;
begin
 f:=scorecard_private.require_member_fixture(p_fixture_id);
 actor:=public.my_member_profile_id();
 admin:=public.is_app_superuser() or public.is_club_admin(f.club_id);
 select m.id,m.competition_id,m.round_id,c.name competition_name,r.name round_name,r.play_by,c.settings||r.rule_overrides settings
 into match_record from public.competition_draw_matches m
 join public.club_competitions c on c.id=m.competition_id
 join public.competition_rounds r on r.id=m.round_id where m.fixture_id=f.id;
 rules:=coalesce(match_record.settings,'{}'::jsonb);
 with rinks as (
  select fr.*,coalesce((
    select jsonb_agg(jsonb_build_object('memberId',a.member_profile_id,'position',a.position,
      'name',coalesce(nullif(btrim(a.display_name),''),nullif(btrim(mp.first_name||' '||mp.last_name),''),mp.display_name,'Unnamed player')) order by a.position)
    from public.fixture_rink_assignments a left join public.member_profiles mp on mp.id=a.member_profile_id
    where a.fixture_rink_id=fr.id and a.fixture_id=f.id
  ),'[]'::jsonb) players
  from public.fixture_rinks fr where fr.fixture_id=f.id
 ), snapshots as (
  select r.id,r.fixture_rink_no,
  jsonb_build_object('fixtureId',f.id,'clubId',f.club_id,'fixtureRinkId',r.id,
   'title',coalesce(nullif(f.team_name,''),(select name from public.competition_types where id=f.competition_type_id),'Member fixture'),
   'startAt',f.start_at,'endAt',f.end_at,'venue',coalesce((select name from public.venues where id=f.venue_id),''),
   'green',coalesce((select name from public.green_areas where id=f.green_area_id),''),'rink',coalesce(r.home_rink_label,r.fixture_rink_no::text),
   'format',r.format,'playersPerSide',r.players_per_rink,'players',r.players,'notes',coalesce(f.notes,''),
   'competitionId',match_record.competition_id,'competitionMatchId',match_record.id,'competitionName',match_record.competition_name,
   'roundName',match_record.round_name,'playBy',match_record.play_by,'rules',rules,
   'handicapA',(select e.handicap from public.competition_entries e join public.competition_entry_members em on em.entry_id=e.id
      join public.fixture_rink_assignments a on a.member_profile_id=em.member_profile_id and a.fixture_rink_id=r.id and a.position between 1 and r.players_per_rink
      where em.competition_id=match_record.competition_id limit 1),
   'handicapB',(select e.handicap from public.competition_entries e join public.competition_entry_members em on em.entry_id=e.id
      join public.fixture_rink_assignments a on a.member_profile_id=em.member_profile_id and a.fixture_rink_id=r.id and a.position between 101 and 100+r.players_per_rink
      where em.competition_id=match_record.competition_id limit 1)
  ) snapshot,
  f.cancelled_at is null and f.archived_at is null and (admin or exists(
   select 1 from public.fixture_rink_assignments a where a.fixture_id=f.id and a.fixture_rink_id=r.id and a.member_profile_id=actor
   and (a.position between 1 and r.players_per_rink or a.position between 101 and 100+r.players_per_rink or a.position=201)
  )) can_score
  from rinks r
 ) select jsonb_agg(jsonb_build_object('fixtureRinkId',s.id,'snapshot',s.snapshot,'sourceFingerprint',md5(s.snapshot::text),'canScore',s.can_score,
    'setup',case when stored.id is null then null else jsonb_build_object('id',stored.id,'matchId',stored.match_id,'snapshot',stored.source_snapshot,'conditions',stored.conditions,'createdAt',stored.created_at) end) order by s.fixture_rink_no)
 into result from snapshots s left join scorecard_private.fixture_rink_setups stored on stored.fixture_rink_id=s.id;
 return jsonb_build_object('fixtureId',f.id,'actorUserId',auth.uid(),'sharedWorkflow',true,'rinks',coalesce(result,'[]'::jsonb));
end $$;
