create or replace function public.swap_fixture_rink_labels(
  p_a_fixture_rink_id uuid,
  p_b_fixture_rink_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  a_label text;
  b_label text;
  a_fixture_id uuid;
  b_fixture_id uuid;
begin
  select fr.home_rink_label, fr.fixture_id
  into a_label, a_fixture_id
  from public.fixture_rinks fr
  where fr.id = p_a_fixture_rink_id;

  select fr.home_rink_label, fr.fixture_id
  into b_label, b_fixture_id
  from public.fixture_rinks fr
  where fr.id = p_b_fixture_rink_id;

  if a_fixture_id is null or b_fixture_id is null then
    raise exception 'Both fixture rinks must exist.';
  end if;

  if not public.can_manage_fixture(a_fixture_id)
     or not public.can_manage_fixture(b_fixture_id) then
    raise exception 'You do not have permission to move these rink bookings.';
  end if;

  if a_label is null or b_label is null then
    raise exception 'Both fixture rinks must have a home_rink_label before swapping.';
  end if;

  update public.fixture_rinks
  set home_rink_label = null
  where id = p_a_fixture_rink_id;

  update public.fixture_rinks
  set home_rink_label = a_label
  where id = p_b_fixture_rink_id;

  update public.fixture_rinks
  set home_rink_label = b_label
  where id = p_a_fixture_rink_id;
end;
$function$;

revoke all on function public.swap_fixture_rink_labels(uuid, uuid)
from public, anon;
grant execute on function public.swap_fixture_rink_labels(uuid, uuid)
to authenticated, service_role;
