create or replace function public.manage_fixture_team_structure(
  p_fixture_id uuid,
  p_action text,
  p_fixture_rink_id uuid default null,
  p_format text default null,
  p_home_rink_label text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_fixture public.fixtures%rowtype;
  v_rink public.fixture_rinks%rowtype;
  v_actor_member_profile_id uuid;
  v_is_superuser boolean := false;
  v_has_permission boolean := false;
  v_action text := lower(btrim(coalesce(p_action, '')));
  v_format text := lower(btrim(coalesce(p_format, '')));
  v_new_players integer;
  v_old_players integer;
  v_next_team integer;
  v_middle_count integer;
  v_i integer;
  v_new_rink_id uuid;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  select f.* into v_fixture
  from public.fixtures f
  where f.id = p_fixture_id
  for update;

  if not found then raise exception 'Fixture not found.'; end if;
  if v_fixture.cancelled_at is not null then
    raise exception 'A cancelled fixture cannot be structurally changed.';
  end if;

  select public.my_member_profile_id() into v_actor_member_profile_id;
  select exists(select 1 from public.app_superusers s where s.user_id=auth.uid())
    into v_is_superuser;
  select v_is_superuser or exists(
    select 1 from public.club_memberships cm
    where cm.club_id=v_fixture.club_id
      and cm.member_profile_id=v_actor_member_profile_id
      and cm.is_active=true
      and lower(cm.role::text)<>'guest'
      and (lower(cm.role::text) in ('admin','selector')
        or v_actor_member_profile_id=v_fixture.captain_member_profile_id
        or v_actor_member_profile_id=v_fixture.vice_captain_member_profile_id)
  ) into v_has_permission;
  if not v_has_permission then
    raise exception 'You do not have permission to change the team structure.';
  end if;

  if v_action not in ('add','update','delete') then
    raise exception 'Unsupported team structure action.';
  end if;

  if v_action in ('add','update') then
    v_new_players := case v_format
      when 'singles' then 1 when 'pairs' then 2 when 'aussie_pairs' then 2
      when 'triples' then 3 when 'fours' then 4 when 'rinks' then 4
      else null end;
    if v_new_players is null then raise exception 'Unsupported team format.'; end if;

    if nullif(btrim(coalesce(p_home_rink_label,'')),'') is not null then
      if not v_fixture.is_home or v_fixture.green_area_id is null then
        raise exception 'Only a home fixture can be assigned a physical rink.';
      end if;
      if exists(
        select 1 from public.fixture_rinks fr
        where fr.fixture_id=p_fixture_id
          and fr.id is distinct from p_fixture_rink_id
          and fr.home_rink_label=p_home_rink_label
      ) then raise exception 'That physical rink is already assigned to another team.'; end if;
      if not exists(
        select 1 from public.get_green_rink_availability(
          v_fixture.green_area_id,v_fixture.start_at,v_fixture.end_at,p_fixture_id
        ) a where a.rink_label=p_home_rink_label and a.is_booked=false
      ) then raise exception 'That physical rink is not available.'; end if;
    end if;
  end if;

  if v_action='add' then
    select coalesce(max(fr.fixture_rink_no),0)+1 into v_next_team
    from public.fixture_rinks fr where fr.fixture_id=p_fixture_id;
    insert into public.fixture_rinks(
      fixture_id,fixture_rink_no,format,players_per_rink,home_rink_label,marker_required
    ) values(
      p_fixture_id,v_next_team,v_format,v_new_players,
      nullif(btrim(coalesce(p_home_rink_label,'')),''),false
    ) returning id into v_new_rink_id;
  else
    select fr.* into v_rink from public.fixture_rinks fr
    where fr.id=p_fixture_rink_id and fr.fixture_id=p_fixture_id for update;
    if not found then raise exception 'The selected team was not found.'; end if;

    if v_action='delete' then
      if (select count(*) from public.fixture_rinks fr where fr.fixture_id=p_fixture_id) <= 1 then
        raise exception 'A rink-based fixture must retain at least one team.';
      end if;
      delete from public.fixture_rinks where id=v_rink.id;
      with numbered as (
        select id,row_number() over(order by fixture_rink_no,id)::integer n
        from public.fixture_rinks where fixture_id=p_fixture_id
      )
      update public.fixture_rinks fr set fixture_rink_no=numbered.n
      from numbered where numbered.id=fr.id;
    else
      v_old_players := v_rink.players_per_rink;
      create temporary table desired_structure_assignments(
        member_profile_id uuid, display_name text, old_position integer,
        new_position integer
      ) on commit drop;

      if v_new_players = v_old_players then
        insert into desired_structure_assignments
        select a.member_profile_id,a.display_name,a.position,a.position
        from public.fixture_rink_assignments a
        where a.fixture_rink_id=v_rink.id and a.position between 1 and v_old_players;
        insert into desired_structure_assignments
        select a.member_profile_id,a.display_name,a.position,a.position
        from public.fixture_rink_assignments a
        where a.fixture_rink_id=v_rink.id and a.position between 101 and 100+v_old_players;
      else
        insert into desired_structure_assignments
        select a.member_profile_id,a.display_name,a.position,1
        from public.fixture_rink_assignments a where a.fixture_rink_id=v_rink.id and a.position=1;
        insert into desired_structure_assignments
        select a.member_profile_id,a.display_name,a.position,101
        from public.fixture_rink_assignments a where a.fixture_rink_id=v_rink.id and a.position=101;

        if v_old_players>1 and v_new_players>1 then
          insert into desired_structure_assignments
          select a.member_profile_id,a.display_name,a.position,v_new_players
          from public.fixture_rink_assignments a where a.fixture_rink_id=v_rink.id and a.position=v_old_players;
          insert into desired_structure_assignments
          select a.member_profile_id,a.display_name,a.position,100+v_new_players
          from public.fixture_rink_assignments a where a.fixture_rink_id=v_rink.id and a.position=100+v_old_players;
        end if;

        v_middle_count := least(greatest(v_old_players-2,0),greatest(v_new_players-2,0));
        for v_i in 1..v_middle_count loop
          insert into desired_structure_assignments
          select a.member_profile_id,a.display_name,a.position,
            case when v_new_players<v_old_players then 1+v_i else a.position end
          from public.fixture_rink_assignments a
          where a.fixture_rink_id=v_rink.id
            and a.position=(case when v_new_players<v_old_players
              then v_old_players-v_middle_count+v_i-1 else 1+v_i end);
          insert into desired_structure_assignments
          select a.member_profile_id,a.display_name,a.position,
            case when v_new_players<v_old_players then 101+v_i else a.position end
          from public.fixture_rink_assignments a
          where a.fixture_rink_id=v_rink.id
            and a.position=100+(case when v_new_players<v_old_players
              then v_old_players-v_middle_count+v_i-1 else 1+v_i end);
        end loop;
      end if;

      delete from public.fixture_rink_assignments a
      where a.fixture_rink_id=v_rink.id
        and (a.position between 1 and 4 or a.position between 101 and 104);
      update public.fixture_rinks set format=v_format,players_per_rink=v_new_players,
        home_rink_label=nullif(btrim(coalesce(p_home_rink_label,'')),'')
      where id=v_rink.id;
      insert into public.fixture_rink_assignments(
        fixture_id,fixture_rink_id,member_profile_id,display_name,position
      )
      select p_fixture_id,v_rink.id,d.member_profile_id,d.display_name,d.new_position
      from desired_structure_assignments d;
    end if;
  end if;

  update public.fixtures f set
    rinks_required=(select count(*) from public.fixture_rinks fr where fr.fixture_id=p_fixture_id),
    players_per_rink=coalesce((select max(fr.players_per_rink) from public.fixture_rinks fr where fr.fixture_id=p_fixture_id),1)
  where f.id=p_fixture_id;

  return jsonb_build_object('fixture_id',p_fixture_id,'action',v_action,
    'fixture_rink_id',coalesce(v_new_rink_id,p_fixture_rink_id),
    'rinks_required',(select count(*) from public.fixture_rinks fr where fr.fixture_id=p_fixture_id));
end;
$function$;

revoke all on function public.manage_fixture_team_structure(uuid,text,uuid,text,text) from public,anon;
grant execute on function public.manage_fixture_team_structure(uuid,text,uuid,text,text) to authenticated;
