-- Captain deletion is deliberately separate from Superuser force deletion.
-- A claimed/shared or legacy prepared scorecard is protected even before its
-- next offline save uploads; absence of a cloud timer is not proof of no play.
create function audit_private.captain_member_fixture_delete_access(p_fixture_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare f public.fixtures; candidate boolean; blocked text;
begin
 select * into f from public.fixtures where id=p_fixture_id;
 candidate := auth.uid() is not null and exists(
  select 1 from public.club_memberships cm join public.member_profiles mp on mp.id=cm.member_profile_id
  join public.competition_types ct on ct.id=f.competition_type_id and ct.club_id=f.club_id
  where cm.club_id=f.club_id and cm.is_active and cm.role::text<>'guest'
   and mp.user_id=auth.uid() and mp.id=f.captain_member_profile_id
   and ct.is_internal and ct.bookable_by_members and ct.uses_rinks
   and lower(replace(replace(ct.selection_mode,'-','_'),' ','_'))='preselect');
 if candidate then
  if exists(select 1 from public.competition_draw_matches where fixture_id=f.id)
     or exists(select 1 from public.competition_fixture_management_events where fixture_id=f.id)
     or f.fixture_type::text='competition' then
   blocked:='competition-linked fixture';
  elsif exists(select 1 from scorecard_private.shared_cards where fixture_id=f.id)
     or exists(select 1 from scorecard_private.fixture_rink_setups s
       join scorecard_private.fixture_matches m on m.id=s.match_id where m.fixture_id=f.id) then
   blocked:='a scorecard has already been prepared or claimed';
  end if;
 end if;
 return jsonb_build_object('candidate',candidate,'can_delete',candidate and blocked is null,'blocker',blocked);
end $$;
revoke all on function audit_private.captain_member_fixture_delete_access(uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.fixture_deletion_preview(p_fixture_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  f public.fixtures;
  v_actor uuid := auth.uid();
  v_is_super boolean;
  v_is_manager boolean;
  v_is_creator boolean;
  v_rsvps integer;
  v_selected integer;
  v_assigned integer;
  v_marker_requests integer;
  v_email_queue integer;
  v_notification_queue integer;
  v_app_notifications integer;
  v_email_log integer;
  v_email_actions integer;
  v_communication_audit integer;
  v_diary integer;
  v_ever_published boolean;
  v_has_players boolean;
  v_captain_access jsonb;
  v_can_delete boolean;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  select * into f from public.fixtures where id = p_fixture_id;
  if not found then raise exception 'Fixture not found'; end if;

  select exists(select 1 from public.app_superusers s where s.user_id = v_actor)
    into v_is_super;
  select public.can_manage_fixture(f.id) into v_is_manager;
  select f.created_by_user_id = v_actor and exists(
    select 1 from public.club_memberships cm
    join public.member_profiles mp on mp.id = cm.member_profile_id
    where mp.user_id = v_actor and cm.club_id = f.club_id and cm.is_active
      and cm.role::text <> 'guest'
  ) into v_is_creator;
  v_is_creator := coalesce(v_is_creator, false);
  if not (v_is_super or v_is_manager or v_is_creator) then
    raise exception 'Not authorized to delete this fixture';
  end if;

  select count(*) into v_rsvps from public.fixture_rsvps where fixture_id = f.id;
  select count(*) into v_selected from public.team_selection_members m
    join public.team_selections s on s.id = m.team_selection_id
    where s.fixture_id = f.id;
  select count(*) into v_assigned from public.fixture_rink_assignments
    where fixture_id = f.id and member_profile_id is not null;
  select count(*) into v_marker_requests from public.fixture_marker_requests mr
    join public.fixture_rinks fr on fr.id = mr.fixture_rink_id
    where fr.fixture_id = f.id;
  select count(*) into v_email_queue from public.email_queue where fixture_id = f.id;
  select count(*) into v_notification_queue from public.notification_queue where fixture_id = f.id;
  select count(*) into v_app_notifications from public.app_notifications where fixture_id = f.id;
  select count(*) into v_email_log from public.fixture_email_log where fixture_id = f.id;
  select count(*) into v_email_actions from public.email_action_requests where fixture_id = f.id;
  select count(*) into v_communication_audit from public.fixture_communication_audit where fixture_id = f.id;
  select count(*) into v_diary from public.club_schedule_items where linked_fixture_id = f.id;
  select
    exists(select 1 from public.team_selections s where s.fixture_id = f.id
      and (s.status::text = 'published' or s.published_at is not null))
    or exists(select 1 from public.audit_journal j where j.fixture_id = f.id
      and j.record_type = 'team_selections' and j.action = 'published')
    into v_ever_published;

  v_has_players := v_rsvps > 0 or v_selected > 0
    or v_assigned > 0 or v_marker_requests > 0;

  v_captain_access := audit_private.captain_member_fixture_delete_access(f.id);
  v_can_delete := case when (v_captain_access->>'candidate')::boolean then
    (v_captain_access->>'can_delete')::boolean else not v_has_players end;
  return jsonb_build_object(
    'captain_member_delete', (v_captain_access->>'can_delete')::boolean,
    'can_delete', v_can_delete,
    'can_force_delete', v_is_super and not v_can_delete and v_has_players,
    'is_superuser', v_is_super,
    'is_creator', v_is_creator,
    'has_players', v_has_players,
    'ever_published', v_ever_published,
    'rsvps', v_rsvps, 'selected_members', v_selected,
    'rink_assignments', v_assigned, 'marker_requests', v_marker_requests,
    'email_queue', v_email_queue, 'notification_queue', v_notification_queue,
    'app_notifications', v_app_notifications, 'fixture_email_log', v_email_log,
    'email_actions', v_email_actions, 'communication_audit', v_communication_audit,
    'diary_items', v_diary,
    'blockers', to_jsonb(array_remove(array[
      case when (v_captain_access->>'candidate')::boolean then v_captain_access->>'blocker'
        when v_has_players then 'players are attached' end
    ]::text[], null))
  );
end $function$
;
CREATE OR REPLACE FUNCTION public.delete_fixture(p_fixture_id uuid, p_reason text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_preview jsonb;
  f public.fixtures;
  v_reason text;
begin
  perform 1 from public.fixtures where id = p_fixture_id for update;
  if not found then raise exception 'Fixture not found'; end if;
  v_preview := public.fixture_deletion_preview(p_fixture_id);
  if not (v_preview->>'can_delete')::boolean then
    raise exception 'Deletion is blocked because %',
      v_preview->'blockers';
  end if;
  if (v_preview->>'captain_member_delete')::boolean then
    select * into strict f from public.fixtures where id=p_fixture_id;
    v_reason:=coalesce(nullif(trim(p_reason),''),'Unused booking removed by the fixture captain.');
    -- Stop pending invitations/reminders. Queue a self-contained cancellation
    -- notice: no fixture/team foreign link or stale navigation survives deletion.
    update public.notification_queue set status='cancelled'
     where fixture_id=f.id and status='pending' and event_type<>'fixture_cancelled';
    update public.email_queue set status='cancelled'
     where fixture_id=f.id and status in ('pending','failed') and sent_at is null and event_type<>'fixture_cancelled';
    with recipients as (
      select member_profile_id from public.fixture_rink_assignments where fixture_id=f.id
      union select m.member_profile_id from public.team_selection_members m join public.team_selections s on s.id=m.team_selection_id
        where s.fixture_id=f.id and m.is_selected
      union select member_profile_id from public.fixture_rsvps where fixture_id=f.id and status::text in ('yes','maybe')
      union select f.vice_captain_member_profile_id
    )
    insert into public.notification_queue(event_type,member_profile_id,target_member_profile_id,payload,status)
    select 'fixture_cancelled',public.my_member_profile_id(),r.member_profile_id,
      jsonb_strip_nulls(jsonb_build_object('fixture_label',coalesce(nullif(f.team_name,''),'Member Internal Fixture'),
        'start_at',f.start_at,'end_at',f.end_at,'reason',v_reason,
        'deleted_fixture_id',f.id,'club_id',f.club_id,'fixture_deleted',true)), 'pending'
    from recipients r
    where r.member_profile_id is not null and r.member_profile_id<>public.my_member_profile_id()
     and not exists(select 1 from public.notification_queue n where n.fixture_id=f.id
       and n.target_member_profile_id=r.member_profile_id and n.event_type='fixture_cancelled' and n.status in ('pending','sent'));
    -- An already-cancelled fixture may have cancellation notices queued earlier.
    update public.notification_queue set fixture_id=null,team_selection_id=null,
      payload=payload || jsonb_build_object('deleted_fixture_id',f.id,'fixture_deleted',true,'club_id',f.club_id)
      where fixture_id=f.id and event_type='fixture_cancelled';
    update public.email_queue set fixture_id=null,team_selection_id=null,
      payload=(payload-'fixture_id'-'team_selection_id') || jsonb_build_object('deleted_fixture_id',f.id,'club_id',f.club_id)
      where fixture_id=f.id and event_type='fixture_cancelled';
    update public.app_notifications set fixture_id=null,team_selection_id=null,
      data=(data-'fixture_id'-'team_selection_id') || jsonb_build_object('deleted_fixture_id',f.id,'fixture_deleted',true)
      where fixture_id=f.id and type='fixture_cancelled';
  end if;
  perform set_config('app.audit_reason', coalesce(trim(p_reason),''), true);
  perform set_config('app.audit_delete_mode', 'ordinary', true);
  delete from public.club_schedule_items where linked_fixture_id = p_fixture_id;
  delete from public.fixtures where id = p_fixture_id;
  return true;
end $function$
;
revoke all on function public.fixture_deletion_preview(uuid),public.delete_fixture(uuid,text) from public,anon;
grant execute on function public.fixture_deletion_preview(uuid),public.delete_fixture(uuid,text) to authenticated;
notify pgrst, 'reload schema';
