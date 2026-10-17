create or replace function public.set_fixture_instructions(
  p_fixture_id uuid, p_notes text, p_expected_notes text)
returns void language plpgsql security definer set search_path = '' as $body$
declare f public.fixtures%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Sign in to edit instructions.' using errcode='42501';
  end if;
  select * into f from public.fixtures where id=p_fixture_id for update;
  if not found then raise exception 'Fixture not found.'; end if;
  if not (exists (select 1 from public.app_superusers where user_id=auth.uid())
    or exists (select 1 from public.club_memberships cm
      where cm.club_id=f.club_id and cm.member_profile_id=public.my_member_profile_id()
        and cm.is_active=true and lower(cm.role::text)<>'guest'
        and (lower(cm.role::text)='admin'
          or cm.member_profile_id=f.captain_member_profile_id
          or cm.member_profile_id=f.vice_captain_member_profile_id))) then
    raise exception 'Only fixture captains, vice-captains and administrators can edit instructions.' using errcode='42501';
  end if;
  if length(p_notes)>5000 then raise exception 'Instructions must be at most 5000 characters.' using errcode='22023'; end if;
  if f.notes is distinct from p_expected_notes then
    raise exception 'Instructions were changed by someone else. Reopen the fixture and try again.' using errcode='40001';
  end if;
  update public.fixtures set notes=nullif(btrim(p_notes),'') where id=p_fixture_id;
end;
$body$;
revoke all on function public.set_fixture_instructions(uuid,text,text) from public,anon;
grant execute on function public.set_fixture_instructions(uuid,text,text) to authenticated;
notify pgrst, 'reload schema';
-- Save and publish in one transaction, retaining existing publication checks.
create or replace function public.publish_team_with_instructions(
 p_fixture_id uuid, p_team_selection_id uuid, p_allow_incomplete boolean,
 p_notes text, p_expected_notes text)
returns void language plpgsql security definer set search_path='' as $body$
declare current_notes text;
begin
 if auth.uid() is null or not coalesce(public.can_manage_team_selection(p_fixture_id),false) then
   raise exception 'You cannot publish this fixture.' using errcode='42501';
 end if;
 if length(p_notes)>5000 then raise exception 'Instructions must be at most 5000 characters.' using errcode='22023'; end if;
 select notes into current_notes from public.fixtures where id=p_fixture_id for update;
 if not found then raise exception 'Fixture not found.'; end if;
 if current_notes is distinct from p_expected_notes then
   raise exception 'Instructions changed. Reopen publication and review them.' using errcode='40001';
 end if;
 update public.fixtures set notes=nullif(btrim(p_notes),'') where id=p_fixture_id;
 perform public.publish_team_selection_safe(p_fixture_id,p_team_selection_id,p_allow_incomplete);
end;
$body$;
revoke all on function public.publish_team_with_instructions(uuid,uuid,boolean,text,text) from public,anon;
grant execute on function public.publish_team_with_instructions(uuid,uuid,boolean,text,text) to authenticated;

-- Preserve each environment's unrelated queue fixes.
do $migration$
declare d text; marker text;
begin
 select pg_get_functiondef('public.queue_team_publication_communications(uuid,uuid,boolean)'::regprocedure) into d;
 marker := '''fixture_label'', v_fixture_label,';
 if strpos(d,marker)=0 then raise exception 'Publication payload marker missing'; end if;
 execute replace(d,marker,marker || chr(10) ||
   '''special_instructions'', (select notes from public.fixtures where id=p_fixture_id),');
 select pg_get_functiondef('public.process_notification_queue(integer)'::regprocedure) into d;
 marker := '      insert into app_notifications (';
 if strpos(d,marker)=0 then raise exception 'Notification body marker missing'; end if;
 execute replace(d,marker,
   '      if r.event_type in (''team_published_player'',''team_published_reserve'',''team_published_captain'',''team_published_vice'')
         and nullif(btrim(r.payload->>''special_instructions''),'''') is not null then
         v_body := v_body || chr(10) || chr(10) || ''Special instructions:'' || chr(10) || (r.payload->>''special_instructions'');
       end if;
' || marker);
end;
$migration$;
notify pgrst, 'reload schema';
