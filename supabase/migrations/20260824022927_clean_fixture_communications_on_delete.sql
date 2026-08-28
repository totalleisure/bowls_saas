create or replace function public.delete_fixture(p_fixture_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_club_id uuid;
  v_member_profile_id uuid;
  v_is_admin boolean;
  v_is_super boolean;
  v_has_accepted boolean;
begin
  select club_id into v_club_id
  from public.fixtures
  where id = p_fixture_id;

  if v_club_id is null then
    raise exception 'Fixture not found';
  end if;

  select mp.id into v_member_profile_id
  from public.member_profiles mp
  where mp.user_id = auth.uid();

  if v_member_profile_id is null then
    raise exception 'Member profile not found for current user';
  end if;

  select exists (
    select 1
    from public.club_memberships cm
    where cm.club_id = v_club_id
      and cm.member_profile_id = v_member_profile_id
      and cm.role = 'admin'
  ) into v_is_admin;

  select exists (
    select 1
    from public.app_superusers su
    where su.user_id = auth.uid()
  ) into v_is_super;

  if not (v_is_admin or v_is_super) then
    raise exception 'Not authorized';
  end if;

  select exists (
    select 1
    from public.team_selections ts
    join public.team_selection_members tsm on tsm.team_selection_id = ts.id
    where ts.fixture_id = p_fixture_id
      and tsm.acceptance = 'accepted'
  ) into v_has_accepted;

  if v_has_accepted then
    raise exception 'Cannot delete fixture: accepted members exist. Reverse acceptances first.';
  end if;

  delete from public.fixture_email_log
  where fixture_id = p_fixture_id;

  delete from public.notification_queue
  where fixture_id = p_fixture_id;

  delete from public.email_queue
  where fixture_id = p_fixture_id;

  delete from public.app_notifications
  where fixture_id = p_fixture_id;

  delete from public.fixtures where id = p_fixture_id;
  return true;
end;
$$;
