create or replace function public.queue_post_publication_player_change(
  p_team_selection_member_id uuid,
  p_event_type text,
  p_actor_member_profile_id uuid
)
returns boolean
language plpgsql
security invoker
set search_path = public
as $function$
declare
  v_row record;
begin
  if p_event_type not in ('fixture_selected', 'reserve_promoted') then
    raise exception 'Unsupported player-change event type.';
  end if;

  select
    tsm.member_profile_id,
    ts.id as team_selection_id,
    ts.status::text as selection_status,
    f.id as fixture_id,
    f.start_at,
    f.is_home,
    coalesce(nullif(btrim(f.team_name), ''), 'Fixture') as fixture_label,
    coalesce(v.name, ov.name, '') as venue_name,
    coalesce(nullif(btrim(mp.display_name), ''),
      concat_ws(' ', nullif(btrim(mp.first_name), ''), nullif(btrim(mp.last_name), '')),
      'A player') as player_name,
    fr.fixture_rink_no as team_no,
    fr.home_rink_label,
    fr.players_per_rink,
    fra.position
  into v_row
  from public.team_selection_members tsm
  join public.team_selections ts on ts.id = tsm.team_selection_id
  join public.fixtures f on f.id = ts.fixture_id
  join public.member_profiles mp on mp.id = tsm.member_profile_id
  left join public.venues v on v.id = f.venue_id
  left join public.venues ov on ov.id = f.opponent_venue_id
  left join public.fixture_rink_assignments fra
    on fra.fixture_id = f.id and fra.member_profile_id = tsm.member_profile_id
  left join public.fixture_rinks fr on fr.id = fra.fixture_rink_id
  where tsm.id = p_team_selection_member_id
    and tsm.role = 'player'::public.selection_member_role
    and tsm.is_selected = true;

  if not found
     or v_row.selection_status <> 'published'
     or exists (
       select 1 from public.fixtures f
       where f.id = v_row.fixture_id and f.cancelled_at is not null
     ) then
    return false;
  end if;

  if p_event_type = 'reserve_promoted' then
    update public.notification_queue set status = 'cancelled'
    where fixture_id = v_row.fixture_id
      and target_member_profile_id = v_row.member_profile_id
      and event_type = 'team_published_reserve' and status = 'pending';

    update public.email_queue set status = 'cancelled'
    where fixture_id = v_row.fixture_id
      and member_profile_id = v_row.member_profile_id
      and event_type = 'team_published_reserve'
      and status in ('pending', 'failed') and sent_at is null;
  end if;

  insert into public.notification_queue (
    event_type, member_profile_id, target_member_profile_id,
    fixture_id, team_selection_id, payload, status
  ) values (
    p_event_type,
    p_actor_member_profile_id,
    v_row.member_profile_id,
    v_row.fixture_id,
    v_row.team_selection_id,
    jsonb_strip_nulls(jsonb_build_object(
      'player_name', v_row.player_name,
      'fixture_label', v_row.fixture_label,
      'fixture_date', v_row.start_at,
      'start_at', v_row.start_at,
      'home_away', case when v_row.is_home then 'Home' else 'Away' end,
      'venue_name', v_row.venue_name,
      'team_no', v_row.team_no,
      'home_rink_label', v_row.home_rink_label,
      'players_per_rink', v_row.players_per_rink,
      'position', v_row.position,
      'role', 'player',
      'old_role', case when p_event_type = 'reserve_promoted' then 'reserve' end,
      'new_role', case when p_event_type = 'reserve_promoted' then 'player' end
    )),
    'pending'
  );

  return true;
end;
$function$;

revoke all on function public.queue_post_publication_player_change(uuid, text, uuid)
from public, anon, authenticated, service_role;

