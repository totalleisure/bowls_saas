-- Record individual RSVP creation, response changes and removal in the durable journal.
create or replace function audit_private.capture_fixture_rsvp() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  b jsonb;
  a jsonb;
  r jsonb;
  v_actor uuid := auth.uid();
  v_actor_name text;
  v_club_id uuid;
  v_club_name text;
  v_fixture_id uuid;
  v_fixture_label text;
  v_member_name text;
  v_action text := lower(TG_OP);
  v_origin text;
begin
  if TG_OP <> 'INSERT' then
    b := audit_private.pick(to_jsonb(old), array[
      'id','fixture_id','member_profile_id','status','responded_at'
    ]);
  end if;
  if TG_OP <> 'DELETE' then
    a := audit_private.pick(to_jsonb(new), array[
      'id','fixture_id','member_profile_id','status','responded_at'
    ]);
  end if;
  if TG_OP = 'UPDATE' and b = a then return new; end if;

  r := coalesce(a,b);
  v_fixture_id := (r->>'fixture_id')::uuid;
  select f.club_id,
         coalesce(nullif(f.team_name,''),nullif(f.opponent_name,''),'Fixture') ||
           ' / ' || f.start_at::text
    into v_club_id,v_fixture_label
    from public.fixtures f where f.id = v_fixture_id;
  select nullif(trim(concat_ws(' ',p.first_name,p.last_name)),'')
    into v_member_name
    from public.member_profiles p where p.id = (r->>'member_profile_id')::uuid;
  select c.name into v_club_name from public.clubs c where c.id = v_club_id;

  v_origin := case
    when v_actor is not null then 'app'
    when coalesce(auth.role(),'') = 'service_role' then 'service'
    else 'database maintenance'
  end;
  select nullif(trim(concat_ws(' ',p.first_name,p.last_name)),'')
    into v_actor_name
    from public.member_profiles p where p.user_id = v_actor limit 1;
  v_actor_name := coalesce(v_actor_name,v_actor::text,v_origin || ' (individual not identified)');

  insert into public.audit_journal(
    actor_user_id,actor_name,origin,club_id,club_name,record_type,
    record_id,record_label,fixture_id,action,reason,before_values,after_values,outcome
  ) values (
    v_actor,v_actor_name,v_origin,v_club_id,v_club_name,'fixture_rsvps',
    r->>'id',concat_ws(' / ',v_fixture_label,v_member_name),v_fixture_id,v_action,
    nullif(current_setting('app.audit_reason',true),''),b,a,'completed'
  );

  if TG_OP = 'DELETE' then return old; end if;
  return new;
end $$;
revoke all on function audit_private.capture_fixture_rsvp()
  from public,anon,authenticated,service_role;

drop trigger if exists durable_audit on public.fixture_rsvps;
create trigger durable_audit
before insert or update or delete on public.fixture_rsvps
for each row execute function audit_private.capture_fixture_rsvp();

-- Deletion reasons are optional. Direct fixture deletion remains blocked unless one
-- of the checked deletion RPCs sets this transaction-local mode.
create or replace function audit_private.guard_fixture_delete() returns trigger
language plpgsql set search_path = '' as $$
begin
  if current_user = 'postgres'
    and current_setting('app.audit_delete_mode', true) in ('ordinary','force')
  then return old; end if;
  raise exception 'Use the audited fixture deletion action';
end $$;

