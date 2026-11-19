begin;
create table public.competition_player_replacements (
 id uuid primary key default gen_random_uuid(),
 competition_id uuid not null references public.club_competitions(id),
 entry_id uuid not null references public.competition_entries(id),
 actor_user_id uuid not null references auth.users(id),
 outgoing_member_id uuid not null references public.member_profiles(id),
 incoming_member_id uuid not null references public.member_profiles(id),
 reason text not null, before_entry jsonb not null, after_entry jsonb not null,
 fixture_ids uuid[] not null default '{}', created_at timestamptz not null default now()
);
alter table public.competition_player_replacements enable row level security;
revoke all on public.competition_player_replacements from public,anon,authenticated;
grant select on public.competition_player_replacements to authenticated;
create policy replacement_admin_read on public.competition_player_replacements for select to authenticated
 using(exists(select 1 from public.club_competitions c where c.id=competition_id and competition_private.can_manage(c.club_id)));
-- Pending frozen messages must not send obsolete names/contact details after a correction.
do $$ declare kind text; con record; rel regclass; begin
 foreach kind in array array['publication','round_ready','deadline','amendment'] loop
  rel:=('public.competition_'||kind||'_deliveries')::regclass;
  for con in select conname from pg_constraint where conrelid=rel and contype='c'
   and pg_get_constraintdef(oid) like '%status%' loop
   execute format('alter table %s drop constraint %I',rel,con.conname);
  end loop;
  execute format('alter table %s add constraint %I check(status in (''pending'',''claimed'',''sent'',''uncertain'',''cancelled''))',rel,'competition_'||kind||'_delivery_status');
 end loop;
end $$;