create or replace function public.set_team_selection_member_active(
  p_team_selection_id uuid,
  p_member_profile_id uuid,
  p_is_selected boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_actor uuid;
  v_fixture_id uuid;
  v_club_id uuid;
  v_selection_status text;
  v_member public.team_selection_members%rowtype;
  v_queued boolean := false;
begin
  if auth.uid() is null then raise exception 'Not signed in.'; end if;
  v_actor := public.my_member_profile_id();
  if v_actor is null then raise exception 'Member profile not found.'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_team_selection_id::text, 0));
  select ts.fixture_id, f.club_id, ts.status::text
  into v_fixture_id, v_club_id, v_selection_status
  from public.team_selections ts
  join public.fixtures f on f.id = ts.fixture_id
  where ts.id = p_team_selection_id
  for update of ts;
  if not found then raise exception 'Team selection not found.'; end if;
  if not (
    public.can_manage_team_selection(v_fixture_id)
    or exists (
      select 1 from public.fixtures f
      where f.id = v_fixture_id
        and v_actor in (f.captain_member_profile_id, f.vice_captain_member_profile_id)
    )
  ) then
    raise exception 'You do not have permission to manage this fixture.';
  end if;

  select * into v_member from public.team_selection_members
  where team_selection_id = p_team_selection_id
    and member_profile_id = p_member_profile_id for update;

  if p_is_selected then
    if found and v_member.is_selected then
      return jsonb_build_object('action', 'no_change', 'queued', false);
    end if;

    if not exists (
      select 1
      from public.club_memberships cm
      where cm.club_id = v_club_id
        and cm.member_profile_id = p_member_profile_id
        and cm.is_active = true
    ) then
      raise exception 'Target member is not an active member of this club';
    end if;

    insert into public.team_selection_members (
      team_selection_id, member_profile_id, role, acceptance,
      responded_at, is_selected, acceptance_by
    ) values (
      p_team_selection_id, p_member_profile_id, 'player', 'pending', null, true, null
    )
    on conflict (team_selection_id, member_profile_id) do update set
      role = 'player', acceptance = 'pending', responded_at = null,
      is_selected = true, acceptance_by = null
    returning * into v_member;

    delete from public.notification_queue
    where fixture_id = v_fixture_id
      and team_selection_id = p_team_selection_id
      and member_profile_id = p_member_profile_id
      and event_type = 'team_acceptance_changed'
      and status = 'pending'
      and payload->>'new_acceptance' = 'pending';

    v_queued := public.queue_post_publication_player_change(v_member.id, 'fixture_selected', v_actor);
    return jsonb_build_object('action', 'selected', 'queued', v_queued);
  end if;

  if not found or not v_member.is_selected then
    return jsonb_build_object('action', 'no_change', 'queued', false);
  end if;

  update public.team_selection_members set is_selected = false where id = v_member.id;
  delete from public.fixture_rink_assignments
  where fixture_id = v_fixture_id and member_profile_id = p_member_profile_id;
  update public.email_action_requests set status = 'cancelled', updated_at = now()
  where target_record_id = v_member.id and status in ('pending', 'responded');
  update public.notification_queue set status = 'cancelled'
  where fixture_id = v_fixture_id and target_member_profile_id = p_member_profile_id
    and event_type in ('fixture_selected', 'reserve_promoted', 'team_published_player', 'team_published_reserve')
    and status = 'pending';
  update public.email_queue set status = 'cancelled'
  where fixture_id = v_fixture_id and member_profile_id = p_member_profile_id
    and event_type in ('fixture_selected', 'reserve_promoted', 'team_published_player', 'team_published_reserve')
    and status in ('pending', 'failed') and sent_at is null;

  return jsonb_build_object('action', 'removed', 'queued', false);
end;
$function$;

revoke all on function public.set_team_selection_member_active(uuid, uuid, boolean)
from public, anon;
grant execute on function public.set_team_selection_member_active(uuid, uuid, boolean)
to authenticated;