create or replace function public.delete_fixture(p_fixture_id uuid, p_reason text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_preview jsonb;
begin
  perform 1 from public.fixtures where id = p_fixture_id for update;
  if not found then raise exception 'Fixture not found'; end if;
  v_preview := public.fixture_deletion_preview(p_fixture_id);
  if not (v_preview->>'can_delete')::boolean then
    raise exception 'Deletion is blocked because %',
      v_preview->'blockers';
  end if;
  perform set_config('app.audit_reason', coalesce(trim(p_reason),''), true);
  perform set_config('app.audit_delete_mode', 'ordinary', true);
  delete from public.club_schedule_items where linked_fixture_id = p_fixture_id;
  delete from public.fixtures where id = p_fixture_id;
  return true;
end $$;
revoke all on function public.delete_fixture(uuid,text) from public, anon;
grant execute on function public.delete_fixture(uuid,text) to authenticated;

create or replace function public.delete_fixture(p_fixture_id uuid) returns boolean
language sql security definer set search_path = '' as $$
  select public.delete_fixture(p_fixture_id, null::text)
$$;
revoke all on function public.delete_fixture(uuid) from public, anon;
grant execute on function public.delete_fixture(uuid) to authenticated;

create or replace function public.admin_force_delete_fixture(
  p_fixture_id uuid, p_reason text, p_confirm text)
returns table(item text, deleted_count integer)
language plpgsql security definer set search_path = '' as $$
declare
  f public.fixtures;
  v_actor uuid := auth.uid();
  v_actor_name text;
  v_club_name text;
  v_preview jsonb;
  v_count integer;
begin
  if v_actor is null or not exists(
    select 1 from public.app_superusers s where s.user_id = v_actor
  ) then raise exception 'Superuser access required'; end if;
  if p_confirm <> 'DELETE FIXTURE' then
    raise exception 'Type DELETE FIXTURE to confirm'; end if;
  select * into f from public.fixtures where id = p_fixture_id for update;
  if not found then raise exception 'Fixture not found'; end if;
  v_preview := public.fixture_deletion_preview(p_fixture_id);
  select nullif(trim(concat_ws(' ',m.first_name,m.last_name)), '')
    into v_actor_name from public.member_profiles m where m.user_id = v_actor limit 1;
  select c.name into v_club_name from public.clubs c where c.id = f.club_id;

  -- This entry and the automatic DELETE entry share one transaction.
  insert into public.audit_journal(
    actor_user_id, actor_name, origin, club_id, club_name,
    record_type, record_id, record_label, fixture_id, action,
    reason, before_values, after_values)
  values(
    v_actor, coalesce(v_actor_name,v_actor::text), 'app', f.club_id, v_club_name,
    'fixtures', f.id::text,
    coalesce(nullif(f.team_name,''),nullif(f.opponent_name,''),'Fixture') || ' / ' || f.start_at::text,
    f.id, 'force deletion authorized', nullif(trim(coalesce(p_reason,'')),''),
    audit_private.pick(to_jsonb(f), array[
      'id','club_id','team_id','team_name','start_at','end_at','venue_id',
      'opponent_venue_id','opponent_name','section','competition_type_id',
      'captain_member_profile_id','vice_captain_member_profile_id',
      'cancelled_at','cancellation_reason','archived_at','archive_reason',
      'created_by_user_id'
    ]), v_preview
  );
  perform set_config('app.audit_reason', coalesce(trim(p_reason),''), true);
  perform set_config('app.audit_delete_mode', 'force', true);

  delete from public.club_schedule_items where linked_fixture_id = f.id;
  get diagnostics v_count = row_count;
  item := 'club_schedule_items'; deleted_count := v_count; return next;
  delete from public.fixture_email_log where fixture_id = f.id;
  get diagnostics v_count = row_count;
  item := 'fixture_email_log'; deleted_count := v_count; return next;
  delete from public.notification_queue where fixture_id = f.id;
  get diagnostics v_count = row_count;
  item := 'notification_queue'; deleted_count := v_count; return next;
  delete from public.email_queue where fixture_id = f.id;
  get diagnostics v_count = row_count;
  item := 'email_queue'; deleted_count := v_count; return next;
  delete from public.app_notifications where fixture_id = f.id;
  get diagnostics v_count = row_count;
  item := 'app_notifications'; deleted_count := v_count; return next;
  -- Remaining fixture-linked rows have database-managed ON DELETE actions.
  delete from public.fixtures where id = f.id;
  get diagnostics v_count = row_count;
  item := 'fixtures'; deleted_count := v_count; return next;
end $$;
revoke all on function public.admin_force_delete_fixture(uuid,text,text) from public, anon;
grant execute on function public.admin_force_delete_fixture(uuid,text,text) to authenticated;
