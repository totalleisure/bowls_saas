create schema if not exists fixture_pool_private;
revoke all on schema fixture_pool_private from public, anon;
grant usage on schema fixture_pool_private to authenticated;

create function fixture_pool_private.add_members(p_fixture_id uuid,
  p_member_profile_ids uuid[], p_override_unavailable boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $body$
declare
  fixture public.fixtures%rowtype;
  is_admin boolean;
  member_id uuid;
begin
  if auth.uid() is null or not public.can_manage_fixture(p_fixture_id) then
    raise exception 'You do not have permission to add players to this fixture.' using errcode='42501';
  end if;
  select * into fixture from public.fixtures where id=p_fixture_id for update;
  if not found or fixture.cancelled_at is not null or fixture.archived_at is not null then
    raise exception 'This fixture is no longer available for team changes.';
  end if;
  if fixture.team_id is not null or not exists(select 1 from public.competition_types ct
    where ct.id=fixture.competition_type_id and ct.selection_mode='rsvp' and ct.uses_rinks) then
    raise exception 'This action is only for RSVP match pools.';
  end if;
  if p_member_profile_ids is null or cardinality(p_member_profile_ids) not between 1 and 100 then
    raise exception 'Choose between one and 100 members.';
  end if;
  if exists(select 1 from unnest(p_member_profile_ids) m(id) where id is null or not exists(
    select 1 from public.club_memberships cm where cm.club_id=fixture.club_id
    and cm.member_profile_id=m.id and cm.is_active and cm.role::text<>'guest')) then
    raise exception 'Every added player must be an active club member.' using errcode='42501';
  end if;
  is_admin := exists(select 1 from public.app_superusers s where s.user_id=auth.uid())
    or exists(select 1 from public.club_memberships cm where cm.club_id=fixture.club_id
      and cm.member_profile_id=public.my_member_profile_id() and cm.is_active and cm.role::text='admin');
  if coalesce(p_override_unavailable,false) and not is_admin then
    raise exception 'Only a club admin can override Not available.' using errcode='42501';
  end if;
  if not coalesce(p_override_unavailable,false) and exists(select 1 from public.fixture_rsvps r
    where r.fixture_id=p_fixture_id and r.member_profile_id=any(p_member_profile_ids) and r.status::text='no') then
    raise exception 'A selected member previously answered Not available. A club admin must confirm an override before adding them to the pool.';
  end if;
  foreach member_id in array p_member_profile_ids loop
    insert into public.fixture_rsvps(fixture_id,member_profile_id,status)
      values(p_fixture_id,member_id,'maybe') on conflict(fixture_id,member_profile_id) do nothing;
    if coalesce(p_override_unavailable,false) then
      update public.fixture_rsvps set status='maybe',responded_at=now()
        where fixture_id=p_fixture_id and member_profile_id=member_id and status::text='no';
    end if;
  end loop;
  -- Catch a concurrent member response without silently reversing it.
  if exists(select 1 from public.fixture_rsvps r where r.fixture_id=p_fixture_id
    and r.member_profile_id=any(p_member_profile_ids) and r.status::text='no') then
    raise exception 'Availability changed while adding players. Refresh and try again.' using errcode='40001';
  end if;
  return jsonb_build_object('pool_updated',true);
end;
$body$;
revoke all on function fixture_pool_private.add_members(uuid,uuid[],boolean) from public,anon;
grant execute on function fixture_pool_private.add_members(uuid,uuid[],boolean) to authenticated;

create function public.add_fixture_members_to_pool(p_fixture_id uuid,
  p_member_profile_ids uuid[], p_override_unavailable boolean default false)
returns jsonb language sql security invoker set search_path='' as $body$
  select fixture_pool_private.add_members(p_fixture_id,p_member_profile_ids,p_override_unavailable);
$body$;
revoke all on function public.add_fixture_members_to_pool(uuid,uuid[],boolean) from public,anon;
grant execute on function public.add_fixture_members_to_pool(uuid,uuid[],boolean) to authenticated;
notify pgrst,'reload schema';
