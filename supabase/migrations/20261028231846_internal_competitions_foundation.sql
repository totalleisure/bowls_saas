-- Internal competitions are separate from existing fixture categories.
create schema if not exists competition_private;
revoke all on schema competition_private from public, anon, authenticated;

create table public.club_competitions (
 id uuid primary key default gen_random_uuid(),
 club_id uuid not null references public.clubs(id),
 name text not null check(length(btrim(name)) between 1 and 160),
 season text not null check(length(btrim(season)) between 1 and 40),
 structure text not null default 'knockout' check(structure='knockout'),
 status text not null default 'draft' check(status in ('draft','published')),
 settings jsonb not null default '{}' check(jsonb_typeof(settings)='object'),
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 unique(id,club_id)
);
create table public.competition_entries (
 id uuid primary key default gen_random_uuid(),
 competition_id uuid not null references public.club_competitions(id),
 name text not null check(length(btrim(name)) between 1 and 200),
 payment_status text not null default 'not_recorded' check(payment_status in ('not_recorded','unpaid','paid')),
 handicap numeric,
 created_at timestamptz not null default now(),
 unique(competition_id,name), unique(id,competition_id)
);
create table public.competition_entry_members (
 competition_id uuid not null references public.club_competitions(id),
 entry_id uuid not null,
 member_profile_id uuid not null references public.member_profiles(id),
 primary key(competition_id,member_profile_id),
 foreign key(entry_id,competition_id) references public.competition_entries(id,competition_id)
);
create table public.competition_rounds (
 id uuid primary key default gen_random_uuid(),
 competition_id uuid not null references public.club_competitions(id),
 round_number int not null check(round_number>0),
 name text not null,
 play_by date,
 rule_overrides jsonb not null default '{}' check(jsonb_typeof(rule_overrides)='object'),
 unique(competition_id,round_number), unique(id,competition_id)
);
create table public.competition_draw_matches (
 id uuid primary key default gen_random_uuid(),
 competition_id uuid not null references public.club_competitions(id),
 round_id uuid not null,
 match_number int not null check(match_number>0),
 side_a_kind text not null check(side_a_kind in ('entry','winner','bye')),
 side_b_kind text not null check(side_b_kind in ('entry','winner','bye')),
 side_a_entry_id uuid,
 side_b_entry_id uuid,
 side_a_source_id uuid,
 side_b_source_id uuid,
 status text not null default 'to_be_arranged' check(status in ('to_be_arranged','bye','result_pending','completed')),
 score_a int check(score_a>=0), score_b int check(score_b>=0),
 winner_entry_id uuid,
 proposed_winner_entry_id uuid,
 fixture_id uuid unique references public.fixtures(id),
 foreign key(round_id,competition_id) references public.competition_rounds(id,competition_id),
 foreign key(side_a_entry_id,competition_id) references public.competition_entries(id,competition_id),
 foreign key(side_b_entry_id,competition_id) references public.competition_entries(id,competition_id),
 foreign key(winner_entry_id,competition_id) references public.competition_entries(id,competition_id),
 foreign key(proposed_winner_entry_id,competition_id) references public.competition_entries(id,competition_id),
 unique(id,competition_id), unique(round_id,match_number),
 foreign key(side_a_source_id,competition_id) references public.competition_draw_matches(id,competition_id),
 foreign key(side_b_source_id,competition_id) references public.competition_draw_matches(id,competition_id)
);
create table public.competition_result_events (
 id uuid primary key default gen_random_uuid(),
 match_id uuid not null references public.competition_draw_matches(id),
 actor_user_id uuid not null references auth.users(id),
 action text not null check(action in ('submitted','confirmed')),
 score_a int not null, score_b int not null,
 winner_entry_id uuid not null references public.competition_entries(id),
 recorded_at timestamptz not null default clock_timestamp()
);
create index club_competitions_club on public.club_competitions(club_id);
create index competition_entry_members_entry on public.competition_entry_members(entry_id);
create index competition_rounds_competition on public.competition_rounds(competition_id);
create index competition_matches_competition on public.competition_draw_matches(competition_id);
create index competition_result_events_match on public.competition_result_events(match_id);

