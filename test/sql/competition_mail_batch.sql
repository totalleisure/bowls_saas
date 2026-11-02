begin;
do $$
declare c public.club_competitions;cid uuid;eid uuid;mp uuid;recipient text;i int;batch jsonb;
begin
 if exists(select 1 from public.competition_publication_deliveries where status='pending') or exists(select 1 from public.competition_round_ready_deliveries where status='pending') or exists(select 1 from public.competition_deadline_deliveries where status='pending') then raise exception 'Existing pending mail; test stopped';end if;
 select * into strict c from public.club_competitions where id='f6d357b6-7d72-4639-9064-b9df52ea7738';
 select id into strict mp from public.member_profiles where lower(email_address)='wayne@totalleisure.com' limit 1;
 update public.competition_mail_batch_control set next_batch_at='-infinity' where id;
 for i in 1..4 loop
  cid:=gen_random_uuid();eid:=gen_random_uuid();
  insert into public.club_competitions(id,club_id,name,season,status,settings,created_by,fixture_type_id) values(cid,c.club_id,'Synthetic batch test','test','draft',c.settings,c.created_by,c.fixture_type_id);
  insert into public.competition_publication_events(id,competition_id,club_id,actor_user_id,snapshot,total_players,eligible_count,missing_email_count,restricted_count) values(eid,cid,c.club_id,c.created_by,'{}',7,7,0,0);
  foreach recipient in array array['wayne@totalleisure.com','wayne.s.sayers@gmail.com','wayne.streem@gmail.com','wayne.sayers@telius.co.uk','wayne.sayers@icloud.com','wayne.sayers@me.com','suesayers9@gmail.com'] loop
   insert into public.competition_publication_deliveries(event_id,member_profile_id,recipient) values(eid,mp,recipient);
  end loop;
 end loop;
 batch:=public.claim_competition_mail_batch();if jsonb_array_length(batch)<>20 then raise exception 'Expected first batch 20';end if;
 batch:=public.claim_competition_mail_batch();if jsonb_array_length(batch)<>0 then raise exception 'Repeated invocation bypassed batch window';end if;
 update public.competition_mail_batch_control set next_batch_at='-infinity' where id;
 batch:=public.claim_competition_mail_batch();if jsonb_array_length(batch)<>8 then raise exception 'Expected remaining batch 8';end if;
end $$;
rollback;
select 'PASS: 28 queued messages claimed as 20 then 8; immediate repeated claim blocked; all synthetic data rolled back' as result;
