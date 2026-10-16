alter table public.team_selections
  add column if not exists composition_version bigint not null default 0;

comment on column public.team_selections.composition_version is
  'Optimistic concurrency version for confirmed published Team/RSVP composition changes.';

-- Remove the unused legacy overload, which can publish without queueing the
-- canonical publication communications. Current clients call the boolean
-- overload explicitly.
drop function if exists public.publish_team_selection_safe(uuid, uuid);


create or replace function public.confirm_team_changes(
  p_team_selection_id uuid,
  p_expected_version bigint,
  p_members jsonb,
  p_assignments jsonb
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
  v_current_version bigint;
  v_selection_mode text;
  v_team_id uuid;
  v_requires_rsvp boolean;
  v_before_positioned uuid[] := array[]::uuid[];
  v_before_reserves uuid[] := array[]::uuid[];
  v_after_positioned uuid[] := array[]::uuid[];
  v_added uuid[] := array[]::uuid[];
  v_removed uuid[] := array[]::uuid[];
  v_before_assignments jsonb := '{}'::jsonb;
  v_after_assignments jsonb := '{}'::jsonb;
  v_member_id uuid;
  v_event_type text;
  v_added_count integer := 0;
  v_removed_count integer := 0;
  v_promoted_count integer := 0;
  v_moved_count integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Not signed in.';
  end if;

  v_actor := public.my_member_profile_id();
  if v_actor is null then
    raise exception 'Member profile not found.';
  end if;

  if jsonb_typeof(coalesce(p_members, '[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_assignments, '[]'::jsonb)) <> 'array' then
    raise exception 'Team change payload must contain arrays.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_team_selection_id::text, 0));

  select
    ts.fixture_id,
    f.club_id,
    ts.composition_version,
    lower(btrim(coalesce(ct.selection_mode, ''))),
    f.team_id,
    coalesce(f.requires_rsvp, false)
  into
    v_fixture_id,
    v_club_id,
    v_current_version,
    v_selection_mode,
    v_team_id,
    v_requires_rsvp
  from public.team_selections ts
  join public.fixtures f on f.id = ts.fixture_id
  left join public.competition_types ct on ct.id = f.competition_type_id
  where ts.id = p_team_selection_id
    and ts.status = 'published'::public.selection_status
  for update of ts;

  if not found then
    raise exception 'Published team selection not found.';
  end if;

  if v_selection_mode = 'preselect'
     or (v_team_id is null and not v_requires_rsvp) then
    raise exception 'Confirm Team Changes is only available for published Team or RSVP fixtures.';
  end if;

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

  if exists (
    select 1
    from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
      as m(member_profile_id uuid, role text, is_selected boolean)
    where m.member_profile_id is null
       or lower(btrim(coalesce(m.role, ''))) not in ('player', 'reserve')
       or coalesce(m.is_selected, false) = false
  ) then
    raise exception 'Invalid desired team member state.';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
      as m(member_profile_id uuid, role text, is_selected boolean)
    group by m.member_profile_id
    having count(*) > 1
  ) then
    raise exception 'A member cannot appear more than once in the desired team.';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
      as m(member_profile_id uuid, role text, is_selected boolean)
    where not exists (
      select 1 from public.club_memberships cm
      where cm.club_id = v_club_id
        and cm.member_profile_id = m.member_profile_id
        and cm.is_active = true
    )
  ) then
    raise exception 'Target member is not an active member of this club';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(coalesce(p_assignments, '[]'::jsonb))
      as a(fixture_rink_id uuid, position integer, member_profile_id uuid)
    left join public.fixture_rinks fr
      on fr.id = a.fixture_rink_id and fr.fixture_id = v_fixture_id
    where a.member_profile_id is null
       or fr.id is null
       or a.position not between 1 and fr.players_per_rink
       or not exists (
         select 1
         from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
           as m(member_profile_id uuid, role text, is_selected boolean)
         where m.member_profile_id = a.member_profile_id
           and lower(btrim(m.role)) = 'player'
           and m.is_selected = true
       )
  ) then
    raise exception 'Invalid player-position assignment.';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(coalesce(p_assignments, '[]'::jsonb))
      as a(fixture_rink_id uuid, position integer, member_profile_id uuid)
    group by a.member_profile_id
    having count(*) > 1
  ) or exists (
    select 1
    from jsonb_to_recordset(coalesce(p_assignments, '[]'::jsonb))
      as a(fixture_rink_id uuid, position integer, member_profile_id uuid)
    group by a.fixture_rink_id, a.position
    having count(*) > 1
  ) then
    raise exception 'Duplicate desired player-position assignment.';
  end if;

  perform 1 from public.team_selection_members
  where team_selection_id = p_team_selection_id for update;
  perform 1 from public.fixture_rink_assignments
  where fixture_id = v_fixture_id for update;

  if not exists (
    (
      select tsm.member_profile_id, tsm.role::text
      from public.team_selection_members tsm
      where tsm.team_selection_id = p_team_selection_id
        and tsm.is_selected = true
        and tsm.role in (
          'player'::public.selection_member_role,
          'reserve'::public.selection_member_role
        )
      except
      select m.member_profile_id, lower(btrim(m.role))
      from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
        as m(member_profile_id uuid, role text, is_selected boolean)
    )
    union all
    (
      select m.member_profile_id, lower(btrim(m.role))
      from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
        as m(member_profile_id uuid, role text, is_selected boolean)
      except
      select tsm.member_profile_id, tsm.role::text
      from public.team_selection_members tsm
      where tsm.team_selection_id = p_team_selection_id
        and tsm.is_selected = true
        and tsm.role in (
          'player'::public.selection_member_role,
          'reserve'::public.selection_member_role
        )
    )
  ) and not exists (
    (
      select fra.fixture_rink_id, fra.position, fra.member_profile_id
      from public.fixture_rink_assignments fra
      join public.fixture_rinks fr
        on fr.id = fra.fixture_rink_id
       and fr.fixture_id = v_fixture_id
      where fra.fixture_id = v_fixture_id
        and fra.position between 1 and fr.players_per_rink
      except
      select a.fixture_rink_id, a.position, a.member_profile_id
      from jsonb_to_recordset(coalesce(p_assignments, '[]'::jsonb))
        as a(fixture_rink_id uuid, position integer, member_profile_id uuid)
    )
    union all
    (
      select a.fixture_rink_id, a.position, a.member_profile_id
      from jsonb_to_recordset(coalesce(p_assignments, '[]'::jsonb))
        as a(fixture_rink_id uuid, position integer, member_profile_id uuid)
      except
      select fra.fixture_rink_id, fra.position, fra.member_profile_id
      from public.fixture_rink_assignments fra
      join public.fixture_rinks fr
        on fr.id = fra.fixture_rink_id
       and fr.fixture_id = v_fixture_id
      where fra.fixture_id = v_fixture_id
        and fra.position between 1 and fr.players_per_rink
    )
  ) then
    return jsonb_build_object(
      'composition_version', v_current_version,
      'newly_positioned', 0,
      'reserve_promotions', 0,
      'removed_from_player_positions', 0,
      'position_only_moves', 0,
      'communications_queued', 0,
      'no_change', true
    );
  end if;

  if p_expected_version is distinct from v_current_version then
    raise exception 'TEAM_COMPOSITION_VERSION_CONFLICT:%:%',
      p_expected_version, v_current_version;
  end if;

  select
    coalesce(array_agg(distinct tsm.member_profile_id), array[]::uuid[]),
    coalesce(jsonb_object_agg(
      tsm.member_profile_id::text,
      jsonb_build_object('fixture_rink_id', fra.fixture_rink_id, 'position', fra.position)
    ), '{}'::jsonb)
  into v_before_positioned, v_before_assignments
  from public.team_selection_members tsm
  join public.fixture_rink_assignments fra
    on fra.fixture_id = v_fixture_id
   and fra.member_profile_id = tsm.member_profile_id
  join public.fixture_rinks fr
    on fr.id = fra.fixture_rink_id and fr.fixture_id = v_fixture_id
  where tsm.team_selection_id = p_team_selection_id
    and tsm.is_selected = true
    and tsm.role = 'player'::public.selection_member_role
    and fra.position between 1 and fr.players_per_rink;

  select coalesce(array_agg(member_profile_id), array[]::uuid[])
  into v_before_reserves
  from public.team_selection_members
  where team_selection_id = p_team_selection_id
    and is_selected = true
    and role = 'reserve'::public.selection_member_role;

  insert into public.team_selection_members (
    team_selection_id, member_profile_id, role, acceptance,
    responded_at, is_selected, acceptance_by
  )
  select
    p_team_selection_id,
    m.member_profile_id,
    lower(btrim(m.role))::public.selection_member_role,
    'pending'::public.acceptance_status,
    null,
    true,
    null
  from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
    as m(member_profile_id uuid, role text, is_selected boolean)
  on conflict (team_selection_id, member_profile_id) do update set
    role = excluded.role,
    is_selected = true;

  update public.team_selection_members tsm
  set is_selected = false
  where tsm.team_selection_id = p_team_selection_id
    and tsm.is_selected = true
    and tsm.role in (
      'player'::public.selection_member_role,
      'reserve'::public.selection_member_role
    )
    and not exists (
      select 1
      from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
        as m(member_profile_id uuid, role text, is_selected boolean)
      where m.member_profile_id = tsm.member_profile_id
    );

  delete from public.fixture_rink_assignments fra
  using public.fixture_rinks fr
  where fra.fixture_id = v_fixture_id
    and fr.id = fra.fixture_rink_id
    and fr.fixture_id = v_fixture_id
    and fra.position between 1 and fr.players_per_rink;

  insert into public.fixture_rink_assignments (
    fixture_id, fixture_rink_id, member_profile_id, position
  )
  select v_fixture_id, a.fixture_rink_id, a.member_profile_id, a.position
  from jsonb_to_recordset(coalesce(p_assignments, '[]'::jsonb))
    as a(fixture_rink_id uuid, position integer, member_profile_id uuid);

  select
    coalesce(array_agg(distinct tsm.member_profile_id), array[]::uuid[]),
    coalesce(jsonb_object_agg(
      tsm.member_profile_id::text,
      jsonb_build_object('fixture_rink_id', fra.fixture_rink_id, 'position', fra.position)
    ), '{}'::jsonb)
  into v_after_positioned, v_after_assignments
  from public.team_selection_members tsm
  join public.fixture_rink_assignments fra
    on fra.fixture_id = v_fixture_id
   and fra.member_profile_id = tsm.member_profile_id
  join public.fixture_rinks fr
    on fr.id = fra.fixture_rink_id and fr.fixture_id = v_fixture_id
  where tsm.team_selection_id = p_team_selection_id
    and tsm.is_selected = true
    and tsm.role = 'player'::public.selection_member_role
    and fra.position between 1 and fr.players_per_rink;

  select coalesce(array_agg(x), array[]::uuid[]) into v_added
  from unnest(v_after_positioned) x where not (x = any(v_before_positioned));
  select coalesce(array_agg(x), array[]::uuid[]) into v_removed
  from unnest(v_before_positioned) x where not (x = any(v_after_positioned));

  update public.team_selection_members
  set acceptance = 'pending'::public.acceptance_status,
      responded_at = null,
      acceptance_by = null
  where team_selection_id = p_team_selection_id
    and member_profile_id = any(v_added);

  delete from public.notification_queue
  where fixture_id = v_fixture_id
    and team_selection_id = p_team_selection_id
    and member_profile_id = any(v_added)
    and event_type = 'team_acceptance_changed'
    and status = 'pending'
    and payload->>'new_acceptance' = 'pending';

  update public.email_action_requests
  set status = 'cancelled', updated_at = now()
  where team_selection_id = p_team_selection_id
    and member_profile_id = any(v_removed)
    and status in ('pending', 'responded');

  update public.notification_queue
  set status = 'cancelled'
  where fixture_id = v_fixture_id
    and team_selection_id = p_team_selection_id
    and target_member_profile_id = any(v_removed)
    and event_type in ('fixture_selected', 'reserve_promoted', 'team_published_player')
    and status = 'pending';

  update public.email_queue
  set status = 'cancelled'
  where fixture_id = v_fixture_id
    and team_selection_id = p_team_selection_id
    and member_profile_id = any(v_removed)
    and event_type in ('fixture_selected', 'reserve_promoted', 'team_published_player')
    and status in ('pending', 'failed')
    and sent_at is null;

  foreach v_member_id in array v_added loop
    v_event_type := case
      when v_member_id = any(v_before_reserves) then 'reserve_promoted'
      else 'fixture_selected'
    end;
    perform public.queue_post_publication_player_change(
      (select id from public.team_selection_members
       where team_selection_id = p_team_selection_id
         and member_profile_id = v_member_id),
      v_event_type,
      v_actor
    );
    v_added_count := v_added_count + 1;
    if v_event_type = 'reserve_promoted' then
      v_promoted_count := v_promoted_count + 1;
    end if;
  end loop;

  v_removed_count := coalesce(array_length(v_removed, 1), 0);
  select count(*) into v_moved_count
  from unnest(v_after_positioned) x
  where x = any(v_before_positioned)
    and v_before_assignments->(x::text) is distinct from v_after_assignments->(x::text);

  update public.team_selections
  set composition_version = composition_version + 1
  where id = p_team_selection_id
  returning composition_version into v_current_version;

  return jsonb_build_object(
    'composition_version', v_current_version,
    'newly_positioned', v_added_count,
    'reserve_promotions', v_promoted_count,
    'removed_from_player_positions', v_removed_count,
    'position_only_moves', v_moved_count,
    'communications_queued', v_added_count
  );
