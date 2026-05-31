CREATE OR REPLACE FUNCTION public.queue_fixture_selected_notifications(
  p_fixture_id uuid,
  p_attachments jsonb default null
)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare
    v_count integer := 0;
begin

    insert into notification_queue (
        target_member_profile_id,
        event_type,
        fixture_id,
        payload,
        status,
        created_at
    )
    select
        fra.member_profile_id,
        'fixture_selected',
        f.id,
        jsonb_build_object(
            'fixture_id', f.id,
            'fixture_name',
                coalesce(ct.name, 'Fixture'),
            'start_at',
                f.start_at,
            'team_no',
                fr.fixture_rink_no,
            'position',
                fra.position,
            'players_per_rink',
                fr.players_per_rink,
            'home_rink_label',
                fr.home_rink_label,
            'role',
                case
                    when fra.position = 201 then 'marker'
                    when fra.position >= 100 then 'opponent'
                    else 'player'
                end,
            'captain_member_profile_id',
                f.captain_member_profile_id,
            'venue_id',
                f.venue_id,
            'opponent_venue_id',
                f.opponent_venue_id,
            'attachments', coalesce(p_attachments, '[]'::jsonb)
        ),
        'pending',
        now()
    from fixture_rink_assignments fra
    join fixture_rinks fr
      on fr.id = fra.fixture_rink_id
    join fixtures f
      on f.id = fra.fixture_id
    left join competition_types ct
      on ct.id = f.competition_type_id
    where f.id = p_fixture_id;

    get diagnostics v_count = row_count;

    return v_count;
end;
$function$
