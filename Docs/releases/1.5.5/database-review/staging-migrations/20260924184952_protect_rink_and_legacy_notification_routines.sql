CREATE OR REPLACE FUNCTION public.remap_green_rink_labels(p_green_area_id uuid, p_old_labels text[], p_new_labels text[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO pg_catalog, public, pg_temp
AS $function$
declare
  v_updated_count integer := 0;
begin
  if not (
    current_setting('role',true) = 'service_role'
    or (session_user='postgres' and coalesce(current_setting('role',true),'none') in ('none','postgres'))
    or (auth.uid() is not null and (
      public.is_app_superuser()
      or exists(select 1 from public.green_areas g where g.id=p_green_area_id and public.is_club_admin(g.club_id))
    ))
  ) then raise exception 'Green administrator access required' using errcode='42501'; end if;
  if array_length(p_old_labels, 1) is distinct from array_length(p_new_labels, 1) then
    raise exception 'Old and new rink label lists must be the same length';
  end if;

  with mapping as (
    select
      old_label,
      new_label
    from unnest(p_old_labels, p_new_labels) as m(old_label, new_label)
    where old_label is not null
      and new_label is not null
      and old_label <> new_label
  )
  update public.fixture_rinks fr
  set home_rink_label = mapping.new_label
  from public.fixtures f,
       mapping
  where f.id = fr.fixture_id
    and f.green_area_id = p_green_area_id
    and fr.home_rink_label = mapping.old_label;

  get diagnostics v_updated_count = row_count;

  return v_updated_count;
end;
$function$;
revoke all on function public.remap_green_rink_labels(uuid,text[],text[]) from public,anon;
grant execute on function public.remap_green_rink_labels(uuid,text[],text[]) to authenticated,service_role;
-- No current client or SQL-function caller; retain the legacy utility for server use.
revoke all on function public.queue_fixture_selected_notifications(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.queue_fixture_selected_notifications(uuid,jsonb) to service_role;
alter function public.queue_fixture_selected_notifications(uuid,jsonb) set search_path=pg_catalog,public,pg_temp;
