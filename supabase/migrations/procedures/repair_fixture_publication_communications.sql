create or replace function public.repair_fixture_publication_communications(
  p_fixture_id uuid
)
returns table(
  team_selection_id uuid,
  deleted_notifications integer,
  deleted_app_notifications integer,
  deleted_emails integer,
  queued_notifications integer,
  processed_notifications integer,
  status text
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_team_selection_id uuid;
  v_selection_mode text;
  v_before integer;
  v_after integer;
begin
  perform public.communications_require_superuser();

  select ts.id, lower(coalesce(ct.selection_mode::text, ''))
  into v_team_selection_id, v_selection_mode
  from public.fixtures f
  left join public.competition_types ct on ct.id = f.competition_type_id
  join lateral (
    select x.id
    from public.team_selections x
    where x.fixture_id = f.id and x.status::text = 'published'
    order by x.created_at desc
    limit 1
  ) ts on true
  where f.id = p_fixture_id;

  if v_team_selection_id is null then
    raise exception 'Published team selection not found.';
  end if;

  select count(*) into v_before
  from public.notification_queue nq
  where nq.fixture_id = p_fixture_id
    and nq.team_selection_id = v_team_selection_id
    and nq.status <> 'cancelled';

  if v_selection_mode = 'preselect' then
    perform public.reconcile_preselect_communications(p_fixture_id);
  else
    perform public.queue_team_publication_communications(
      p_fixture_id,
      v_team_selection_id,
      true
    );
  end if;

  select count(*) into v_after
  from public.notification_queue nq
  where nq.fixture_id = p_fixture_id
    and nq.team_selection_id = v_team_selection_id
    and nq.status <> 'cancelled';

  return query select
    v_team_selection_id,
    0,
    0,
    0,
    greatest(v_after - v_before, 0),
    0,
    'communications reconciled; no history deleted and no queue processed'::text;
end;
$function$;

revoke all on function public.repair_fixture_publication_communications(uuid)
from public, anon, authenticated;
grant execute on function public.repair_fixture_publication_communications(uuid)
to authenticated;
