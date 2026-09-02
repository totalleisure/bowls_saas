create or replace function public.set_team_selection_member_active(
  p_team_selection_id uuid,
  p_member_profile_id uuid,
  p_is_selected boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_actor uuid;
  v_fixture_id uuid;
  v_club_id uuid;
  v_selection_status text;
  v_selection_mode text;
  v_team_id uuid;
  v_requires_rsvp boolean;
  v_member public.team_selection_members%rowtype;
  v_queued boolean := false;
begin
  if auth.uid() is null then raise exception 'Not signed in.'; end if;
  v_actor := public.my_member_profile_id();
  if v_actor is null then raise exception 'Member profile not found.'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_team_selection_id::text, 0));
  select ts.fixture_id, f.club_id, ts.status::text,
         lower(btrim(coalesce(ct.selection_mode, ''))),
         f.team_id, coalesce(f.requires_rsvp, false)
  into v_fixture_id, v_club_id, v_selection_status,
       v_selection_mode, v_team_id, v_requires_rsvp
  from public.team_selections ts
  join public.fixtures f on f.id = ts.fixture_id
  left join public.competition_types ct on ct.id = f.competition_type_id
  where ts.id = p_team_selection_id
  for update of ts;
  if not found then raise exception 'Team selection not found.'; end if;
  if not (
    public.can_manage_team_selection(v_fixture_id)
    or exists (
      select 1 from public.fixtures f
      where f.id = v_fixture_id
        and v_actor in (f.captain_member_profile_id, f.vice_captain_member_profile_id)
    )
  ) then
    raise exception 'You do not have permission to manage this fixture.';
  end if;

  select * into v_member from public.team_selection_members
  where team_selection_id = p_team_selection_id
    and member_profile_id = p_member_profile_id for update;

  if v_selection_status = 'published'
     and v_selection_mode <> 'preselect'
     and (v_team_id is not null or v_requires_rsvp)
     and (
       (p_is_selected and (not found or not coalesce(v_member.is_selected, false)))
       or (not p_is_selected and found and coalesce(v_member.is_selected, false))
     ) then
    raise exception 'Published Team/RSVP composition changes must be confirmed together.';
  end if;

  if p_is_selected then
    if found and v_member.is_selected then
      return jsonb_build_object('action', 'no_change', 'queued', false);
    end if;

    if not exists (
      select 1
      from public.club_memberships cm
      where cm.club_id = v_club_id
        and cm.member_profile_id = p_member_profile_id
        and cm.is_active = true
    ) then
      raise exception 'Target member is not an active member of this club';
    end if;

    insert into public.team_selection_members (
      team_selection_id, member_profile_id, role, acceptance,
      responded_at, is_selected, acceptance_by
    ) values (
      p_team_selection_id, p_member_profile_id, 'player', 'pending', null, true, null
    )
    on conflict (team_selection_id, member_profile_id) do update set
      role = 'player', acceptance = 'pending', responded_at = null,
      is_selected = true, acceptance_by = null
    returning * into v_member;

    delete from public.notification_queue
    where fixture_id = v_fixture_id
      and team_selection_id = p_team_selection_id
      and member_profile_id = p_member_profile_id
      and event_type = 'team_acceptance_changed'
      and status = 'pending'
      and payload->>'new_acceptance' = 'pending';

    v_queued := public.queue_post_publication_player_change(v_member.id, 'fixture_selected', v_actor);
    return jsonb_build_object('action', 'selected', 'queued', v_queued);
  end if;

  if not found or not v_member.is_selected then
    return jsonb_build_object('action', 'no_change', 'queued', false);
  end if;

  update public.team_selection_members set is_selected = false where id = v_member.id;
  delete from public.fixture_rink_assignments
  where fixture_id = v_fixture_id and member_profile_id = p_member_profile_id;
  update public.email_action_requests set status = 'cancelled', updated_at = now()
  where target_record_id = v_member.id and status in ('pending', 'responded');
  update public.notification_queue set status = 'cancelled'
  where fixture_id = v_fixture_id and target_member_profile_id = p_member_profile_id
    and event_type in ('fixture_selected', 'reserve_promoted', 'team_published_player', 'team_published_reserve')
    and status = 'pending';
  update public.email_queue set status = 'cancelled'
  where fixture_id = v_fixture_id and member_profile_id = p_member_profile_id
    and event_type in ('fixture_selected', 'reserve_promoted', 'team_published_player', 'team_published_reserve')
    and status in ('pending', 'failed') and sent_at is null;

  return jsonb_build_object('action', 'removed', 'queued', false);
end;
$function$;

revoke all on function public.set_team_selection_member_active(uuid, uuid, boolean)
from public, anon;
grant execute on function public.set_team_selection_member_active(uuid, uuid, boolean)
to authenticated;
