begin;
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
        'team_published_player','competition_fixture_booked',
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

      if r.event_type in ('team_published_player','competition_fixture_booked','team_published_reserve','team_published_captain','team_published_vice')
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
        'team_published_player','competition_fixture_booked',
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
CREATE OR REPLACE FUNCTION public.cancel_fixture_safe(p_fixture_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_current_member uuid := public.my_member_profile_id();
  v_club_id uuid;
  v_start_at timestamptz;
  v_end_at timestamptz;
  v_fixture_label text;
  v_home_away text;
  v_venue_name text;
  v_opponent_name text;
  v_team_selection_id uuid;
  v_is_admin boolean := false;
  v_is_super boolean := false;
  v_is_captain_or_vice boolean := false;
  v_count integer := 0;
begin
  if v_current_member is null then
    raise exception 'Not signed in.';
  end if;

  select
    f.club_id,
    f.start_at,
    f.end_at,
    coalesce(nullif(f.team_name, ''), nullif(ct.name, ''), 'Fixture'),
    case when f.is_home then 'Home' else 'Away' end,
    coalesce(v.name, ''),
    coalesce(ov.name, ''),
    (f.captain_member_profile_id = v_current_member
      or f.vice_captain_member_profile_id = v_current_member)
  into
    v_club_id,
    v_start_at,
    v_end_at,
    v_fixture_label,
    v_home_away,
    v_venue_name,
    v_opponent_name,
    v_is_captain_or_vice
  from public.fixtures f
  left join public.competition_types ct on ct.id = f.competition_type_id
  left join public.venues v on v.id = f.venue_id
  left join public.venues ov on ov.id = f.opponent_venue_id
  where f.id = p_fixture_id;

  if not found then
    raise exception 'Fixture not found.';
  end if;

  select exists (
    select 1
    from public.club_memberships cm
    where cm.club_id = v_club_id
      and cm.member_profile_id = v_current_member
      and cm.is_active = true
      and cm.role in ('admin', 'selector')
  ) into v_is_admin;

  select exists (
    select 1
    from public.app_superusers su
    where su.user_id = auth.uid()
  ) into v_is_super;

  if not (public.can_manage_fixture(p_fixture_id) or public.is_active_fixture_creator(p_fixture_id)) then
    raise exception 'You do not have permission to cancel this fixture.';
  end if;

  if exists (
    select 1
    from public.fixtures f
    where f.id = p_fixture_id
      and f.cancelled_at is not null
  ) then
    raise exception 'Fixture is already cancelled.';
  end if;

  select ts.id
  into v_team_selection_id
  from public.team_selections ts
  where ts.fixture_id = p_fixture_id
  order by ts.created_at desc nulls last
  limit 1;

  --------------------------------------------------------------------
  -- Suppress undelivered operational communications for this fixture.
  -- Cancellation is a lifecycle event and is deliberately preserved.
  --------------------------------------------------------------------

  update public.email_queue eq
  set status = 'cancelled'
  where eq.fixture_id = p_fixture_id
    and eq.event_type in (
      'acceptance_reminder',
      'fixture_message',
      'fixture_moved',
      'fixture_opponent_changed',
      'fixture_rescheduled_availability',
      'fixture_rescheduled_manager',
      'fixture_rescheduled_selected',
      'fixture_selected',
      'marker_request_opened',
      'reserve_promoted',
      'team_acceptance_changed',
      'team_published_captain',
      'team_published_incomplete_request',
      'team_published_not_selected',
      'team_published_player','competition_fixture_booked',
      'team_published_reserve',
      'team_published_vice'
    )
    and eq.status in ('pending', 'failed')
    and eq.sent_at is null;

  update public.notification_queue nq
  set status = 'cancelled'
  where nq.fixture_id = p_fixture_id
    and nq.event_type in (
      'acceptance_reminder',
      'fixture_message',
      'fixture_moved',
      'fixture_opponent_changed',
      'fixture_rescheduled_availability',
      'fixture_rescheduled_manager',
      'fixture_rescheduled_selected',
      'fixture_selected',
      'marker_request_opened',
      'reserve_promoted',
      'team_acceptance_changed',
      'team_published_captain',
      'team_published_incomplete_request',
      'team_published_not_selected',
      'team_published_player','competition_fixture_booked',
      'team_published_reserve',
      'team_published_vice'
    )
    and nq.status = 'pending';

  update public.fixtures
  set
    cancelled_at = now(),
    cancelled_by_member_profile_id = v_current_member,
    cancellation_reason = nullif(btrim(p_reason), '')
  where id = p_fixture_id;

  insert into public.fixture_lifecycle_events (
    fixture_id,
    event_type,
    old_start_at,
    old_end_at,
    reason,
    created_by_member_profile_id
  )
  values (
    p_fixture_id,
    'cancelled',
    v_start_at,
    v_end_at,
    nullif(btrim(p_reason), ''),
    v_current_member
  );

  with recipients as (
    select f.captain_member_profile_id as member_profile_id
    from public.fixtures f
    where f.id = p_fixture_id
      and f.captain_member_profile_id is not null

    union

    select f.vice_captain_member_profile_id
    from public.fixtures f
    where f.id = p_fixture_id
      and f.vice_captain_member_profile_id is not null

    union

    select tsm.member_profile_id
    from public.team_selection_members tsm
    join public.team_selections ts on ts.id = tsm.team_selection_id
    where ts.fixture_id = p_fixture_id
      and tsm.member_profile_id is not null
      and coalesce(tsm.is_selected, false) = true

    union

    select frsvp.member_profile_id
    from public.fixture_rsvps frsvp
    where frsvp.fixture_id = p_fixture_id
      and frsvp.member_profile_id is not null
      and lower(coalesce(frsvp.status::text, '')) in ('yes', 'maybe')
  ),
  inserted as (
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
      'fixture_cancelled',
      v_current_member,
      r.member_profile_id,
      p_fixture_id,
      v_team_selection_id,
      jsonb_strip_nulls(
        jsonb_build_object(
          'fixture_label', v_fixture_label,
          'start_at', v_start_at,
          'end_at', v_end_at,
          'home_away', v_home_away,
          'venue_name', nullif(v_venue_name, ''),
          'opponent_name', nullif(v_opponent_name, ''),
          'reason', nullif(btrim(p_reason), '')
        )
      ),
      'pending'
    from recipients r
    where r.member_profile_id is not null
      and r.member_profile_id <> v_current_member
      and not exists (
        select 1
        from public.notification_queue nq
        where nq.fixture_id = p_fixture_id
          and nq.target_member_profile_id = r.member_profile_id
          and nq.event_type = 'fixture_cancelled'
          and nq.status in ('pending', 'sent')
      )
    returning 1
  )
  select count(*) into v_count from inserted;

  return v_count;
end;
$function$;
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
  if new.event_type not in ('fixture_selected', 'team_published_player','competition_fixture_booked', 'team_published_reserve', 'reserve_promoted', 'acceptance_reminder', 'fixture_rescheduled_selected')
     or new.member_profile_id is null
     or new.fixture_id is null then
    return new;
  end if;

  select
    ts.id,
    tsm.id,
    f.club_id,
    f.start_at,
    public.published_assignment_response_type(tsm.id)
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
    and (new.event_type not in ('acceptance_reminder', 'fixture_rescheduled_selected') or tsm.acceptance::text = 'pending')
    and coalesce(tsm.is_selected, false) = true
    and public.published_assignment_response_type(tsm.id) is not null
    and f.cancelled_at is null
  limit 1;

  if v_team_selection_member_id is null or v_action_type is null then
    return new;
  end if;

  -- Superseded unsent messages must not reach the token issuer.
  -- Keep sent messages as historical records; their old action is cancelled below.
  update public.email_queue eq
     set status = 'cancelled', last_error = null
   where eq.id in (
     select ear.source_email_queue_id from public.email_action_requests ear
     where ear.action_type = v_action_type
       and ear.target_record_id = v_team_selection_member_id
       and ear.status in ('pending', 'responded')
   )
     and eq.id <> new.id
     and eq.sent_at is null
     and eq.status in ('pending', 'failed');

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
  elsif exists(select 1 from public.team_selection_members where id=v_team_selection_member_id and role::text='reserve') then
    v_heading := 'Please respond to your reserve place';
    v_accept_label := 'Accept reserve place';
    v_decline_label := 'Decline reserve place';
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
    response_protocol_version,
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
    2,
    v_expires_at
  )
  returning id into v_request_id;

  update public.email_queue
     set payload = coalesce(payload, '{}'::jsonb) ||
       jsonb_build_object(
         'action_block',
         jsonb_build_object(
           'version', 2,
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
CREATE OR REPLACE FUNCTION public.reschedule_cancelled_fixture_safe(p_fixture_id uuid, p_new_start_at timestamp with time zone, p_new_end_at timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_current_member uuid := public.my_member_profile_id();
  v_source public.fixtures%rowtype;

  v_new_fixture_id uuid;
  v_old_team_selection_id uuid;
  v_new_team_selection_id uuid;

  v_is_admin boolean := false;
  v_is_super boolean := false;

  v_free_rinks integer;

  v_old_selection_status selection_status;

  v_fixture_label text;
  v_recipient record;
begin
  --------------------------------------------------------------------
  -- Basic validation
  --------------------------------------------------------------------

  if v_current_member is null then
    raise exception 'Not signed in.';
  end if;

  if p_new_start_at is null
     or p_new_end_at is null
     or p_new_start_at >= p_new_end_at then
    raise exception 'Invalid new fixture start/end time.';
  end if;

  select *
  into v_source
  from public.fixtures
  where id = p_fixture_id
  for update;

  if not found then
    raise exception 'Fixture not found.';
  end if;

  if v_source.cancelled_at is null then
    raise exception
      'Only a cancelled fixture can be rescheduled by this procedure.';
  end if;

  if v_source.rescheduled_to_fixture_id is not null then
    raise exception
      'This cancelled fixture has already been rescheduled.';
  end if;

  --------------------------------------------------------------------
  -- Fixture label for notifications
  --------------------------------------------------------------------

  select coalesce(
    nullif(btrim(v_source.team_name), ''),
    nullif(btrim(ct.name), ''),
    'Fixture'
  )
  into v_fixture_label
  from public.competition_types ct
  where ct.id = v_source.competition_type_id;

  if v_fixture_label is null then
    v_fixture_label := coalesce(
      nullif(btrim(v_source.team_name), ''),
      'Fixture'
    );
  end if;

  --------------------------------------------------------------------
  -- Permission
  --------------------------------------------------------------------

  select exists (
    select 1
    from public.club_memberships cm
    where cm.club_id = v_source.club_id
      and cm.member_profile_id = v_current_member
      and cm.is_active = true
      and cm.role = 'admin'
  )
  into v_is_admin;

  select exists (
    select 1
    from public.app_superusers su
    where su.user_id = auth.uid()
  )
  into v_is_super;

  if not (v_is_admin or v_is_super or public.is_active_fixture_creator(p_fixture_id)) then
    raise exception
      'You do not have permission to reschedule this fixture.';
  end if;

  --------------------------------------------------------------------
  -- Defensively suppress legacy undelivered operational communications
  -- for the cancelled fixture. Its lifecycle cancellation is preserved.
  --------------------------------------------------------------------

  update public.email_queue eq
  set status = 'cancelled'
  where eq.fixture_id = p_fixture_id
    and eq.event_type in (
      'acceptance_reminder',
      'fixture_message',
      'fixture_moved',
      'fixture_opponent_changed',
      'fixture_rescheduled_availability',
      'fixture_rescheduled_manager',
      'fixture_rescheduled_selected',
      'fixture_selected',
      'marker_request_opened',
      'reserve_promoted',
      'team_acceptance_changed',
      'team_published_captain',
      'team_published_incomplete_request',
      'team_published_not_selected',
      'team_published_player','competition_fixture_booked',
      'team_published_reserve',
      'team_published_vice'
    )
    and eq.status in ('pending', 'failed')
    and eq.sent_at is null;

  update public.notification_queue nq
  set status = 'cancelled'
  where nq.fixture_id = p_fixture_id
    and nq.event_type in (
      'acceptance_reminder',
      'fixture_message',
      'fixture_moved',
      'fixture_opponent_changed',
      'fixture_rescheduled_availability',
      'fixture_rescheduled_manager',
      'fixture_rescheduled_selected',
      'fixture_selected',
      'marker_request_opened',
      'reserve_promoted',
      'team_acceptance_changed',
      'team_published_captain',
      'team_published_incomplete_request',
      'team_published_not_selected',
      'team_published_player','competition_fixture_booked',
      'team_published_reserve',
      'team_published_vice'
    )
    and nq.status = 'pending';

  --------------------------------------------------------------------
  -- Final capacity check for a HOME fixture using rinks
  --------------------------------------------------------------------

  if v_source.is_home = true
     and v_source.green_area_id is not null
     and v_source.rinks_required > 0 then

    select free_capacity_rinks
    into v_free_rinks
    from public.get_green_rink_availability(
      v_source.green_area_id,
      p_new_start_at,
      p_new_end_at
    )
    limit 1;

    if v_free_rinks is null then
      raise exception
        'No rink availability returned for the selected green.';
    end if;

    if v_free_rinks < v_source.rinks_required then
      raise exception
        'Not enough rinks available on the new date: % free, % required.',
        v_free_rinks,
        v_source.rinks_required;
    end if;

  end if;

  --------------------------------------------------------------------
  -- Create the new LIVE fixture
  --------------------------------------------------------------------

  insert into public.fixtures (
    club_id,
    start_at,
    end_at,
    is_home,
    venue_id,
    green_area_id,
    opponent_name,
    opponent_contact,
    notes,
    fixture_type,
    section,
    dress_code,
    rinks_required,
    players_per_rink,
    orientation,
    time_range,
    captain_member_profile_id,
    opponent_venue_id,
    vice_captain_member_profile_id,
    team_name,
    team_id,
    requires_rsvp,
    competition_type_id,
    rescheduled_from_fixture_id,
    rescheduled_at,
    rescheduled_by_member_profile_id
  )
  values (
    v_source.club_id,
    p_new_start_at,
    p_new_end_at,
    v_source.is_home,
    v_source.venue_id,
    v_source.green_area_id,
    v_source.opponent_name,
    v_source.opponent_contact,
    v_source.notes,
    v_source.fixture_type,
    v_source.section,
    v_source.dress_code,
    v_source.rinks_required,
    v_source.players_per_rink,
    v_source.orientation,
    tstzrange(p_new_start_at, p_new_end_at, '[)'),
    v_source.captain_member_profile_id,
    v_source.opponent_venue_id,
    v_source.vice_captain_member_profile_id,
    v_source.team_name,
    v_source.team_id,
    v_source.requires_rsvp,
    v_source.competition_type_id,
    p_fixture_id,
    now(),
    v_current_member
  )
  returning id into v_new_fixture_id;

  --------------------------------------------------------------------
  -- Link OLD cancelled fixture to NEW fixture
  --------------------------------------------------------------------

  update public.fixtures
  set
    rescheduled_to_fixture_id = v_new_fixture_id,
    rescheduled_at = now(),
    rescheduled_by_member_profile_id = v_current_member
  where id = p_fixture_id;

  --------------------------------------------------------------------
  -- Copy logical rink/team structure
  --
  -- Physical rink labels are deliberately NOT carried forward.
  --------------------------------------------------------------------

  insert into public.fixture_rinks (
    fixture_id,
    fixture_rink_no,
    format,
    players_per_rink,
    home_rink_label,
    marker_required
  )
  select
    v_new_fixture_id,
    fr.fixture_rink_no,
    fr.format,
    fr.players_per_rink,
    null,
    fr.marker_required
  from public.fixture_rinks fr
  where fr.fixture_id = p_fixture_id
  order by fr.fixture_rink_no;

  --------------------------------------------------------------------
  -- Carry picked players into same logical team/rink positions
  --------------------------------------------------------------------

  insert into public.fixture_rink_assignments (
    fixture_id,
    fixture_rink_id,
    member_profile_id,
    position,
    display_name
  )
  select
    v_new_fixture_id,
    new_fr.id,
    fra.member_profile_id,
    fra.position,
    fra.display_name
  from public.fixture_rink_assignments fra
  join public.fixture_rinks old_fr
    on old_fr.id = fra.fixture_rink_id
  join public.fixture_rinks new_fr
    on new_fr.fixture_id = v_new_fixture_id
   and new_fr.fixture_rink_no = old_fr.fixture_rink_no
  where fra.fixture_id = p_fixture_id;

  --------------------------------------------------------------------
  -- Find latest team selection on original fixture
  --------------------------------------------------------------------

  select
    ts.id,
    ts.status
  into
    v_old_team_selection_id,
    v_old_selection_status
  from public.team_selections ts
  where ts.fixture_id = p_fixture_id
  order by ts.created_at desc
  limit 1;

  --------------------------------------------------------------------
  -- Recreate team selection on replacement fixture
  --------------------------------------------------------------------

  if v_old_team_selection_id is not null then

    insert into public.team_selections (
      fixture_id,
      status,
      published_at,
      published_by_member_profile_id,
      captain_member_profile_id,
      vice_captain_member_profile_id
    )
    values (
      v_new_fixture_id,
      v_old_selection_status,

      case
        when v_old_selection_status::text = 'published'
          then now()
        else null
      end,

      case
        when v_old_selection_status::text = 'published'
          then v_current_member
        else null
      end,

      v_source.captain_member_profile_id,
      v_source.vice_captain_member_profile_id
    )
    returning id into v_new_team_selection_id;

    ------------------------------------------------------------------
    -- Carry players/reserves but reset ALL acceptance responses
    ------------------------------------------------------------------

    insert into public.team_selection_members (
      team_selection_id,
      member_profile_id,
      role,
      acceptance,
      responded_at,
      is_selected,
      acceptance_by
    )
    select
      v_new_team_selection_id,
      tsm.member_profile_id,
      tsm.role,
      'pending'::acceptance_status,
      null,
      tsm.is_selected,
      null
    from public.team_selection_members tsm
    where tsm.team_selection_id = v_old_team_selection_id;

  end if;

  --------------------------------------------------------------------
  -- Deliberately DO NOT copy fixture_rsvps.
  --
  -- Availability belongs to the old date.
  --------------------------------------------------------------------

  --------------------------------------------------------------------
  -- Queue reschedule communications
  --
  -- Precedence:
  --   1. Selected player/reserve   -> selected (including captain/vice)
  --   2. Other Captain / Vice      -> manager
  --   3. Other eligible member     -> availability
  --------------------------------------------------------------------

  for v_recipient in
  with managers as (
    select v_source.captain_member_profile_id as member_profile_id
    where v_source.captain_member_profile_id is not null

    union

    select v_source.vice_captain_member_profile_id
    where v_source.vice_captain_member_profile_id is not null
  ),

  selected_members as (
    select distinct tsm.member_profile_id
    from public.team_selection_members tsm
    where tsm.team_selection_id = v_new_team_selection_id
      and tsm.member_profile_id is not null
      and coalesce(tsm.is_selected, false) = true

  ),

  eligible_team_members as (
    select distinct tm.member_profile_id
    from public.team_members tm
    where v_source.team_id is not null
      and tm.team_id = v_source.team_id
      and tm.is_active = true
  ),

  eligible_rsvp_members as (
    select distinct fr.member_profile_id
    from public.fixture_rsvps fr
    join public.club_memberships cm
      on cm.club_id = v_source.club_id
    and cm.member_profile_id = fr.member_profile_id
    and cm.is_active = true
    where v_source.team_id is null
      and fr.fixture_id = p_fixture_id
      and fr.status::text in ('yes', 'maybe')
  ),

  availability_members as (
    select member_profile_id
    from eligible_team_members

    union

    select member_profile_id
    from eligible_rsvp_members
  ),

  recipients as (
    ------------------------------------------------------------------
    -- Unselected managers receive information only
    ------------------------------------------------------------------
    select
      m.member_profile_id,
      'fixture_rescheduled_manager'::text as event_type
    from managers m
    where not exists (
      select 1 from selected_members s
      where s.member_profile_id = m.member_profile_id
    )

    union all

    ------------------------------------------------------------------
    -- Selected players/reserves, including managers, receive one request
    ------------------------------------------------------------------
    select
      s.member_profile_id,
      'fixture_rescheduled_selected'::text
    from selected_members s

    union all

    ------------------------------------------------------------------
    -- Remaining eligible members can submit fresh availability
    ------------------------------------------------------------------
    select
      a.member_profile_id,
      'fixture_rescheduled_availability'::text
    from availability_members a
    where not exists (
      select 1
      from managers m
      where m.member_profile_id = a.member_profile_id
    )
    and not exists (
      select 1
      from selected_members s
      where s.member_profile_id = a.member_profile_id
    )
  )
  select
    r.member_profile_id,
    r.event_type,
    case
      when r.event_type = 'fixture_rescheduled_selected'
       and exists (
         select 1
         from public.fixture_rink_assignments fra
         join public.team_selection_members tsm
           on tsm.team_selection_id = v_new_team_selection_id
          and tsm.member_profile_id = fra.member_profile_id
          and coalesce(tsm.is_selected, false) = true
          and lower(tsm.role::text) = 'marker'
         where fra.fixture_id = v_new_fixture_id
           and fra.member_profile_id = r.member_profile_id
           and fra.position = 201
       )
        then 'marker'::text
      else null::text
    end as recipient_role
  from recipients r
  where r.member_profile_id is not null
  loop
    -- Replace only this recipient's undelivered cancellation with the
    -- rescheduling event. Sent cancellations remain part of the audit trail.
    delete from public.notification_queue nq
    where nq.fixture_id = p_fixture_id
      and nq.target_member_profile_id = v_recipient.member_profile_id
      and nq.event_type = 'fixture_cancelled'
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
    select
      v_recipient.event_type,
      v_current_member,
      v_recipient.member_profile_id,
      v_new_fixture_id,
      v_new_team_selection_id,
      jsonb_strip_nulls(
        jsonb_build_object(
          'fixture_label', v_fixture_label,
          'old_fixture_id', p_fixture_id,
          'new_fixture_id', v_new_fixture_id,
          'old_start_at', v_source.start_at,
          'old_end_at', v_source.end_at,
          'new_start_at', p_new_start_at,
          'new_end_at', p_new_end_at,
          'recipient_role', v_recipient.recipient_role
        )
      ),
      'pending'
    where not exists (
      select 1
      from public.notification_queue nq
      where nq.fixture_id = v_new_fixture_id
        and nq.target_member_profile_id = v_recipient.member_profile_id
        and nq.event_type = v_recipient.event_type
        and nq.status in ('pending', 'sent')
    );
  end loop;

  --------------------------------------------------------------------
  -- Lifecycle audit
  --------------------------------------------------------------------

  insert into public.fixture_lifecycle_events (
    fixture_id,
    event_type,
    old_start_at,
    old_end_at,
    new_start_at,
    new_end_at,
    reason,
    created_by_member_profile_id
  )
  values (
    p_fixture_id,
    'rescheduled',
    v_source.start_at,
    v_source.end_at,
    p_new_start_at,
    p_new_end_at,
    v_source.cancellation_reason,
    v_current_member
  );

  return v_new_fixture_id;
end;
$function$;

create or replace function competition_private.queue_booking_communications(
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
 select case when p_kind='booked' then 'competition_fixture_booked' else 'fixture_moved' end,
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

commit;
