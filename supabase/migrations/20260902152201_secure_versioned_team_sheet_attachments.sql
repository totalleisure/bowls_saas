DROP FUNCTION IF EXISTS public.attach_publication_team_sheet(uuid, uuid, jsonb);

CREATE OR REPLACE FUNCTION public.attach_publication_team_sheet(
  p_fixture_id uuid,
  p_team_selection_id uuid,
  p_expected_composition_version integer,
  p_attachment jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_actual_composition_version integer;
  v_notification_rows integer := 0;
  v_email_rows integer := 0;
  v_pdf_bytes bytea;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not signed in.';
  END IF;

  IF NOT (
    COALESCE(public.can_manage_team_selection(p_fixture_id), false)
    OR EXISTS (
      SELECT 1
      FROM public.app_superusers su
      WHERE su.user_id = v_user_id
    )
  ) THEN
    RAISE EXCEPTION 'You do not have permission to attach this team sheet.';
  END IF;

  SELECT ts.composition_version
  INTO v_actual_composition_version
  FROM public.team_selections ts
  WHERE ts.id = p_team_selection_id
    AND ts.fixture_id = p_fixture_id
    AND ts.status = 'published'::public.selection_status
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Published team selection not found for this fixture.';
  END IF;

  IF p_expected_composition_version IS NULL
     OR p_expected_composition_version <> v_actual_composition_version THEN
    RAISE EXCEPTION
      'Team composition changed. Expected version %, current version %.',
      p_expected_composition_version,
      v_actual_composition_version;
  END IF;

  IF jsonb_typeof(p_attachment) <> 'object'
     OR NULLIF(BTRIM(p_attachment->>'name'), '') IS NULL
     OR p_attachment->>'contentType' <> 'application/pdf'
     OR NULLIF(BTRIM(p_attachment->>'contentBytes'), '') IS NULL
     OR NOT (p_attachment ? 'compositionVersion')
     OR (p_attachment->>'compositionVersion')::integer
        <> v_actual_composition_version THEN
    RAISE EXCEPTION
      'Invalid or obsolete team-sheet attachment for composition version %.',
      v_actual_composition_version;
  END IF;

  BEGIN
    v_pdf_bytes := decode(p_attachment->>'contentBytes', 'base64');
  EXCEPTION
    WHEN OTHERS THEN
      RAISE EXCEPTION 'Invalid Team Sheet PDF encoding.';
  END;

  IF octet_length(v_pdf_bytes) = 0
     OR substring(v_pdf_bytes FROM 1 FOR 4) <> convert_to('%PDF', 'UTF8') THEN
    RAISE EXCEPTION 'The Team Sheet attachment is not a valid PDF.';
  END IF;

  -- Enforce a conservative decoded-byte ceiling below Graph's transport limit.
  IF octet_length(v_pdf_bytes) > 2000000 THEN
    RAISE EXCEPTION 'The Team Sheet PDF exceeds the 2 MB attachment limit.';
  END IF;

  UPDATE public.notification_queue nq
  SET
    payload = jsonb_set(
      jsonb_set(
        COALESCE(nq.payload, '{}'::jsonb),
        '{attachments}',
        jsonb_build_array(p_attachment),
        true
      ),
      '{team_sheet_composition_version}',
      to_jsonb(v_actual_composition_version),
      true
    ),
    status = 'pending',
    last_error = NULL
  WHERE nq.fixture_id = p_fixture_id
    AND nq.team_selection_id = p_team_selection_id
    AND (
      nq.status = 'pending'
      OR (
        nq.status = 'failed'
        AND nq.last_error = 'Required Team Sheet attachment is missing or stale.'
      )
    )
    AND nq.event_type IN (
      'team_published_player',
      'team_published_reserve',
      'team_published_captain',
      'team_published_vice',
      'fixture_selected',
      'reserve_promoted'
    )
    AND (
      nq.event_type IN ('fixture_selected', 'reserve_promoted')
      OR nq.payload->>'team_sheet_required' = 'true'
    )
    AND (
      nq.payload->'attachments' IS DISTINCT FROM jsonb_build_array(p_attachment)
      OR nq.payload->>'team_sheet_composition_version'
         IS DISTINCT FROM v_actual_composition_version::text
      OR nq.status = 'failed'
    );

  GET DIAGNOSTICS v_notification_rows = ROW_COUNT;

  UPDATE public.email_queue eq
  SET
    attachments = jsonb_build_array(p_attachment),
    payload = jsonb_set(
      COALESCE(eq.payload, '{}'::jsonb),
      '{team_sheet_composition_version}',
      to_jsonb(v_actual_composition_version),
      true
    ),
    status = CASE
      WHEN eq.status = 'failed'
       AND eq.last_error = 'Required Team Sheet attachment is missing or stale.'
        THEN 'pending'
      ELSE eq.status
    END,
    last_error = CASE
      WHEN eq.status = 'failed'
       AND eq.last_error = 'Required Team Sheet attachment is missing or stale.'
        THEN NULL
      ELSE eq.last_error
    END
  WHERE eq.fixture_id = p_fixture_id
    AND eq.team_selection_id = p_team_selection_id
    AND eq.status IN ('pending', 'failed')
    AND eq.sent_at IS NULL
    AND eq.event_type IN (
      'team_published_player',
      'team_published_reserve',
      'team_published_captain',
      'team_published_vice',
      'fixture_selected',
      'reserve_promoted'
    )
    AND (
      eq.attachments IS DISTINCT FROM jsonb_build_array(p_attachment)
      OR eq.payload->>'team_sheet_composition_version'
         IS DISTINCT FROM v_actual_composition_version::text
      OR (
        eq.status = 'failed'
        AND eq.last_error = 'Required Team Sheet attachment is missing or stale.'
      )
    );

  GET DIAGNOSTICS v_email_rows = ROW_COUNT;

  RETURN jsonb_build_object(
    'composition_version', v_actual_composition_version,
    'notification_rows_updated', v_notification_rows,
    'email_rows_updated', v_email_rows
  );
END;
$function$;

REVOKE ALL
ON FUNCTION public.attach_publication_team_sheet(uuid, uuid, integer, jsonb)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.attach_publication_team_sheet(uuid, uuid, integer, jsonb)
TO authenticated;

CREATE OR REPLACE FUNCTION public.validate_required_team_sheet_email_attachment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_current_version integer;
  v_attachment jsonb;
  v_pdf_bytes bytea;
BEGIN
  IF NEW.event_type NOT IN (
    'team_published_player',
    'team_published_reserve',
    'team_published_captain',
    'team_published_vice',
    'fixture_selected',
    'reserve_promoted'
  ) THEN
    RETURN NEW;
  END IF;

  IF NEW.fixture_id IS NULL OR NEW.team_selection_id IS NULL THEN
    RAISE EXCEPTION 'Required Team Sheet attachment is missing or stale.';
  END IF;

  SELECT ts.composition_version
  INTO v_current_version
  FROM public.team_selections ts
  WHERE ts.id = NEW.team_selection_id
    AND ts.fixture_id = NEW.fixture_id
    AND ts.status = 'published'::public.selection_status;

  IF NOT FOUND
     OR jsonb_typeof(COALESCE(NEW.attachments, '[]'::jsonb)) <> 'array'
     OR jsonb_array_length(COALESCE(NEW.attachments, '[]'::jsonb)) <> 1 THEN
    RAISE EXCEPTION 'Required Team Sheet attachment is missing or stale.';
  END IF;

  v_attachment := NEW.attachments->0;

  IF jsonb_typeof(v_attachment) <> 'object'
     OR v_attachment->>'contentType' <> 'application/pdf'
     OR NULLIF(BTRIM(v_attachment->>'contentBytes'), '') IS NULL
     OR NOT (v_attachment ? 'compositionVersion')
     OR (v_attachment->>'compositionVersion')::integer <> v_current_version THEN
    RAISE EXCEPTION 'Required Team Sheet attachment is missing or stale.';
  END IF;

  BEGIN
    v_pdf_bytes := decode(v_attachment->>'contentBytes', 'base64');
  EXCEPTION
    WHEN OTHERS THEN
      RAISE EXCEPTION 'Required Team Sheet attachment is missing or stale.';
  END;

  IF octet_length(v_pdf_bytes) = 0
     OR octet_length(v_pdf_bytes) > 2000000
     OR substring(v_pdf_bytes FROM 1 FOR 4) <> convert_to('%PDF', 'UTF8') THEN
    RAISE EXCEPTION 'Required Team Sheet attachment is missing or stale.';
  END IF;

  RETURN NEW;
EXCEPTION
  WHEN invalid_text_representation THEN
    RAISE EXCEPTION 'Required Team Sheet attachment is missing or stale.';
END;
$function$;

REVOKE ALL
ON FUNCTION public.validate_required_team_sheet_email_attachment()
FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS trg_00_validate_required_team_sheet_attachment
ON public.email_queue;

CREATE TRIGGER trg_00_validate_required_team_sheet_attachment
BEFORE INSERT OR UPDATE OF attachments
ON public.email_queue
FOR EACH ROW
EXECUTE FUNCTION public.validate_required_team_sheet_email_attachment();

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
      'team_sheet_required', true,
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

CREATE OR REPLACE FUNCTION public.reconcile_preselect_communications(p_fixture_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_actor_member_profile_id uuid;
  v_club_id uuid;
  v_team_selection_id uuid;
  v_selection_mode text := '';
  v_is_superuser boolean := false;
  v_has_permission boolean := false;
  v_fixture_selected_queued integer := 0;
  v_leadership_queued integer := 0;
  v_fixture_label text;
  v_start_at timestamptz;
  v_is_home boolean;
  v_venue_name text;
  v_captain uuid;
  v_vice uuid;
  v_marker_result jsonb := '{}'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  select
    f.club_id,
    ts.id,
    lower(coalesce(ct.selection_mode::text, '')),
    coalesce(nullif(btrim(f.team_name), ''), nullif(btrim(ct.name), ''), 'Pre-Select Fixture'),
    f.start_at,
    f.is_home,
    coalesce(v.name, ov.name, ''),
    f.captain_member_profile_id,
    f.vice_captain_member_profile_id
  into
    v_club_id,
    v_team_selection_id,
    v_selection_mode,
    v_fixture_label,
    v_start_at,
    v_is_home,
    v_venue_name,
    v_captain,
    v_vice
  from public.fixtures f
  left join public.competition_types ct
    on ct.id = f.competition_type_id
  left join public.venues v on v.id = f.venue_id
  left join public.venues ov on ov.id = f.opponent_venue_id
  left join lateral (
    select x.id
    from public.team_selections x
    where x.fixture_id = f.id
    order by x.created_at desc
    limit 1
  ) ts on true
  where f.id = p_fixture_id;

  if not found then
    raise exception 'Fixture not found.';
  end if;

  if v_team_selection_id is null then
    raise exception 'No team selection exists for this fixture.';
  end if;

  if v_selection_mode <> 'preselect' then
    raise exception 'This repair routine is only for Pre-Select fixtures.';
  end if;

  select public.my_member_profile_id()
  into v_actor_member_profile_id;

  select exists (
    select 1
    from public.app_superusers su
    where su.user_id = auth.uid()
  )
  into v_is_superuser;

  v_has_permission :=
    v_is_superuser
    or exists (
      select 1
      from public.fixtures f
      where f.id = p_fixture_id
        and (
          f.captain_member_profile_id = v_actor_member_profile_id
          or f.vice_captain_member_profile_id = v_actor_member_profile_id
        )
    )
    or exists (
      select 1
      from public.club_memberships cm
      where cm.club_id = v_club_id
        and cm.member_profile_id = v_actor_member_profile_id
        and cm.is_active = true
        and lower(cm.role::text) in ('admin', 'selector')
    );

  if not v_has_permission then
    raise exception
      'You do not have permission to repair this fixture''s communications.';
  end if;

  insert into public.notification_queue (
    event_type,
    member_profile_id,
    target_member_profile_id,
    fixture_id,
    team_selection_id,
    payload,
    status
  )
  select
    'fixture_selected',
    v_actor_member_profile_id,
    fra.member_profile_id,
    p_fixture_id,
    v_team_selection_id,
    jsonb_build_object(
      'fixture_label',
        coalesce(
          nullif(btrim(f.team_name), ''),
          nullif(btrim(ct.name), ''),
          'Pre-Select Fixture'
        ),
      'start_at', f.start_at,
      'fixture_date', f.start_at,
      'fixture_rink_id', fr.id,
      'team_no', fr.fixture_rink_no,
      'home_rink_label', fr.home_rink_label,
      'players_per_rink', fr.players_per_rink,
      'position', fra.position,
      'role',
        case
          when fra.position = 201 then 'marker'
          when fra.position between 101 and (100 + fr.players_per_rink)
            then 'opponent'
          else 'player'
        end,
      'team_sheet_required', true
    ),
    'pending'
  from public.fixture_rink_assignments fra
  join public.fixture_rinks fr
    on fr.id = fra.fixture_rink_id
  join public.fixtures f
    on f.id = fr.fixture_id
  left join public.competition_types ct
    on ct.id = f.competition_type_id
  where fra.fixture_id = p_fixture_id
    and fra.member_profile_id is not null
    and (
      fra.position between 1 and fr.players_per_rink
      or fra.position between 101 and (100 + fr.players_per_rink)
      or fra.position = 201
    )
    and not exists (
      select 1
      from public.notification_queue nq
      where nq.fixture_id = p_fixture_id
        and nq.team_selection_id = v_team_selection_id
        and nq.event_type = 'fixture_selected'
        and nq.target_member_profile_id = fra.member_profile_id
        and (
          nullif(nq.payload ->> 'position', '') is null
          or nq.payload ->> 'position' = fra.position::text
        )
        and (
          nullif(nq.payload ->> 'team_no', '') is null
          or nq.payload ->> 'team_no' = fr.fixture_rink_no::text
        )
    );

  get diagnostics v_fixture_selected_queued = row_count;

  -- Leadership who are not already receiving an assignment-specific message
  -- receive one informational publication copy of the same Team Sheet.
  insert into public.notification_queue (
    event_type,
    member_profile_id,
    target_member_profile_id,
    fixture_id,
    team_selection_id,
    payload,
    status
  )
  select
    leadership.event_type,
    v_actor_member_profile_id,
    leadership.member_profile_id,
    p_fixture_id,
    v_team_selection_id,
    jsonb_build_object(
      'fixture_label', v_fixture_label,
      'fixture_date', v_start_at,
      'start_at', v_start_at,
      'home_away', case when v_is_home then 'Home' else 'Away' end,
      'venue_name', v_venue_name,
      'team_sheet_required', true
    ),
    'pending'
  from (
    values
      ('team_published_captain'::text, v_captain),
      ('team_published_vice'::text, v_vice)
  ) as leadership(event_type, member_profile_id)
  where leadership.member_profile_id is not null
    and not exists (
      select 1
      from public.notification_queue existing
      where existing.fixture_id = p_fixture_id
        and existing.team_selection_id = v_team_selection_id
        and existing.target_member_profile_id = leadership.member_profile_id
        and existing.status in ('pending', 'sent')
        and existing.event_type in (
          'fixture_selected',
          'team_published_captain',
          'team_published_vice'
        )
    );

  get diagnostics v_leadership_queued = row_count;

  -- Reuses the existing duplicate-safe marker routine.
  select public.queue_open_marker_request_communications(p_fixture_id)
  into v_marker_result;

  return jsonb_build_object(
    'fixture_id', p_fixture_id,
    'fixture_selected_queued', v_fixture_selected_queued,
    'leadership_queued', v_leadership_queued,
    'marker_communications',
      coalesce(v_marker_result, '{}'::jsonb),
    'total_communications_queued',
      v_fixture_selected_queued
      + v_leadership_queued
      + coalesce(
          (v_marker_result ->> 'communications_queued')::integer,
          0
        )
  );
end;
$function$;


revoke all on function public.reconcile_preselect_communications(uuid) from public;
revoke all on function public.reconcile_preselect_communications(uuid) from anon;
revoke all on function public.reconcile_preselect_communications(uuid) from authenticated;
