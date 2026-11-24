-- Explicit starter participation modes. No environment/mailbox settings change.
create or replace function club_setup_private.onboarding_participation_defaults()
returns table(fixture_name text,participation_mode text,member_bookable boolean)
language sql immutable set search_path='' as $modes$ values
('Roll-ups and open sessions','open',false),
('Drives','open',false),
('Aggregates','open',false),
('Friendly matches','rsvp',false),
('League matches','team',false),
('Internal competitions','preselect',true),
('National & County Matches','preselect',true),
('Coaching','open',false),
('Practice','preselect',true),
('Member rink bookings','preselect',true),
('Team Trials','rsvp',false),
('Committee meetings','rsvp',false),
('Social events','rsvp',false),
('Meals and celebrations','rsvp',false),
('Fundraising events','rsvp',false),
('Club meetings and AGMs','rsvp',false),
('Other club events','rsvp',false);
$modes$;
revoke all on function club_setup_private.onboarding_participation_defaults() from public,anon,authenticated,service_role;
create or replace function club_setup_private.apply_onboarding_participation_defaults(p_club uuid)
returns void language sql set search_path='' as $apply$
 update public.competition_types t set team_selection_enabled=true,selection_mode=d.participation_mode,
 lock_participation=false,bookable_by_members=d.member_bookable,
 default_rinks_required=case when d.member_bookable then 1 else t.default_rinks_required end,
 default_players_per_rink=case when d.member_bookable then 1 else t.default_players_per_rink end,
 default_format=case when d.member_bookable then 'singles' else t.default_format end
 from club_setup_private.onboarding_participation_defaults() d
 where t.club_id=p_club and lower(t.name)=lower(d.fixture_name);
$apply$;
revoke all on function club_setup_private.apply_onboarding_participation_defaults(uuid) from public,anon,authenticated,service_role;

-- Amend the deployed creator in place, retaining all existing verification,
-- identity linking, platform administrator and email-separation safeguards.
do $patch$
declare f text; anchor text;
begin
 select pg_get_functiondef('club_setup_private.create_staging_club(uuid,jsonb)'::regprocedure) into f;
 if position('not between 1 and 15' in f)=0 or position('then ''Coaching and practice''' in f)=0
 then raise exception 'Unreviewed onboarding creator'; end if;
 f:=replace(f,'not between 1 and 15','not between 1 and 17');
 f:=replace(f,'when ''coaching'' then ''Coaching and practice''','when ''coaching'' then ''Coaching'' when ''practice'' then ''Practice'' when ''trials'' then ''Team Trials''');
 anchor:=substring(f from '  for v_row in select value from jsonb_array_elements');
 if anchor is null then raise exception 'Member import boundary missing'; end if;
 f:=replace(f,anchor,'  perform club_setup_private.apply_onboarding_participation_defaults(v_club);'||chr(10)||anchor);
 execute f;
 select pg_get_functiondef('club_setup_private.onboarding_fixture_palettes()'::regprocedure) into f;
 if position('(''Coaching and practice'',''Heather'',''#F3E8FF'',''#6B21A8'')' in f)=0 then raise exception 'Unreviewed palette mapping'; end if;
 f:=replace(f,'(''Coaching and practice'',''Heather'',''#F3E8FF'',''#6B21A8'')',
 '(''Coaching'',''Heather'',''#F3E8FF'',''#6B21A8''),'||chr(10)||
 '(''Practice'',''Onboarding Indigo Practice'',''#E0E7FF'',''#3730A3''),'||chr(10)||
 '(''Team Trials'',''Onboarding Blue Trials'',''#BFDBFE'',''#1E3A8A'')');
 execute f;
end $patch$;

insert into public.fixture_colour_schemes(name,background_hex,foreground_hex,sort_order,is_active)
select distinct p.palette_name,p.background_hex,p.foreground_hex,200,true from club_setup_private.onboarding_fixture_palettes() p
where not exists(select 1 from public.fixture_colour_schemes s where s.is_active and s.background_hex=p.background_hex and s.foreground_hex=p.foreground_hex);

-- Only clubs created through onboarding are adjusted. Existing unrelated clubs
-- and all fixture records retain their settings and type references.
do $existing$
declare c uuid;
begin
 for c in select distinct club_id from club_setup_private.requests loop
  update public.competition_types t set name='Coaching'
  where t.club_id=c and lower(t.name)='coaching and practice'
   and not exists(select 1 from public.competition_types x where x.club_id=c and lower(x.name)='coaching');
  insert into public.competition_types(club_id,name,section,is_internal,uses_rinks,default_rinks_required,
   default_players_per_rink,default_format,default_duration_minutes,dress_code,team_selection_enabled,
   selection_mode,bookable_by_members,lock_participation,colour_scheme_id)
  select c,d.fixture_name,'open',true,true,1,1,'singles',120,'open',true,d.participation_mode,d.member_bookable,false,
   club_setup_private.onboarding_fixture_palette(d.fixture_name)
  from club_setup_private.onboarding_participation_defaults() d
  where d.fixture_name in ('Practice','Team Trials')
   and (d.fixture_name='Team Trials' or exists(select 1 from public.competition_types t where t.club_id=c and lower(t.name)='coaching'))
   and not exists(select 1 from public.competition_types t where t.club_id=c and lower(t.name)=lower(d.fixture_name));
  perform club_setup_private.apply_onboarding_participation_defaults(c);
 end loop;
end $existing$;


