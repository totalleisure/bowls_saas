begin;
-- Deliberately do not widen can_manage_fixture/can_manage_team_selection:
-- ordinary fixtures and the creator's existing Captain controls retain their permissions.
create function competition_private.can_arrange_linked_fixture(p_fixture_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(
  select 1 from public.competition_draw_matches m
  join public.club_competitions c on c.id=m.competition_id
  join public.fixtures f on f.id=m.fixture_id
  where f.id=p_fixture_id and f.cancelled_at is null and c.status='published'
  and m.status not in ('bye','completed') and (
   competition_private.can_manage(c.club_id) or exists(
    select 1 from public.club_memberships cm
    where cm.club_id=c.club_id and cm.member_profile_id=public.my_member_profile_id()
    and cm.is_active and cm.role::text<>'guest' and (
     f.created_by_user_id=auth.uid() or exists(
      select 1 from public.competition_entry_members em where em.competition_id=c.id
      and em.entry_id in (m.side_a_entry_id,m.side_b_entry_id) and em.member_profile_id=cm.member_profile_id
     )
    )
   )
  )
 );
$$;
revoke all on function competition_private.can_arrange_linked_fixture(uuid) from public,anon,authenticated;

create function public.competition_fixture_access(p_fixture_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select case when auth.uid() is not null and exists(
   select 1 from public.fixtures f where f.id=p_fixture_id and (
     competition_private.can_manage(f.club_id) or exists(select 1 from public.club_memberships cm
       where cm.club_id=f.club_id and cm.member_profile_id=public.my_member_profile_id() and cm.is_active)
   )
 ) then jsonb_build_object(
   'is_competition',exists(select 1 from public.competition_draw_matches where fixture_id=p_fixture_id),
   'can_manage',competition_private.can_arrange_linked_fixture(p_fixture_id),
   'is_creator',exists(select 1 from public.fixtures where id=p_fixture_id and created_by_user_id=auth.uid())
 ) else jsonb_build_object('is_competition',false,'can_manage',false,'is_creator',false) end;
$$;

create table public.competition_fixture_management_events(
 id uuid primary key default gen_random_uuid(),
 club_id uuid not null references public.clubs(id),
 fixture_id uuid not null references public.fixtures(id),
 match_id uuid not null references public.competition_draw_matches(id),
 actor_user_id uuid not null references auth.users(id),
 action text not null check(action in ('booking_changed','marker_changed')),
 details jsonb not null,
 created_at timestamptz not null default now()
);
create index competition_fixture_events_fixture_idx on public.competition_fixture_management_events(fixture_id,created_at);
alter table public.competition_fixture_management_events enable row level security;
revoke all on public.competition_fixture_management_events from public,anon,authenticated;
grant select on public.competition_fixture_management_events to authenticated;
create policy competition_fixture_events_admin_read on public.competition_fixture_management_events
for select to authenticated using(competition_private.can_manage(club_id));

create function public.competition_fixture_management_state(p_fixture_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if not competition_private.can_arrange_linked_fixture(p_fixture_id) then
 raise exception 'Only the organiser, a drawn player or Club Admin may manage this active competition fixture' using errcode='42501'; end if;
 select jsonb_build_object('fixture',jsonb_build_object('id',f.id,'club_id',f.club_id,'name',c.name,
   'round',r.name||' '||m.match_number,'start_at',f.start_at,'end_at',f.end_at,
   'green_area_id',f.green_area_id,'orientation',f.orientation,'rinks_required',f.rinks_required),
   'rinks',coalesce((select jsonb_agg(jsonb_build_object('id',fr.id,'number',fr.fixture_rink_no,
      'home_rink_label',fr.home_rink_label,'marker_required',fr.marker_required,
      'marker_member_id',a.member_profile_id,'marker_name',mp.display_name)
      order by fr.fixture_rink_no)
     from public.fixture_rinks fr left join public.fixture_rink_assignments a on a.fixture_rink_id=fr.id and a.position=201
     left join public.member_profiles mp on mp.id=a.member_profile_id where fr.fixture_id=f.id),'[]'::jsonb),
   'assigned_member_ids',coalesce((select jsonb_agg(member_profile_id) from public.fixture_rink_assignments where fixture_id=f.id and member_profile_id is not null),'[]'::jsonb)) into result
 from public.fixtures f join public.competition_draw_matches m on m.fixture_id=f.id
 join public.club_competitions c on c.id=m.competition_id join public.competition_rounds r on r.id=m.round_id
 where f.id=p_fixture_id;
 return result;
end $$;

create function public.change_competition_fixture_booking(
 p_fixture_id uuid,p_green_area_id uuid,p_start_at timestamptz,p_end_at timestamptz,
 p_rink_labels text[],p_orientation text,p_expected_start_at timestamptz,p_expected_end_at timestamptz,
 p_expected_green_area_id uuid,p_expected_rink_labels text[]
) returns void language plpgsql security definer set search_path='' as $$
declare f public.fixtures; m public.competition_draw_matches; cid uuid; venue uuid; current_labels text[];
begin
 if not competition_private.can_arrange_linked_fixture(p_fixture_id) then raise exception 'You cannot manage this competition fixture, or it is locked' using errcode='42501'; end if;
 select competition_id into cid from public.competition_draw_matches where fixture_id=p_fixture_id;
 if cid is null then raise exception 'This fixture is not linked to a competition match' using errcode='42501'; end if;
 perform 1 from public.club_competitions where id=cid for update;
 select * into strict m from public.competition_draw_matches where fixture_id=p_fixture_id for update;
 -- Same serialization as initial competition booking, including ordinary fixture writes.
 lock table public.fixtures in share row exclusive mode;
 lock table public.fixture_rinks in share row exclusive mode;
 select * into strict f from public.fixtures where id=p_fixture_id for update;
 if not competition_private.can_arrange_linked_fixture(p_fixture_id) then raise exception 'You cannot manage this competition fixture, or it is locked' using errcode='42501'; end if;
 select array_agg(home_rink_label order by fixture_rink_no) into current_labels from public.fixture_rinks where fixture_id=f.id;
 if f.start_at is distinct from p_expected_start_at or f.end_at is distinct from p_expected_end_at
 or f.green_area_id is distinct from p_expected_green_area_id or current_labels is distinct from p_expected_rink_labels
 then raise exception 'The booking has changed. Refresh before making another change.' using errcode='40001'; end if;
 if p_start_at is null or p_end_at is null or p_start_at<=now() or p_end_at<=p_start_at or p_end_at>p_start_at+interval '24 hours'
 then raise exception 'Choose a future start and valid end time'; end if;
 select g.venue_id into venue from public.green_areas g join public.venues v on v.id=g.venue_id
 where g.id=p_green_area_id and v.club_id=f.club_id and v.is_home_venue;
 if venue is null then raise exception 'Choose a home green for this Club'; end if;
 if p_rink_labels is null or cardinality(p_rink_labels)<>f.rinks_required
 or (select count(distinct label) from unnest(p_rink_labels) label where nullif(btrim(label),'') is not null)<>f.rinks_required
 or (select count(*) from public.fixture_rinks where fixture_id=f.id)<>f.rinks_required
 then raise exception 'Select the required number of different rinks'; end if;
 if (select count(*) from public.get_green_rink_availability(p_green_area_id,p_start_at,p_end_at,p_fixture_id) a
 where a.rink_label=any(p_rink_labels) and not a.is_booked and a.free_capacity_rinks>=f.rinks_required)<>f.rinks_required
 then raise exception 'The selected rinks are no longer available. Refresh and choose another rink or time.'; end if;
 update public.fixtures set start_at=p_start_at,end_at=p_end_at,venue_id=venue,green_area_id=p_green_area_id,
 orientation=nullif(btrim(p_orientation),'')::public.orientation where id=f.id;
 with ordered as(select id,row_number() over(order by fixture_rink_no)::int as i from public.fixture_rinks where fixture_id=f.id)
 update public.fixture_rinks fr set home_rink_label=p_rink_labels[o.i] from ordered o where fr.id=o.id;
 insert into public.competition_fixture_management_events(club_id,fixture_id,match_id,actor_user_id,action,details)
 values(f.club_id,f.id,m.id,auth.uid(),'booking_changed',jsonb_build_object('previous',jsonb_build_object('start_at',f.start_at,'end_at',f.end_at,'green_area_id',f.green_area_id,'rinks',current_labels),
 'current',jsonb_build_object('start_at',p_start_at,'end_at',p_end_at,'green_area_id',p_green_area_id,'rinks',p_rink_labels)));
end $$;

create function public.set_competition_fixture_marker(
 p_fixture_id uuid,p_fixture_rink_id uuid,p_required boolean,p_marker_member_id uuid,
 p_expected_required boolean,p_expected_marker_member_id uuid
) returns void language plpgsql security definer set search_path='' as $$
declare f public.fixtures; fr public.fixture_rinks; previous uuid; ts uuid; mid uuid; match uuid;
begin
 if not competition_private.can_arrange_linked_fixture(p_fixture_id) then raise exception 'You cannot manage markers for this competition fixture, or it is locked' using errcode='42501'; end if;
 select * into strict f from public.fixtures where id=p_fixture_id for update;
 if not competition_private.can_arrange_linked_fixture(p_fixture_id) then raise exception 'You cannot manage markers for this competition fixture, or it is locked' using errcode='42501'; end if;
 select * into strict fr from public.fixture_rinks where id=p_fixture_rink_id and fixture_id=f.id for update;
 select member_profile_id into previous from public.fixture_rink_assignments where fixture_rink_id=fr.id and position=201;
 if fr.marker_required is distinct from p_expected_required or previous is distinct from p_expected_marker_member_id
 then raise exception 'The marker has changed. Refresh before making another change.' using errcode='40001'; end if;
 if p_required is null or (not p_required and p_marker_member_id is not null) then raise exception 'A named marker requires a marker slot'; end if;
 if p_marker_member_id is not null and not exists(select 1 from public.club_memberships where club_id=f.club_id and member_profile_id=p_marker_member_id and is_active and role::text<>'guest') then raise exception 'Choose an active non-Guest Club member as marker'; end if;
 if p_marker_member_id is not null and exists(select 1 from public.fixture_rink_assignments where fixture_id=f.id and member_profile_id=p_marker_member_id and not(fixture_rink_id=fr.id and position=201)) then raise exception 'This member already has another position in the fixture'; end if;
 select id into ts from public.team_selections where fixture_id=f.id order by created_at desc limit 1;
 if ts is null then raise exception 'The fixture team selection is missing. Contact a Club Admin.'; end if;
 if p_marker_member_id is not null and exists(select 1 from public.team_selection_members where team_selection_id=ts and member_profile_id=p_marker_member_id and is_selected and role::text<>'marker') then raise exception 'This member already has another selected role'; end if;
 if fr.marker_required=p_required and previous is not distinct from p_marker_member_id then return; end if;
 delete from public.fixture_rink_assignments where fixture_rink_id=fr.id and position=201;
 update public.fixture_rinks set marker_required=p_required where id=fr.id;
 if previous is not null and previous is distinct from p_marker_member_id and not exists(select 1 from public.fixture_rink_assignments where fixture_id=f.id and member_profile_id=previous) then
  update public.team_selection_members set is_selected=false where team_selection_id=ts and member_profile_id=previous and role::text='marker';
 end if;
 if p_marker_member_id is not null then
  insert into public.fixture_rink_assignments(fixture_id,fixture_rink_id,member_profile_id,position) values(f.id,fr.id,p_marker_member_id,201);
  insert into public.team_selection_members as existing(team_selection_id,member_profile_id,role,acceptance,is_selected)
  values(ts,p_marker_member_id,'marker','pending',true)
  on conflict(team_selection_id,member_profile_id) do update set is_selected=true,acceptance=case when existing.is_selected then existing.acceptance else 'pending'::public.acceptance_status end;
  update public.fixture_marker_requests set status='fulfilled',fulfilled_by_member_profile_id=p_marker_member_id,fulfilled_at=now()
  where fixture_rink_id=fr.id and status='open';
 elsif not p_required then
  update public.fixture_marker_requests set status='cancelled',cancelled_by_member_profile_id=public.my_member_profile_id(),cancelled_at=now()
  where fixture_rink_id=fr.id and status='open';
 end if;
 select id into match from public.competition_draw_matches where fixture_id=f.id;
 insert into public.competition_fixture_management_events(club_id,fixture_id,match_id,actor_user_id,action,details)
 values(f.club_id,f.id,match,auth.uid(),'marker_changed',jsonb_build_object('fixture_rink_id',fr.id,'previous_required',fr.marker_required,'required',p_required,'previous_marker_member_id',previous,'marker_member_id',p_marker_member_id));
end $$;

revoke all on function public.competition_fixture_access(uuid),public.competition_fixture_management_state(uuid),
 public.change_competition_fixture_booking(uuid,uuid,timestamptz,timestamptz,text[],text,timestamptz,timestamptz,uuid,text[]),
 public.set_competition_fixture_marker(uuid,uuid,boolean,uuid,boolean,uuid) from public,anon;
grant execute on function public.competition_fixture_access(uuid),public.competition_fixture_management_state(uuid),
 public.change_competition_fixture_booking(uuid,uuid,timestamptz,timestamptz,text[],text,timestamptz,timestamptz,uuid,text[]),
 public.set_competition_fixture_marker(uuid,uuid,boolean,uuid,boolean,uuid) to authenticated;
commit;
