-- Corrective migration: the officer editor saves blank name/email/phone fields.
create or replace function public.complete_app_guest_registration(p_club_id uuid,p_member_profile_id uuid,p_alert_email text,p_allow_existing boolean default false)
returns uuid language plpgsql security definer set search_path='' as $$
declare membership uuid; profile public.member_profiles; club_name text; officer jsonb;
 home_count int; secretary_email text; secretary_profile uuid; reason text; base_body text;
 member_name text; subject text; alert_email text:=lower(btrim(p_alert_email));
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Registration service access required' using errcode='42501';end if;
 if alert_email is null or alert_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then raise exception 'Registration alert mailbox is not configured' using errcode='22023';end if;
 select * into strict profile from public.member_profiles where id=p_member_profile_id;
 if profile.user_id is null then raise exception 'Registration requires an attached account' using errcode='22023';end if;
 select name into strict club_name from public.clubs where id=p_club_id;
 perform pg_advisory_xact_lock(hashtextextended(p_club_id::text||':'||p_member_profile_id::text,0));
 select id into membership from public.club_memberships where club_id=p_club_id and member_profile_id=p_member_profile_id;
 if membership is not null then
  if not coalesce(p_allow_existing,false) then raise exception 'Already registered with this Club' using errcode='23505';end if;
  update public.club_memberships set role='guest' where id=membership;
 else
  insert into public.club_memberships(club_id,member_profile_id,role) values(p_club_id,p_member_profile_id,'guest') returning id into membership;
 end if;
 if exists(select 1 from mailing_private.app_registration_notices where membership_id=membership) then return membership;end if;

 select count(*) into home_count from public.venues where club_id=p_club_id and is_home_venue;
 if home_count=1 then
  select club_officers->'membership_secretary' into officer from public.venues where club_id=p_club_id and is_home_venue;
  secretary_email:=lower(btrim(coalesce(officer->>'email','')));
  if officer is null or officer='null'::jsonb or (btrim(coalesce(officer->>'name',''))='' and secretary_email='' and btrim(coalesce(officer->>'phone',''))='') then
   reason:='No Membership Secretary is recorded for this Club.';
  elsif secretary_email='' then
   reason:='The Membership Secretary has no email address recorded for this Club.';
  elsif secretary_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then
   reason:='The Membership Secretary email address is invalid. No secretary email was queued.';
  end if;
 else
  reason:=case when home_count=0 then 'No Membership Secretary is recorded: this Club has no home venue configured.' else 'The Membership Secretary could not be determined: multiple home venues are configured.' end;
 end if;
 if reason is not null then secretary_email:=null;end if;
 member_name:=regexp_replace(btrim(coalesce(profile.first_name,'')||' '||coalesce(profile.last_name,'')),E'[\r\n]+',' ','g');
 club_name:=regexp_replace(club_name,E'[\r\n]+',' ','g');
 subject:='New App registration - '||club_name||' - '||member_name;
 base_body:='A registration has been completed in the Bowls Club App.'||chr(10)||chr(10)
  ||'Club: '||club_name||chr(10)||'Name: '||member_name||chr(10)
  ||'Email: '||coalesce(profile.email_address,'Not recorded')||chr(10)
  ||'Telephone: '||coalesce(nullif(profile.phone,''),'Not recorded')||chr(10)
  ||'Registered: '||to_char(clock_timestamp() at time zone 'Europe/London','DD Mon YYYY HH24:MI')||' (UK time)'||chr(10)||chr(10)
  ||'Registered with the Guest App role. This does not confirm Club membership approval.';
 insert into mailing_private.app_registration_notices(membership_id,platform_email,secretary_email) values(membership,alert_email,secretary_email);
 insert into public.email_queue(member_profile_id,event_type,recipient_email,subject,body,payload)
 values(p_member_profile_id,'app_registration_received',alert_email,subject,
  base_body||chr(10)||chr(10)||coalesce(reason,'Membership Secretary notification: '||secretary_email)||chr(10)||chr(10)||'Total Leisure Bowls',
  jsonb_build_object('club_id',p_club_id,'membership_id',membership,'registration_recipient','platform'));
 if secretary_email is not null and secretary_email<>alert_email then
  insert into public.email_queue(member_profile_id,event_type,recipient_email,subject,body,payload)
  values(p_member_profile_id,'app_registration_received',secretary_email,subject,
   base_body||chr(10)||chr(10)||'Please review this registration for your Club.'||chr(10)||chr(10)||'Total Leisure Bowls',
   jsonb_build_object('club_id',p_club_id,'membership_id',membership,'registration_recipient','membership_secretary'));
 end if;
 -- Preserve the existing in-App secretary alert without creating another email.
 if secretary_email is not null then
  select mp.id into secretary_profile from public.member_profiles mp join public.club_memberships cm on cm.member_profile_id=mp.id
   where cm.club_id=p_club_id and cm.is_active and lower(btrim(mp.email_address))=secretary_email order by mp.id limit 1;
  if secretary_profile is not null then
   insert into public.app_notifications(member_profile_id,type,title,body,data)
   values(secretary_profile,'guest_membership_request','New Registration',base_body,jsonb_build_object('source_member_profile_id',p_member_profile_id,'club_id',p_club_id));
  end if;
 end if;
 return membership;
end $$;
revoke all on function public.complete_app_guest_registration(uuid,uuid,text,boolean) from public,anon,authenticated;
grant execute on function public.complete_app_guest_registration(uuid,uuid,text,boolean) to service_role;