create function competition_private.can_manage(p_club uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (public.is_app_superuser() or public.is_club_admin(p_club));
$$;
create function competition_private.can_read(p_competition uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.club_competitions c where c.id=p_competition and
 (competition_private.can_manage(c.club_id) or (c.status='published' and exists(
 select 1 from public.club_memberships cm join public.member_profiles mp on mp.id=cm.member_profile_id
 where cm.club_id=c.club_id and cm.is_active and mp.user_id=auth.uid()))));
$$;
revoke all on all functions in schema competition_private from public,anon,authenticated;
grant usage on schema competition_private to authenticated;
grant execute on function competition_private.can_manage(uuid), competition_private.can_read(uuid) to authenticated;

alter table public.club_competitions enable row level security;
create policy competition_read on public.club_competitions for select to authenticated
 using(competition_private.can_read(id));
do $$ declare t text; begin
 foreach t in array array['competition_entries','competition_entry_members','competition_rounds','competition_draw_matches'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('create policy competition_read on public.%I for select to authenticated using(competition_private.can_read(competition_id))',t);
 end loop;
end $$;
alter table public.competition_result_events enable row level security;
create policy competition_result_read on public.competition_result_events for select to authenticated
 using(exists(select 1 from public.competition_draw_matches m join public.club_competitions c on c.id=m.competition_id
 where m.id=match_id and competition_private.can_manage(c.club_id)));
revoke all on public.club_competitions,public.competition_entries,public.competition_entry_members,
 public.competition_rounds,public.competition_draw_matches,public.competition_result_events from public,anon,authenticated;
grant select on public.club_competitions,public.competition_entries,public.competition_entry_members,
 public.competition_rounds,public.competition_draw_matches,public.competition_result_events to authenticated;

create function competition_private.validate_settings(p_settings jsonb)
returns void language plpgsql set search_path='' as $$
begin
 if p_settings is null or jsonb_typeof(p_settings)<>'object' or length(p_settings::text)>16000
 or coalesce(p_settings->>'playing_format','')='' or coalesce(p_settings->>'section','')=''
 or coalesce(p_settings->>'scoring','')=''
 or coalesce(p_settings->>'time_limit_mode','') not in ('unknown','none','minutes')
 or (p_settings->>'players_per_entry')::int not between 1 and 12
 or (p_settings->>'booking_minutes')::int not between 1 and 1440
 or (p_settings->>'time_limit_mode'='minutes' and coalesce((p_settings->>'time_limit_minutes')::int,0) not between 1 and 1440)
 then raise exception 'Invalid competition playing conditions' using errcode='22023'; end if;
 if p_settings->>'players_per_entry' is null or p_settings->>'booking_minutes' is null then
 raise exception 'Players and booking duration required'; end if;
end $$;
revoke all on function competition_private.validate_settings(jsonb) from public,anon,authenticated;

create function public.create_club_competition(p_club_id uuid,p_name text,p_season text,p_settings jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if not competition_private.can_manage(p_club_id) then raise exception 'Club administrator access required' using errcode='42501'; end if;
 perform competition_private.validate_settings(p_settings);
 insert into public.club_competitions(club_id,name,season,settings,created_by)
 values(p_club_id,btrim(p_name),btrim(p_season),p_settings,auth.uid()) returning id into v_id;
 return v_id;
end $$;

create function public.update_club_competition(p_competition_id uuid,p_name text,p_season text,p_settings jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare c public.club_competitions;
begin
 select * into c from public.club_competitions where id=p_competition_id for update;
 if not found or not competition_private.can_manage(c.club_id) then raise exception 'Club administrator access required' using errcode='42501'; end if;
 if exists(select 1 from public.competition_rounds where competition_id=c.id) then raise exception 'Playing conditions are locked after creating the draw'; end if;
 perform competition_private.validate_settings(p_settings);
 if exists(select 1 from public.competition_entries where competition_id=c.id) and p_settings->>'players_per_entry' is distinct from c.settings->>'players_per_entry' then raise exception 'Remove entries before changing team size'; end if;
 update public.club_competitions set name=btrim(p_name),season=btrim(p_season),settings=p_settings where id=c.id;
end $$;

create function public.remove_competition_entry(p_entry_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare cid uuid; club uuid;
begin
 select e.competition_id,c.club_id into cid,club from public.competition_entries e join public.club_competitions c on c.id=e.competition_id where e.id=p_entry_id;
 if cid is null or not competition_private.can_manage(club) then raise exception 'Club administrator access required' using errcode='42501'; end if;
 perform 1 from public.club_competitions where id=cid for update;
 if exists(select 1 from public.competition_rounds where competition_id=cid) then raise exception 'Entries are locked after creating the draw'; end if;
 delete from public.competition_entry_members where entry_id=p_entry_id;
 delete from public.competition_entries where id=p_entry_id;
end $$;

create function public.add_competition_entry(p_competition_id uuid,p_name text,p_members uuid[],p_payment text default 'not_recorded',p_handicap numeric default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare c public.club_competitions; v_id uuid; n int;
begin
 select * into c from public.club_competitions where id=p_competition_id for update;
 if not found or not competition_private.can_manage(c.club_id) then raise exception 'Club administrator access required' using errcode='42501'; end if;
 if exists(select 1 from public.competition_rounds where competition_id=c.id) then raise exception 'Entries are locked after creating the draw'; end if;
 n:=cardinality(p_members);
 if n is null or n<>(c.settings->>'players_per_entry')::int or n<>(select count(distinct x) from unnest(p_members) x)
 or exists(select 1 from unnest(p_members) x where x is null or not exists(select 1 from public.club_memberships cm
 where cm.club_id=c.club_id and cm.member_profile_id=x and cm.is_active and cm.role::text<>'guest')) then
 raise exception 'Select the required number of active Club members; each player can enter once'; end if;
 insert into public.competition_entries(competition_id,name,payment_status,handicap)
 values(c.id,btrim(p_name),p_payment,p_handicap) returning id into v_id;
 insert into public.competition_entry_members(competition_id,entry_id,member_profile_id)
 select c.id,v_id,x from unnest(p_members) x;
 return v_id;
end $$;

create function public.build_competition_draw(p_competition_id uuid,p_entry_order uuid[])
returns void language plpgsql security definer set search_path='' as $$
declare c public.club_competitions; n int; capacity int:=2; levels int:=1; r int; j int;
 rid uuid; mid uuid; previous uuid[]; current_ids uuid[]; pos int:=1; byes int; a uuid; b uuid; sa uuid; sb uuid;
begin
 select * into c from public.club_competitions where id=p_competition_id for update;
 if not found or not competition_private.can_manage(c.club_id) then raise exception 'Club administrator access required' using errcode='42501'; end if;
 if exists(select 1 from public.competition_rounds where competition_id=c.id) then raise exception 'A draw already exists; published rounds are never silently redrawn'; end if;
 n:=cardinality(p_entry_order);
 if n is null or n not between 2 and 256 or n<>(select count(*) from public.competition_entries where competition_id=c.id)
 or n<>(select count(distinct x) from unnest(p_entry_order) x)
 or exists(select 1 from unnest(p_entry_order) x where x is null or not exists(select 1 from public.competition_entries e where e.id=x and e.competition_id=c.id)) then
 raise exception 'Supply every entry once (2–256 entries)'; end if;
 while capacity<n loop capacity:=capacity*2; levels:=levels+1; end loop;
 byes:=capacity-n;
 for r in 1..levels loop
 insert into public.competition_rounds(competition_id,round_number,name) values(c.id,r,
 case when r=levels then 'Final' when r=levels-1 then 'Semi-final' when r=levels-2 then 'Quarter-final' else 'Round '||r end)
 returning id into rid;
 current_ids:='{}'::uuid[];
 for j in 1..(capacity/(2^r)::int) loop
 a:=null; b:=null; sa:=null; sb:=null;
 if r=1 then
 a:=p_entry_order[pos]; pos:=pos+1;
 if j>byes then b:=p_entry_order[pos]; pos:=pos+1; end if;
 else
 sa:=previous[j*2-1]; sb:=previous[j*2];
 select winner_entry_id into a from public.competition_draw_matches where id=sa;
 select winner_entry_id into b from public.competition_draw_matches where id=sb;
 end if;
 insert into public.competition_draw_matches(competition_id,round_id,match_number,side_a_kind,side_b_kind,
 side_a_entry_id,side_b_entry_id,side_a_source_id,side_b_source_id,status,winner_entry_id)
 values(c.id,rid,j,case when r=1 then 'entry' else 'winner' end,
 case when r=1 and b is null then 'bye' when r=1 then 'entry' else 'winner' end,
 a,b,sa,sb,case when r=1 and b is null then 'bye' else 'to_be_arranged' end,
 case when r=1 and b is null then a else null end) returning id into mid;
 current_ids:=array_append(current_ids,mid);
 end loop;
 previous:=current_ids;
 end loop;
end $$;

create function public.update_competition_round(p_round_id uuid,p_play_by date,p_rule_overrides jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare cid uuid; club uuid;
begin
 select r.competition_id,c.club_id into cid,club from public.competition_rounds r join public.club_competitions c on c.id=r.competition_id where r.id=p_round_id;
 if not competition_private.can_manage(club) then raise exception 'Club administrator access required' using errcode='42501'; end if;
 perform 1 from public.club_competitions where id=cid for update;
 if exists(select 1 from public.club_competitions where id=cid and status='published') then raise exception 'Published round conditions are locked in this first release'; end if;
 if p_rule_overrides is null or jsonb_typeof(p_rule_overrides)<>'object' or length(p_rule_overrides::text)>16000 then raise exception 'Invalid round rules'; end if;
 update public.competition_rounds set play_by=p_play_by,rule_overrides=p_rule_overrides where id=p_round_id;
end $$;

create function public.publish_club_competition(p_competition_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare c public.club_competitions;
begin
 select * into c from public.club_competitions where id=p_competition_id for update;
 if not found or not competition_private.can_manage(c.club_id) then raise exception 'Club administrator access required' using errcode='42501'; end if;
 if not exists(select 1 from public.competition_rounds where competition_id=c.id) then raise exception 'Create and review the draw first'; end if;
 update public.club_competitions set status='published' where id=c.id;
end $$;

create function public.record_competition_result(p_match_id uuid,p_score_a int,p_score_b int,p_winner_entry_id uuid,p_confirm boolean default false)
returns void language plpgsql security definer set search_path='' as $$
declare m public.competition_draw_matches; club uuid; cid uuid;
begin
 select d.competition_id,c.club_id into cid,club from public.competition_draw_matches d join public.club_competitions c on c.id=d.competition_id where d.id=p_match_id;
 if not competition_private.can_manage(club) then raise exception 'Club administrator access required' using errcode='42501'; end if;
 -- Serialize all changes to one bracket, including simultaneous upstream results.
 perform 1 from public.club_competitions where id=cid for update;
 select * into m from public.competition_draw_matches where id=p_match_id for update;
 if m.status in ('bye','completed') or m.side_a_entry_id is null or m.side_b_entry_id is null
 or p_score_a is null or p_score_b is null or p_score_a<0 or p_score_b<0 or p_winner_entry_id is null
 or p_winner_entry_id not in (m.side_a_entry_id,m.side_b_entry_id) then raise exception 'A playable match and valid result are required'; end if;
 if not exists(select 1 from public.club_competitions where id=cid and status='published') then raise exception 'Publish the competition before recording results'; end if;
 if p_confirm then
 if m.status<>'result_pending' or m.score_a is distinct from p_score_a or m.score_b is distinct from p_score_b or m.proposed_winner_entry_id is distinct from p_winner_entry_id then
 raise exception 'Review the latest submitted result before confirming'; end if;
 update public.competition_draw_matches set status='completed',winner_entry_id=p_winner_entry_id where id=m.id;
 update public.competition_draw_matches set side_a_entry_id=p_winner_entry_id where side_a_source_id=m.id;
 update public.competition_draw_matches set side_b_entry_id=p_winner_entry_id where side_b_source_id=m.id;
 else
 update public.competition_draw_matches set status='result_pending',score_a=p_score_a,score_b=p_score_b,proposed_winner_entry_id=p_winner_entry_id where id=m.id;
 end if;
 insert into public.competition_result_events(match_id,actor_user_id,action,score_a,score_b,winner_entry_id)
 values(m.id,auth.uid(),case when p_confirm then 'confirmed' else 'submitted' end,p_score_a,p_score_b,p_winner_entry_id);
end $$;

revoke all on function public.update_club_competition(uuid,text,text,jsonb),public.remove_competition_entry(uuid),public.create_club_competition(uuid,text,text,jsonb),public.add_competition_entry(uuid,text,uuid[],text,numeric),
 public.build_competition_draw(uuid,uuid[]),public.update_competition_round(uuid,date,jsonb),public.publish_club_competition(uuid),
 public.record_competition_result(uuid,int,int,uuid,boolean) from public,anon,authenticated;
grant execute on function public.update_club_competition(uuid,text,text,jsonb),public.remove_competition_entry(uuid),public.create_club_competition(uuid,text,text,jsonb),public.add_competition_entry(uuid,text,uuid[],text,numeric),
 public.build_competition_draw(uuid,uuid[]),public.update_competition_round(uuid,date,jsonb),public.publish_club_competition(uuid),
 public.record_competition_result(uuid,int,int,uuid,boolean) to authenticated;
