begin;
-- Both initial booking and updates use the ordinary fixture notification/email workers.
-- A revision key prevents retries from producing duplicate recipient messages.
create unique index notification_competition_booking_revision on public.notification_queue
 ((payload->>'competition_booking_key'),target_member_profile_id)
 where payload ? 'competition_booking_key';

create function competition_private.queue_booking_communications(
 p_fixture_id uuid,p_kind text,p_revision text,p_old_start_at timestamptz default null,p_old_end_at timestamptz default null
) returns integer language plpgsql security definer set search_path='' as $$
declare f public.fixtures; c public.club_competitions; m public.competition_draw_matches; r public.competition_rounds;
 selection_id uuid; details text; intro text; n integer; env text; rink_text text;
begin
 if auth.uid() is null or not competition_private.can_arrange_linked_fixture(p_fixture_id) then
 raise exception 'Only authorised competition participants or a Club Admin can communicate this booking' using errcode='42501';end if;
 if p_kind not in ('booked','updated') or nullif(p_revision,'') is null then raise exception 'A valid booking revision is required';end if;
 select * into strict f from public.fixtures where id=p_fixture_id for update;
 select * into strict m from public.competition_draw_matches where fixture_id=f.id;
 select * into strict c from public.club_competitions where id=m.competition_id;
 select * into strict r from public.competition_rounds where id=m.round_id;
 select id into strict selection_id from public.team_selections where fixture_id=f.id and status='published';
 select environment into strict env from public.competition_release_controls where id;
 select string_agg(coalesce(nullif(home_rink_label,''),'Not allocated'),', ' order by fixture_rink_no) into rink_text
 from public.fixture_rinks where fixture_id=f.id;
 details:=concat_ws(chr(10),'Competition: '||c.name,'Round: '||r.name||' '||m.match_number,
 (select name from public.competition_entries where id=m.side_a_entry_id)||' versus '||(select name from public.competition_entries where id=m.side_b_entry_id),
 'Date: '||to_char(f.start_at at time zone 'Europe/London','FMDay DD Mon YYYY'),
 'Time: '||to_char(f.start_at at time zone 'Europe/London','HH24:MI')||' to '||
 to_char(f.end_at at time zone 'Europe/London',case when (f.start_at at time zone 'Europe/London')::date=(f.end_at at time zone 'Europe/London')::date then 'HH24:MI' else 'FMDay DD Mon YYYY HH24:MI' end),
 'Venue: '||(select name from public.venues where id=f.venue_id),
 'Green: '||(select name from public.green_areas where id=f.green_area_id),'Rink: '||coalesce(rink_text,'Not allocated'),
 'Play by: '||coalesce(to_char(r.play_by,'DD Mon YYYY'),'Not set'));
 intro:=case when p_kind='booked' then 'Your competition fixture has been booked.'
 else 'Your competition fixture booking has changed.'||chr(10)||
 'Previous: '||to_char(p_old_start_at at time zone 'Europe/London','FMDay DD Mon YYYY HH24:MI')||' to '||to_char(p_old_end_at at time zone 'Europe/London','HH24:MI') end;
 insert into public.notification_queue(event_type,member_profile_id,target_member_profile_id,fixture_id,team_selection_id,payload,status)
 select case when p_kind='booked' then 'team_published_player' else 'fixture_moved' end,
 public.my_member_profile_id(),em.member_profile_id,f.id,selection_id,
 jsonb_build_object('competition_booking_key',f.id::text||':'||p_revision,
 'competition_booking_details',details,'competition_booking_intro',intro,
 'fixture_label',c.name||' - '||r.name||' '||m.match_number,'fixture_name',c.name,
 'fixture_date',f.start_at,'start_at',f.start_at,'old_start_at',p_old_start_at,'old_end_at',p_old_end_at,
 'new_start_at',f.start_at,'new_end_at',f.end_at,'team_sheet_required',false), 'pending'
 from public.competition_entry_members em join public.member_profiles mp on mp.id=em.member_profile_id
 where em.competition_id=c.id and em.entry_id in(m.side_a_entry_id,m.side_b_entry_id)
 -- Staging must never send copied production members either email or App notifications.
 and (env='production' or competition_private.email_recipient_allowed(mp.email_address))
 on conflict do nothing;
 get diagnostics n=row_count;
 return n;
