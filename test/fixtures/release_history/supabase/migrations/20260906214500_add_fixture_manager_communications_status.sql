create or replace function public.communications_fixture_manager_status(
  p_fixture_id uuid
)
returns table(
  status text,
  next_action text,
  message text,
  progress integer,
  can_repair boolean,
  can_prepare boolean,
  can_send boolean,
  can_retry boolean,
  blocking_issues jsonb,
  diagnostics jsonb
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_user_id uuid := auth.uid();
  v_member_profile_id uuid;
  v_club_id uuid;
  v_captain_id uuid;
  v_vice_captain_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication required.';
  end if;

  select
    f.club_id,
    f.captain_member_profile_id,
    f.vice_captain_member_profile_id
  into
    v_club_id,
    v_captain_id,
    v_vice_captain_id
  from public.fixtures f
  where f.id = p_fixture_id;

  if not found then
    raise exception 'Fixture % was not found.', p_fixture_id;
  end if;

  v_member_profile_id := public.my_member_profile_id();

  if not (
    exists (
      select 1
      from public.app_superusers su
      where su.user_id = v_user_id
    )
    or (
      v_member_profile_id is not null
      and (
        v_member_profile_id = v_captain_id
        or v_member_profile_id = v_vice_captain_id
        or exists (
          select 1
          from public.club_memberships cm
          where cm.club_id = v_club_id
            and cm.member_profile_id = v_member_profile_id
            and cm.is_active = true
            and lower(cm.role::text) in ('admin', 'selector')
        )
      )
    )
  ) then
    raise exception 'Fixture manager access required.';
  end if;

  return query
  select *
  from public.communications_fixture_status(p_fixture_id);
end;
$function$;

revoke all on function public.communications_fixture_manager_status(uuid)
from public, anon, authenticated;

grant execute on function public.communications_fixture_manager_status(uuid)
to authenticated;
