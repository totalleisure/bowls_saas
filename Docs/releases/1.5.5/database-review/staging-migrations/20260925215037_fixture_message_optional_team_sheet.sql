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

CREATE OR REPLACE FUNCTION public.validate_required_team_sheet_email_attachment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
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
  ) AND NOT (NEW.event_type = 'fixture_message' AND
    (coalesce(NEW.payload->>'team_sheet_required', 'false') = 'true' OR jsonb_array_length(coalesce(NEW.attachments, '[]'::jsonb)) > 0)) THEN
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
     OR v_attachment->>'contentType' IS DISTINCT FROM 'application/pdf'
     OR NULLIF(BTRIM(v_attachment->>'contentBytes'), '') IS NULL
     OR NOT (v_attachment ? 'compositionVersion')
     OR (v_attachment->>'compositionVersion')::integer IS DISTINCT FROM v_current_version THEN
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

CREATE OR REPLACE FUNCTION public.attach_publication_team_sheet(p_fixture_id uuid, p_team_selection_id uuid, p_expected_composition_version integer, p_attachment jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
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

  IF jsonb_typeof(p_attachment) IS DISTINCT FROM 'object'
     OR NULLIF(BTRIM(p_attachment->>'name'), '') IS NULL
     OR p_attachment->>'contentType' IS DISTINCT FROM 'application/pdf'
     OR NULLIF(BTRIM(p_attachment->>'contentBytes'), '') IS NULL
     OR NOT (p_attachment ? 'compositionVersion')
     OR (p_attachment->>'compositionVersion')::integer
        IS DISTINCT FROM v_actual_composition_version THEN
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
      'reserve_promoted',
      'fixture_message'
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
    AND (eq.event_type <> 'fixture_message' OR eq.payload->>'team_sheet_required' = 'true')
    AND eq.status IN ('pending', 'failed')
    AND eq.sent_at IS NULL
    AND eq.event_type IN (
      'team_published_player',
      'team_published_reserve',
      'team_published_captain',
      'team_published_vice',
      'fixture_selected',
      'reserve_promoted',
      'fixture_message'
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