end $$;
revoke all on function competition_private.queue_booking_communications(uuid,text,text,timestamptz,timestamptz) from public,anon,authenticated;
CREATE OR REPLACE FUNCTION public.arrange_competition_match(p_match_id uuid, p_green_area_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_rink_labels text[], p_orientation text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 m public.competition_draw_matches; c public.club_competitions; r public.competition_rounds;
 actor uuid; cid uuid; venue uuid; settings jsonb; nr int; nplayers int; ppr int;
 home_entry uuid; away_entry uuid; v_fixture uuid; assignments jsonb; selections jsonb; labels jsonb;
 is_admin boolean; requested int; conditions text;
begin
 if auth.uid() is null then raise exception 'Sign in required' using errcode='42501'; end if;
 select competition_id into cid from public.competition_draw_matches where id=p_match_id;
 select * into c from public.club_competitions where id=cid for update;
 if not found then raise exception 'Competition match not found'; end if;
 select * into strict m from public.competition_draw_matches where id=p_match_id for update;
 actor:=public.my_member_profile_id();
 is_admin:=competition_private.can_manage(c.club_id);
 if not is_admin and not exists (
   select 1 from public.competition_entry_members em
   join public.club_memberships cm on cm.member_profile_id=em.member_profile_id and cm.club_id=c.club_id
   where em.competition_id=c.id and em.entry_id in (m.side_a_entry_id,m.side_b_entry_id)
   and em.member_profile_id=actor and cm.is_active and cm.role::text<>'guest'
 ) then raise exception 'Only a player in this match or a Club Admin can arrange it' using errcode='42501'; end if;
 -- Retry returns the existing booking; it can never create a second fixture.
 if m.fixture_id is not null then return m.fixture_id; end if;
 if c.status<>'published' or m.status<>'to_be_arranged' or m.side_a_entry_id is null or m.side_b_entry_id is null
 then raise exception 'A published playable match is required'; end if;
 if c.fixture_type_id is null then raise exception 'Choose the competition Fixture Type first'; end if;
 if p_start_at is null or p_end_at is null or p_start_at<=now() or p_end_at<=p_start_at
    or p_end_at>p_start_at+interval '24 hours' then raise exception 'Choose a future date and a valid start and end time'; end if;
 select g.venue_id into venue from public.green_areas g join public.venues v on v.id=g.venue_id
 where g.id=p_green_area_id and v.club_id=c.club_id and v.is_home_venue;
 if venue is null then raise exception 'Choose a home green belonging to this Club'; end if;
 select * into strict r from public.competition_rounds where id=m.round_id;
 settings:=c.settings||r.rule_overrides;
 nr:=coalesce((settings->>'rinks_required')::int,1);
 nplayers:=(c.settings->>'players_per_entry')::int;
 if nr<1 or nplayers<1 or nplayers%nr<>0 then raise exception 'Competition team and rink settings are inconsistent'; end if;
 ppr:=nplayers/nr;
 if ppr not between 1 and 4 then raise exception 'Competition format requires between one and four players per rink'; end if;
 select count(distinct label) into requested from unnest(p_rink_labels) label where nullif(btrim(label),'') is not null;
 if p_rink_labels is null or cardinality(p_rink_labels)<>nr or requested<>nr then raise exception 'Select exactly % different rinks',nr; end if;
 -- Serialize against ordinary fixture inserts/updates as well as competition bookings.
 -- These locks last only for this short booking transaction, never while the user chooses.
 lock table public.fixtures in share row exclusive mode;
 lock table public.fixture_rinks in share row exclusive mode;
 if (select count(*) from public.get_green_rink_availability(p_green_area_id,p_start_at,p_end_at) a
     where a.rink_label=any(p_rink_labels) and not a.is_booked and a.free_capacity_rinks>=nr)<>nr
 then raise exception 'The selected rinks are no longer available. Refresh and choose another rink or time.'; end if;
 home_entry:=m.side_a_entry_id; away_entry:=m.side_b_entry_id;
 -- The ordinary member booking workflow requires its organiser on the player side.
 if exists(select 1 from public.competition_entry_members where entry_id=away_entry and member_profile_id=actor)
 then home_entry:=m.side_b_entry_id; away_entry:=m.side_a_entry_id; end if;
 if (select count(*) from public.competition_entry_members where entry_id=home_entry)<>nplayers
 or (select count(*) from public.competition_entry_members where entry_id=away_entry)<>nplayers
 then raise exception 'Both entries must contain the competition team size'; end if;
 with members as (
  select em.member_profile_id, em.entry_id,
   row_number() over(partition by em.entry_id order by
    nullif(strpos(lower(e.name),lower(btrim(mp.first_name||' '||mp.last_name))),0) nulls last,
    mp.last_name,mp.first_name,em.member_profile_id)::int as pos
  from public.competition_entry_members em join public.member_profiles mp on mp.id=em.member_profile_id
  join public.competition_entries e on e.id=em.entry_id
  where em.competition_id=c.id and em.entry_id in (home_entry,away_entry)
 ) select jsonb_agg(jsonb_build_object('team_no',((pos-1)/ppr)+1,
    'position',((pos-1)%ppr)+1+case when entry_id=home_entry then 0 else 100 end,
    'member_profile_id',member_profile_id)),
   jsonb_agg(jsonb_build_object('member_profile_id',member_profile_id,
    'role',case when entry_id=home_entry then 'player' else 'opponent' end,
    'is_selected',true,'acceptance',case when member_profile_id=actor then 'accepted' else 'pending' end))
 into assignments,selections from members;
 select jsonb_agg(jsonb_build_object('team_no',i,'home_rink_label',label)) into labels
 from unnest(p_rink_labels) with ordinality t(label,i);
 conditions:=concat_ws(E'\n',c.name||' - '||r.name||' '||m.match_number,
    'Play by: '||coalesce(r.play_by::text,'Not set'),
    'Scoring: '||nullif(settings->>'scoring',''),
    'Woods per player: '||nullif(settings->>'woods_per_player',''),
    nullif(settings->>'rules',''));
 v_fixture:=public.create_fixture_with_match_fee(
   p_club_id=>c.club_id,p_start_at=>p_start_at,p_end_at=>p_end_at,p_is_home=>true,
   p_section=>coalesce(settings->>'section','open'),p_rinks_required=>nr,p_players_per_rink=>ppr,
   p_format=>settings->>'playing_format',p_competition_type_id=>c.fixture_type_id,
   p_dress_code=>coalesce(nullif(settings->>'dress',''),'open'),p_team_id=>null,p_team_name=>c.name,
   p_requires_rsvp=>false,p_venue_id=>venue,p_opponent_venue_id=>null,p_green_area_id=>p_green_area_id,
   p_orientation=>p_orientation,p_captain_member_profile_id=>actor,p_vice_captain_member_profile_id=>null,
   p_notes=>conditions,p_create_team_selection=>true,p_team_selection_status=>'published',
   p_home_rink_labels=>labels,p_rink_assignments=>assignments,p_team_selection_members=>selections,
   p_match_fee_pence=>null);
 update public.competition_draw_matches set fixture_id=v_fixture where id=m.id;
 perform competition_private.queue_booking_communications(v_fixture,'booked','booked');
 return v_fixture;
end $function$;
CREATE OR REPLACE FUNCTION public.change_competition_fixture_booking(p_fixture_id uuid, p_green_area_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_rink_labels text[], p_orientation text, p_expected_start_at timestamp with time zone, p_expected_end_at timestamp with time zone, p_expected_green_area_id uuid, p_expected_rink_labels text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f public.fixtures; m public.competition_draw_matches; cid uuid; venue uuid; current_labels text[];
begin
 if not competition_private.can_arrange_linked_fixture(p_fixture_id) then raise exception 'You cannot manage this competition fixture, or it is locked' using errcode='42501'; end if;
 select competition_id into cid from public.competition_draw_matches where fixture_id=p_fixture_id;
 if cid is null then raise exception 'This fixture is not linked to a competition match' using errcode='42501'; end if;
 perform 1 from public.club_competitions where id=cid for update;
 select * into strict m from public.competition_draw_matches where fixture_id=p_fixture_id for update;
 -- Same serialization as initial competition booking, including ordinary fixture writes.
 lock table public.fixtures in share row exclusive mode;
 lock table public.fixture_rinks in share row exclusive mode;
 select * into strict f from public.fixtures where id=p_fixture_id for update;
 if not competition_private.can_arrange_linked_fixture(p_fixture_id) then raise exception 'You cannot manage this competition fixture, or it is locked' using errcode='42501'; end if;
 select array_agg(home_rink_label order by fixture_rink_no) into current_labels from public.fixture_rinks where fixture_id=f.id;
 if f.start_at is distinct from p_expected_start_at or f.end_at is distinct from p_expected_end_at
 or f.green_area_id is distinct from p_expected_green_area_id or current_labels is distinct from p_expected_rink_labels
 then raise exception 'The booking has changed. Refresh before making another change.' using errcode='40001'; end if;
 if p_start_at is null or p_end_at is null or p_start_at<=now() or p_end_at<=p_start_at or p_end_at>p_start_at+interval '24 hours'
 then raise exception 'Choose a future start and valid end time'; end if;
 select g.venue_id into venue from public.green_areas g join public.venues v on v.id=g.venue_id
 where g.id=p_green_area_id and v.club_id=f.club_id and v.is_home_venue;
 if venue is null then raise exception 'Choose a home green for this Club'; end if;
 if p_rink_labels is null or cardinality(p_rink_labels)<>f.rinks_required
 or (select count(distinct label) from unnest(p_rink_labels) label where nullif(btrim(label),'') is not null)<>f.rinks_required
 or (select count(*) from public.fixture_rinks where fixture_id=f.id)<>f.rinks_required
 then raise exception 'Select the required number of different rinks'; end if;
 if (select count(*) from public.get_green_rink_availability(p_green_area_id,p_start_at,p_end_at,p_fixture_id) a
 where a.rink_label=any(p_rink_labels) and not a.is_booked and a.free_capacity_rinks>=f.rinks_required)<>f.rinks_required
 then raise exception 'The selected rinks are no longer available. Refresh and choose another rink or time.'; end if;
 if f.start_at=p_start_at and f.end_at=p_end_at and f.green_area_id=p_green_area_id
 and f.orientation::text is not distinct from nullif(btrim(p_orientation),'') and current_labels=p_rink_labels then return;end if;
 update public.fixtures set start_at=p_start_at,end_at=p_end_at,venue_id=venue,green_area_id=p_green_area_id,
 orientation=nullif(btrim(p_orientation),'')::public.orientation where id=f.id;
 with ordered as(select id,row_number() over(order by fixture_rink_no)::int as i from public.fixture_rinks where fixture_id=f.id)
 update public.fixture_rinks fr set home_rink_label=p_rink_labels[o.i] from ordered o where fr.id=o.id;
 insert into public.competition_fixture_management_events(club_id,fixture_id,match_id,actor_user_id,action,details)
 values(f.club_id,f.id,m.id,auth.uid(),'booking_changed',jsonb_build_object('previous',jsonb_build_object('start_at',f.start_at,'end_at',f.end_at,'green_area_id',f.green_area_id,'rinks',current_labels),
 'current',jsonb_build_object('start_at',p_start_at,'end_at',p_end_at,'green_area_id',p_green_area_id,'rinks',p_rink_labels)));
 perform competition_private.queue_booking_communications(f.id,'updated',
 'management:'||(select id::text from public.competition_fixture_management_events where fixture_id=f.id order by recorded_at desc,id desc limit 1),f.start_at,f.end_at);
end $function$;
CREATE OR REPLACE FUNCTION public.queue_fixture_moved_notifications(p_fixture_id uuid, p_old_start_at timestamp with time zone, p_old_end_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_count int := 0;
begin
  if not (public.can_manage_fixture(p_fixture_id) or public.is_active_fixture_creator(p_fixture_id)) then
    raise exception 'You do not have permission to queue fixture-move notifications.';
  end if;

  if exists(select 1 from public.competition_draw_matches where fixture_id=p_fixture_id) then
    if exists(select 1 from public.fixtures where id=p_fixture_id and start_at is not distinct from p_old_start_at and end_at is not distinct from p_old_end_at) then return 0;end if;
    return competition_private.queue_booking_communications(p_fixture_id,'updated',
      'time:'||(select revision::text from calendar_private.fixture_events where fixture_id=p_fixture_id),p_old_start_at,p_old_end_at);
  end if;
  -- Serialize retries for this fixture without locking other clubs' fixtures.
  perform 1 from public.fixtures where id = p_fixture_id for update;

  with recipients as (
    -- Includes assigned markers (position 201), as well as playing positions.
    select fra.member_profile_id
    from public.fixture_rink_assignments fra
    where fra.fixture_id = p_fixture_id

    union

    select tsm.member_profile_id
    from public.team_selections ts
    join public.team_selection_members tsm on tsm.team_selection_id = ts.id
    where ts.fixture_id = p_fixture_id
      and ts.status = 'published'
      and tsm.is_selected = true

    union

    select f.captain_member_profile_id
    from public.fixtures f where f.id = p_fixture_id

    union

    select f.vice_captain_member_profile_id
    from public.fixtures f where f.id = p_fixture_id
  )
  insert into public.notification_queue (
    target_member_profile_id,
    event_type,
    fixture_id,
    payload,
    status,
    created_at
  )
  select distinct
    recipient.member_profile_id,
    'fixture_moved',
    f.id,
    jsonb_build_object(
      'fixture_id', f.id,
      'fixture_name', coalesce(ct.name, 'Fixture'),
      'old_start_at', p_old_start_at,
      'old_end_at', p_old_end_at,
      'new_start_at', f.start_at,
      'new_end_at', f.end_at,
      'is_home', f.is_home,
      'venue_name', venue.name,
      'opponent_name', opponent.name
    ),
    'pending',
    now()
  from public.fixtures f
  cross join recipients recipient
  left join public.competition_types ct
    on ct.id = f.competition_type_id
  left join public.venues venue
    on venue.id = f.venue_id
  left join public.venues opponent
    on opponent.id = f.opponent_venue_id
  where f.id = p_fixture_id
    and recipient.member_profile_id is not null
    and not exists (
      select 1
      from public.notification_queue existing
      where existing.fixture_id = f.id
        and existing.event_type = 'fixture_moved'
        and existing.target_member_profile_id = recipient.member_profile_id
        and (existing.payload ->> 'old_start_at')::timestamptz is not distinct from p_old_start_at
        and nullif(existing.payload ->> 'old_end_at', '')::timestamptz is not distinct from p_old_end_at
        and (existing.payload ->> 'new_start_at')::timestamptz is not distinct from f.start_at
        and nullif(existing.payload ->> 'new_end_at', '')::timestamptz is not distinct from f.end_at
        and existing.status in ('pending', 'processing', 'sent')
    );

  get diagnostics v_count = row_count;

  return v_count;
end;
$function$;
CREATE OR REPLACE FUNCTION public.process_notification_queue(p_limit integer DEFAULT 20)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions', 'pg_temp'
AS $function$
declare
  r record;
  v_title text;
  v_body text;
  v_count int := 0;
  v_player_name text;
  v_fixture_label text;
  v_fixture_date_text text;
  v_home_away text;
  v_venue_name text;
  v_start_at timestamptz;
  v_created_text text;
  v_source text;

  v_team_no text;
  v_position int;
  v_players_per_rink int;
  v_role text;
  v_position_text text;
  v_home_rink_label text;

  v_team_no_int int;
  v_fixture_context_text text;
  v_team_lines text;
  v_marker_lines text;

  v_opponent_lines text;

  v_selected_position int;
  v_selected_role text;
  v_selected_role_text text;

  v_captain_name text;
  v_captain_email text;
  v_captain_phone text;
  v_is_named_marker boolean;
begin
  -- current_user is the function owner here; inspect the invoking SQL role instead.
  if not (
    current_setting('role', true) = 'service_role'
    or (session_user = 'postgres' and coalesce(current_setting('role', true), 'none') in ('none','postgres'))
    or (auth.uid() is not null and public.is_app_superuser())
  ) then
    raise exception 'Superuser or server access required' using errcode = '42501';
  end if;
  for r in
    select *
    from notification_queue
    where status = 'pending'
      and (
        nullif(
          current_setting('app.notification_queue_ids', true),
          ''
        ) is null
        or id = any (
          string_to_array(
            current_setting('app.notification_queue_ids', true),
            ','
          )::uuid[]
        )
      )
    order by created_at
    limit p_limit
  loop
    begin
      if r.target_member_profile_id is null then
        update notification_queue
        set status = 'failed',
            attempts = attempts + 1,
            last_error = 'target_member_profile_id is null'
        where id = r.id;

        continue;
      end if;

      v_player_name := coalesce(r.payload->>'player_name', 'A player');
      v_fixture_label := coalesce(r.payload->>'fixture_label', 'Fixture');
      v_home_away := coalesce(r.payload->>'home_away', '');
      v_venue_name := coalesce(r.payload->>'venue_name', '');

      begin
        v_start_at := nullif(r.payload->>'fixture_date', '')::timestamptz;
      exception
        when others then
          v_start_at := null;
      end;

      v_fixture_date_text := case
        when v_start_at is not null then
          to_char(
            v_start_at at time zone 'Europe/London',
            'DD Mon YYYY HH24:MI'
          )
        else ''
      end;

      v_created_text := to_char(
        r.created_at,
        'DD-Mon-YYYY HH24:MI'
      );

      if r.event_type = 'team_acceptance_changed' then
        v_source := 'Team Update';
        v_title := v_source;

        v_fixture_date_text := case
          when v_start_at is not null then
            to_char(
              v_start_at at time zone 'Europe/London',
              'FMDay FMDD FMMonth YYYY "at" HH24:MI'
            )
          else ''
        end;

        select exists (
          select 1
          from public.team_selection_members tsm
          join public.fixture_rink_assignments fra
            on fra.fixture_id = r.fixture_id
           and fra.member_profile_id = tsm.member_profile_id
           and fra.position = 201
          where tsm.team_selection_id = r.team_selection_id
            and tsm.member_profile_id = r.member_profile_id
            and coalesce(tsm.is_selected, false) = true
            and lower(tsm.role::text) = 'marker'
        )
        into v_is_named_marker;

        if (r.payload->>'new_acceptance') = 'accepted' then
          v_body := v_player_name
            || case
                 when v_is_named_marker then
                   ' has accepted their marker assignment for '
                 else
                   ' has accepted their selection for '
               end
            || v_fixture_label;
        elsif (r.payload->>'new_acceptance') = 'declined' then
          v_body := v_player_name
            || case
                 when v_is_named_marker then
                   ' has declined their marker assignment for '
                 else
                   ' has declined their selection for '
               end
            || v_fixture_label;
        else
          v_body := v_player_name
            || case
                 when v_is_named_marker then
                   ' has changed their marker assignment response for '
                 else
                   ' has changed their selection response for '
               end
            || v_fixture_label;
        end if;

        if v_fixture_date_text <> '' then
          v_body := v_body || ' on ' || v_fixture_date_text;
        end if;

        v_body := v_body || '.';

        if (r.payload->>'new_acceptance') = 'declined' then
          v_body := v_body || ' Team changes may be needed.';
        end if;

        if v_home_away <> '' or v_venue_name <> '' then
          v_body := v_body
            || ' '
            || case
                 when v_home_away <> '' and v_venue_name <> '' then
                   v_home_away || ' at ' || v_venue_name
                 when v_home_away <> '' then
                   v_home_away
                 else
                   'Venue: ' || v_venue_name
               end
            || '.';
        end if;
      elsif r.event_type = 'guest_membership_request' then
        v_source := 'New Registration';
        v_title := v_source;

        v_body :=
          coalesce(r.payload->>'member_name', 'A new member')
          || ' has requested guest membership for '
          || coalesce(r.payload->>'club_name', 'the club')
          || '.';

        if coalesce(nullif(r.payload->>'member_email', ''), '') <> '' then
          v_body := v_body
            || chr(10) || chr(10)
            || 'Email: '
            || (r.payload->>'member_email');
        end if;

        if coalesce(nullif(r.payload->>'member_phone', ''), '') <> '' then
          v_body := v_body
            || chr(10)
            || 'Telephone: '
            || (r.payload->>'member_phone');
        end if;
      elsif r.event_type = 'guest_membership_approved' then
        v_source := 'Membership Approved';
        v_title := v_source;

        v_body :=
          'Welcome to '
          || coalesce(r.payload->>'club_name', 'the club')
          || '.'
          || chr(10) || chr(10)
          || 'Your membership has now been approved';

        if coalesce(nullif(r.payload->>'approved_by', ''), '') <> '' then
          v_body := v_body
            || ' by '
            || (r.payload->>'approved_by');
        end if;

        v_body := v_body
          || '.'
          || chr(10) || chr(10)
          || 'You can now access the members areas of the app.';
      elsif r.event_type in (
        'team_published_player',
        'fixture_selected',
        'reserve_promoted'
      ) then
        v_source := case r.event_type
          when 'team_published_player' then 'Team Published'
          when 'reserve_promoted' then 'Team Selection Changed'
          else 'Fixture Selection'
        end;
        v_title := v_source;

        v_team_no := null;
        v_selected_position := null;
        v_players_per_rink := null;
        v_home_rink_label := null;

        select
          fr.fixture_rink_no::text,
          fra.position,
          fr.players_per_rink,
          coalesce(fr.home_rink_label, '')
        into
          v_team_no,
          v_selected_position,
          v_players_per_rink,
          v_home_rink_label
        from public.fixture_rinks fr
        join public.fixture_rink_assignments fra
          on fra.fixture_rink_id = fr.id
        where fr.fixture_id = r.fixture_id
          and fra.member_profile_id = r.target_member_profile_id
        order by
          case when fra.position between 1 and 4 then 0 else 1 end,
          fr.fixture_rink_no,
          fra.position
        limit 1;

        v_team_no := coalesce(v_team_no, r.payload->>'team_no', '');
        v_team_no_int := nullif(v_team_no, '')::int;
        v_home_rink_label := coalesce(
          v_home_rink_label,
          r.payload->>'home_rink_label',
          ''
        );
        v_selected_position := coalesce(
          v_selected_position,
          nullif(r.payload->>'position', '')::int
        );
        v_players_per_rink := coalesce(
          v_players_per_rink,
          nullif(r.payload->>'players_per_rink', '')::int
        );
        v_selected_role := coalesce(r.payload->>'role', '');

        v_selected_role_text :=
          case
            when v_selected_position = 201 then
              'Marker'

            when v_selected_position >= 100 then
              'Opponent ' || (v_selected_position - 100)::text

            when v_selected_position = 1 then
              'Lead'

            when v_selected_position = 2
                 and v_players_per_rink = 2 then
              'Skip'

            when v_selected_position = 2 then
              'Second'

            when v_selected_position = 3 then
              'Third'

            when v_selected_position = 4 then
              'Skip'

            when v_selected_position is not null then
              'Position ' || v_selected_position::text

            else
              'Selected'
          end;

        select f.start_at
        into v_start_at
        from public.fixtures f
        where f.id = r.fixture_id;

        v_start_at := coalesce(
          v_start_at,
          nullif(r.payload->>'start_at', '')::timestamptz,
          nullif(r.payload->>'fixture_date', '')::timestamptz
        );

        v_fixture_date_text :=
          case
            when v_start_at is not null then
              to_char(
                v_start_at at time zone 'Europe/London',
                'FMDay DD Mon YYYY "at" HH24:MI'
              )
            else ''
          end;

        select
          case
            when coalesce(ct.is_internal, false) = true then
              coalesce(
                nullif(ct.name, ''),
                nullif(f.team_name, ''),
                'Internal Fixture'
              )

            when f.is_home = true then
              'Home against '
              || coalesce(opp.name, 'Opponent not set')

            else
              'Away at '
              || coalesce(venue.name, 'Venue not set')
          end
        into v_fixture_context_text
        from public.fixtures f
        left join public.competition_types ct
          on ct.id = f.competition_type_id
        left join public.venues venue
          on venue.id = f.venue_id
        left join public.venues opp
          on opp.id = f.opponent_venue_id
        where f.id = r.fixture_id;

        select string_agg(
          line_text,
          chr(10)
          order by sort_order
        )
        into v_team_lines
        from (
          select
            fra.position as sort_order,

            case
              when fra.position = 1 then
                'Lead: '

              when fra.position = 2
                   and fr.players_per_rink = 2 then
                'Skip: '

              when fra.position = 2 then
                'Second: '

              when fra.position = 3 then
                'Third: '

              when fra.position = 4 then
                'Skip: '

              else
                'Position ' || fra.position::text || ': '
            end

            ||

            coalesce(
              nullif(mp.display_name, ''),
              nullif(
                trim(
                  coalesce(mp.first_name, '')
                  || ' '
                  || coalesce(mp.last_name, '')
                ),
                ''
              ),
              'Unknown'
            ) as line_text

          from public.fixture_rinks fr
          join public.fixture_rink_assignments fra
            on fra.fixture_rink_id = fr.id
          left join public.member_profiles mp
            on mp.id = fra.member_profile_id

          where fr.fixture_id = r.fixture_id
            and fr.fixture_rink_no = v_team_no_int
            and fra.position between 1 and 4
        ) x;

        select string_agg(
          line_text,
          chr(10)
          order by sort_order
        )
        into v_opponent_lines
        from (
          select
            fra.position as sort_order,

            'Opponent '
            || (fra.position - 100)::text
            || ': '

            ||

            coalesce(
              nullif(fra.display_name, ''),
              nullif(mp.display_name, ''),
              nullif(
                trim(
                  coalesce(mp.first_name, '')
                  || ' '
                  || coalesce(mp.last_name, '')
                ),
                ''
              ),
              'Unknown'
            ) as line_text

          from public.fixture_rinks fr
          join public.fixture_rink_assignments fra
            on fra.fixture_rink_id = fr.id
          left join public.member_profiles mp
            on mp.id = fra.member_profile_id

          where fr.fixture_id = r.fixture_id
            and fr.fixture_rink_no = v_team_no_int
            and fra.position between 101 and 199
        ) x;

        select string_agg(
          line_text,
          chr(10)
          order by sort_order
        )
        into v_marker_lines
        from (
          select
            fra.position as sort_order,

            'Marker: '

            ||

            coalesce(
              nullif(mp.display_name, ''),
              nullif(
                trim(
                  coalesce(mp.first_name, '')
                  || ' '
                  || coalesce(mp.last_name, '')
                ),
                ''
              ),
              'Unknown'
            ) as line_text

          from public.fixture_rinks fr
          join public.fixture_rink_assignments fra
            on fra.fixture_rink_id = fr.id
          left join public.member_profiles mp
            on mp.id = fra.member_profile_id

          where fr.fixture_id = r.fixture_id
            and fr.fixture_rink_no = v_team_no_int
            and fra.position = 201
        ) x;

        v_body :=
          case
            when r.event_type = 'reserve_promoted' then
              'You have been promoted from reserve to '
            else
              'You have been selected as '
          end
          || coalesce(v_selected_role_text, 'Selected')
          || ' for '
          || coalesce(
               nullif(r.payload->>'fixture_label', ''),
               nullif(r.payload->>'fixture_name', ''),
               coalesce(v_fixture_context_text, 'this fixture')
             )

          || case
               when v_fixture_date_text <> ''
                 then chr(10)
                      || v_fixture_date_text
               else ''
             end

          || chr(10)

          || coalesce(v_fixture_context_text, '')

          || chr(10)
          || chr(10)

          || coalesce(
               v_team_lines,
               'Team details unavailable'
             );

        if coalesce(v_opponent_lines, '') <> '' then
          v_body :=
            v_body
            || chr(10)
            || v_opponent_lines;
        end if;

        if coalesce(v_marker_lines, '') <> '' then
          v_body :=
            v_body
            || chr(10)
            || v_marker_lines;
        end if;

        if v_home_rink_label <> '' then
          v_body :=
            v_body
            || chr(10)
            || chr(10)
            || 'Home Rink: '
            || v_home_rink_label;
        end if;
      elsif r.event_type = 'marker_request_opened' then
        v_source := 'Marker Required';
        v_title := v_source;

        v_fixture_label := coalesce(
          nullif(r.payload->>'fixture_label', ''),
          'Pre-Select Fixture'
        );

        v_team_no := coalesce(r.payload->>'team_no', '');
        v_home_rink_label := coalesce(
          nullif(r.payload->>'home_rink_label', ''),
          ''
        );
        v_home_away := coalesce(r.payload->>'home_away', '');
        v_venue_name := coalesce(r.payload->>'venue_name', '');

        begin
          v_start_at := coalesce(
            nullif(r.payload->>'start_at', '')::timestamptz,
            nullif(r.payload->>'fixture_date', '')::timestamptz
          );
        exception
          when others then
            v_start_at := null;
        end;

        v_fixture_date_text :=
          case
            when v_start_at is not null then
              to_char(
                v_start_at at time zone 'Europe/London',
                'FMDay DD Mon YYYY "at" HH24:MI'
              )
            else ''
          end;

        select
          coalesce(
            nullif(btrim(mp.display_name), ''),
            nullif(
              btrim(
                coalesce(mp.first_name, '')
                || ' '
                || coalesce(mp.last_name, '')
              ),
              ''
            ),
            'Fixture captain'
          ),
          coalesce(nullif(btrim(mp.email_address), ''), 'Not recorded'),
          coalesce(nullif(btrim(mp.phone), ''), 'Not recorded')
        into
          v_captain_name,
          v_captain_email,
          v_captain_phone
        from public.fixtures f
        left join public.member_profiles mp
          on mp.id = f.captain_member_profile_id
        where f.id = r.fixture_id;

        v_body :=
          'A volunteer marker is required for '
          || v_fixture_label
          || '.';

        if v_fixture_date_text <> '' then
          v_body :=
            v_body
            || chr(10) || chr(10)
            || 'When: '
            || v_fixture_date_text;
        end if;

        if v_home_away <> '' then
          v_body :=
            v_body
            || chr(10)
            || 'Home/Away: '
            || v_home_away;
        end if;

        if v_venue_name <> '' then
          v_body :=
            v_body
            || chr(10)
            || 'Venue: '
            || v_venue_name;
        end if;

        if coalesce(nullif(r.payload->>'opponent_name', ''), '') <> '' then
          v_body :=
            v_body
            || chr(10)
            || 'Opponent: '
            || (r.payload->>'opponent_name');
        end if;

        if v_team_no <> '' then
          v_body :=
            v_body
            || chr(10)
            || 'Team: '
            || v_team_no;
        end if;

        if v_home_rink_label <> '' then
          v_body :=
            v_body
            || chr(10)
            || 'Rink: '
            || v_home_rink_label;
        end if;

        v_body :=
          v_body
          || chr(10) || chr(10)
          || 'Please contact the fixture captain if you can help.'
          || chr(10)
          || 'Captain: '
          || coalesce(v_captain_name, 'Fixture captain')
          || chr(10)
          || 'Email: '
          || coalesce(v_captain_email, 'Not recorded')
          || chr(10)
          || 'Telephone: '
          || coalesce(v_captain_phone, 'Not recorded');

      elsif r.event_type = 'fixture_moved' then
        v_source := 'Fixture Moved';
        v_title := v_source;

        v_body :=
          coalesce(r.payload->>'fixture_name', 'Fixture')
          || chr(10)
          || chr(10)
          || 'This fixture has been moved.'
          || chr(10)
          || chr(10)
          || 'Old: '
          || to_char(
               (r.payload->>'old_start_at')::timestamptz at time zone 'Europe/London',
               'FMDay DD Mon YYYY "at" HH24:MI'
             )
          || chr(10)
          || 'New: '
          || to_char(
               (r.payload->>'new_start_at')::timestamptz at time zone 'Europe/London',
               'FMDay DD Mon YYYY "at" HH24:MI'
             );

        if coalesce(r.payload->>'is_home', '') = 'true' then
          v_body := v_body
            || chr(10)
            || chr(10)
            || 'Home against '
            || coalesce(r.payload->>'opponent_name', 'Opponent not set');
        else
          v_body := v_body
            || chr(10)
            || chr(10)
            || 'Away at '
            || coalesce(r.payload->>'venue_name', 'Venue not set');
        end if;

      elsif r.event_type = 'fixture_rescheduled_selected' then
        v_source := 'Fixture Rescheduled';
        v_title := v_source;

        v_body :=
          coalesce(r.payload->>'fixture_label', 'Fixture')
          || chr(10)
          || chr(10)
          || 'This fixture has been rescheduled.'
          || chr(10)
          || chr(10)
          || 'Old: '
          || to_char(
               (r.payload->>'old_start_at')::timestamptz
                 at time zone 'Europe/London',
               'FMDay DD Mon YYYY "at" HH24:MI'
             )
          || chr(10)
          || 'New: '
          || to_char(
               (r.payload->>'new_start_at')::timestamptz
                 at time zone 'Europe/London',
               'FMDay DD Mon YYYY "at" HH24:MI'
             )
          || chr(10)
          || chr(10)
          || case
               when r.payload->>'recipient_role' = 'marker' then
                 'Your previous marker assignment has been carried forward.'
                 || chr(10)
                 || 'Please check the new fixture and Accept or Decline your marker assignment.'
               else
                 'Your previous team selection has been carried forward.'
                 || chr(10)
                 || 'Please check the new fixture and Accept or Decline your selection.'
             end;

      elsif r.event_type = 'fixture_rescheduled_manager' then
        v_source := 'Fixture Rescheduled';
        v_title := v_source;

        v_body :=
          coalesce(r.payload->>'fixture_label', 'Fixture')
          || chr(10)
          || chr(10)
          || 'This fixture has been rescheduled.'
          || chr(10)
          || chr(10)
          || 'Old: '
          || to_char(
               (r.payload->>'old_start_at')::timestamptz
                 at time zone 'Europe/London',
               'FMDay DD Mon YYYY "at" HH24:MI'
             )
          || chr(10)
          || 'New: '
          || to_char(
               (r.payload->>'new_start_at')::timestamptz
                 at time zone 'Europe/London',
               'FMDay DD Mon YYYY "at" HH24:MI'
             )
          || chr(10)
          || chr(10)
          || 'The existing team has been carried forward.'
          || chr(10)
          || 'Player acceptance responses have been reset for the new date.';

      elsif r.event_type = 'fixture_rescheduled_availability' then
        v_source := 'Fixture Rescheduled';
        v_title := v_source;

        v_body :=
          coalesce(r.payload->>'fixture_label', 'Fixture')
          || chr(10)
          || chr(10)
          || 'This fixture has been rescheduled.'
          || chr(10)
          || chr(10)
          || 'Old: '
          || to_char(
               (r.payload->>'old_start_at')::timestamptz
                 at time zone 'Europe/London',
               'FMDay DD Mon YYYY "at" HH24:MI'
             )
          || chr(10)
          || 'New: '
          || to_char(
               (r.payload->>'new_start_at')::timestamptz
                 at time zone 'Europe/London',
               'FMDay DD Mon YYYY "at" HH24:MI'
             )
          || chr(10)
          || chr(10)
          || 'Please indicate your availability for the new date.';

      elsif r.event_type = 'acceptance_reminder' then
        
        v_source := 'Selection Reminder';
        v_title := v_source;

        v_body :=
            'Please confirm whether you accept your team selection for '
            || v_fixture_label
            || '.';

        if v_fixture_date_text <> '' then
            v_body := v_body || chr(10) || chr(10) || 'When: ' || v_fixture_date_text;
        end if;

        if v_home_away <> '' then
            v_body := v_body || chr(10) || 'Home/Away: ' || v_home_away;
        end if;
        if v_venue_name <> '' then
            v_body := v_body || chr(10) || 'Venue: ' || v_venue_name;
        end if;

      elsif r.event_type = 'team_published_reserve' then
        v_source := 'Selected as Reserve';
        v_title := v_source;

        v_body :=
          'You have been selected as a reserve for '
          || v_fixture_label
          || '.';

        if v_fixture_date_text <> '' then
          v_body := v_body || chr(10) || chr(10) || 'When: ' || v_fixture_date_text;
        end if;

        if v_home_away <> '' then
          v_body := v_body || chr(10) || 'Home/Away: ' || v_home_away;
        end if;

        if v_venue_name <> '' then
          v_body := v_body || chr(10) || 'Venue: ' || v_venue_name;
        end if;

      elsif r.event_type in ('team_published_captain', 'team_published_vice') then
        v_source := 'Team Published';
        v_title := v_source;

        v_body :=
          'The team has been published for '
          || v_fixture_label
          || '.';

        if coalesce((r.payload->>'missing_players')::int, 0) > 0 then
          v_body := v_body
            || chr(10)
            || chr(10)
            || 'The team is currently short of '
            || (r.payload->>'missing_players')
            || ' player(s).';
        end if;

        if v_fixture_date_text <> '' then
          v_body := v_body || chr(10) || chr(10) || 'When: ' || v_fixture_date_text;
        end if;

        if v_home_away <> '' then
          v_body := v_body || chr(10) || 'Home/Away: ' || v_home_away;
        end if;

        if v_venue_name <> '' then
          v_body := v_body || chr(10) || 'Venue: ' || v_venue_name;
        end if;

      elsif r.event_type = 'team_published_not_selected' then
        v_source := 'Team Selected';
        v_title := v_source;

        v_body :=
          'Thank you for making yourself available for '
          || v_fixture_label
          || '.'
          || chr(10)
          || chr(10)
          || 'The team has now been selected and you have not been selected on this occasion.';

        if v_fixture_date_text <> '' then
          v_body := v_body || chr(10) || chr(10) || 'When: ' || v_fixture_date_text;
        end if;

      elsif r.event_type = 'team_published_incomplete_request' then
        v_source := 'Players Still Required';
        v_title := v_source;

        v_body :=
          'The team has been published for '
          || v_fixture_label
          || ', but we are still looking for '
          || coalesce(nullif(r.payload->>'missing_players', ''), 'more')
          || ' player(s).'
          || chr(10)
          || chr(10)
          || 'If you are available, please contact the captain.';

        if v_fixture_date_text <> '' then
          v_body := v_body || chr(10) || chr(10) || 'When: ' || v_fixture_date_text;
        end if;

      elsif r.event_type = 'fixture_opponent_changed' then
        v_source := 'Fixture Update';
        v_title := 'Fixture opponent changed';

        v_start_at :=
          nullif(r.payload->>'start_at', '')::timestamptz;

        v_fixture_date_text :=
          case
            when v_start_at is not null then
              to_char(
                v_start_at at time zone 'Europe/London',
                'FMDay DD Mon YYYY "at" HH24:MI'
              )
            else
              ''
          end;

        v_body :=
          case
            when coalesce(r.payload->>'team_name', '') <> '' then
              'Home '
              || (r.payload->>'team_name')
              || ' v '
              || coalesce(
                  nullif(r.payload->>'new_opponent_name', ''),
                  'Opponent to be confirmed'
                )

            else
              'Home against '
              || coalesce(
                  nullif(r.payload->>'new_opponent_name', ''),
                  'opponent to be confirmed'
                )
          end;

        if v_fixture_date_text <> '' then
          v_body :=
            v_body
            || chr(10)
            || v_fixture_date_text;
        end if;

        v_body :=
          v_body
          || chr(10)
          || chr(10)
          || 'The opponent has changed from '
          || coalesce(
               nullif(r.payload->>'old_opponent_name', ''),
               'To be confirmed'
             )
          || ' to '
          || coalesce(
               nullif(r.payload->>'new_opponent_name', ''),
               'To be confirmed'
             )
          || '.';

      elsif r.event_type = 'fixture_cancelled' then
        v_source := 'Fixture Cancelled';
        v_title := v_source;

        v_start_at := nullif(r.payload->>'start_at', '')::timestamptz;

        v_fixture_date_text :=
          case
            when v_start_at is not null then
              to_char(
                v_start_at at time zone 'Europe/London',
                'FMDay DD Mon YYYY "at" HH24:MI'
              )
            else ''
          end;

        v_body := coalesce(nullif(r.payload->>'fixture_label', ''), 'Fixture');

        if v_fixture_date_text <> '' then
          v_body := v_body || chr(10) || v_fixture_date_text;
        end if;

        if coalesce(r.payload->>'home_away', '') = 'Home' then
          v_body := v_body || chr(10) || 'Home against ' || coalesce(nullif(r.payload->>'opponent_name', ''), 'opponent to be confirmed');
        elsif coalesce(r.payload->>'home_away', '') = 'Away' then
          v_body := v_body || chr(10) || 'Away at ' || coalesce(nullif(r.payload->>'venue_name', ''), 'venue not set');
        end if;

        v_body := v_body || chr(10) || chr(10) || 'This fixture has been cancelled.';

        if coalesce(nullif(r.payload->>'reason', ''), '') <> '' then
          v_body := v_body || chr(10) || chr(10) || 'Reason: ' || (r.payload->>'reason');
        end if;

      elsif r.event_type = 'fixture_message' then
        v_source := coalesce(
          nullif(r.payload->>'title', ''),
          'Fixture Message'
        );

        v_title := v_source || ' : ' || v_created_text;

        v_body := coalesce(nullif(r.payload->>'message', ''), 'You have a new fixture message.');

        if v_fixture_label <> '' then
          v_body := v_body || chr(10) || chr(10) || 'Fixture: ' || v_fixture_label;
        end if;

        if v_fixture_date_text <> '' then
          v_body := v_body || chr(10) || 'When: ' || v_fixture_date_text;
        end if;

        if v_home_away <> '' then
          v_body := v_body || chr(10) || 'Home/Away: ' || v_home_away;
        end if;

        if v_venue_name <> '' then
          v_body := v_body || chr(10) || 'Venue: ' || v_venue_name;
        end if;

        if coalesce(nullif(r.payload->>'opponent_name', ''), '') <> '' then
          v_body := v_body || chr(10) || 'Opponent: ' || (r.payload->>'opponent_name');
        end if;

        if coalesce(nullif(r.payload->>'captain_name', ''), '') <> '' then
          v_body := v_body || chr(10) || 'Captain: ' || (r.payload->>'captain_name');
        end if;

        if coalesce(nullif(r.payload->>'vice_captain_name', ''), '') <> '' then
          v_body := v_body || chr(10) || 'Vice-Captain: ' || (r.payload->>'vice_captain_name');
        end if;

        if coalesce(nullif(r.payload->>'sender_name', ''), '') <> '' then
          v_body := v_body || chr(10) || chr(10) || 'From: ' || (r.payload->>'sender_name');
        end if;
      else
        v_title := 'Update';
        v_body := 'You have a new notification';
      end if;

      if r.event_type in ('team_published_player','team_published_reserve','team_published_captain','team_published_vice')
         and nullif(btrim(r.payload->>'special_instructions'),'') is not null then
         v_body := v_body || chr(10) || chr(10) || 'Special instructions:' || chr(10) || (r.payload->>'special_instructions');
       end if;
      if nullif(r.payload->>'competition_booking_details','') is not null then
        v_title:=case when r.event_type='fixture_moved' then 'Competition fixture updated' else 'Competition fixture booked' end;
        v_body:=(r.payload->>'competition_booking_intro')||chr(10)||chr(10)||(r.payload->>'competition_booking_details');
      end if;
      insert into app_notifications (
        member_profile_id,
        type,
        title,
        body,
        data,
        fixture_id,
        team_selection_id
      )
      values (
        r.target_member_profile_id,
        r.event_type,
        v_title,
        v_body,
        jsonb_strip_nulls(
          jsonb_build_object(
            'source_member_profile_id', r.member_profile_id,
            'marker_request_id', nullif(r.payload->>'marker_request_id', ''),
            'fixture_rink_id', nullif(r.payload->>'fixture_rink_id', ''),
            'team_no', nullif(r.payload->>'team_no', '')
          )
        ),
        r.fixture_id,
        r.team_selection_id
      );

      -- Optional email queue for important notifications
      if r.event_type in (
        'team_acceptance_changed',
        'reserve_promoted',
        'guest_membership_request',
        'guest_membership_approved',
        'fixture_selected',
        'fixture_moved',
        'fixture_rescheduled_selected',
        'fixture_rescheduled_manager',
        'fixture_rescheduled_availability',        
        'fixture_opponent_changed',
        'fixture_cancelled',
        'marker_request_opened',
        'team_published_player',
        'team_published_reserve',
        'team_published_captain',
        'team_published_vice',
        'team_published_not_selected',
        'team_published_incomplete_request',        
        'acceptance_reminder',
        'fixture_message'
      ) then
        insert into public.email_queue (
          member_profile_id,
          event_type,
          recipient_email,
          subject,
          body,
          payload,
          fixture_id,
          team_selection_id,
          attachments
        )

        select
          r.target_member_profile_id,
          r.event_type,
          mp.email_address,
          v_title,
          v_body,
          jsonb_build_object(
            'fixture_id', r.fixture_id,
            'team_selection_id', r.team_selection_id,
            'team_sheet_required', coalesce(r.payload->'team_sheet_required', 'false'::jsonb)
          ),
          r.fixture_id,
          r.team_selection_id,
          coalesce(r.payload->'attachments', '[]'::jsonb)
        from public.member_profiles mp
        where mp.id = r.target_member_profile_id
          and mp.email_address is not null
          and btrim(mp.email_address) <> '';
      end if;

      update notification_queue
      set status = 'sent',
          processed_at = now(),
          last_error = null
      where id = r.id;

      v_count := v_count + 1;

    exception when others then
      update notification_queue
      set status = 'failed',
          attempts = attempts + 1,
          last_error = sqlerrm
      where id = r.id;
    end;
  end loop;

  return v_count;
end;
$function$;
commit;
