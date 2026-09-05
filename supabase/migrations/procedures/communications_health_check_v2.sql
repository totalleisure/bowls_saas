create or replace function public.communications_health_check_v2(p_fixture_id uuid)
returns table(item text, expected integer, actual integer, status text)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
begin
  perform public.communications_require_superuser();

  return query
  with detail as materialized (
    select * from public.communications_health_detail_v2(p_fixture_id)
  ),
  rows as (
    select 1 sort_order, 'Playing players'::text item,
      count(*) filter (where category = 'Player')::integer expected,
      count(*) filter (where category = 'Player' and app_notification = 'Created')::integer actual
    from detail
    union all select 2, 'Opponents',
      count(*) filter (where category = 'Opponent')::integer,
      count(*) filter (where category = 'Opponent' and app_notification = 'Created')::integer from detail
    union all select 3, 'Named markers',
      count(*) filter (where category = 'Named Marker')::integer,
      count(*) filter (where category = 'Named Marker' and app_notification = 'Created')::integer from detail
    union all select 4, 'Marker volunteers',
      count(*) filter (where category like 'Marker Volunteer%')::integer,
      count(*) filter (where category like 'Marker Volunteer%' and app_notification = 'Created')::integer from detail
    union all select 5, 'Reserves',
      count(*) filter (where category = 'Reserve')::integer,
      count(*) filter (where category = 'Reserve' and app_notification = 'Created')::integer from detail
    union all select 6, 'Captain/Vice copies',
      count(*) filter (where category in ('Captain','Vice Captain'))::integer,
      count(*) filter (where category in ('Captain','Vice Captain') and app_notification = 'Created')::integer from detail
    union all select 7, 'Not selected',
      count(*) filter (where category = 'Not Selected')::integer,
      count(*) filter (where category = 'Not Selected' and app_notification = 'Created')::integer from detail
    union all select 8, 'App notifications created',
      count(*)::integer,
      count(*) filter (where app_notification = 'Created')::integer from detail
    union all select 9, 'Emails queued',
      count(*) filter (where email_status <> 'No Email')::integer,
      count(*) filter (where email_status not in ('No Email','Missing'))::integer from detail
    union all select 10, 'Emails sent',
      count(*) filter (where email_status <> 'No Email')::integer,
      count(*) filter (where email_status = 'sent')::integer from detail
    union all select 11, 'Emails failed', 0,
      count(*) filter (where email_status = 'failed')::integer from detail
    union all select 12, 'Team sheets required',
      count(*) filter (where team_sheet <> 'Not Required')::integer,
      count(*) filter (where team_sheet <> 'Not Required')::integer from detail
    union all select 13, 'Team sheets attached',
      count(*) filter (where team_sheet <> 'Not Required')::integer,
      count(*) filter (where team_sheet = 'Attached')::integer from detail
    union all select 14, 'Team sheets sent',
      count(*) filter (where team_sheet <> 'Not Required' and email_status <> 'No Email')::integer,
      count(*) filter (where team_sheet = 'Attached' and email_status = 'sent')::integer from detail
  )
  select rows.item, rows.expected, rows.actual,
    case when rows.item = 'Emails failed'
      then case when rows.actual = 0 then 'OK' else 'CHECK' end
      when rows.actual >= rows.expected then 'OK' else 'CHECK' end
  from rows order by rows.sort_order;
end;
$function$;

revoke all on function public.communications_health_check_v2(uuid)
from public, anon, authenticated;
grant execute on function public.communications_health_check_v2(uuid)
to authenticated;