create or replace function public.set_team_selection_member_role(
  p_team_selection_id uuid,
  p_member_profile_id uuid,
  p_role text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_actor uuid;
  v_fixture_id uuid;
  v_club_id uuid;
  v_selection_status text;
  v_member public.team_selection_members%rowtype;
  v_new_role text := lower(btrim(coalesce(p_role, '')));
  v_queued boolean := false;
begin
  if auth.uid() is null then raise exception 'Not signed in.'; end if;
  v_actor := public.my_member_profile_id();
  if v_actor is null then raise exception 'Member profile not found.'; end if;
  if v_new_role not in ('player', 'reserve') then raise exception 'Unsupported role transition.'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_team_selection_id::text, 0));
  select ts.fixture_id, f.club_id, ts.status::text
  into v_fixture_id, v_club_id, v_selection_status
  from public.team_selections ts
  join public.fixtures f on f.id = ts.fixture_id
  where ts.id = p_team_selection_id
  for update of ts;
  if not found then raise exception 'Team selection not found.'; end if;
  if not (
    public.can_manage_team_selection(v_fixture_id)
    or exists (
      select 1 from public.fixtures f
      where f.id = v_fixture_id
        and v_actor in (f.captain_member_profile_id, f.vice_captain_member_profile_id)
    )
  ) then
    raise exception 'You do not have permission to manage this fixture.';
  end if;

  select * into strict v_member from public.team_selection_members
  where team_selection_id = p_team_selection_id
    and member_profile_id = p_member_profile_id for update;
  if not v_member.is_selected then raise exception 'Member is not actively selected.'; end if;
  if v_member.role::text = v_new_role then
    return jsonb_build_object('action', 'no_change', 'queued', false);
  end if;

  if not exists (
    select 1
    from public.club_memberships cm
    where cm.club_id = v_club_id
      and cm.member_profile_id = p_member_profile_id
      and cm.is_active = true
  ) then
    raise exception 'Target member is not an active member of this club';
  end if;

  if v_member.role = 'reserve' and v_new_role = 'player' then
    update public.team_selection_members set
      role = 'player', acceptance = 'pending', responded_at = null, acceptance_by = null
    where id = v_member.id;
    delete from public.notification_queue
    where fixture_id = v_fixture_id
      and team_selection_id = p_team_selection_id
      and member_profile_id = p_member_profile_id
      and event_type = 'team_acceptance_changed'
      and status = 'pending'
      and payload->>'new_acceptance' = 'pending';
    v_queued := public.queue_post_publication_player_change(v_member.id, 'reserve_promoted', v_actor);
    return jsonb_build_object('action', 'reserve_promoted', 'queued', v_queued);
  end if;

  if v_member.role = 'player' and v_new_role = 'reserve' then
    update public.team_selection_members set role = 'reserve' where id = v_member.id;
    delete from public.fixture_rink_assignments
    where fixture_id = v_fixture_id and member_profile_id = p_member_profile_id;
    update public.email_action_requests set status = 'cancelled', updated_at = now()
    where target_record_id = v_member.id and status in ('pending', 'responded');
    update public.notification_queue set status = 'cancelled'
    where fixture_id = v_fixture_id and target_member_profile_id = p_member_profile_id
      and event_type in ('fixture_selected', 'reserve_promoted', 'team_published_player')
      and status = 'pending';
    update public.email_queue set status = 'cancelled'
    where fixture_id = v_fixture_id and member_profile_id = p_member_profile_id
      and event_type in ('fixture_selected', 'reserve_promoted', 'team_published_player')
      and status in ('pending', 'failed') and sent_at is null;
    return jsonb_build_object('action', 'player_demoted', 'queued', false);
  end if;

  raise exception 'Unsupported role transition.';
end;
$function$;

revoke all on function public.set_team_selection_member_role(uuid, uuid, text)
from public, anon;
grant execute on function public.set_team_selection_member_role(uuid, uuid, text)
to authenticated;

