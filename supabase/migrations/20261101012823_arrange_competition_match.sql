begin;
-- Book a drawn match atomically. Client supplies only time, green and physical rinks;
-- Club, Fixture Type, rules and all players are derived from the approved draw.
create function public.arrange_competition_match(
 p_match_id uuid, p_green_area_id uuid, p_start_at timestamptz,
 p_end_at timestamptz, p_rink_labels text[], p_orientation text default null
) returns uuid language plpgsql security definer set search_path='' as $$
declare
 m public.competition_draw_matches; c public.club_competitions; r public.competition_rounds;
 actor uuid; cid uuid; venue uuid; settings jsonb; nr int; nplayers int; ppr int;
 home_entry uuid; away_entry uuid; v_fixture uuid; assignments jsonb; selections jsonb; labels jsonb;
 is_admin boolean; requested int; conditions text;
begin
 if auth.uid() is null then raise exception 'Sign in required' using errcode='42501'; end if;
 select competition_id into cid from public.competition_draw_matches where id=p_match_id;
 select * into c from public.club_competitions where id=cid for update;
 if not found then raise exception 'Competition match not found'; end if;
 select * into strict m from public.competition_draw_matches where id=p_match_id for update;
 actor:=public.my_member_profile_id();
 is_admin:=competition_private.can_manage(c.club_id);
 if not is_admin and not exists (
   select 1 from public.competition_entry_members em
   join public.club_memberships cm on cm.member_profile_id=em.member_profile_id and cm.club_id=c.club_id
   where em.competition_id=c.id and em.entry_id in (m.side_a_entry_id,m.side_b_entry_id)
   and em.member_profile_id=actor and cm.is_active and cm.role::text<>'guest'
 ) then raise exception 'Only a player in this match or a Club Admin can arrange it' using errcode='42501'; end if;
 -- Retry returns the existing booking; it can never create a second fixture.
 if m.fixture_id is not null then return m.fixture_id; end if;
 if c.status<>'published' or m.status<>'to_be_arranged' or m.side_a_entry_id is null or m.side_b_entry_id is null
 then raise exception 'A published playable match is required'; end if;
 if c.fixture_type_id is null then raise exception 'Choose the competition Fixture Type first'; end if;
 if p_start_at is null or p_end_at is null or p_start_at<=now() or p_end_at<=p_start_at
    or p_end_at>p_start_at+interval '24 hours' then raise exception 'Choose a future date and a valid start and end time'; end if;
 select g.venue_id into venue from public.green_areas g join public.venues v on v.id=g.venue_id
 where g.id=p_green_area_id and v.club_id=c.club_id and v.is_home_venue;
 if venue is null then raise exception 'Choose a home green belonging to this Club'; end if;
 select * into strict r from public.competition_rounds where id=m.round_id;
 settings:=c.settings||r.rule_overrides;
 nr:=coalesce((settings->>'rinks_required')::int,1);
 nplayers:=(c.settings->>'players_per_entry')::int;
 if nr<1 or nplayers<1 or nplayers%nr<>0 then raise exception 'Competition team and rink settings are inconsistent'; end if;
 ppr:=nplayers/nr;
 if ppr not between 1 and 4 then raise exception 'Competition format requires between one and four players per rink'; end if;
 select count(distinct label) into requested from unnest(p_rink_labels) label where nullif(btrim(label),'') is not null;
 if p_rink_labels is null or cardinality(p_rink_labels)<>nr or requested<>nr then raise exception 'Select exactly % different rinks',nr; end if;
 -- Serialize against ordinary fixture inserts/updates as well as competition bookings.
 -- These locks last only for this short booking transaction, never while the user chooses.
 lock table public.fixtures in share row exclusive mode;
 lock table public.fixture_rinks in share row exclusive mode;
 if (select count(*) from public.get_green_rink_availability(p_green_area_id,p_start_at,p_end_at) a
     where a.rink_label=any(p_rink_labels) and not a.is_booked and a.free_capacity_rinks>=nr)<>nr
 then raise exception 'The selected rinks are no longer available. Refresh and choose another rink or time.'; end if;
 home_entry:=m.side_a_entry_id; away_entry:=m.side_b_entry_id;
 -- The ordinary member booking workflow requires its organiser on the player side.
 if exists(select 1 from public.competition_entry_members where entry_id=away_entry and member_profile_id=actor)
 then home_entry:=m.side_b_entry_id; away_entry:=m.side_a_entry_id; end if;
 if (select count(*) from public.competition_entry_members where entry_id=home_entry)<>nplayers
 or (select count(*) from public.competition_entry_members where entry_id=away_entry)<>nplayers
 then raise exception 'Both entries must contain the competition team size'; end if;
 with members as (
  select em.member_profile_id, em.entry_id,
   row_number() over(partition by em.entry_id order by
    nullif(strpos(lower(e.name),lower(btrim(mp.first_name||' '||mp.last_name))),0) nulls last,
    mp.last_name,mp.first_name,em.member_profile_id)::int as pos
  from public.competition_entry_members em join public.member_profiles mp on mp.id=em.member_profile_id
  join public.competition_entries e on e.id=em.entry_id
  where em.competition_id=c.id and em.entry_id in (home_entry,away_entry)
 ) select jsonb_agg(jsonb_build_object('team_no',((pos-1)/ppr)+1,
    'position',((pos-1)%ppr)+1+case when entry_id=home_entry then 0 else 100 end,
    'member_profile_id',member_profile_id)),
   jsonb_agg(jsonb_build_object('member_profile_id',member_profile_id,
    'role',case when entry_id=home_entry then 'player' else 'opponent' end,
    'is_selected',true,'acceptance',case when member_profile_id=actor then 'accepted' else 'pending' end))
 into assignments,selections from members;
 select jsonb_agg(jsonb_build_object('team_no',i,'home_rink_label',label)) into labels
 from unnest(p_rink_labels) with ordinality t(label,i);
 conditions:=concat_ws(E'\n',c.name||' - '||r.name||' '||m.match_number,
    'Play by: '||coalesce(r.play_by::text,'Not set'),
    'Scoring: '||nullif(settings->>'scoring',''),
    'Woods per player: '||nullif(settings->>'woods_per_player',''),
    nullif(settings->>'rules',''));
 v_fixture:=public.create_fixture_with_match_fee(
   p_club_id=>c.club_id,p_start_at=>p_start_at,p_end_at=>p_end_at,p_is_home=>true,
   p_section=>coalesce(settings->>'section','open'),p_rinks_required=>nr,p_players_per_rink=>ppr,
   p_format=>settings->>'playing_format',p_competition_type_id=>c.fixture_type_id,
   p_dress_code=>coalesce(nullif(settings->>'dress',''),'open'),p_team_id=>null,p_team_name=>c.name,
   p_requires_rsvp=>false,p_venue_id=>venue,p_opponent_venue_id=>null,p_green_area_id=>p_green_area_id,
   p_orientation=>p_orientation,p_captain_member_profile_id=>actor,p_vice_captain_member_profile_id=>null,
   p_notes=>conditions,p_create_team_selection=>true,p_team_selection_status=>'published',
   p_home_rink_labels=>labels,p_rink_assignments=>assignments,p_team_selection_members=>selections,
   p_match_fee_pence=>null);
 update public.competition_draw_matches set fixture_id=v_fixture where id=m.id;
 return v_fixture;
end $$;
revoke all on function public.arrange_competition_match(uuid,uuid,timestamptz,timestamptz,text[],text) from public,anon;
grant execute on function public.arrange_competition_match(uuid,uuid,timestamptz,timestamptz,text[],text) to authenticated;
commit;
