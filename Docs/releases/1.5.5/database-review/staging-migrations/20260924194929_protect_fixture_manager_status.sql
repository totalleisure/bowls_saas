-- Use active club-scoped fixture authorization and reject null permission results.
CREATE OR REPLACE FUNCTION public.communications_fixture_manager_status(p_fixture_id uuid)
 RETURNS TABLE(status text, next_action text, message text, progress integer, can_repair boolean, can_prepare boolean, can_send boolean, can_retry boolean, blocking_issues jsonb, diagnostics jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
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

  if public.can_manage_fixture(p_fixture_id) is not true then
    raise exception 'Fixture manager access required.';
  end if;

  return query
  select *
  from public.communications_fixture_status(p_fixture_id);
end;
$function$
;

