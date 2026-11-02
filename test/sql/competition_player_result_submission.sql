-- Synthetic users, membership and draw; every record is rolled back.
begin;
do $$
declare ids uuid[]:='{}'; profiles uuid[]:='{}'; u uuid; mp uuid; c uuid:=gen_random_uuid();
 a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); r uuid:=gen_random_uuid(); m uuid:=gen_random_uuid();
 club uuid; ft uuid; green uuid; f uuid; label text; settings jsonb; emails bigint; notices bigint; r2 uuid:=gen_random_uuid(); m2 uuid:=gen_random_uuid();
begin
 select cc.club_id,cc.fixture_type_id,cc.settings into strict club,ft,settings
 from public.club_competitions cc where cc.name='Mens Pairs' limit 1;
 select g.id into strict green from public.green_areas g join public.venues v on v.id=g.venue_id where v.club_id=club and v.is_home_venue limit 1;
 for i in 1..6 loop
  u:=gen_random_uuid();
  insert into auth.users(id,email,raw_user_meta_data) values(u,'competition-test-'||u||'@example.invalid',jsonb_build_object('first_name','Synthetic','last_name','Player '||i));
  select id into mp from public.member_profiles where user_id=u;
  if mp is null then insert into public.member_profiles(user_id,display_name,first_name,last_name) values(u,'Synthetic Player '||i,'Synthetic','Player '||i) returning id into mp; end if;
  insert into public.club_memberships(club_id,member_profile_id,role,is_active) values(club,mp,'member',true);
  ids:=array_append(ids,u); profiles:=array_append(profiles,mp);
 end loop;
 insert into public.club_competitions(id,club_id,name,season,status,settings,created_by,fixture_type_id) values(c,club,'Synthetic arrangement verification','test','published',settings,ids[1],ft);
 insert into public.competition_entries(id,competition_id,name) values(a,c,'Synthetic Players 1 / 2'),(b,c,'Synthetic Players 3 / 4');
 for i in 1..4 loop insert into public.competition_entry_members(competition_id,entry_id,member_profile_id) values(c,case when i<=2 then a else b end,profiles[i]); end loop;
 insert into public.competition_rounds(id,competition_id,round_number,name) values(r,c,1,'Final');
 insert into public.competition_draw_matches(id,competition_id,round_id,match_number,side_a_kind,side_b_kind,side_a_entry_id,side_b_entry_id) values(m,c,r,1,'entry','entry',a,b);

 update public.club_memberships set role='admin' where club_id=club and member_profile_id=profiles[6];
 update public.competition_rounds set name='Semi-final' where id=r;
 insert into public.competition_rounds(id,competition_id,round_number,name) values(r2,c,2,'Final');
 insert into public.competition_draw_matches(id,competition_id,round_id,match_number,side_a_kind,side_b_kind,side_a_source_id) values(m2,c,r2,1,'winner','winner',m);
 select count(*) into emails from public.email_queue; select count(*) into notices from public.notification_queue;
 for i in 1..4 loop
  update public.competition_draw_matches set status='to_be_arranged',score_a=null,score_b=null,proposed_winner_entry_id=null where id=m;
  perform set_config('request.jwt.claim.sub',ids[i]::text,true);
  perform public.record_competition_result(m,21,12,a,false);
  if not exists(select 1 from public.competition_draw_matches where id=m and status='result_pending' and score_a=21 and score_b=12 and proposed_winner_entry_id=a and winner_entry_id is null) then raise exception 'Player % result not pending',i; end if;
  if exists(select 1 from public.competition_draw_matches where id=m2 and side_a_entry_id is not null) then raise exception 'Submission advanced the winner'; end if;
  if not exists(select 1 from public.competition_result_events where match_id=m and actor_user_id=ids[i] and action='submitted') then raise exception 'Player submission not audited'; end if;
  begin
   perform public.record_competition_result(m,21,12,a,true);
   raise exception 'Player could confirm';
  exception when insufficient_privilege then null; end;
  begin
   perform public.record_competition_result(m,12,21,b,false);
   raise exception 'Player could overwrite a pending result';
  exception when raise_exception then if sqlerrm<>'A result is already awaiting Club Admin confirmation' then raise; end if; end;
 end loop;
 perform set_config('request.jwt.claim.sub',ids[5]::text,true);
 begin perform public.record_competition_result(m,21,12,a,false);raise exception 'Unrelated member submitted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',ids[6]::text,true);
 begin perform public.record_competition_result(m,22,12,a,true);raise exception 'Admin confirmed stale scores';exception when raise_exception then if sqlerrm<>'Review the latest submitted result before confirming' then raise;end if;end;
 perform public.record_competition_result(m,21,12,a,true);
 if not exists(select 1 from public.competition_draw_matches where id=m and status='completed' and winner_entry_id=a) then raise exception 'Admin confirmation failed'; end if;
 if not exists(select 1 from public.competition_draw_matches where id=m2 and side_a_entry_id=a) then raise exception 'Confirmed winner not advanced'; end if;
 update public.club_memberships set is_active=false where club_id=club and member_profile_id=profiles[2];
 perform set_config('request.jwt.claim.sub',ids[2]::text,true);
 begin perform public.record_competition_result(m,21,12,a,false);raise exception 'Inactive member submitted';exception when insufficient_privilege then null;end;
 update public.club_memberships set role='guest' where club_id=club and member_profile_id=profiles[3];
 perform set_config('request.jwt.claim.sub',ids[3]::text,true);
 begin perform public.record_competition_result(m,21,12,a,false);raise exception 'Guest submitted';exception when insufficient_privilege then null;end;
 if (select count(*) from public.email_queue)<>emails or (select count(*) from public.notification_queue)<>notices then raise exception 'Unexpected messages'; end if;
end $$;
rollback;
select 'PASS: all four drawn players submit; pending results cannot be overwritten; unrelated/inactive/Guest players denied; only Admin confirms and advances; audit checked; all synthetic data rolled back; no messages' as result;