create or replace function public.save_fixture_rink_assignments(
  p_fixture_id uuid,
  p_team_selection_id uuid,
  p_assignments jsonb default '[]'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_current_member uuid := public.my_member_profile_id();
  v_fixture_id uuid;
  v_club_id uuid;
  v_promoted_ids uuid[] := array[]::uuid[];
  v_promoted_id uuid;
begin
  if auth.uid() is null or v_current_member is null then
    raise exception 'Not signed in.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_team_selection_id::text, 0));

  select ts.fixture_id, f.club_id
  into v_fixture_id, v_club_id
  from public.team_selections ts
  join public.fixtures f on f.id = ts.fixture_id
  where ts.id = p_team_selection_id
  for update of ts;

  if not found then raise exception 'Team selection not found.'; end if;
  if p_fixture_id is distinct from v_fixture_id then
    raise exception 'Team selection does not belong to this fixture.';
  end if;

  if not (
    public.can_manage_team_selection(v_fixture_id)
    or exists (
      select 1 from public.fixtures f
      where f.id = v_fixture_id
        and v_current_member in (
          f.captain_member_profile_id,
          f.vice_captain_member_profile_id
        )
    )
  ) then
    raise exception 'You do not have permission to manage this fixture.';
  end if;

  if exists (
    select 1
    from (
      select item->>'member_profile_id' as member_profile_id
      from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb)) item
      where nullif(item->>'member_profile_id', '') is not null
      group by item->>'member_profile_id'
      having count(*) > 1
    ) d
  ) then
    raise exception 'A player cannot be assigned more than once.';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb)) item
    left join public.fixture_rinks fr
      on fr.id = (item->>'fixture_rink_id')::uuid
     and fr.fixture_id = v_fixture_id
    where fr.id is null
  ) then
    raise exception 'Invalid team/rink assignment.';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb)) item
    left join public.team_selection_members tsm
      on tsm.team_selection_id = p_team_selection_id
     and tsm.member_profile_id = (item->>'member_profile_id')::uuid
     and tsm.is_selected = true
    where nullif(item->>'member_profile_id', '') is not null
      and tsm.member_profile_id is null
  ) then
    raise exception 'Assigned member is not active in the team selection.';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb)) item
    join public.team_selection_members tsm
      on tsm.team_selection_id = p_team_selection_id
     and tsm.member_profile_id = (item->>'member_profile_id')::uuid
     and tsm.is_selected = true
     and tsm.role in (
       'player'::public.selection_member_role,
       'reserve'::public.selection_member_role
     )
    where nullif(item->>'member_profile_id', '') is not null
      and not exists (
        select 1
        from public.club_memberships cm
        where cm.club_id = v_club_id
          and cm.member_profile_id = tsm.member_profile_id
          and cm.is_active = true
      )
  ) then
    raise exception 'Target member is not an active member of this club';
  end if;

  perform 1
  from public.team_selection_members tsm
  where tsm.team_selection_id = p_team_selection_id
  for update;

  with promoted as (
    update public.team_selection_members tsm
    set role = 'player'::selection_member_role,
        acceptance = 'pending'::acceptance_status,
        responded_at = null,
        acceptance_by = null
    where tsm.team_selection_id = p_team_selection_id
      and tsm.role = 'reserve'::selection_member_role
      and tsm.is_selected = true
      and exists (
        select 1
        from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb)) item
        where (item->>'member_profile_id')::uuid = tsm.member_profile_id
      )
    returning tsm.id
  )
  select coalesce(array_agg(id), array[]::uuid[]) into v_promoted_ids
  from promoted;

  delete from public.notification_queue
  where fixture_id = v_fixture_id
    and team_selection_id = p_team_selection_id
    and event_type = 'team_acceptance_changed'
    and status = 'pending'
    and payload->>'new_acceptance' = 'pending'
    and member_profile_id in (
      select tsm.member_profile_id
      from public.team_selection_members tsm
      where tsm.id = any(v_promoted_ids)
    );

  delete from public.fixture_rink_assignments
  where fixture_id = v_fixture_id;

  insert into public.fixture_rink_assignments (
    fixture_id,
    fixture_rink_id,
    member_profile_id,
    position
  )
  select
    v_fixture_id,
    (item->>'fixture_rink_id')::uuid,
    (item->>'member_profile_id')::uuid,
    (item->>'position')::integer
  from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb)) item
  where nullif(item->>'member_profile_id', '') is not null;

  foreach v_promoted_id in array v_promoted_ids loop
    perform public.queue_post_publication_player_change(
      v_promoted_id, 'reserve_promoted', v_current_member
    );
  end loop;
end;
$$;

revoke all on function public.save_fixture_rink_assignments(uuid, uuid, jsonb)
from public, anon;
grant execute on function public.save_fixture_rink_assignments(uuid, uuid, jsonb)
to authenticated;

CREATE OR REPLACE FUNCTION public.prepare_team_selection_email_action()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_request_id uuid;
  v_code text;
  v_code_hash text;
  v_team_selection_id uuid;
  v_team_selection_member_id uuid;
  v_club_id uuid;
  v_expires_at timestamptz;
  v_action_type text;
  v_heading text;
  v_accept_label text;
  v_decline_label text;
