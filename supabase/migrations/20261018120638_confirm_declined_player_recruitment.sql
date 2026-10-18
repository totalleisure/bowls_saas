CREATE OR REPLACE FUNCTION fixture_pool_private.add_members_reviewed(p_fixture_id uuid, p_member_profile_ids uuid[], p_override_unavailable boolean, p_confirm_declined boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  -- Serialize and validate the declined responses before changing the pool.
  perform 1 from public.team_selection_members m join public.team_selections s on s.id=m.team_selection_id
    where s.fixture_id=p_fixture_id and m.member_profile_id=any(p_member_profile_ids) for update of m;
  if exists(select 1 from public.team_selection_members m join public.team_selections s on s.id=m.team_selection_id
    where s.fixture_id=p_fixture_id and m.member_profile_id=any(p_member_profile_ids) and m.acceptance='declined'
      and (m.is_selected or exists(select 1 from public.fixture_rink_assignments a join public.fixture_rinks r on r.id=a.fixture_rink_id
        where r.fixture_id=p_fixture_id and a.member_profile_id=m.member_profile_id))) then
    raise exception 'Remove the declined player from the team before returning them to the pool.';
  end if;
  if not coalesce(p_confirm_declined,false) and exists(select 1 from public.team_selection_members m join public.team_selections s on s.id=m.team_selection_id
    where s.fixture_id=p_fixture_id and m.member_profile_id=any(p_member_profile_ids) and m.acceptance='declined') then
    raise exception 'A player previously declined team selection. Refresh and confirm before adding them back to the pool.';
  end if;
  if coalesce(p_confirm_declined,false) then
    -- The audit journal retains the previous decline; this is not acceptance.
    update public.team_selection_members m set acceptance='pending',responded_at=null,acceptance_by=null
      from public.team_selections s where s.id=m.team_selection_id and s.fixture_id=p_fixture_id
      and m.member_profile_id=any(p_member_profile_ids) and not m.is_selected and m.acceptance='declined';
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
$function$;

CREATE OR REPLACE FUNCTION public.queue_team_acceptance_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$

declare

  v_team_selection record;

  v_fixture record;

  v_player_name text;

  v_fixture_label text;

  v_home_away text;

  v_venue_name text;

  v_opponent_name text;

  v_selection_mode text;

begin

  -- Returning an inactive player to the pool is not a player response.

  if not new.is_selected or new.acceptance = 'pending' then return new; end if;

  if tg_op <> 'UPDATE' then

    return new;

  end if;



  if old.acceptance is not distinct from new.acceptance then

    return new;

  end if;



  if new.acceptance is null then

    return new;

  end if;



  select ts.*

  into v_team_selection

  from public.team_selections ts

  where ts.id = new.team_selection_id;



  if v_team_selection is null then

    return new;

  end if;



  if v_team_selection.status is distinct from 'published' then

    return new;

  end if;



  select f.*

  into v_fixture

  from public.fixtures f

  where f.id = v_team_selection.fixture_id;



  if v_fixture is null then

    return new;

  end if;



  select lower(btrim(coalesce(ct.selection_mode, '')))

  into v_selection_mode

  from public.competition_types ct

  where ct.id = v_fixture.competition_type_id;



  if new.role = 'player'::public.selection_member_role

     and coalesce(v_selection_mode, '') <> 'preselect'

     and (v_fixture.team_id is not null or coalesce(v_fixture.requires_rsvp, false))

     and not exists (

       select 1

       from public.fixture_rink_assignments fra

       join public.fixture_rinks fr

         on fr.id = fra.fixture_rink_id

        and fr.fixture_id = v_fixture.id

       where fra.fixture_id = v_fixture.id

         and fra.member_profile_id = new.member_profile_id

         and fra.position between 1 and fr.players_per_rink

     ) then

    return new;

  end if;



  if v_fixture.captain_member_profile_id is null then

    return new;

  end if;



  -- Do not notify the captain about their own acceptance change.

  if v_fixture.captain_member_profile_id = new.member_profile_id then

    return new;

  end if;



  select mp.display_name

  into v_player_name

  from public.member_profiles mp

  where mp.id = new.member_profile_id;



  v_home_away := case when v_fixture.is_home then 'Home' else 'Away' end;



  select coalesce(v.name, '')

  into v_venue_name

  from public.venues v

  where v.id = v_fixture.venue_id;



  select coalesce(ov.name, '')

  into v_opponent_name

  from public.venues ov

  where ov.id = v_fixture.opponent_venue_id;



  v_fixture_label := coalesce(

    nullif(v_fixture.team_name, ''),

    case

      when v_opponent_name <> '' then

        v_home_away || ' v ' || v_opponent_name

      else

        'Fixture'

    end

  );



  /*

    Coalesce repeated acceptance changes before the queue is processed.



    Example:

      pending  -> accepted

      accepted -> declined

      declined -> accepted



    If all of that happens before process_notification_queue runs,

    the captain should receive one Team Update, not three.

  */

  delete from public.notification_queue nq

  where nq.event_type = 'team_acceptance_changed'

    and nq.fixture_id = v_fixture.id

    and nq.team_selection_id = new.team_selection_id

    and nq.member_profile_id = new.member_profile_id

    and nq.target_member_profile_id = v_fixture.captain_member_profile_id

    and nq.status = 'pending';



  insert into public.notification_queue (

    event_type,

    member_profile_id,

    target_member_profile_id,

    fixture_id,

    team_selection_id,

    payload,

    status

  )

  values (

    'team_acceptance_changed',

    new.member_profile_id,

    v_fixture.captain_member_profile_id,

    v_fixture.id,

    new.team_selection_id,

    jsonb_build_object(

      'changed_member_profile_id', new.member_profile_id,

      'old_acceptance', old.acceptance::text,

      'new_acceptance', new.acceptance::text,

      'player_name', coalesce(v_player_name, 'A player'),

      'fixture_label', v_fixture_label,

      'fixture_date', v_fixture.start_at,

      'home_away', v_home_away,

      'venue_name', coalesce(v_venue_name, ''),

      'opponent_name', coalesce(v_opponent_name, '')

    ),

    'pending'

  );



  return new;

end;

$function$;


revoke all on function fixture_pool_private.add_members_reviewed(uuid,uuid[],boolean,boolean) from public,anon;
grant execute on function fixture_pool_private.add_members_reviewed(uuid,uuid[],boolean,boolean) to authenticated;
create or replace function fixture_pool_private.add_members(p_fixture_id uuid,p_member_profile_ids uuid[],p_override_unavailable boolean default false)
returns jsonb language sql security invoker set search_path='' as $$
 select fixture_pool_private.add_members_reviewed(p_fixture_id,p_member_profile_ids,p_override_unavailable,false);
$$;
create function public.add_fixture_members_to_pool_reviewed(p_fixture_id uuid,p_member_profile_ids uuid[],p_override_unavailable boolean,p_confirm_declined boolean)
returns jsonb language sql security invoker set search_path='' as $$
 select fixture_pool_private.add_members_reviewed(p_fixture_id,p_member_profile_ids,p_override_unavailable,p_confirm_declined);
$$;
revoke all on function public.add_fixture_members_to_pool_reviewed(uuid,uuid[],boolean,boolean) from public,anon;
grant execute on function public.add_fixture_members_to_pool_reviewed(uuid,uuid[],boolean,boolean) to authenticated;
notify pgrst,'reload schema';