create or replace function public.replace_competition_entry_player(
 p_entry_id uuid,p_outgoing_member_id uuid,p_incoming_member_id uuid,p_expected_members uuid[],
 p_expected_name text,p_expected_handicap numeric,p_individual_handicap integer,p_reason text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.club_competitions; e public.competition_entries; replacement_id uuid:=gen_random_uuid();
 current_ids uuid[]; new_ids uuid[]; old_entry jsonb; new_entry jsonb; before_members jsonb;
 new_name text; old_name text; incoming_name text; match_row public.competition_draw_matches;
 fixture public.fixtures; rink record; selection record; affected_entries uuid[]; affected_members uuid[];
 v_fixture_ids uuid[]:='{}'; snap jsonb; event_id uuid; kind text; claimed boolean; emails int:=0; n int;
begin
 select cc.* into c from public.club_competitions cc join public.competition_entries ce on ce.competition_id=cc.id
 where ce.id=p_entry_id for update of cc;
 if not found or not coalesce(competition_private.can_manage(c.club_id),false) then raise exception 'Club administrator access required' using errcode='42501'; end if;
 if c.status not in ('draft','published') then raise exception 'This competition is not open for an entry correction'; end if;
 select * into strict e from public.competition_entries where id=p_entry_id for update;
 select array_agg(member_profile_id order by member_profile_id),jsonb_agg(to_jsonb(em)) into current_ids,before_members
 from public.competition_entry_members em where entry_id=e.id;
 if p_expected_name is distinct from e.name or p_expected_handicap is distinct from e.handicap
 or cardinality(p_expected_members) is distinct from cardinality(current_ids)
 or cardinality(p_expected_members) is distinct from (select count(distinct id) from unnest(p_expected_members) id)
 or not coalesce(current_ids @> p_expected_members and current_ids <@ p_expected_members,false)
 or p_outgoing_member_id is null or not(p_outgoing_member_id=any(current_ids)) then
 raise exception 'This entry has changed. Reload it before replacing a player'; end if;
 if p_incoming_member_id is null or p_incoming_member_id=p_outgoing_member_id then raise exception 'Select a different replacement player'; end if;
 if not exists(select 1 from public.club_memberships where club_id=c.club_id and member_profile_id=p_incoming_member_id and is_active and role::text<>'guest') then raise exception 'Choose an active Club member'; end if;
 if exists(select 1 from public.competition_entry_members where competition_id=c.id and member_profile_id=p_incoming_member_id) then raise exception 'This player is already entered in the competition'; end if;
 if length(btrim(coalesce(p_reason,''))) not between 1 and 2000 then raise exception 'Give a short reason for the correction'; end if;
 if c.settings->>'handicap_mode'='team_difference' and (p_individual_handicap is null or p_individual_handicap not between -1000 and 1000) then raise exception 'Enter the replacement player''s individual handicap'; end if;
 select string_agg(btrim(concat_ws(' ',mp.first_name,mp.last_name)),' / ' order by x.ord) into old_name
 from unnest(p_expected_members) with ordinality x(id,ord) join public.member_profiles mp on mp.id=x.id;
 if old_name is distinct from e.name then raise exception 'Player names or order have changed. Refresh the entry before correcting it'; end if;
 perform 1 from public.competition_draw_matches where competition_id=c.id and e.id in(side_a_entry_id,side_b_entry_id) order by id for update;
 if exists(select 1 from public.competition_draw_matches where competition_id=c.id and e.id in(side_a_entry_id,side_b_entry_id)
 and (status not in ('to_be_arranged','bye') or score_a is not null or score_b is not null or proposed_winner_entry_id is not null or (status<>'bye' and winner_entry_id is not null))) then
 raise exception 'This entry has a played, submitted or confirmed result. Resolve that result with the Competition Secretary before replacing a player'; end if;
 select array_agg(distinct id) into affected_entries from (
 select e.id id union select side_a_entry_id from public.competition_draw_matches where competition_id=c.id and e.id in(side_a_entry_id,side_b_entry_id)
 union select side_b_entry_id from public.competition_draw_matches where competition_id=c.id and e.id in(side_a_entry_id,side_b_entry_id)) x where id is not null;
 select array_agg(distinct id) into affected_members from (
 select member_profile_id id from public.competition_entry_members where competition_id=c.id and entry_id=any(affected_entries)
 union select p_incoming_member_id) x;
 -- Serialize against the existing worker's claim transaction; never amend an in-flight mail batch.
 perform 1 from public.competition_mail_batch_control where id for update;
 foreach kind in array array['publication','round_ready','deadline','amendment'] loop
  execute format('select exists(select 1 from public.competition_%I_deliveries d join public.competition_%I_events ev on ev.id=d.event_id where ev.competition_id=$1 and d.member_profile_id=any($2) and d.status=''claimed'')',kind,kind) into claimed using c.id,affected_members;
  if claimed then raise exception 'An affected email is being sent. Wait a minute, refresh, then retry the correction'; end if;
 end loop;
 for fixture in select f.* from public.fixtures f join public.competition_draw_matches m on m.fixture_id=f.id
 where m.competition_id=c.id and e.id in(m.side_a_entry_id,m.side_b_entry_id) order by f.id for update of f loop
  if fixture.start_at<=now() or fixture.cancelled_at is not null or fixture.archived_at is not null then raise exception 'A linked fixture has started, been cancelled or archived. Resolve it before correcting the entry'; end if;
  for rink in select id from public.fixture_rinks where fixture_id=fixture.id order by id loop
   perform pg_advisory_xact_lock(hashtextextended(rink.id::text,75205));
   if exists(select 1 from scorecard_private.shared_cards where rink_id=rink.id)
    or exists(select 1 from scorecard_private.fixture_rink_setups where fixture_rink_id=rink.id) then
    raise exception 'A linked fixture already has a scorecard setup. Resolve the scorecard before replacing a player'; end if;
  end loop;
  if exists(select 1 from public.fixture_rink_assignments where fixture_id=fixture.id and member_profile_id=p_incoming_member_id) then raise exception 'The replacement is already assigned to this fixture'; end if;
  perform 1 from public.notification_queue where fixture_id=fixture.id order by id for update;
  perform 1 from public.email_queue where fixture_id=fixture.id order by id for update;
  if exists(select 1 from public.notification_queue where fixture_id=fixture.id and status='processing')
   or exists(select 1 from public.email_queue where fixture_id=fixture.id and status='processing') then raise exception 'A fixture message is being processed. Wait a minute and retry'; end if;
  if (select count(*) from public.fixture_rink_assignments a join public.fixture_rinks fr on fr.id=a.fixture_rink_id where a.fixture_id=fixture.id and a.member_profile_id=p_outgoing_member_id and (a.position between 1 and fr.players_per_rink or a.position between 101 and 100+fr.players_per_rink))<>1 then raise exception 'The linked fixture player list differs from the draw. Resolve the fixture first'; end if;
  v_fixture_ids:=array_append(v_fixture_ids,fixture.id);
 end loop;
 old_entry:=to_jsonb(e)||jsonb_build_object('members',before_members,'fixture_assignments',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from public.fixture_rink_assignments a where fixture_id=any(v_fixture_ids)));
 new_ids:=array_replace(p_expected_members,p_outgoing_member_id,p_incoming_member_id);
 select string_agg(btrim(concat_ws(' ',mp.first_name,mp.last_name)),' / ' order by x.ord) into new_name
 from unnest(new_ids) with ordinality x(id,ord) join public.member_profiles mp on mp.id=x.id;
 select btrim(concat_ws(' ',first_name,last_name)) into old_name from public.member_profiles where id=p_outgoing_member_id;
 select btrim(concat_ws(' ',first_name,last_name)) into incoming_name from public.member_profiles where id=p_incoming_member_id;
 update public.competition_entry_members set member_profile_id=p_incoming_member_id,
 individual_handicap=case when c.settings->>'handicap_mode'='team_difference' then p_individual_handicap else null end
 where entry_id=e.id and member_profile_id=p_outgoing_member_id;
 update public.competition_entries set name=new_name where id=e.id;
 for fixture in select * from public.fixtures where id=any(v_fixture_ids) order by id for update loop
  update public.fixture_rink_assignments set member_profile_id=p_incoming_member_id,display_name=null where fixture_id=fixture.id and member_profile_id=p_outgoing_member_id;
  for selection in select * from public.team_selections where fixture_id=fixture.id for update loop
   delete from public.team_selection_members where team_selection_id=selection.id and member_profile_id=p_outgoing_member_id;
   insert into public.team_selection_members(team_selection_id,member_profile_id,role,acceptance,is_selected)
   values(selection.id,p_incoming_member_id,'player','pending',true);
   update public.team_selections set captain_member_profile_id=case when captain_member_profile_id=p_outgoing_member_id then p_incoming_member_id else captain_member_profile_id end,
    vice_captain_member_profile_id=case when vice_captain_member_profile_id=p_outgoing_member_id then p_incoming_member_id else vice_captain_member_profile_id end,composition_version=composition_version+1 where id=selection.id;
  end loop;
  update public.fixtures set captain_member_profile_id=case when captain_member_profile_id=p_outgoing_member_id then p_incoming_member_id else captain_member_profile_id end,
   vice_captain_member_profile_id=case when vice_captain_member_profile_id=p_outgoing_member_id then p_incoming_member_id else vice_captain_member_profile_id end where id=fixture.id;
  update public.notification_queue set status='cancelled' where fixture_id=fixture.id and status in ('pending','failed');
  update public.email_action_requests set status='cancelled',updated_at=now() where status in ('pending','responded') and source_email_queue_id in(select id from public.email_queue where fixture_id=fixture.id);
  update public.email_queue set status='cancelled' where fixture_id=fixture.id and status in ('pending','failed');
  perform competition_private.queue_booking_communications(fixture.id,'booked','player-replacement:'||replacement_id::text);
 end loop;
 select to_jsonb(ce)||jsonb_build_object('members',(select jsonb_agg(to_jsonb(em)) from public.competition_entry_members em where entry_id=e.id)) into new_entry from public.competition_entries ce where id=e.id;
 insert into public.competition_player_replacements(id,competition_id,entry_id,actor_user_id,outgoing_member_id,incoming_member_id,reason,before_entry,after_entry,fixture_ids)
 values(replacement_id,c.id,e.id,auth.uid(),p_outgoing_member_id,p_incoming_member_id,btrim(p_reason),old_entry,new_entry,v_fixture_ids);
 if c.status='published' then
  foreach kind in array array['publication','round_ready','deadline','amendment'] loop
   execute format('update public.competition_%I_deliveries d set status=''cancelled'',last_error=''Superseded by entry player replacement; not sent'' from public.competition_%I_events ev where ev.id=d.event_id and ev.competition_id=$1 and d.member_profile_id=any($2) and d.status=''pending''',kind,kind) using c.id,affected_members;
  end loop;
  select m.* into match_row from public.competition_draw_matches m join public.competition_rounds r on r.id=m.round_id
   where m.competition_id=c.id and e.id in(m.side_a_entry_id,m.side_b_entry_id) order by (m.status='bye'),r.round_number,m.match_number limit 1;
  if match_row.id is null then raise exception 'Published entry has no draw record. Review the competition before correcting it'; end if;
  snap:=jsonb_build_object('amendment',true,'matchId',match_row.id,'playerReplacement',jsonb_build_object('id',replacement_id,'entryId',e.id,'outgoingId',p_outgoing_member_id,'incomingId',p_incoming_member_id,'oldName',old_name,'newName',incoming_name,'entryName',new_name,'reason',btrim(p_reason)),
   'clubName',(select name from public.clubs where id=c.club_id),'competitions',jsonb_build_array(to_jsonb(c)),
   'entries',(select jsonb_agg(to_jsonb(ce)) from public.competition_entries ce where id=any(affected_entries)),
   'entryMembers',(select jsonb_agg(to_jsonb(em)) from public.competition_entry_members em where competition_id=c.id and entry_id=any(affected_entries)),
   'matches',(select jsonb_agg(to_jsonb(m)) from public.competition_draw_matches m where competition_id=c.id and e.id in(side_a_entry_id,side_b_entry_id)),
   'rounds',(select jsonb_agg(to_jsonb(r)) from public.competition_rounds r where competition_id=c.id),
   'profiles',(select jsonb_agg(jsonb_build_object('id',mp.id,'first_name',mp.first_name,'last_name',mp.last_name,'email_address',mp.email_address,'phone',mp.phone)) from public.member_profiles mp where id=any(affected_members)));
  insert into public.competition_amendment_events(match_id,competition_id,club_id,actor_user_id,before_match,snapshot)
   values(match_row.id,c.id,c.club_id,auth.uid(),old_entry,snap) returning id into event_id;
  if competition_private.publication_enabled() then
   insert into public.competition_amendment_deliveries(event_id,member_profile_id,recipient)
   select distinct on(lower(btrim(mp.email_address))) event_id,mp.id,lower(btrim(mp.email_address)) from public.member_profiles mp where mp.id=any(affected_members)
    and competition_private.email_recipient_allowed(mp.email_address) and exists(select 1 from public.club_memberships cm where cm.club_id=c.club_id and cm.member_profile_id=mp.id and cm.is_active and cm.role::text<>'guest') order by lower(btrim(mp.email_address)),mp.id;
   get diagnostics emails=row_count;
  end if;
 end if;
 return jsonb_build_object('entry_id',e.id,'name',new_name,'replacement_id',replacement_id,'fixtures_updated',cardinality(v_fixture_ids),'emails_queued',emails);
end $$;
revoke all on function public.replace_competition_entry_player(uuid,uuid,uuid,uuid[],text,numeric,integer,text) from public,anon;
grant execute on function public.replace_competition_entry_player(uuid,uuid,uuid,uuid[],text,numeric,integer,text) to authenticated;
commit;