begin
  if new.event_type not in ('fixture_selected', 'team_published_player', 'reserve_promoted')
     or new.member_profile_id is null
     or new.fixture_id is null then
    return new;
  end if;

  select
    ts.id,
    tsm.id,
    f.club_id,
    f.start_at,
    case
      when new.event_type = 'fixture_selected'
       and tsm.role::text = 'marker'
       and exists (
         select 1
         from public.fixture_rink_assignments fra
         where fra.fixture_id = f.id
           and fra.member_profile_id = tsm.member_profile_id
           and fra.position = 201
       ) then 'marker_assignment'
      when tsm.role::text = 'player' then 'team_selection'
      else null
    end
  into
    v_team_selection_id,
    v_team_selection_member_id,
    v_club_id,
    v_expires_at,
    v_action_type
  from public.team_selections ts
  join public.team_selection_members tsm
    on tsm.team_selection_id = ts.id
   and tsm.member_profile_id = new.member_profile_id
  join public.fixtures f
    on f.id = ts.fixture_id
  where ts.fixture_id = new.fixture_id
    and (new.team_selection_id is null or ts.id = new.team_selection_id)
    and ts.status = 'published'
    and coalesce(tsm.is_selected, false) = true
    and (
      (new.event_type in ('fixture_selected', 'team_published_player', 'reserve_promoted')
       and tsm.role::text = 'player')
      or
      (new.event_type = 'fixture_selected'
       and tsm.role::text = 'marker'
       and exists (
         select 1
         from public.fixture_rink_assignments fra
         where fra.fixture_id = f.id
           and fra.member_profile_id = tsm.member_profile_id
           and fra.position = 201
       ))
    )
    and f.cancelled_at is null
  limit 1;

  if v_team_selection_member_id is null or v_action_type is null then
    return new;
  end if;

  update public.email_action_requests
     set status = 'cancelled',
         updated_at = now()
   where action_type = v_action_type
     and target_record_id = v_team_selection_member_id
     and status in ('pending', 'responded');

  if v_action_type = 'marker_assignment' then
    v_heading := 'Please respond to your marker assignment';
    v_accept_label := 'Accept marker assignment';
    v_decline_label := 'Decline marker assignment';
  else
    v_heading := 'Please respond to your selection';
    v_accept_label := 'Accept selection';
    v_decline_label := 'Decline selection';
  end if;

  v_code := 'BWL-' || upper(encode(extensions.gen_random_bytes(6), 'hex'));
  v_code_hash := encode(
    extensions.digest(upper(v_code), 'sha256'),
    'hex'
  );

  insert into public.email_action_requests (
    club_id,
    member_profile_id,
    recipient_email,
    action_type,
    target_record_id,
    fixture_id,
    team_selection_id,
    source_email_queue_id,
    allowed_actions,
    response_code_hash,
    expires_at
  )
  values (
    v_club_id,
    new.member_profile_id,
    new.recipient_email,
    v_action_type,
    v_team_selection_member_id,
    new.fixture_id,
    v_team_selection_id,
    new.id,
    array['ACCEPT','DECLINE'],
    v_code_hash,
    v_expires_at
  )
  returning id into v_request_id;

  update public.email_queue
     set payload = coalesce(payload, '{}'::jsonb) ||
       jsonb_build_object(
         'action_block',
         jsonb_build_object(
           'version', 1,
           'request_id', v_request_id,
           'action_type', v_action_type,
           'heading', v_heading,
           'instructions',
             'Select Accept or Decline. Your email application will open a prepared reply; send it without changing the response code.',
           'response_code', v_code,
           'expires_at', v_expires_at,
           'actions', jsonb_build_array(
             jsonb_build_object(
               'command', 'ACCEPT',
               'label', v_accept_label,
               'style', 'positive'
             ),
             jsonb_build_object(
               'command', 'DECLINE',
               'label', v_decline_label,
               'style', 'negative'
             )
           )
         )
       )
   where id = new.id;

  return new;
end;
$function$;

comment on function public.prepare_team_selection_email_action() is
  'Adds modular Accept/Decline action blocks to active published-player, promoted-player and named-marker selection emails.';

grant execute
on function public.prepare_team_selection_email_action()
to public, anon, authenticated, service_role;
