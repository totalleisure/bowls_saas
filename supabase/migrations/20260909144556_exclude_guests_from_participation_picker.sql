create or replace function public.get_club_member_picker_list(
  p_club_id uuid,
  p_section text default 'open'::text,
  p_team_id uuid default null::uuid,
  p_fixture_id uuid default null::uuid,
  p_rsvp_statuses text[] default null::text[],
  p_search text default null::text,
  p_use_fixture_section boolean default true
)
returns table(
  member_profile_id uuid,
  display_name text,
  picker_name text,
  email_address text,
  phone text,
  sex_at_birth text,
  preferred_position text
)
language sql
security definer
set search_path = public
as $function$
with fixture_context as (
  select
    case
      when p_fixture_id is not null and p_use_fixture_section = true then
        (
          select lower(f.section::text)
          from public.fixtures f
          where f.id = p_fixture_id
          limit 1
        )
      else
        lower(coalesce(p_section, 'open'))
    end as effective_section
)

select
  mp.id as member_profile_id,
  coalesce(
    nullif(trim(mp.display_name), ''),
    nullif(trim(concat_ws(' ', mp.first_name, mp.last_name)), ''),
    'Unnamed member'
  ) as display_name,
  case
    when nullif(trim(mp.last_name), '') is not null then
      trim(concat_ws(', ',
        nullif(trim(mp.last_name), ''),
        nullif(trim(mp.first_name), '')
      ))
    else
      coalesce(
        nullif(trim(mp.display_name), ''),
        nullif(trim(concat_ws(' ', mp.first_name, mp.last_name)), ''),
        'Unnamed member'
      )
  end as picker_name,
  mp.email_address,
  mp.phone,
  mp.sex_at_birth,
  mp.preferred_position

from public.member_profiles mp
cross join fixture_context fc

where exists (
  select 1
  from public.club_memberships cm
  where cm.club_id = p_club_id
    and cm.member_profile_id = mp.id
    and cm.is_active = true
    and lower(cm.role::text) <> 'guest'
)

  and (
    fc.effective_section in ('open', 'mixed')
    or (
      fc.effective_section in ('men', 'mens')
      and lower(coalesce(mp.sex_at_birth, '')) = 'male'
    )
    or (
      fc.effective_section in ('ladies', 'women')
      and lower(coalesce(mp.sex_at_birth, '')) = 'female'
    )
  )

  and (
    p_team_id is null
    or exists (
      select 1
      from public.team_members tm
      where tm.team_id = p_team_id
        and tm.member_profile_id = mp.id
    )
  )

  and (
    p_fixture_id is null
    or p_rsvp_statuses is null
    or exists (
      select 1
      from public.fixture_rsvps fr
      where fr.fixture_id = p_fixture_id
        and fr.member_profile_id = mp.id
        and fr.status::text = any(p_rsvp_statuses)
    )
  )

  and (
    p_search is null
    or trim(p_search) = ''
    or (
      coalesce(mp.display_name, '') ilike '%' || p_search || '%'
      or concat_ws(' ', mp.first_name, mp.last_name) ilike '%' || p_search || '%'
      or coalesce(mp.email_address, '') ilike '%' || p_search || '%'
      or coalesce(mp.phone, '') ilike '%' || p_search || '%'
    )
  )

order by
  lower(coalesce(mp.last_name, '')),
  lower(coalesce(mp.first_name, '')),
  lower(coalesce(mp.display_name, ''));
$function$;
