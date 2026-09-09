create or replace function public.add_team_members_to_pool(
  p_team_id uuid,
  p_member_profile_ids uuid[]
)
returns setof public.team_members
language sql
security invoker
set search_path = pg_catalog, public
as $function$
  with requested_ids as (
    select distinct requested.member_profile_id
    from unnest(coalesce(p_member_profile_ids, array[]::uuid[]))
      as requested(member_profile_id)
    where requested.member_profile_id is not null
  ),
  requested_members as (
    select requested.member_profile_id
    from requested_ids requested
    join public.teams team
      on team.id = p_team_id
    join public.club_memberships membership
      on membership.club_id = team.club_id
     and membership.member_profile_id = requested.member_profile_id
     and membership.is_active = true
     and lower(membership.role::text) <> 'guest'
  ),
  activated_members as (
    insert into public.team_members as existing_team_member (
      team_id,
      member_profile_id,
      is_active
    )
    select
      p_team_id,
      requested.member_profile_id,
      true
    from requested_members requested
    on conflict (team_id, member_profile_id) do update
      set is_active = true
      where existing_team_member.is_active = false
    returning existing_team_member.*
  )
  select activated.*
  from activated_members activated

  union all

  select team_member.*
  from public.team_members team_member
  join requested_members requested
    on requested.member_profile_id = team_member.member_profile_id
  where team_member.team_id = p_team_id
    and team_member.is_active = true
    and not exists (
      select 1
      from activated_members activated
      where activated.id = team_member.id
    );
$function$;

revoke execute on function public.add_team_members_to_pool(uuid, uuid[])
  from public, anon;

grant execute on function public.add_team_members_to_pool(uuid, uuid[])
  to authenticated;
