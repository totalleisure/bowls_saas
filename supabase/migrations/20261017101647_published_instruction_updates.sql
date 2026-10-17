-- Explicit save-and-send only; normal set_fixture_instructions still sends nothing.
create or replace function public.send_fixture_instructions_update(
  p_fixture_id uuid, p_notes text, p_expected_notes text, p_request_id uuid)
returns integer language plpgsql security definer set search_path='' as $body$
declare f public.fixtures%rowtype; selection_id uuid; recipient_count integer;
begin
  if auth.uid() is null then raise exception 'Sign in to send instructions.' using errcode='42501'; end if;
  select * into f from public.fixtures where id=p_fixture_id for update;
  if not found then raise exception 'Fixture not found.'; end if;
  if not (exists(select 1 from public.app_superusers where user_id=auth.uid())
    or exists(select 1 from public.club_memberships cm
      where cm.club_id=f.club_id and cm.member_profile_id=public.my_member_profile_id()
      and cm.is_active=true and lower(cm.role::text)<>'guest'
      and (lower(cm.role::text)='admin' or cm.member_profile_id=f.captain_member_profile_id
        or cm.member_profile_id=f.vice_captain_member_profile_id))) then
    raise exception 'Only fixture captains, vice-captains and administrators can send instructions.' using errcode='42501';
  end if;
  if p_request_id is null then raise exception 'Update request ID is required.'; end if;
  -- A repeated network request must not send a second copy.
  select count(*) into recipient_count from public.notification_queue
    where fixture_id=p_fixture_id and event_type='fixture_message'
      and payload->>'instructions_update_request'=p_request_id::text;
  if recipient_count>0 then return recipient_count; end if;
  select id into selection_id from public.team_selections
    where fixture_id=p_fixture_id and status='published' order by created_at desc limit 1;
  if selection_id is null or f.cancelled_at is not null then
    raise exception 'Instructions updates can only be sent for a published, active fixture.';
  end if;
  perform public.set_fixture_instructions(p_fixture_id,p_notes,p_expected_notes);
  insert into public.notification_queue(event_type,member_profile_id,target_member_profile_id,
    fixture_id,team_selection_id,payload,status)
  select 'fixture_message',public.my_member_profile_id(),recipients.id,p_fixture_id,selection_id,
    jsonb_build_object('title','Special Instructions Update',
      'message',case when nullif(btrim(p_notes),'') is null then 'The special instructions for this fixture have been removed.'
        else 'Special instructions:' || chr(10) || btrim(p_notes) end,
      'fixture_label',coalesce(nullif(f.team_name,''),'Fixture'), 'fixture_date',f.start_at,
      'home_away',case when f.is_home then 'Home' else 'Away' end,
      'venue_name',(select name from public.venues where id=f.venue_id),
      'opponent_name',(select name from public.venues where id=f.opponent_venue_id),
      'team_sheet_required',false,'instructions_update_request',p_request_id), 'pending'
  from (
    select fra.member_profile_id as id from public.fixture_rink_assignments fra
      join public.fixture_rinks fr on fr.id=fra.fixture_rink_id
      where fra.fixture_id=p_fixture_id and fra.position between 1 and fr.players_per_rink
    union select tsm.member_profile_id from public.team_selection_members tsm
      where tsm.team_selection_id=selection_id and tsm.is_selected=true and tsm.role::text='reserve'
    union select f.captain_member_profile_id
    union select f.vice_captain_member_profile_id
  ) recipients where recipients.id is not null;
  get diagnostics recipient_count=row_count;
  if recipient_count=0 then raise exception 'There are no team members to notify. Save without sending instead.'; end if;
  return recipient_count;
end;
$body$;
revoke all on function public.send_fixture_instructions_update(uuid,text,text,uuid) from public,anon;
grant execute on function public.send_fixture_instructions_update(uuid,text,text,uuid) to authenticated;
notify pgrst, 'reload schema';
