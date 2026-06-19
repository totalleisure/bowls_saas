create or replace function public.admin_force_delete_fixture(
  p_fixture_id uuid,
  p_confirm text default null
)
returns table (
  item text,
  deleted_count integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  -- Safety phrase
  if coalesce(p_confirm, '') <> 'DELETE FIXTURE' then
    raise exception 'Confirmation text must be DELETE FIXTURE';
  end if;

  -- Superuser only
  if not exists (
    select 1
    from app_superusers su
    where su.user_id = auth.uid()
  ) then
    raise exception 'Only superusers can force delete fixtures';
  end if;

  -- Check fixture exists
  if not exists (
    select 1
    from fixtures f
    where f.id = p_fixture_id
  ) then
    raise exception 'Fixture not found: %', p_fixture_id;
  end if;

  -- 1. Rink assignments
  delete from fixture_rink_assignments fra
  where fra.fixture_id = p_fixture_id;

  get diagnostics v_count = row_count;
  item := 'fixture_rink_assignments';
  deleted_count := v_count;
  return next;

  -- 2. Rinks
  delete from fixture_rinks fr
  where fr.fixture_id = p_fixture_id;

  get diagnostics v_count = row_count;
  item := 'fixture_rinks';
  deleted_count := v_count;
  return next;

  -- 3. RSVPs
  delete from fixture_rsvps r
  where r.fixture_id = p_fixture_id;

  get diagnostics v_count = row_count;
  item := 'fixture_rsvps';
  deleted_count := v_count;
  return next;

  -- 4. Team selection members
  delete from team_selection_members tsm
  using team_selections ts
  where tsm.team_selection_id = ts.id
    and ts.fixture_id = p_fixture_id;

  get diagnostics v_count = row_count;
  item := 'team_selection_members';
  deleted_count := v_count;
  return next;

  -- 5. Team selections
  delete from team_selections ts
  where ts.fixture_id = p_fixture_id;

  get diagnostics v_count = row_count;
  item := 'team_selections';
  deleted_count := v_count;
  return next;

  -- 6. Linked club diary / schedule items
  delete from club_schedule_items csi
  where csi.linked_fixture_id = p_fixture_id;

  get diagnostics v_count = row_count;
  item := 'club_schedule_items';
  deleted_count := v_count;
  return next;

  -- 7. Fixture email log
  delete from fixture_email_log fel
  where fel.fixture_id = p_fixture_id;

  get diagnostics v_count = row_count;
  item := 'fixture_email_log';
  deleted_count := v_count;
  return next;

  -- 8. Notification queue
  delete from notification_queue nq
  where nq.fixture_id = p_fixture_id;

  get diagnostics v_count = row_count;
  item := 'notification_queue';
  deleted_count := v_count;
  return next;

  -- 9. Finally delete fixture
  delete from fixtures f
  where f.id = p_fixture_id;

  get diagnostics v_count = row_count;
  item := 'fixtures';
  deleted_count := v_count;
  return next;

end;
$$;