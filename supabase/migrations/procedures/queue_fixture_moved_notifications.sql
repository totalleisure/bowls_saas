create or replace function public.queue_fixture_moved_notifications(
  p_fixture_id uuid,
  p_old_start_at timestamptz,
  p_old_end_at timestamptz default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_count int := 0;
begin
  insert into public.notification_queue (
    target_member_profile_id,
    event_type,
    fixture_id,
    payload,
    status,
    created_at
  )
  select distinct
    fra.member_profile_id,
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
  join public.fixture_rink_assignments fra
    on fra.fixture_id = f.id
  left join public.competition_types ct
    on ct.id = f.competition_type_id
  left join public.venues venue
    on venue.id = f.venue_id
  left join public.venues opponent
    on opponent.id = f.opponent_venue_id
  where f.id = p_fixture_id
    and fra.member_profile_id is not null
    and not exists (
      select 1
      from public.notification_queue existing
      where existing.fixture_id = f.id
        and existing.event_type = 'fixture_moved'
        and existing.target_member_profile_id = fra.member_profile_id
        and existing.payload ->> 'old_start_at' = p_old_start_at::text
        and coalesce(existing.payload ->> 'old_end_at', '') =
            coalesce(p_old_end_at::text, '')
        and existing.payload ->> 'new_start_at' = f.start_at::text
        and coalesce(existing.payload ->> 'new_end_at', '') =
            coalesce(f.end_at::text, '')
        and existing.status in ('pending', 'processing', 'sent')
    );

  get diagnostics v_count = row_count;

  return v_count;
end;
$function$;

grant execute on function public.queue_fixture_moved_notifications(
  uuid,
  timestamptz,
  timestamptz
)
to authenticated;