end;
$function$;

revoke all on function public.confirm_team_changes(uuid, bigint, jsonb, jsonb)
from public, anon;
grant execute on function public.confirm_team_changes(uuid, bigint, jsonb, jsonb)
to authenticated;

CREATE OR REPLACE FUNCTION public.apply_email_action_response(p_response_code text, p_command text, p_sender_email text, p_graph_message_id text, p_received_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_request public.email_action_requests%rowtype;
  v_command text := upper(btrim(coalesce(p_command, '')));
  v_sender text := lower(btrim(coalesce(p_sender_email, '')));
  v_code_hash text;
  v_acceptance public.acceptance_status;
  v_target_valid boolean := false;
  v_result_detail text;
begin
  if nullif(btrim(coalesce(p_graph_message_id, '')), '') is null then
    return jsonb_build_object('ok', false, 'status', 'invalid_message_id');
  end if;

  if exists (
    select 1
    from public.email_action_response_log
    where graph_message_id = p_graph_message_id
  ) then
    return jsonb_build_object('ok', true, 'status', 'duplicate');
  end if;

  if nullif(btrim(coalesce(p_response_code, '')), '') is null then
    insert into public.email_action_response_log(
      graph_message_id, sender_email, command, result_status,
      result_detail, received_at
    ) values (
      p_graph_message_id, v_sender, v_command, 'invalid_code',
      'Response code was empty', p_received_at
    );

    return jsonb_build_object('ok', false, 'status', 'invalid_code');
  end if;

  v_code_hash := encode(
    extensions.digest(upper(btrim(p_response_code)), 'sha256'),
    'hex'
  );

  select *
  into v_request
  from public.email_action_requests
  where response_code_hash = v_code_hash
  for update;

  if not found then
    insert into public.email_action_response_log(
      graph_message_id, sender_email, command, result_status,
      result_detail, received_at
    ) values (
      p_graph_message_id, v_sender, v_command, 'invalid_code',
      'No action request matched the supplied response code', p_received_at
    );

    return jsonb_build_object('ok', false, 'status', 'invalid_code');
  end if;

  if v_request.status in ('cancelled', 'expired') then
    insert into public.email_action_response_log(
      request_id, graph_message_id, sender_email, command,
      result_status, result_detail, received_at
    ) values (
      v_request.id, p_graph_message_id, v_sender, v_command,
      v_request.status, 'The action request is no longer active', p_received_at
    );

    return jsonb_build_object('ok', false, 'status', v_request.status);
  end if;

  if v_request.expires_at is not null and now() >= v_request.expires_at then
    update public.email_action_requests
       set status = 'expired', updated_at = now()
     where id = v_request.id;

    insert into public.email_action_response_log(
      request_id, graph_message_id, sender_email, command,
      result_status, result_detail, received_at
    ) values (
      v_request.id, p_graph_message_id, v_sender, v_command,
      'expired', 'The response arrived after the fixture response deadline',
      p_received_at
    );

    return jsonb_build_object('ok', false, 'status', 'expired');
  end if;

  if v_sender = ''
     or v_sender <> lower(btrim(v_request.recipient_email)) then
    insert into public.email_action_response_log(
      request_id, graph_message_id, sender_email, command,
      result_status, result_detail, received_at
    ) values (
      v_request.id, p_graph_message_id, v_sender, v_command,
      'sender_mismatch', 'Sender did not match the selected member email address',
      p_received_at
    );

    return jsonb_build_object('ok', false, 'status', 'sender_mismatch');
  end if;

  if not (v_command = any(v_request.allowed_actions)) then
    insert into public.email_action_response_log(
      request_id, graph_message_id, sender_email, command,
      result_status, result_detail, received_at
    ) values (
      v_request.id, p_graph_message_id, v_sender, v_command,
      'invalid_command', 'Command is not allowed for this action request',
      p_received_at
    );

    return jsonb_build_object('ok', false, 'status', 'invalid_command');
  end if;

  if v_request.action_type = 'team_selection' then
    select exists (
      select 1
      from public.team_selection_members tsm
      join public.team_selections ts
        on ts.id = tsm.team_selection_id
      join public.fixtures f
        on f.id = ts.fixture_id
      where tsm.id = v_request.target_record_id
        and tsm.member_profile_id = v_request.member_profile_id
        and tsm.role::text = 'player'
        and coalesce(tsm.is_selected, false) = true
        and ts.status = 'published'
        and f.cancelled_at is null
        and f.id = v_request.fixture_id
        and exists (
          select 1
          from public.fixture_rink_assignments fra
          join public.fixture_rinks fr
            on fr.id = fra.fixture_rink_id
           and fr.fixture_id = f.id
          where fra.fixture_id = f.id
            and fra.member_profile_id = tsm.member_profile_id
            and fra.position between 1 and fr.players_per_rink
        )
    ) into v_target_valid;

    v_result_detail := 'Team selection acceptance was updated';

  elsif v_request.action_type = 'marker_assignment' then
    select exists (
      select 1
      from public.team_selection_members tsm
      join public.team_selections ts
        on ts.id = tsm.team_selection_id
      join public.fixtures f
        on f.id = ts.fixture_id
      where tsm.id = v_request.target_record_id
        and tsm.member_profile_id = v_request.member_profile_id
        and tsm.role::text = 'marker'
        and coalesce(tsm.is_selected, false) = true
        and ts.status = 'published'
        and f.cancelled_at is null
        and f.id = v_request.fixture_id
        and exists (
          select 1
          from public.fixture_rink_assignments fra
          where fra.fixture_id = f.id
            and fra.member_profile_id = tsm.member_profile_id
            and fra.position = 201
        )
    ) into v_target_valid;

    v_result_detail := 'Marker assignment acceptance was updated';

  else
    insert into public.email_action_response_log(
      request_id, graph_message_id, sender_email, command,
      result_status, result_detail, received_at
    ) values (
      v_request.id, p_graph_message_id, v_sender, v_command,
      'unsupported_action_type', 'No response handler is installed for this action type',
      p_received_at
    );

    return jsonb_build_object('ok', false, 'status', 'unsupported_action_type');
  end if;

  if not v_target_valid then
    update public.email_action_requests
       set status = 'cancelled', updated_at = now()
     where id = v_request.id;

    insert into public.email_action_response_log(
      request_id, graph_message_id, sender_email, command,
      result_status, result_detail, received_at
    ) values (
      v_request.id, p_graph_message_id, v_sender, v_command,
      'selection_no_longer_active',
      case
        when v_request.action_type = 'marker_assignment'
          then 'The member is no longer the active named marker for this published fixture'
        else 'The player is no longer actively selected for this published fixture'
      end,
      p_received_at
    );

    return jsonb_build_object(
      'ok', false,
      'status', 'selection_no_longer_active'
    );
  end if;

  v_acceptance := case v_command
    when 'ACCEPT' then 'accepted'::public.acceptance_status
    when 'DECLINE' then 'declined'::public.acceptance_status
  end;

  update public.team_selection_members
     set acceptance = v_acceptance,
         responded_at = p_received_at,
         acceptance_by = v_request.member_profile_id
   where id = v_request.target_record_id;

  update public.email_action_requests
     set status = 'responded',
         last_action = v_command,
         last_responded_at = p_received_at,
         last_sender_email = v_sender,
         last_graph_message_id = p_graph_message_id,
         updated_at = now()
   where id = v_request.id;

  insert into public.email_action_response_log(
    request_id, graph_message_id, sender_email, command,
    result_status, result_detail, received_at
  ) values (
    v_request.id, p_graph_message_id, v_sender, v_command,
    'processed', v_result_detail, p_received_at
  );

  return jsonb_build_object(
    'ok', true,
    'status', 'processed',
    'action_type', v_request.action_type,
    'action', v_command,
    'fixture_id', v_request.fixture_id,
    'team_selection_member_id', v_request.target_record_id
  );
end;
$function$;

revoke all
on function public.apply_email_action_response(text, text, text, text, timestamptz)
from public, anon, authenticated;

grant execute
on function public.apply_email_action_response(text, text, text, text, timestamptz)
to service_role;


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
  join public.fixture_rink_assignments fra
    on fra.fixture_id = f.id and fra.member_profile_id = tsm.member_profile_id
  join public.fixture_rinks fr
    on fr.id = fra.fixture_rink_id
   and fr.fixture_id = f.id
  where tsm.id = p_team_selection_member_id
    and tsm.role = 'player'::public.selection_member_role
    and tsm.is_selected = true
    and fra.position between 1 and fr.players_per_rink;

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
  v_selection_mode text;
  v_team_id uuid;
  v_requires_rsvp boolean;
  v_member public.team_selection_members%rowtype;
  v_queued boolean := false;
begin
  if auth.uid() is null then raise exception 'Not signed in.'; end if;
  v_actor := public.my_member_profile_id();
  if v_actor is null then raise exception 'Member profile not found.'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_team_selection_id::text, 0));
  select ts.fixture_id, f.club_id, ts.status::text,
         lower(btrim(coalesce(ct.selection_mode, ''))),
         f.team_id, coalesce(f.requires_rsvp, false)
  into v_fixture_id, v_club_id, v_selection_status,
       v_selection_mode, v_team_id, v_requires_rsvp
  from public.team_selections ts
  join public.fixtures f on f.id = ts.fixture_id
  left join public.competition_types ct on ct.id = f.competition_type_id
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

  if v_selection_status = 'published'
     and v_selection_mode <> 'preselect'
     and (v_team_id is not null or v_requires_rsvp)
     and (
       (p_is_selected and (not found or not coalesce(v_member.is_selected, false)))
       or (not p_is_selected and found and coalesce(v_member.is_selected, false))
     ) then
    raise exception 'Published Team/RSVP composition changes must be confirmed together.';
  end if;

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
  v_selection_mode text;
  v_team_id uuid;
  v_requires_rsvp boolean;
  v_member public.team_selection_members%rowtype;
  v_new_role text := lower(btrim(coalesce(p_role, '')));
  v_queued boolean := false;
