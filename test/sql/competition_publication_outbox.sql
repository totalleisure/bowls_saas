-- SQL-only, rollback-only publication/claim tests. No email transport is invoked.
begin;
do $$
declare actor uuid:=gen_random_uuid(); mp uuid; club uuid; ft uuid; config jsonb; c uuid; c2 uuid;
 ids uuid[]:='{}'; profiles uuid[]:='{}'; u uuid; member uuid; a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); r uuid:=gen_random_uuid();
 event uuid; again uuid; summary jsonb; claims int; existing_test uuid;
begin
 select club_id,fixture_type_id,settings into strict club,ft,config from public.club_competitions where name='Mens Pairs' limit 1;
 select p.id into strict existing_test from public.member_profiles p join public.club_memberships cm on cm.member_profile_id=p.id where lower(btrim(p.email_address))='wayne@totalleisure.com' and cm.club_id=club and cm.is_active limit 1;
 insert into auth.users(id,email,raw_user_meta_data) values(actor,'publication-admin-'||actor||'@example.invalid','{"first_name":"Synthetic","last_name":"Publication Admin"}');
 select id into mp from public.member_profiles where user_id=actor;
 if mp is null then insert into public.member_profiles(user_id,display_name,first_name,last_name) values(actor,'Synthetic Publication Admin','Synthetic','Publication Admin') returning id into mp; end if;
 insert into public.club_memberships(club_id,member_profile_id,role,is_active) values(club,mp,'admin',true);
 for i in 1..3 loop
  u:=gen_random_uuid();insert into auth.users(id,email,raw_user_meta_data) values(u,'publication-player-'||u||'@example.invalid','{"first_name":"Synthetic","last_name":"Player"}');
  select id into member from public.member_profiles where user_id=u;
  if member is null then insert into public.member_profiles(user_id,display_name,first_name,last_name) values(u,'Synthetic Player','Synthetic','Player') returning id into member; end if;
  insert into public.club_memberships(club_id,member_profile_id,role,is_active) values(club,member,'member',true);
  profiles:=array_append(profiles,member);
 end loop;
 update public.member_profiles set email_address='synthetic-publication-'||id||'@example.invalid' where id=any(profiles[1:2]);
 update public.member_profiles set email_address=null where id=profiles[3];
 perform set_config('request.jwt.claim.sub',actor::text,true);
 c:=public.create_club_competition(club,'Synthetic publication verification','test',config,ft);
 insert into public.competition_entries(id,competition_id,name) values(a,c,'Approved test account / synthetic partner'),(b,c,'Synthetic opponents');
 insert into public.competition_entry_members(competition_id,entry_id,member_profile_id) values(c,a,existing_test),(c,a,profiles[1]),(c,b,profiles[2]),(c,b,profiles[3]);
 insert into public.competition_rounds(id,competition_id,round_number,name,play_by) values(r,c,1,'Final','2030-07-01');
 insert into public.competition_draw_matches(competition_id,round_id,match_number,side_a_kind,side_b_kind,side_a_entry_id,side_b_entry_id) values(c,r,1,'entry','entry',a,b);
 summary:=public.competition_publication_summary(c,actor);
 if (summary->>'eligible_count')::int<>1 or (summary->>'missing_email_count')::int<>1 or (summary->>'restricted_count')::int<>2 then raise exception 'Incorrect eligibility: %',summary; end if;
 perform public.publish_club_competition(c);
 select id into strict event from public.competition_publication_events where competition_id=c;
 again:=public.prepare_competition_publication(c,actor);
 if again<>event then raise exception 'Duplicate publication event'; end if;
 if (select jsonb_array_length(snapshot->'competitions') from public.competition_publication_events where id=event)<>1 then raise exception 'Snapshot contains other competitions'; end if;
 if (select count(*) from public.competition_publication_deliveries where event_id=event and recipient='wayne@totalleisure.com')<>1 then raise exception 'Missing approved delivery'; end if;
 if not exists(select 1 from public.club_competitions where id=c and status='published') then raise exception 'Competition not published'; end if;
 begin
  insert into public.competition_publication_deliveries(event_id,member_profile_id,recipient) values(event,profiles[1],'ordinary@example.org');
  raise exception 'Non-approved recipient accepted';
 exception when check_violation then null; end;
 select count(*) into claims from public.claim_competition_publication_deliveries(event,actor);
 if claims<>1 then raise exception 'First claim failed'; end if;
 select count(*) into claims from public.claim_competition_publication_deliveries(event,actor);
 if claims<>0 then raise exception 'Repeat claim could resend'; end if;
 update public.competition_publication_deliveries set status='uncertain' where event_id=event;
 select count(*) into claims from public.claim_competition_publication_deliveries(event,actor);
 if claims<>0 then raise exception 'Uncertain send retried'; end if;
 begin perform public.prepare_competition_publication(c,ids[1]);raise exception 'Non-admin published';exception when insufficient_privilege then null;end;
 if has_function_privilege('authenticated','public.prepare_competition_publication(uuid,uuid)','execute') then raise exception 'Client can supply a forged actor'; end if;
 if has_table_privilege('authenticated','public.competition_publication_deliveries','insert') then raise exception 'Client can bypass allowlist through delivery inserts'; end if;
end $$;
rollback;
select 'PASS: publication event atomic and competition-specific; approved-only outbox, missing/restricted counts, no duplicate claims or uncertain retries, client access denied; all tests rolled back; no transport used' as result;