begin
  if auth.uid() is null then raise exception 'Not signed in.'; end if;
  v_actor := public.my_member_profile_id();
  if v_actor is null then raise exception 'Member profile not found.'; end if;
  if v_new_role not in ('player', 'reserve') then raise exception 'Unsupported role transition.'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_team_selection_id::text, 0));
  select ts.fixture_id, f.club_id, ts.status::text,
         lower(btrim(coalesce(ct.selection_mode, ''))),
         f.team_id, coalesce(f.requires_rsvp, false)
  into v_fixture_id, v_club_id, v_selection_status,
       v_selection_mode, v_team_id, v_requires_rsvp
  from public.team_selections ts
  join public.fixtures f on f.id = ts.fixture_id
  left join public.competition_types ct on ct.id = f.competition_type_id
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

  if v_selection_status = 'published'
     and v_selection_mode <> 'preselect'
     and (v_team_id is not null or v_requires_rsvp) then
    raise exception 'Published Team/RSVP composition changes must be confirmed together.';
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
  v_selection_status text;
  v_selection_mode text;
  v_team_id uuid;
  v_requires_rsvp boolean;
  v_promoted_ids uuid[] := array[]::uuid[];
  v_promoted_id uuid;
begin
  if auth.uid() is null or v_current_member is null then
    raise exception 'Not signed in.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_team_selection_id::text, 0));

  select ts.fixture_id, f.club_id, ts.status::text,
         lower(btrim(coalesce(ct.selection_mode, ''))),
         f.team_id, coalesce(f.requires_rsvp, false)
  into v_fixture_id, v_club_id, v_selection_status,
       v_selection_mode, v_team_id, v_requires_rsvp
  from public.team_selections ts
  join public.fixtures f on f.id = ts.fixture_id
  left join public.competition_types ct on ct.id = f.competition_type_id
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

  if v_selection_status = 'published'
     and v_selection_mode <> 'preselect'
     and (v_team_id is not null or v_requires_rsvp) then
    raise exception 'Published Team/RSVP composition changes must be confirmed together.';
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
      when tsm.role::text = 'player'
       and exists (
         select 1
         from public.fixture_rink_assignments fra
         join public.fixture_rinks fr
           on fr.id = fra.fixture_rink_id
          and fr.fixture_id = f.id
         where fra.fixture_id = f.id
           and fra.member_profile_id = tsm.member_profile_id
           and fra.position between 1 and fr.players_per_rink
       ) then 'team_selection'
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
       and tsm.role::text = 'player'
       and exists (
         select 1
         from public.fixture_rink_assignments fra
         join public.fixture_rinks fr
           on fr.id = fra.fixture_rink_id
          and fr.fixture_id = f.id
         where fra.fixture_id = f.id
           and fra.member_profile_id = tsm.member_profile_id
           and fra.position between 1 and fr.players_per_rink
       ))
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


create or replace function public.queue_team_acceptance_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
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
