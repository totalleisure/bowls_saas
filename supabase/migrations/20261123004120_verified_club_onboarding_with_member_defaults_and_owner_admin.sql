create schema if not exists club_setup_private; create table if not exists club_setup_private.environment(singleton boolean primary key default true check(singleton),project_ref text not null check(project_ref in ('egxdkaotepgfjmszxlyn','xfjelvvfoguzukgvxchh'))); insert into club_setup_private.environment values(true,'xfjelvvfoguzukgvxchh') on conflict(singleton) do nothing; do $guard$ begin if (select project_ref from club_setup_private.environment where singleton)<>'xfjelvvfoguzukgvxchh' then raise exception 'Environment mismatch'; end if; end $guard$;
-- Reviewed onboarding objects only. No existing business functions, mailbox settings or member rows are replaced.

create schema if not exists club_setup_private; revoke all on schema club_setup_private from public,anon,authenticated; grant usage on schema club_setup_private to authenticated,service_role;

set local check_function_bodies=off;

create table if not exists club_setup_private.requests (
  request_id uuid primary key,
  user_id uuid not null references auth.users(id),
  club_id uuid not null references public.clubs(id),
  payload jsonb not null,
  created_at timestamptz not null default now()
);

alter table club_setup_private.requests enable row level security; revoke all on club_setup_private.requests from public,anon,authenticated;

create table if not exists public.club_onboarding_pending_members (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id),
  first_name text not null check (length(btrim(first_name)) between 1 and 100),
  last_name text not null check (length(btrim(last_name)) between 1 and 100),
  email_address text,
  phone text,
  created_at timestamptz not null default now()
);

alter table public.club_onboarding_pending_members enable row level security; revoke all on public.club_onboarding_pending_members from public,anon,authenticated;

create table if not exists club_setup_private.place_request_budget(
 user_id uuid not null references auth.users(id),day date not null,used integer not null,
 primary key(user_id,day)
);

alter table club_setup_private.place_request_budget enable row level security; revoke all on club_setup_private.place_request_budget from public,anon,authenticated;

create table if not exists club_setup_private.invitations (
 id uuid primary key default gen_random_uuid(),
 membership_id uuid not null unique references public.club_memberships(id) on delete cascade,
 email text not null,
 email_queue_id uuid references public.email_queue(id) on delete set null,
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 expires_at timestamptz not null default now()+interval '14 days',
 accepted_at timestamptz
);

alter table club_setup_private.invitations enable row level security; revoke all on club_setup_private.invitations from public,anon,authenticated;

create table if not exists club_setup_private.registration_budget (
  bucket text not null, day date not null default current_date, used integer not null,
  primary key(bucket,day)
);

alter table club_setup_private.registration_budget enable row level security; revoke all on club_setup_private.registration_budget from public,anon,authenticated;

create table if not exists club_setup_private.registrations (
  id uuid primary key default gen_random_uuid(), created_at timestamptz not null default now(),
  expires_at timestamptz not null default now()+interval '24 hours',
  candidates jsonb not null default '[]', place jsonb, email text,
  first_name text, last_name text, phone text, authority boolean not null default false,
  code_hash text, code_expires_at timestamptz, attempts integer not null default 0,
  sent_at timestamptz, verified_at timestamptz, consumed_at timestamptz,
  club_id uuid references public.clubs(id)
);

alter table club_setup_private.registrations enable row level security; revoke all on club_setup_private.registrations from public,anon,authenticated;

create table if not exists club_setup_private.initial_password_choices (
 user_id uuid primary key references auth.users(id) on delete cascade,
 email_queue_id uuid references public.email_queue(id),
 password_fingerprint text, issued_at timestamptz,
 decision text check(decision in ('kept','changed')), decided_at timestamptz,
 reissue_requested boolean not null default false
);

alter table club_setup_private.initial_password_choices enable row level security; revoke all on club_setup_private.initial_password_choices from public,anon,authenticated;

alter table public.club_onboarding_pending_members add column if not exists member_profile_id uuid references public.member_profiles(id);

create unique index if not exists club_onboarding_pending_email on public.club_onboarding_pending_members(club_id,lower(email_address)) where email_address is not null; create index if not exists club_onboarding_pending_club on public.club_onboarding_pending_members(club_id); create index if not exists registration_email on club_setup_private.registrations(email);

grant select on public.club_onboarding_pending_members to authenticated; drop policy if exists pending_members_admin_read on public.club_onboarding_pending_members; create policy pending_members_admin_read on public.club_onboarding_pending_members for select to authenticated using (public.is_club_admin(club_id));

create table if not exists club_setup_private.environment(singleton boolean primary key default true check(singleton),project_ref text not null check(project_ref in ('egxdkaotepgfjmszxlyn','xfjelvvfoguzukgvxchh'))); alter table club_setup_private.environment enable row level security; revoke all on club_setup_private.environment from public,anon,authenticated;

do $config$ begin if not exists(select 1 from club_setup_private.environment) then raise exception 'Set the local onboarding environment before applying shared functions'; end if; end $config$;

CREATE OR REPLACE FUNCTION public.my_staging_club_invitations()
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select club_setup_private.my_invitations(); $function$;

revoke all on function public.my_staging_club_invitations() from public,anon,authenticated,service_role;

grant execute on function public.my_staging_club_invitations() to authenticated;

grant execute on function public.my_staging_club_invitations() to service_role;

CREATE OR REPLACE FUNCTION club_setup_private.my_invitations()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$


begin


 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and not is_anonymous)


 then raise exception 'Please sign in' using errcode='42501'; end if;


 return (select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'club_id',c.id,'club_name',c.name,'expires_at',i.expires_at) order by c.name),'[]')


 from club_setup_private.invitations i join public.club_memberships cm on cm.id=i.membership_id


 join public.member_profiles p on p.id=cm.member_profile_id join auth.users a on a.id=p.user_id


 join public.clubs c on c.id=cm.club_id join public.email_queue q on q.id=i.email_queue_id


 where p.user_id=auth.uid() and not cm.is_active and i.accepted_at is null and i.expires_at>now()


 and q.status='sent' and lower(btrim(a.email))=i.email and lower(btrim(p.email_address))=i.email);


end $function$;

revoke all on function club_setup_private.my_invitations() from public,anon,authenticated,service_role;

grant execute on function club_setup_private.my_invitations() to authenticated;

CREATE OR REPLACE FUNCTION club_setup_private.accept_invitation(p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$



declare i club_setup_private.invitations%rowtype; mid uuid;



begin



 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and not is_anonymous)



 then raise exception 'Please sign in' using errcode='42501'; end if;



 select inv.* into i from club_setup_private.invitations inv join public.club_memberships cm on cm.id=inv.membership_id



 join public.member_profiles p on p.id=cm.member_profile_id join auth.users a on a.id=p.user_id



 where inv.id=p_id and p.user_id=auth.uid() and lower(btrim(a.email))=inv.email and lower(btrim(p.email_address))=inv.email



 for update of inv;



 if not found then raise exception 'Invitation does not belong to this signed-in member' using errcode='42501'; end if;



 if i.accepted_at is not null then return true; end if;



 if i.expires_at<=now() or not exists(select 1 from public.email_queue where id=i.email_queue_id and status='sent')



 then raise exception 'Invitation is expired or sending has not been confirmed'; end if;



 update public.club_memberships set is_active=true where id=i.membership_id and role in ('member','guest');



 if not found then raise exception 'Membership role has changed; ask the administrator to review'; end if;



 update club_setup_private.invitations set accepted_at=now() where id=p_id;



 return true;



end $function$;

revoke all on function club_setup_private.accept_invitation(p_id uuid) from public,anon,authenticated,service_role;

grant execute on function club_setup_private.accept_invitation(p_id uuid) to authenticated;

CREATE OR REPLACE FUNCTION public.accept_staging_club_invitation(p_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select club_setup_private.accept_invitation(p_id); $function$;

revoke all on function public.accept_staging_club_invitation(p_id uuid) from public,anon,authenticated,service_role;

grant execute on function public.accept_staging_club_invitation(p_id uuid) to authenticated;

grant execute on function public.accept_staging_club_invitation(p_id uuid) to service_role;

CREATE OR REPLACE FUNCTION club_setup_private.match_opponent_venues(p_club uuid, p_places jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb;
begin
 if auth.uid() is null or not public.can_create_external_venue(p_club) then
  raise exception 'Club venue administrator access is required' using errcode='42501';
 end if;
 if jsonb_typeof(p_places) is distinct from 'array' or jsonb_array_length(p_places)>20
  or octet_length(p_places::text)>200000 then raise exception 'Review at most 20 clubs'; end if;
 select coalesce(jsonb_object_agg(place_id,clubs),'{}'::jsonb) into result from (
  select p->>'placeId' place_id,coalesce(jsonb_agg(distinct c.name) filter(where c.id is not null),'[]'::jsonb) clubs
  from jsonb_array_elements(p_places) p
  left join public.venues v on
    (nullif(p->>'placeId','') is not null and v.google_place_id=p->>'placeId')
    or (nullif(p->>'postcode','') is not null
      and lower(regexp_replace(v.postcode,'[^a-zA-Z0-9]','','g'))=lower(regexp_replace(p->>'postcode','[^a-zA-Z0-9]','','g'))
      and club_setup_private.club_name_key(v.name)=club_setup_private.club_name_key(p->>'name'))
  left join public.clubs c on c.id=v.club_id
  where nullif(p->>'placeId','') is not null
  group by p->>'placeId'
 ) matches;
 return result;
end $function$;

revoke all on function club_setup_private.match_opponent_venues(p_club uuid, p_places jsonb) from public,anon,authenticated,service_role;

grant execute on function club_setup_private.match_opponent_venues(p_club uuid, p_places jsonb) to authenticated;

CREATE OR REPLACE FUNCTION public.match_staging_opponent_venues(p_club uuid, p_places jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$
 select club_setup_private.match_opponent_venues(p_club,p_places);
$function$;

revoke all on function public.match_staging_opponent_venues(p_club uuid, p_places jsonb) from public,anon,authenticated,service_role;

grant execute on function public.match_staging_opponent_venues(p_club uuid, p_places jsonb) to authenticated;

grant execute on function public.match_staging_opponent_venues(p_club uuid, p_places jsonb) to service_role;

CREATE OR REPLACE FUNCTION public.staging_invitation_delivery_context(p_queue uuid, p_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$

declare q public.email_queue%rowtype; i club_setup_private.invitations%rowtype;

 m public.club_memberships%rowtype; p public.member_profiles%rowtype; u auth.users%rowtype; club_name text; fresh boolean; reissue boolean;

begin

 select * into q from public.email_queue where id=p_queue;

 if not found then raise exception 'Queue row missing'; end if;

 if q.event_type <> 'staging_club_invitation' then return null; end if;

 if q.status<>'processing' or q.sent_at is not null or q.delivery_lease is null

  or lower(btrim(q.recipient_email)) is distinct from lower(btrim(p_email))

  or not coalesce(club_setup_private.test_invitation_recipient(p_email),false)

 then raise exception 'Invitation is not eligible for delivery'; end if;

 select * into strict i from club_setup_private.invitations where email_queue_id=q.id;

 if i.accepted_at is not null or i.expires_at<=now() or lower(btrim(i.email)) is distinct from lower(btrim(p_email))

 then raise exception 'Invitation accepted, expired or changed'; end if;

 select * into strict m from public.club_memberships where id=i.membership_id;

 if m.is_active then raise exception 'Membership already active'; end if;

 select * into strict p from public.member_profiles where id=m.member_profile_id;

 select * into strict u from auth.users where id=p.user_id and not is_anonymous;

 if lower(btrim(u.email)) is distinct from lower(btrim(p_email)) then raise exception 'Account email changed'; end if;

 select name into strict club_name from public.clubs where id=m.club_id;

 select coalesce(reissue_requested or (decided_at is null and issued_at is not null and (u.last_sign_in_at is null or u.last_sign_in_at<issued_at)),false)

 into reissue from club_setup_private.initial_password_choices where user_id=u.id and email_queue_id=q.id;

 fresh:=(u.last_sign_in_at is null or coalesce(reissue,false)) and exists(

  select 1 from public.club_onboarding_pending_members c where c.club_id=m.club_id and c.member_profile_id=p.id

   and c.id::text=u.raw_app_meta_data->>'staging_onboarding_contact_id')

  and not exists(select 1 from public.club_memberships other where other.member_profile_id=p.id and other.club_id<>m.club_id);

 return jsonb_build_object('club',club_name,'first_name',coalesce(p.first_name,'Member'),'email',lower(btrim(u.email)),

  'user_id',u.id,'new_user',fresh,'reissue_initial',fresh and coalesce(reissue,false));

end $function$;

revoke all on function public.staging_invitation_delivery_context(p_queue uuid, p_email text) from public,anon,authenticated,service_role;

grant execute on function public.staging_invitation_delivery_context(p_queue uuid, p_email text) to service_role;

CREATE OR REPLACE FUNCTION public.record_staging_initial_password(p_queue uuid, p_email text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$

declare ctx jsonb; uid uuid;

begin

 ctx:=public.staging_invitation_delivery_context(p_queue,p_email);

 if ctx is null or ctx->>'new_user'<>'true' then raise exception 'Not a new invitation account'; end if;

 uid:=(ctx->>'user_id')::uuid;

 insert into club_setup_private.initial_password_choices(user_id,email_queue_id,password_fingerprint,issued_at)

 select uid,p_queue,md5(encrypted_password),now() from auth.users where id=uid

 on conflict(user_id) do update set email_queue_id=excluded.email_queue_id,password_fingerprint=excluded.password_fingerprint,

 issued_at=excluded.issued_at,decision=null,decided_at=null,reissue_requested=false;

end $function$;

revoke all on function public.record_staging_initial_password(p_queue uuid, p_email text) from public,anon,authenticated,service_role;

grant execute on function public.record_staging_initial_password(p_queue uuid, p_email text) to service_role;

CREATE OR REPLACE FUNCTION public.staging_initial_password_choice()
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$

 select exists(select 1 from club_setup_private.initial_password_choices c join auth.users u on u.id=c.user_id

 where c.user_id=auth.uid() and not u.is_anonymous and c.decided_at is null

 and c.password_fingerprint=md5(u.encrypted_password));

$function$;

revoke all on function public.staging_initial_password_choice() from public,anon,authenticated,service_role;

grant execute on function public.staging_initial_password_choice() to authenticated;

grant execute on function public.staging_initial_password_choice() to service_role;

CREATE OR REPLACE FUNCTION public.complete_staging_initial_password_choice(p_choice text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$

declare c club_setup_private.initial_password_choices%rowtype; current_fingerprint text;

begin

 if auth.uid() is null or p_choice not in ('kept','changed') or p_choice is null then raise exception 'Invalid password choice'; end if;

 select * into strict c from club_setup_private.initial_password_choices where user_id=auth.uid() for update;

 select md5(encrypted_password) into strict current_fingerprint from auth.users where id=auth.uid() and not is_anonymous;

 if c.decided_at is not null then return; end if;

 if p_choice='changed' and c.password_fingerprint=current_fingerprint then raise exception 'Change the password first'; end if;

 if p_choice='kept' and c.password_fingerprint is distinct from current_fingerprint then raise exception 'The password has changed'; end if;

 update club_setup_private.initial_password_choices set decision=p_choice,decided_at=now() where user_id=auth.uid();

end $function$;

revoke all on function public.complete_staging_initial_password_choice(p_choice text) from public,anon,authenticated,service_role;

grant execute on function public.complete_staging_initial_password_choice(p_choice text) to authenticated;

grant execute on function public.complete_staging_initial_password_choice(p_choice text) to service_role;

CREATE OR REPLACE FUNCTION club_setup_private.invitation_contact_context(p_contact uuid, p_caller uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$

declare r public.club_onboarding_pending_members%rowtype; uid uuid; n integer;

begin

 if auth.role() is distinct from 'service_role' then raise exception 'Server access required' using errcode='42501'; end if;

 select * into strict r from public.club_onboarding_pending_members where id=p_contact;

 if not exists(select 1 from public.club_memberships cm join public.member_profiles p on p.id=cm.member_profile_id join auth.users a on a.id=p.user_id

   where cm.club_id=r.club_id and cm.is_active and cm.role='admin' and p.user_id=p_caller and not a.is_anonymous)

 then raise exception 'Active club administrator required' using errcode='42501'; end if;

 if not coalesce(club_setup_private.test_invitation_recipient(r.email_address),false)

 then raise exception 'Recipient is not approved in this environment'; end if;

 select count(*),(array_agg(id))[1] into n,uid from auth.users where lower(btrim(email))=lower(btrim(r.email_address)) and not is_anonymous;

 if n>1 then raise exception 'Ambiguous sign-in identity'; end if;

 return jsonb_build_object('contact_id',r.id,'club_id',r.club_id,'email',lower(btrim(r.email_address)),

   'first_name',r.first_name,'last_name',r.last_name,'phone',r.phone,'user_id',uid);

end $function$;

revoke all on function club_setup_private.invitation_contact_context(p_contact uuid, p_caller uuid) from public,anon,authenticated,service_role;

grant execute on function club_setup_private.invitation_contact_context(p_contact uuid, p_caller uuid) to service_role;

CREATE OR REPLACE FUNCTION public.staging_invitation_contact_context(p_contact uuid, p_caller uuid)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select club_setup_private.invitation_contact_context(p_contact,p_caller); $function$;

revoke all on function public.staging_invitation_contact_context(p_contact uuid, p_caller uuid) from public,anon,authenticated,service_role;

grant execute on function public.staging_invitation_contact_context(p_contact uuid, p_caller uuid) to service_role;

CREATE OR REPLACE FUNCTION club_setup_private.finish_invitation_contact(p_contact uuid, p_caller uuid, p_user uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$

declare ctx jsonb; a auth.users%rowtype; p public.member_profiles%rowtype; cmid uuid; result jsonb;

 original_claims text; created_for_contact boolean; target_role public.club_role;

begin

 ctx:=club_setup_private.invitation_contact_context(p_contact,p_caller);

 perform 1 from public.club_onboarding_pending_members where id=p_contact for update;

 select * into strict a from auth.users where id=p_user and not is_anonymous and lower(btrim(email))=ctx->>'email';

 created_for_contact:=a.raw_app_meta_data->>'staging_onboarding_contact_id'=p_contact::text;

 select * into strict p from public.member_profiles where user_id=a.id;

 if created_for_contact and a.last_sign_in_at is null then

   update public.member_profiles set first_name=ctx->>'first_name',last_name=ctx->>'last_name',

     email_address=ctx->>'email',phone=ctx->>'phone',display_name=(ctx->>'first_name')||' '||(ctx->>'last_name') where id=p.id;

 elsif lower(btrim(p.email_address)) is distinct from ctx->>'email' then

   raise exception 'Existing profile email requires administrator review';

 end if;

 if exists(select 1 from public.member_profiles where id<>p.id and lower(btrim(email_address))=ctx->>'email')

 then raise exception 'Another profile uses this email; review before inviting'; end if;

 target_role:=case when exists(select 1 from public.club_memberships where member_profile_id=p.id and club_id<>(ctx->>'club_id')::uuid)

   then 'guest'::public.club_role else 'member'::public.club_role end;

 insert into public.club_memberships(club_id,member_profile_id,role,is_active)

 values((ctx->>'club_id')::uuid,p.id,target_role,false) on conflict(club_id,member_profile_id) do nothing;

 select id into strict cmid from public.club_memberships where club_id=(ctx->>'club_id')::uuid and member_profile_id=p.id and not is_active;

 update public.club_onboarding_pending_members set member_profile_id=p.id where id=p_contact;

 original_claims:=current_setting('request.jwt.claims',true);

 perform set_config('request.jwt.claims',jsonb_build_object('sub',p_caller,'role','authenticated')::text,true);

 result:=club_setup_private.queue_invitations((ctx->>'club_id')::uuid,array[cmid],true);

 perform set_config('request.jwt.claims',coalesce(original_claims,'{}'),true);

 if created_for_contact and (result->>'queued')::integer=1 then

  update public.email_queue q set body=replace(q.body,

   'You already have an account. Use your existing email address and password; do not register again.',

   'Your sign-in account has now been prepared. Open the Bowls App and choose Forgotten password using this email address. Enter the code sent to you and set your own password. Then sign in; do not register again.')

  where q.id=(select email_queue_id from club_setup_private.invitations where membership_id=cmid);

 end if;

 return result;

end $function$;

revoke all on function club_setup_private.finish_invitation_contact(p_contact uuid, p_caller uuid, p_user uuid) from public,anon,authenticated,service_role;

grant execute on function club_setup_private.finish_invitation_contact(p_contact uuid, p_caller uuid, p_user uuid) to service_role;

CREATE OR REPLACE FUNCTION public.finish_staging_invitation_contact(p_contact uuid, p_caller uuid, p_user uuid)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select club_setup_private.finish_invitation_contact(p_contact,p_caller,p_user); $function$;

revoke all on function public.finish_staging_invitation_contact(p_contact uuid, p_caller uuid, p_user uuid) from public,anon,authenticated,service_role;

grant execute on function public.finish_staging_invitation_contact(p_contact uuid, p_caller uuid, p_user uuid) to service_role;

CREATE OR REPLACE FUNCTION club_setup_private.invitation_preview(p_club uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$



declare result jsonb; contacts jsonb;



begin



 perform club_setup_private.require_invitation_admin(p_club);



 select coalesce(jsonb_agg(jsonb_build_object('membership_id',cm.id,'name',p.display_name,'role',cm.role,'email',p.email_address,



  'eligible',i.id is null and not p.is_captain_managed and coalesce(club_setup_private.test_invitation_recipient(p.email_address),false)



     and lower(btrim(a.email))=lower(btrim(p.email_address)) and not a.is_anonymous,



  'status',case when i.accepted_at is not null then 'accepted' when i.id is not null then coalesce(q.status,'check')



    when not coalesce(club_setup_private.test_invitation_recipient(p.email_address),false) then 'blocked: recipient is not approved in this environment'



    when p.is_captain_managed or a.id is null or a.is_anonymous or lower(btrim(a.email)) is distinct from lower(btrim(p.email_address)) then 'blocked: check account email'



    else 'ready' end,



  'subject',(case when (select project_ref from club_setup_private.environment where singleton)='egxdkaotepgfjmszxlyn' then '[STAGING TEST] ' else '' end)||'Invitation to join '||c.name,



  'body',club_setup_private.invitation_body(p.first_name,c.name)) order by p.display_name),'[]') into result



 from public.club_memberships cm join public.member_profiles p on p.id=cm.member_profile_id



 join public.clubs c on c.id=cm.club_id left join auth.users a on a.id=p.user_id



 left join club_setup_private.invitations i on i.membership_id=cm.id left join public.email_queue q on q.id=i.email_queue_id



 where cm.club_id=p_club and not cm.is_active and cm.role in ('member','guest');



 select coalesce(jsonb_agg(jsonb_build_object('contact_id',x.id,'name',x.first_name||' '||x.last_name,

 'email',x.email_address,'eligible',coalesce(club_setup_private.test_invitation_recipient(x.email_address),false),

 'status',case when coalesce(club_setup_private.test_invitation_recipient(x.email_address),false) then 'ready: sign-in account prepared when invited' else 'blocked: recipient is not approved in this environment' end,

 'subject',(case when (select project_ref from club_setup_private.environment where singleton)='egxdkaotepgfjmszxlyn' then '[STAGING TEST] ' else '' end)||'Invitation to join '||c.name,

 'body','A sign-in account will be prepared only when you choose to send. Open the Bowls App and use Forgotten password to set your password with the emailed code. Then accept the club invitation under My clubs.')),'[]')

 into contacts from public.club_onboarding_pending_members x join public.clubs c on c.id=x.club_id

 where x.club_id=p_club and (x.member_profile_id is null or not exists(select 1 from public.club_memberships cm where cm.club_id=p_club and cm.member_profile_id=x.member_profile_id));

 return result||contacts;



end $function$;

revoke all on function club_setup_private.invitation_preview(p_club uuid) from public,anon,authenticated,service_role;

grant execute on function club_setup_private.invitation_preview(p_club uuid) to authenticated;

CREATE OR REPLACE FUNCTION public.create_staging_club_onboarding(p_request_id uuid, p_details jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$

 select club_setup_private.create_staging_club(p_request_id,p_details);

$function$;

revoke all on function public.create_staging_club_onboarding(p_request_id uuid, p_details jsonb) from public,anon,authenticated,service_role;

grant execute on function public.create_staging_club_onboarding(p_request_id uuid, p_details jsonb) to authenticated;

grant execute on function public.create_staging_club_onboarding(p_request_id uuid, p_details jsonb) to service_role;

CREATE OR REPLACE FUNCTION club_setup_private.create_staging_club(p_request_id uuid, p_details jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$


declare


  v_user uuid := auth.uid();


  v_profile public.member_profiles%rowtype;


  v_registration club_setup_private.registrations%rowtype;


  v_request club_setup_private.requests%rowtype;


  v_club uuid; v_venue uuid; v_activity text; v_name text; v_event boolean;


  v_row jsonb; v_email text; v_first text; v_last text;


  v_count integer := 0;


  v_start time; v_end time; v_rinks integer; v_discipline public.discipline;


begin


  if not club_setup_private.onboarding_access() and not exists(


    select 1 from club_setup_private.requests where request_id=p_request_id and user_id=v_user) then


    raise exception 'Verify your club and email before starting setup' using errcode='42501';


  end if;


  if p_request_id is null or p_details is null or jsonb_typeof(p_details)<>'object'


     or octet_length(p_details::text)>1000000 then raise exception 'Invalid club setup'; end if;


  -- Serialise retries and competing registrations of the same normalised name.


  perform pg_advisory_xact_lock(hashtextextended('club-setup:'||club_setup_private.club_name_key(p_details->>'name'),0));


  select * into v_request from club_setup_private.requests where request_id=p_request_id;


  if found then


    if v_request.user_id<>v_user or v_request.payload<>p_details then


      raise exception 'This setup request has already been used for different details';


    end if;


    return jsonb_build_object('club_id',v_request.club_id,'name',p_details->>'name','reused',true);


  end if;


  if p_details ? 'registration_id' or not exists(select 1 from public.app_superusers where user_id=v_user) then


    select r.* into v_registration from club_setup_private.registrations r join auth.users a on lower(btrim(a.email))=r.email


    where r.id=(p_details->>'registration_id')::uuid and a.id=v_user and not a.is_anonymous and a.email_confirmed_at is not null


      and r.verified_at is not null and r.expires_at>now() and r.consumed_at is null for update of r;


    if not found then raise exception 'Your verified club check has expired. Please verify again.'; end if;


    if p_details->>'name' is distinct from v_registration.place->>'name'


      or p_details->>'address_line1' is distinct from v_registration.place->>'addressLine1'


      or coalesce(p_details->>'address_line2','') is distinct from coalesce(v_registration.place->>'addressLine2','')


      or coalesce(p_details->>'town_city','') is distinct from coalesce(v_registration.place->>'townCity','')


      or coalesce(p_details->>'postcode','') is distinct from coalesce(v_registration.place->>'postcode','') then


      raise exception 'Club and address must match the verified details. Contact Wayne if a correction is needed.'; end if;


    if v_registration.place->>'source'='website' then


      if nullif(p_details->>'google_place_id','') is not null


        or nullif(p_details->>'website_url','') is null


        or club_setup_private.website_key(p_details->>'website_url') is distinct from club_setup_private.website_key(v_registration.place->>'websiteUrl') then


        raise exception 'The verified club website must be kept. Website evidence is not a Google Maps listing.'; end if;


      perform pg_advisory_xact_lock(hashtextextended('club-website:'||club_setup_private.website_key(v_registration.place->>'websiteUrl'),0));


    else


      if p_details->>'google_place_id' is distinct from v_registration.place->>'placeId' then raise exception 'The verified Google listing must be kept'; end if;


      perform pg_advisory_xact_lock(hashtextextended('club-place:'||(v_registration.place->>'placeId'),0));


    end if;


    if jsonb_array_length(club_setup_private.registration_duplicates(v_registration.place))>0 then


      raise exception 'An existing club or shared home venue needs review. Please contact Wayne before continuing.'; end if;


  end if;


  select * into strict v_profile from public.member_profiles where user_id=v_user;


  if club_setup_private.club_name_key(p_details->>'name')='' or nullif(btrim(p_details->>'name'),'') is null or length(p_details->>'name')>160


     or nullif(btrim(p_details->>'venue_name'),'') is null


     or nullif(btrim(coalesce(p_details->>'address_line1',p_details->>'address')),'') is null


     or nullif(btrim(p_details->>'green_name'),'') is null then


    raise exception 'Club, venue, address and green names are required';


  end if;


  if exists(select 1 from public.clubs where club_setup_private.club_name_key(name)=club_setup_private.club_name_key(p_details->>'name')) then


    raise exception 'A club with this name is already registered. Open the existing club instead.';


  end if;


  v_start := (p_details->>'start_time')::time;


  v_end := (p_details->>'end_time')::time;


  v_rinks := (p_details->>'rink_count')::integer;


  v_discipline := (p_details->>'discipline')::public.discipline;


  if v_start is null or v_end is null or v_start>=v_end


     or v_rinks is null or v_rinks not between 1 and 40


     or v_discipline is null then raise exception 'Check opening hours, discipline and rink count'; end if;


  if jsonb_typeof(p_details->'activities') is distinct from 'array'


     or jsonb_array_length(p_details->'activities') not between 1 and 15 then


    raise exception 'Choose at least one activity';


  end if;


  if jsonb_typeof(p_details->'members') is distinct from 'array'


     or jsonb_array_length(p_details->'members')>5000 then raise exception 'Invalid member list'; end if;


  insert into public.clubs(name) values(btrim(p_details->>'name')) returning id into v_club;


  insert into public.club_memberships(club_id,member_profile_id,role,is_active)


    values(v_club,v_profile.id,'admin',true) on conflict(club_id,member_profile_id) do update set role='admin',is_active=true;


  -- The platform owner is also an active club administrator. Resolve the local

  -- verified account by email; never copy a user/profile ID between projects.

  insert into public.club_memberships(club_id,member_profile_id,role,is_active)

  select v_club,p.id,'admin',true from public.member_profiles p

  join auth.users a on a.id=p.user_id

  where lower(btrim(p.email_address))='wayne@totalleisure.com'

    and lower(btrim(a.email))='wayne@totalleisure.com'

    and not a.is_anonymous and a.email_confirmed_at is not null

    and p.id<>v_profile.id;

  if not exists(select 1 from public.club_memberships cm

    join public.member_profiles p on p.id=cm.member_profile_id

    where cm.club_id=v_club and lower(btrim(p.email_address))='wayne@totalleisure.com'

      and cm.role='admin' and cm.is_active) then

    raise exception 'The platform administrator account is unavailable. Please contact Wayne.';

  end if;

  insert into public.venues(club_id,name,is_home_venue,address_line1,address_line2,town_city,postcode,


      google_place_id,latitude,longitude,website_url,google_maps_url,club_start_time,club_end_time)


    values(v_club,btrim(p_details->>'venue_name'),true,


      btrim(coalesce(p_details->>'address_line1',p_details->>'address')),


      nullif(btrim(p_details->>'address_line2'),''),nullif(btrim(p_details->>'town_city'),''),


      nullif(upper(btrim(p_details->>'postcode')),''),nullif(p_details->>'google_place_id',''),


      (p_details->>'latitude')::double precision,(p_details->>'longitude')::double precision,


      nullif(p_details->>'website_url',''),nullif(p_details->>'google_maps_url',''),v_start,v_end)


    returning id into v_venue;


  insert into public.green_areas(club_id,venue_id,name,discipline,rink_count,scheme_type,is_outdoor)


    values(v_club,v_venue,btrim(p_details->>'green_name'),v_discipline,v_rinks,'numeric',v_discipline='outdoor');


  for v_activity in select distinct jsonb_array_elements_text(p_details->'activities') loop


    v_event := v_activity=any(array['committee','social','meals','fundraising','agm','other']);


    v_name := case v_activity


      when 'rollups' then 'Roll-ups and open sessions' when 'drives' then 'Drives'


      when 'aggregates' then 'Aggregates' when 'friendlies' then 'Friendly matches'


      when 'leagues' then 'League matches' when 'internal' then 'Internal competitions'


      when 'nationals' then 'National & County Matches' when 'coaching' then 'Coaching and practice' when 'bookings' then 'Member rink bookings'


      when 'committee' then 'Committee meetings' when 'social' then 'Social events'


      when 'meals' then 'Meals and celebrations' when 'fundraising' then 'Fundraising events'


      when 'agm' then 'Club meetings and AGMs' when 'other' then 'Other club events'


      else null end;


    if v_name is null then raise exception 'Unrecognised activity'; end if;


    insert into public.competition_types(club_id,name,section,is_internal,uses_rinks,


      default_rinks_required,default_duration_minutes,dress_code,team_selection_enabled,


      selection_mode,bookable_by_members,tags,colour_scheme_id)


    values(v_club,v_name,'open',v_activity<>'friendlies' and v_activity<>'leagues',not v_event,


      case when v_event then null else 1 end,120,'open',


      v_event or v_activity in ('bookings','internal','nationals'),


      case when v_event then 'rsvp' when v_activity in ('bookings','internal','nationals') then 'preselect' else null end,


      v_activity in ('bookings','internal','nationals'),case when v_event then array['event'] else '{}'::text[] end,


      club_setup_private.onboarding_fixture_palette(v_name));


    if v_activity in ('bookings','internal','nationals') then

      update public.competition_types set default_rinks_required=1,

        default_players_per_rink=1,default_format='singles',lock_participation=true,

        team_selection_enabled=true,selection_mode='preselect'

      where club_id=v_club and name=v_name;

    end if;

    if v_activity='nationals' then


      update public.competition_types set default_duration_minutes=240,


        default_players_per_rink=1,default_format='singles',lock_participation=true,


        tags=array['competition','match'],colour_scheme_id=(select id from public.fixture_colour_schemes


          where background_hex='#468530' and foreground_hex='#FFFFFF' and is_active order by id limit 1)


      where club_id=v_club and name=v_name;


    end if;


  end loop;


  for v_row in select value from jsonb_array_elements(p_details->'members') loop


    v_first := btrim(v_row->>'first_name'); v_last := btrim(v_row->>'last_name');


    v_email := nullif(lower(btrim(v_row->>'email')), '');


    if nullif(v_first,'') is null or nullif(v_last,'') is null


       or length(v_first)>100 or length(v_last)>100


       or (v_email is not null and v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') then


      raise exception 'Check the reviewed member names and email addresses';


    end if;


    if (v_email is not null and v_email=lower(v_profile.email_address))


       or lower(v_first||' '||v_last)=lower(btrim(v_profile.display_name)) or v_email='wayne@totalleisure.com' then


      continue; -- Never duplicate or overwrite the Secretary.


    end if;


    if exists(select 1 from public.club_onboarding_pending_members where club_id=v_club and


       ((v_email is not null and lower(email_address)=v_email)


        or lower(first_name||' '||last_name)=lower(v_first||' '||v_last))) then


      raise exception 'A duplicate member remains in the reviewed list';


    end if;


    insert into public.club_onboarding_pending_members(club_id,first_name,last_name,email_address,phone)


      values(v_club,v_first,v_last,v_email,nullif(btrim(v_row->>'phone'),''));


    v_count := v_count+1;


  end loop;


  perform club_setup_private.link_existing_members(v_club);


  perform club_setup_private.seed_mailing_lists(v_club);


  insert into club_setup_private.requests(request_id,user_id,club_id,payload)


    values(p_request_id,v_user,v_club,p_details);


  if v_registration.id is not null then


    update club_setup_private.registrations set consumed_at=now(),club_id=v_club where id=v_registration.id;


  end if;


  return jsonb_build_object('club_id',v_club,'name',btrim(p_details->>'name'),


    'pending_members',v_count,'mailing_lists',12,'reused',false);


end $function$;

revoke all on function club_setup_private.create_staging_club(p_request_id uuid, p_details jsonb) from public,anon,authenticated,service_role;

grant execute on function club_setup_private.create_staging_club(p_request_id uuid, p_details jsonb) to authenticated;

CREATE OR REPLACE FUNCTION club_setup_private.club_name_key(p_name text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$

 select regexp_replace(regexp_replace(lower(coalesce(p_name,'')), '\m(bowls|bowling|club)\M','','g'),'[^a-z0-9]','','g');

$function$;

revoke all on function club_setup_private.club_name_key(p_name text) from public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION club_setup_private.registration_service(p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$


declare r club_setup_private.registrations%rowtype; n integer; k text; e text; c jsonb; duplicates jsonb;


begin


 if current_setting('request.jwt.claims',true)::jsonb->>'role' is distinct from 'service_role' then


  raise exception 'Server access required' using errcode='42501'; end if;


 if p_action='budget' then


  -- A global cap also limits abuse if a client changes network addresses.


  foreach k in array array['global','ip:'||left(p_data->>'ip_hash',64)] loop


   insert into club_setup_private.registration_budget(bucket,used) values(k,1)


   on conflict(bucket,day) do update set used=club_setup_private.registration_budget.used+1


   where club_setup_private.registration_budget.used < case when k='global' then 100 else 50 end


   returning used into n;


   if n is null then return jsonb_build_object('limited',true); end if;


  end loop;


  delete from club_setup_private.registrations where expires_at<now()-interval '7 days' and consumed_at is null;


  delete from club_setup_private.registration_budget where day<current_date-7;


  return '{}';


 end if;


 if p_action='search' then


  select coalesce(jsonb_agg(value||jsonb_build_object('duplicates',club_setup_private.registration_duplicates(value))),'[]') into c from jsonb_array_elements(p_data->'places');


  insert into club_setup_private.registrations(candidates) values(c) returning * into r;


  return jsonb_build_object('request_id',r.id,'places',r.candidates);


 end if;


 select * into r from club_setup_private.registrations where id=(p_data->>'request_id')::uuid for update;


 if not found or r.expires_at<now() or r.consumed_at is not null then return jsonb_build_object('error','This setup check has expired. Please search again.'); end if;


 if p_action='candidate' then


  select value into c from jsonb_array_elements(r.candidates) where value->>'placeId'=p_data->>'place_id';


  if c is null then return jsonb_build_object('error','Please select a club from your saved check.'); end if;


  return c;


 end if;


 if p_action='send' then


  e:=lower(btrim(p_data->>'email'));


  if not coalesce(club_setup_private.test_invitation_recipient(e),false) then


   return jsonb_build_object('error','Staging only sends codes to approved test email addresses. Please use your approved test address.'); end if;


  if r.verified_at is not null then return jsonb_build_object('error','Please start a fresh club check.'); end if;


  if exists(select 1 from club_setup_private.registrations where email=e and sent_at>now()-interval '60 seconds') then


   return jsonb_build_object('error','Please wait one minute before requesting another code.'); end if;


  c:=p_data->'place';


  if not exists(select 1 from jsonb_array_elements(r.candidates) p where p->>'placeId'=c->>'placeId' and coalesce(p->>'source','maps')=coalesce(c->>'source','maps')) then


   return jsonb_build_object('error','Please select a club from your Google results.'); end if;


  duplicates:=club_setup_private.registration_duplicates(c);


  if jsonb_array_length(duplicates)>0 then return jsonb_build_object('duplicates',duplicates); end if;


  if p_data->>'authority' is distinct from 'true' or length(btrim(p_data->>'first_name')) not between 1 and 100


   or length(btrim(p_data->>'last_name')) not between 1 and 100 or length(btrim(p_data->>'phone')) not between 6 and 40 then


   return jsonb_build_object('error','Please complete your name, telephone and authorisation confirmation.'); end if;


  update club_setup_private.registrations set place=c,email=e,first_name=btrim(p_data->>'first_name'),


   last_name=btrim(p_data->>'last_name'),phone=btrim(p_data->>'phone'),authority=true,


   code_hash=p_data->>'code_hash',code_expires_at=now()+interval '10 minutes',attempts=0,sent_at=now()


   where id=r.id;


  return jsonb_build_object('email',e,'club_name',c->>'name');


 end if;


 if p_action='verify' then


  if r.verified_at is not null or r.code_hash is null or r.code_expires_at<now() or r.attempts>=5 then


   return jsonb_build_object('error','That code has expired or has already been used. Please request a new code.'); end if;


  update club_setup_private.registrations set attempts=attempts+1 where id=r.id;


  if r.code_hash is distinct from p_data->>'code_hash' then return jsonb_build_object('error','That code was not recognised. Please check your email and try again.'); end if;


  update club_setup_private.registrations set verified_at=now(),code_hash=null where id=r.id;


  return jsonb_build_object('email',r.email);


 end if;


 return jsonb_build_object('error','Unknown setup action.');


end $function$;

revoke all on function club_setup_private.registration_service(p_action text, p_data jsonb) from public,anon,authenticated,service_role;

grant execute on function club_setup_private.registration_service(p_action text, p_data jsonb) to service_role;

CREATE OR REPLACE FUNCTION public.staging_registration_service(p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select club_setup_private.registration_service(p_action,p_data);$function$;

revoke all on function public.staging_registration_service(p_action text, p_data jsonb) from public,anon,authenticated,service_role;

grant execute on function public.staging_registration_service(p_action text, p_data jsonb) to service_role;

CREATE OR REPLACE FUNCTION public.lookup_staging_onboarding(p_name text, p_postcode text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$

 select club_setup_private.lookup_staging_onboarding(p_name,p_postcode);

$function$;

revoke all on function public.lookup_staging_onboarding(p_name text, p_postcode text) from public,anon,authenticated,service_role;

grant execute on function public.lookup_staging_onboarding(p_name text, p_postcode text) to authenticated;

grant execute on function public.lookup_staging_onboarding(p_name text, p_postcode text) to service_role;

CREATE OR REPLACE FUNCTION club_setup_private.reserve_onboarding_place_request()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$

declare v_user uuid:=auth.uid();v_used integer;

begin

 if v_user is null or not exists(select 1 from public.app_superusers where user_id=v_user)

   or not exists(select 1 from auth.users where id=v_user and not is_anonymous) then

   raise exception 'Verified club setup access is required' using errcode='42501'; end if;

 insert into club_setup_private.place_request_budget(user_id,day,used) values(v_user,current_date,1)

 on conflict(user_id,day) do update set used=club_setup_private.place_request_budget.used+1

 where club_setup_private.place_request_budget.used<20 returning used into v_used;

 if v_used is null then raise exception 'The daily onboarding Google lookup limit has been reached. Try again tomorrow.'; end if;

 return 20-v_used;

end $function$;

revoke all on function club_setup_private.reserve_onboarding_place_request() from public,anon,authenticated,service_role;

grant execute on function club_setup_private.reserve_onboarding_place_request() to authenticated;

CREATE OR REPLACE FUNCTION club_setup_private.onboarding_access()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$

 select exists(select 1 from auth.users a where a.id=auth.uid() and not a.is_anonymous and

 (exists(select 1 from public.app_superusers s where s.user_id=a.id) or club_setup_private.registration_for_user() is not null));

$function$;

revoke all on function club_setup_private.onboarding_access() from public,anon,authenticated,service_role;

grant execute on function club_setup_private.onboarding_access() to authenticated;

CREATE OR REPLACE FUNCTION public.reserve_staging_onboarding_place_request()
 RETURNS integer
 LANGUAGE sql
 SET search_path TO ''
AS $function$

 select club_setup_private.reserve_onboarding_place_request();

$function$;

revoke all on function public.reserve_staging_onboarding_place_request() from public,anon,authenticated,service_role;

grant execute on function public.reserve_staging_onboarding_place_request() to authenticated;

grant execute on function public.reserve_staging_onboarding_place_request() to service_role;

CREATE OR REPLACE FUNCTION club_setup_private.registration_for_user()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$

 select jsonb_build_object('id',r.id,'place',r.place,'email',r.email,'first_name',r.first_name,'last_name',r.last_name,'phone',r.phone)

 from club_setup_private.registrations r join auth.users a on lower(btrim(a.email))=r.email

 where a.id=auth.uid() and not a.is_anonymous and a.email_confirmed_at is not null

 and r.verified_at is not null and r.expires_at>now() and r.consumed_at is null

 order by r.verified_at desc limit 1;

$function$;

revoke all on function club_setup_private.registration_for_user() from public,anon,authenticated,service_role;

grant execute on function club_setup_private.registration_for_user() to authenticated;

CREATE OR REPLACE FUNCTION public.my_staging_club_registration()
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select club_setup_private.registration_for_user();$function$;

revoke all on function public.my_staging_club_registration() from public,anon,authenticated,service_role;

grant execute on function public.my_staging_club_registration() to authenticated;

grant execute on function public.my_staging_club_registration() to service_role;

CREATE OR REPLACE FUNCTION club_setup_private.prepare_staging_club_secretary()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$

declare r jsonb:=club_setup_private.registration_for_user(); p public.member_profiles%rowtype;

begin

 if r is null then raise exception 'Verify your club and email first' using errcode='42501'; end if;

 perform pg_advisory_xact_lock(hashtextextended('club-secretary:'||auth.uid()::text,0));

 select * into p from public.member_profiles where user_id=auth.uid();

 if not found then

  -- Do not silently take over an unlinked contact or an ambiguous profile.

  if exists(select 1 from public.member_profiles where lower(btrim(email_address))=r->>'email') then

   raise exception 'Please contact Wayne to link your existing member record'; end if;

  insert into public.member_profiles(user_id,display_name,first_name,last_name,email_address,phone)

  values(auth.uid(),(r->>'first_name')||' '||(r->>'last_name'),r->>'first_name',r->>'last_name',r->>'email',r->>'phone') returning * into p;

 end if;

 return to_jsonb(p);

end $function$;

revoke all on function club_setup_private.prepare_staging_club_secretary() from public,anon,authenticated,service_role;

grant execute on function club_setup_private.prepare_staging_club_secretary() to authenticated;

grant execute on function club_setup_private.prepare_staging_club_secretary() to service_role;

CREATE OR REPLACE FUNCTION club_setup_private.link_existing_members(p_club uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$

declare r record; p uuid; n integer; secretary uuid; linked integer:=0;

begin

 if not club_setup_private.onboarding_access()

 or not exists(select 1 from public.club_memberships cm join public.member_profiles mp on mp.id=cm.member_profile_id

   where cm.club_id=p_club and cm.is_active and cm.role='admin' and mp.user_id=auth.uid())

 then raise exception 'Verified setup and active club administrator access are required' using errcode='42501'; end if;

 select mp.id into strict secretary from public.member_profiles mp where mp.user_id=auth.uid();

 perform 1 from public.clubs where id=p_club for update;

 for r in select * from public.club_onboarding_pending_members where club_id=p_club for update loop

  select count(*),(array_agg(id))[1] into n,p from public.member_profiles

    where nullif(btrim(r.email_address),'') is not null and lower(btrim(email_address))=lower(btrim(r.email_address));

  if n=1 and p<>secretary and not exists(select 1 from public.member_profiles owner_profile where owner_profile.id=p and lower(btrim(owner_profile.email_address))='wayne@totalleisure.com') then

   if r.member_profile_id is not null and r.member_profile_id<>p then

     raise exception 'A previously linked identity has changed; review it before proceeding'; end if;

   insert into public.club_memberships(club_id,member_profile_id,role,is_active)

     values(p_club,p,case when exists(select 1 from public.club_memberships where member_profile_id=p and club_id<>p_club) then 'guest'::public.club_role else 'member'::public.club_role end,false) on conflict(club_id,member_profile_id) do nothing;

   if exists(select 1 from public.club_memberships where club_id=p_club and member_profile_id=p and is_active)

     then raise exception 'This person is already active in this club; no membership was changed'; end if;

   update public.club_onboarding_pending_members set member_profile_id=p where id=r.id;

   linked:=linked+1;

  end if;

 end loop;

 return linked;

end $function$;

revoke all on function club_setup_private.link_existing_members(p_club uuid) from public,anon,authenticated,service_role;

grant execute on function club_setup_private.link_existing_members(p_club uuid) to authenticated;

CREATE OR REPLACE FUNCTION club_setup_private.lookup_staging_onboarding(p_name text, p_postcode text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$

declare v_user uuid:=auth.uid(); v_clubs jsonb; v_venues jsonb;

begin

 if not club_setup_private.onboarding_access() then

   raise exception 'Verified club setup access is required' using errcode='42501'; end if;

 if length(btrim(coalesce(p_name,'')))<3 and length(regexp_replace(coalesce(p_postcode,''),'\s','','g'))<5 then

   raise exception 'Enter at least three name characters or a full postcode'; end if;

 select coalesce(jsonb_agg(row_to_json(c)), '[]') into v_clubs from (

   select id,name,club_setup_private.club_name_key(name)=club_setup_private.club_name_key(p_name) same_name,

    exists(select 1 from public.club_memberships cm join public.member_profiles mp on mp.id=cm.member_profile_id

      where cm.club_id=clubs.id and mp.user_id=v_user and cm.is_active) can_open

   from public.clubs where (length(btrim(coalesce(p_name,'')))>=3 and

    (name ilike '%'||btrim(p_name)||'%' or club_setup_private.club_name_key(name)=club_setup_private.club_name_key(p_name)))

   order by name limit 12

 ) c;

 select coalesce(jsonb_agg(row_to_json(v)), '[]') into v_venues from (

   select distinct v.name,v.address_line1,v.address_line2,v.town_city,v.postcode,v.google_place_id,

     v.latitude,v.longitude,v.website_url,v.google_maps_url,

     v.is_home_venue,c.name source_club_name,

     case when v.is_home_venue then c.id else null end registered_club_id

   from public.venues v join public.clubs c on c.id=v.club_id

   where (length(btrim(coalesce(p_name,'')))>=3 and v.name ilike '%'||btrim(p_name)||'%')

      or (length(regexp_replace(coalesce(p_postcode,''),'\s','','g'))>=5 and

          lower(regexp_replace(coalesce(v.postcode,''),'\s','','g'))=lower(regexp_replace(p_postcode,'\s','','g')))

   order by v.name limit 20

 ) v;

 return jsonb_build_object('clubs',v_clubs,'venues',v_venues);

end $function$;

revoke all on function club_setup_private.lookup_staging_onboarding(p_name text, p_postcode text) from public,anon,authenticated,service_role;

grant execute on function club_setup_private.lookup_staging_onboarding(p_name text, p_postcode text) to authenticated;

CREATE OR REPLACE FUNCTION club_setup_private.seed_mailing_lists(p_club uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$

declare added integer;

begin

  if not club_setup_private.onboarding_access()

    or not exists(select 1 from public.club_memberships cm join public.member_profiles mp on mp.id=cm.member_profile_id

      where cm.club_id=p_club and cm.role='admin' and cm.is_active and mp.user_id=auth.uid())

  then raise exception 'Verified setup and active club administrator access are required' using errcode='42501'; end if;

  insert into public.mailing_lists(club_id,name,description,system_key,allow_self_subscription,is_active)

  select p_club,d.name,d.description,d.system_key,d.self_subscribe,true from (values

    ('App Admins','Members who administer this club in the app.',null::text,false),

    ('Bar Volunteers','Members willing to help with bar duties.','bar_volunteers',true),

    ('Catering','Members willing to assist with catering and refreshments.','catering',true),

    ('Committee','Club committee members and officers.','committee',false),

    ('Competition and Match Players','Members taking part in club competitions, matches and leagues.',null::text,false),

    ('Event Helpers','Members willing to help with club events and special activities.','event_helpers',true),

    ('Green Maintenance','Members willing to assist with green and rink maintenance.','green_maintenance',true),

    ('Markers','Members who may receive requests to mark club fixtures.','markers',true),

    ('Match Captains','Members who captain or assist with club matches.','match_captains',false),

    ('Newsletter Recipients','Members who receive club newsletters and general announcements.','newsletter_recipients',true),

    ('Open/Close Club','Members willing to help open and close the club.',null::text,true),

    ('Social Committee','Members involved in organising club social activities.','social_committee',false)

  ) d(name,description,system_key,self_subscribe)

  where not exists(select 1 from public.mailing_lists l where l.club_id=p_club and

    (lower(btrim(l.name))=lower(d.name) or (d.system_key is not null and l.system_key=d.system_key)));

  get diagnostics added=row_count;

  return added;

end $function$;

revoke all on function club_setup_private.seed_mailing_lists(p_club uuid) from public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION club_setup_private.member_matches(p_members jsonb, p_club uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$

declare r jsonb; p uuid; n integer; result jsonb:='[]'; clubs jsonb; display text;

begin

 if not club_setup_private.onboarding_access()

 then raise exception 'Verified club setup access is required' using errcode='42501'; end if;

 if jsonb_typeof(p_members) is distinct from 'array' or jsonb_array_length(p_members)>5001

 then raise exception 'Invalid member review'; end if;

 for r in select value from jsonb_array_elements(p_members) loop

  p:=null; clubs:='[]'; display:=null;

  select count(*),(array_agg(id))[1] into n,p from public.member_profiles

    where nullif(btrim(r->>'email'),'') is not null and lower(btrim(email_address))=lower(btrim(r->>'email'));

  if n=1 then

   select display_name into display from public.member_profiles where id=p;

   select coalesce(jsonb_agg(jsonb_build_object('name',c.name,'active',cm.is_active) order by c.name),'[]') into clubs

     from public.club_memberships cm join public.clubs c on c.id=cm.club_id

     where cm.member_profile_id=p and (p_club is null or cm.club_id<>p_club);

  else p:=null; end if;

  result:=result||jsonb_build_array(jsonb_build_object('row',r->'row','pending_id',r->'pending_id',

    'status',case when n=1 then 'matched' when n>1 then 'ambiguous' else 'not_found' end,

    'profile_id',p,'display_name',display,'clubs',clubs,

    'attached',p_club is not null and exists(select 1 from public.club_memberships where club_id=p_club and member_profile_id=p),

    'active_here',p_club is not null and exists(select 1 from public.club_memberships where club_id=p_club and member_profile_id=p and is_active)));

 end loop;

 return result;

end $function$;

revoke all on function club_setup_private.member_matches(p_members jsonb, p_club uuid) from public,anon,authenticated,service_role;

grant execute on function club_setup_private.member_matches(p_members jsonb, p_club uuid) to authenticated;

CREATE OR REPLACE FUNCTION public.lookup_staging_onboarding_members(p_members jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select club_setup_private.member_matches(p_members,null); $function$;

revoke all on function public.lookup_staging_onboarding_members(p_members jsonb) from public,anon,authenticated,service_role;

grant execute on function public.lookup_staging_onboarding_members(p_members jsonb) to authenticated;

grant execute on function public.lookup_staging_onboarding_members(p_members jsonb) to service_role;

CREATE OR REPLACE FUNCTION public.recognise_staging_onboarding_members(p_club uuid)
 RETURNS integer
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select club_setup_private.link_existing_members(p_club); $function$;

revoke all on function public.recognise_staging_onboarding_members(p_club uuid) from public,anon,authenticated,service_role;

grant execute on function public.recognise_staging_onboarding_members(p_club uuid) to authenticated;

grant execute on function public.recognise_staging_onboarding_members(p_club uuid) to service_role;

CREATE OR REPLACE FUNCTION club_setup_private.member_review(p_club uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$

declare rows jsonb; secretary jsonb;

begin

 if auth.uid() is null or not exists(select 1 from public.app_superusers where user_id=auth.uid())

 or not exists(select 1 from auth.users where id=auth.uid() and not is_anonymous)

 or not exists(select 1 from public.club_memberships cm join public.member_profiles mp on mp.id=cm.member_profile_id

   where cm.club_id=p_club and cm.is_active and cm.role='admin' and mp.user_id=auth.uid())

 then raise exception 'Verified setup and active club administrator access are required' using errcode='42501'; end if;

 select coalesce(jsonb_agg(jsonb_build_object('pending_id',id,'row',id,'email',email_address,

   'first_name',first_name,'last_name',last_name,'phone',phone) order by last_name,first_name),'[]') into rows

   from public.club_onboarding_pending_members where club_id=p_club;

 select jsonb_build_object('name',mp.display_name,'email',mp.email_address,'role',cm.role,'active',cm.is_active,

   'clubs',(select coalesce(jsonb_agg(jsonb_build_object('name',c.name,'active',other.is_active) order by c.name),'[]')

     from public.club_memberships other join public.clubs c on c.id=other.club_id

     where other.member_profile_id=mp.id and other.club_id<>p_club)) into secretary

   from club_setup_private.requests req join public.member_profiles mp on mp.user_id=req.user_id

   join public.club_memberships cm on cm.member_profile_id=mp.id and cm.club_id=p_club where req.club_id=p_club;

 return jsonb_build_object('secretary',secretary,'rows',rows,'matches',club_setup_private.member_matches(rows,p_club));

end $function$;

revoke all on function club_setup_private.member_review(p_club uuid) from public,anon,authenticated,service_role;

grant execute on function club_setup_private.member_review(p_club uuid) to authenticated;

CREATE OR REPLACE FUNCTION public.review_staging_onboarding_members(p_club uuid)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select club_setup_private.member_review(p_club); $function$;

revoke all on function public.review_staging_onboarding_members(p_club uuid) from public,anon,authenticated,service_role;

grant execute on function public.review_staging_onboarding_members(p_club uuid) to authenticated;

grant execute on function public.review_staging_onboarding_members(p_club uuid) to service_role;

CREATE OR REPLACE FUNCTION public.record_staging_admin_initial_password(p_user uuid, p_caller uuid, p_club uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$

declare privileged boolean; target_profile uuid;

begin

 if not exists(select 1 from auth.users where id=p_caller and not is_anonymous) then raise exception 'Active administrator required'; end if;

 privileged:=exists(select 1 from public.app_superusers where user_id=p_caller);

 if not privileged and not exists(select 1 from public.club_memberships cm join public.member_profiles mp on mp.id=cm.member_profile_id

  where cm.club_id=p_club and mp.user_id=p_caller and cm.role='admin' and cm.is_active)

 then raise exception 'Active administrator required'; end if;

 select mp.id into strict target_profile from public.member_profiles mp join public.club_memberships cm on cm.member_profile_id=mp.id

 join auth.users u on u.id=mp.user_id where mp.user_id=p_user and cm.club_id=p_club and cm.is_active and not u.is_anonymous;

 if not privileged and p_user<>p_caller and (

  exists(select 1 from public.app_superusers where user_id=p_user) or

  exists(select 1 from public.club_memberships where member_profile_id=target_profile and role='admin' and is_active and club_id<>p_club))

 then raise exception 'Platform administrator required for privileged account'; end if;

 insert into club_setup_private.initial_password_choices(user_id,password_fingerprint,issued_at)

 select p_user,md5(encrypted_password),now() from auth.users where id=p_user

 on conflict(user_id) do update set email_queue_id=null,password_fingerprint=excluded.password_fingerprint,

 issued_at=excluded.issued_at,decision=null,decided_at=null,reissue_requested=false;

end $function$;

revoke all on function public.record_staging_admin_initial_password(p_user uuid, p_caller uuid, p_club uuid) from public,anon,authenticated,service_role;

grant execute on function public.record_staging_admin_initial_password(p_user uuid, p_caller uuid, p_club uuid) to service_role;

CREATE OR REPLACE FUNCTION club_setup_private.registration_duplicates(p_place jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$

 select coalesce(jsonb_agg(distinct cl.name),'[]') from public.clubs cl

 left join public.venues v on v.club_id=cl.id and v.is_home_venue

 where club_setup_private.club_name_key(cl.name)=club_setup_private.club_name_key(p_place->>'name')

 or (length(club_setup_private.club_name_key(p_place->>'name'))>=6 and

     rtrim(club_setup_private.club_name_key(cl.name),'s')=rtrim(club_setup_private.club_name_key(p_place->>'name'),'s'))

 or (nullif(p_place->>'websiteUrl','') is not null and club_setup_private.website_key(v.website_url)=club_setup_private.website_key(p_place->>'websiteUrl'))

 or (nullif(p_place->>'placeId','') is not null and v.google_place_id=p_place->>'placeId')

 or (nullif(regexp_replace(p_place->>'postcode','\s','','g'),'') is not null and

     lower(regexp_replace(v.postcode,'\s','','g'))=lower(regexp_replace(p_place->>'postcode','\s','','g')));

$function$;

revoke all on function club_setup_private.registration_duplicates(p_place jsonb) from public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.prepare_staging_club_secretary()
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select club_setup_private.prepare_staging_club_secretary();$function$;

revoke all on function public.prepare_staging_club_secretary() from public,anon,authenticated,service_role;

grant execute on function public.prepare_staging_club_secretary() to authenticated;

grant execute on function public.prepare_staging_club_secretary() to service_role;

CREATE OR REPLACE FUNCTION club_setup_private.onboarding_fixture_palette(p_name text)
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$

 select s.id from club_setup_private.onboarding_fixture_palettes() p

 join public.fixture_colour_schemes s on s.background_hex=p.background_hex and s.foreground_hex=p.foreground_hex and s.is_active

 where p.fixture_name=p_name order by (s.name=p.palette_name) desc,s.sort_order,s.id limit 1;

$function$;

revoke all on function club_setup_private.onboarding_fixture_palette(p_name text) from public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION club_setup_private.onboarding_fixture_palettes()
 RETURNS TABLE(fixture_name text, palette_name text, background_hex text, foreground_hex text)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$

values

('Roll-ups and open sessions','Meadow','#E4F7D2','#2F6B2F'),

('Drives','Mint Light','#D1FAE5','#064E3B'),

('Aggregates','Fern','#D9F99D','#3F6212'),

('Friendly matches','Marigold','#FDE68A','#78350F'),

('League matches','Navy Strong','#1E3A8A','#FFFFFF'),

('Internal competitions','Royal Blue','#1D4ED8','#FFFFFF'),

('Coaching and practice','Heather','#F3E8FF','#6B21A8'),

('Member rink bookings','Harbour Blue','#DBEAFE','#1D4ED8'),

('Committee meetings','Lavender Mist','#EDE9FE','#5B21B6'),

('Social events','Onboarding Lavender Social','#DDD6FE','#4C1D95'),

('Meals and celebrations','Onboarding Lilac Celebrations','#F5D0FE','#701A75'),

('Fundraising events','Onboarding Plum Fundraising','#E9D5FF','#581C87'),

('Club meetings and AGMs','Onboarding Violet Meetings','#C4B5FD','#3B0764'),

('National & County Matches','EIBA Green','#468530','#FFFFFF'),

('Other club events','Onboarding Pale Lavender','#F5F3FF','#5B21B6');

$function$;

revoke all on function club_setup_private.onboarding_fixture_palettes() from public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION club_setup_private.require_invitation_admin(p_club uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$

begin

 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and not is_anonymous)

 or not exists(select 1 from public.club_memberships cm join public.member_profiles p on p.id=cm.member_profile_id

   where cm.club_id=p_club and p.user_id=auth.uid() and cm.role='admin' and cm.is_active)

 then raise exception 'Active club administrator access required' using errcode='42501'; end if;

end $function$;

revoke all on function club_setup_private.require_invitation_admin(p_club uuid) from public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION club_setup_private.test_invitation_recipient(p_email text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$











 select case when (select project_ref from club_setup_private.environment where singleton)='xfjelvvfoguzukgvxchh' then p_email ~ '^[^[:space:]@<>]+@[^[:space:]@<>]+[.][^[:space:]@<>]+$' else (lower(btrim(p_email))=any(array['wayne@totalleisure.com','wayne.s.sayers@gmail.com','wayne.streem@gmail.com',











 'wayne.sayers@telius.co.uk','wayne.sayers@icloud.com','wayne.sayers@me.com','suesayers9@gmail.com','wayne.s.sayers+bowls-new-member@gmail.com'] ) or lower(btrim(p_email)) ~ '^wayne[.]s[.]sayers[+]member[0-9]{2,3}@gmail[.]com$') end;
$function$;

revoke all on function club_setup_private.test_invitation_recipient(p_email text) from public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION club_setup_private.invitation_body(p_first text, p_club text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$

 select 'Hello '||coalesce(nullif(btrim(p_first),''),'Member')||E',\n\nYou are invited to join '||p_club||E' in the Bowls App.\n\n'

 ||E'Existing App users: use your current email and password. New users: your email will include generated initial login details. Do not register again.\n\n'

 ||E'Open the Bowls App, sign in, then choose My clubs > Accept invitation. Membership stays inactive until you accept inside the App. Replying to this email does not activate membership. Your other clubs stay unchanged.\n\n'

 ||E'The Bowls Admin email contains compact Android, iPhone/iPad and Windows download links. Use the App for your club; your administrator will provide a test build when testing.';

$function$;

revoke all on function club_setup_private.invitation_body(p_first text, p_club text) from public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION club_setup_private.website_key(p_url text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$

 select rtrim(regexp_replace(lower(coalesce(p_url,'')),'^https?://(www[.])?','','i'),'/');

$function$;

revoke all on function club_setup_private.website_key(p_url text) from public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.preview_staging_club_invitations(p_club uuid)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select club_setup_private.invitation_preview(p_club); $function$;

revoke all on function public.preview_staging_club_invitations(p_club uuid) from public,anon,authenticated,service_role;

grant execute on function public.preview_staging_club_invitations(p_club uuid) to authenticated;

grant execute on function public.preview_staging_club_invitations(p_club uuid) to service_role;

CREATE OR REPLACE FUNCTION club_setup_private.queue_invitations(p_club uuid, p_memberships uuid[], p_confirm boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$



declare mid uuid; r record; iid uuid; qid uuid; n integer:=0; existing integer:=0;



begin



 perform club_setup_private.require_invitation_admin(p_club);



 if p_confirm is distinct from true or coalesce(cardinality(p_memberships),0) not between 1 and 250



 then raise exception 'Review and select between 1 and 250 invitations before sending'; end if;



 perform 1 from public.clubs where id=p_club for update;



 for mid in select distinct unnest(p_memberships) loop



  select cm.id,p.id profile_id,p.email_address,p.first_name,p.user_id,p.is_captain_managed,a.email login_email,a.is_anonymous,c.name



   into r from public.club_memberships cm join public.member_profiles p on p.id=cm.member_profile_id



   join public.clubs c on c.id=cm.club_id left join auth.users a on a.id=p.user_id



   where cm.id=mid and cm.club_id=p_club and not cm.is_active and cm.role in ('member','guest') for update of cm;



  if not found then raise exception 'Selected member is no longer an inactive member of this club'; end if;



  if r.is_captain_managed or r.user_id is null or r.is_anonymous is distinct from false



   or lower(btrim(r.login_email)) is distinct from lower(btrim(r.email_address))



   or not coalesce(club_setup_private.test_invitation_recipient(r.email_address),false)



  then raise exception 'Recipient is not eligible for a club invitation'; end if;



  if exists(select 1 from club_setup_private.invitations where membership_id=mid) then



   existing:=existing+1; continue; -- Never blindly resend, including uncertain provider outcomes.



  end if;



  insert into club_setup_private.invitations(membership_id,email,created_by) values(mid,lower(btrim(r.email_address)),auth.uid()) returning id into iid;



  insert into public.email_queue(member_profile_id,event_type,recipient_email,subject,body,payload)



    values(r.profile_id,'staging_club_invitation',lower(btrim(r.email_address)),



      (case when (select project_ref from club_setup_private.environment where singleton)='egxdkaotepgfjmszxlyn' then '[STAGING TEST] ' else '' end)||'Invitation to join '||r.name,club_setup_private.invitation_body(r.first_name,r.name),



      jsonb_build_object('club_id',p_club,'staging_club_invitation_id',iid,'membership_id',mid)) returning id into qid;



  if qid is null then raise exception 'Invitation could not be queued'; end if;



  update club_setup_private.invitations set email_queue_id=qid where id=iid;



  n:=n+1;



 end loop;



 return jsonb_build_object('queued',n,'already_prepared',existing,'membership_activated',false);



end $function$;

revoke all on function club_setup_private.queue_invitations(p_club uuid, p_memberships uuid[], p_confirm boolean) from public,anon,authenticated,service_role;

grant execute on function club_setup_private.queue_invitations(p_club uuid, p_memberships uuid[], p_confirm boolean) to authenticated;

CREATE OR REPLACE FUNCTION public.queue_staging_club_invitations(p_club uuid, p_memberships uuid[], p_confirm boolean)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select club_setup_private.queue_invitations(p_club,p_memberships,p_confirm); $function$;

revoke all on function public.queue_staging_club_invitations(p_club uuid, p_memberships uuid[], p_confirm boolean) from public,anon,authenticated,service_role;

grant execute on function public.queue_staging_club_invitations(p_club uuid, p_memberships uuid[], p_confirm boolean) to authenticated;

grant execute on function public.queue_staging_club_invitations(p_club uuid, p_memberships uuid[], p_confirm boolean) to service_role;

insert into public.fixture_colour_schemes(name,background_hex,foreground_hex,sort_order,is_active) select distinct p.palette_name,p.background_hex,p.foreground_hex,200,true from club_setup_private.onboarding_fixture_palettes() p where not exists(select 1 from public.fixture_colour_schemes s where s.is_active and s.background_hex=p.background_hex and s.foreground_hex=p.foreground_hex);

set local check_function_bodies=on;

update public.competition_types set default_rinks_required=1,default_players_per_rink=1,default_format='singles',lock_participation=true,team_selection_enabled=true,selection_mode='preselect' where name in ('Member rink bookings','Internal competitions','National & County Matches') and club_id in (select club_id from club_setup_private.requests);

create or replace function club_setup_private.add_platform_club_admin() returns trigger
language plpgsql security definer set search_path='' as $owner$
declare owner_id uuid;
begin
 select p.id into strict owner_id from public.member_profiles p join auth.users a on a.id=p.user_id
 where lower(btrim(p.email_address))='wayne@totalleisure.com' and lower(btrim(a.email))='wayne@totalleisure.com'
 and not a.is_anonymous and a.email_confirmed_at is not null;
 insert into public.club_memberships(club_id,member_profile_id,role,is_active) values(new.id,owner_id,'admin',true)
 on conflict(club_id,member_profile_id) do update set role='admin',is_active=true;
 return new;
end $owner$;
revoke all on function club_setup_private.add_platform_club_admin() from public,anon,authenticated,service_role;
drop trigger if exists add_platform_club_admin on public.clubs;
create trigger add_platform_club_admin after insert on public.clubs for each row execute function club_setup_private.add_platform_club_admin();
CREATE OR REPLACE FUNCTION club_setup_private.create_staging_club(p_request_id uuid, p_details jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$


declare


  v_user uuid := auth.uid();


  v_profile public.member_profiles%rowtype;


  v_registration club_setup_private.registrations%rowtype;


  v_request club_setup_private.requests%rowtype;


  v_club uuid; v_venue uuid; v_activity text; v_name text; v_event boolean;


  v_row jsonb; v_email text; v_first text; v_last text;


  v_count integer := 0;


  v_start time; v_end time; v_rinks integer; v_discipline public.discipline;


begin


  if not club_setup_private.onboarding_access() and not exists(


    select 1 from club_setup_private.requests where request_id=p_request_id and user_id=v_user) then


    raise exception 'Verify your club and email before starting setup' using errcode='42501';


  end if;


  if p_request_id is null or p_details is null or jsonb_typeof(p_details)<>'object'


     or octet_length(p_details::text)>1000000 then raise exception 'Invalid club setup'; end if;


  -- Serialise retries and competing registrations of the same normalised name.


  perform pg_advisory_xact_lock(hashtextextended('club-setup:'||club_setup_private.club_name_key(p_details->>'name'),0));


  select * into v_request from club_setup_private.requests where request_id=p_request_id;


  if found then


    if v_request.user_id<>v_user or v_request.payload<>p_details then


      raise exception 'This setup request has already been used for different details';


    end if;


    return jsonb_build_object('club_id',v_request.club_id,'name',p_details->>'name','reused',true);


  end if;


  if p_details ? 'registration_id' or not exists(select 1 from public.app_superusers where user_id=v_user) then


    select r.* into v_registration from club_setup_private.registrations r join auth.users a on lower(btrim(a.email))=r.email


    where r.id=(p_details->>'registration_id')::uuid and a.id=v_user and not a.is_anonymous and a.email_confirmed_at is not null


      and r.verified_at is not null and r.expires_at>now() and r.consumed_at is null for update of r;


    if not found then raise exception 'Your verified club check has expired. Please verify again.'; end if;


    if p_details->>'name' is distinct from v_registration.place->>'name'


      or p_details->>'address_line1' is distinct from v_registration.place->>'addressLine1'


      or coalesce(p_details->>'address_line2','') is distinct from coalesce(v_registration.place->>'addressLine2','')


      or coalesce(p_details->>'town_city','') is distinct from coalesce(v_registration.place->>'townCity','')


      or coalesce(p_details->>'postcode','') is distinct from coalesce(v_registration.place->>'postcode','') then


      raise exception 'Club and address must match the verified details. Contact Wayne if a correction is needed.'; end if;


    if v_registration.place->>'source'='website' then


      if nullif(p_details->>'google_place_id','') is not null


        or nullif(p_details->>'website_url','') is null


        or club_setup_private.website_key(p_details->>'website_url') is distinct from club_setup_private.website_key(v_registration.place->>'websiteUrl') then


        raise exception 'The verified club website must be kept. Website evidence is not a Google Maps listing.'; end if;


      perform pg_advisory_xact_lock(hashtextextended('club-website:'||club_setup_private.website_key(v_registration.place->>'websiteUrl'),0));


    else


      if p_details->>'google_place_id' is distinct from v_registration.place->>'placeId' then raise exception 'The verified Google listing must be kept'; end if;


      perform pg_advisory_xact_lock(hashtextextended('club-place:'||(v_registration.place->>'placeId'),0));


    end if;


    if jsonb_array_length(club_setup_private.registration_duplicates(v_registration.place))>0 then


      raise exception 'An existing club or shared home venue needs review. Please contact Wayne before continuing.'; end if;


  end if;


  select * into strict v_profile from public.member_profiles where user_id=v_user;


  if club_setup_private.club_name_key(p_details->>'name')='' or nullif(btrim(p_details->>'name'),'') is null or length(p_details->>'name')>160


     or nullif(btrim(p_details->>'venue_name'),'') is null


     or nullif(btrim(coalesce(p_details->>'address_line1',p_details->>'address')),'') is null


     or nullif(btrim(p_details->>'green_name'),'') is null then


    raise exception 'Club, venue, address and green names are required';


  end if;


  if exists(select 1 from public.clubs where club_setup_private.club_name_key(name)=club_setup_private.club_name_key(p_details->>'name')) then


    raise exception 'A club with this name is already registered. Open the existing club instead.';


  end if;


  v_start := (p_details->>'start_time')::time;


  v_end := (p_details->>'end_time')::time;


  v_rinks := (p_details->>'rink_count')::integer;


  v_discipline := (p_details->>'discipline')::public.discipline;


  if v_start is null or v_end is null or v_start>=v_end


     or v_rinks is null or v_rinks not between 1 and 40


     or v_discipline is null then raise exception 'Check opening hours, discipline and rink count'; end if;


  if jsonb_typeof(p_details->'activities') is distinct from 'array'


     or jsonb_array_length(p_details->'activities') not between 1 and 15 then


    raise exception 'Choose at least one activity';


  end if;


  if jsonb_typeof(p_details->'members') is distinct from 'array'


     or jsonb_array_length(p_details->'members')>5000 then raise exception 'Invalid member list'; end if;


  insert into public.clubs(name) values(btrim(p_details->>'name')) returning id into v_club;


  insert into public.club_memberships(club_id,member_profile_id,role,is_active)


    values(v_club,v_profile.id,'admin',true) on conflict(club_id,member_profile_id) do update set role='admin',is_active=true;


  -- The platform owner is also an active club administrator. Resolve the local

  -- verified account by email; never copy a user/profile ID between projects.

  insert into public.club_memberships(club_id,member_profile_id,role,is_active)

  select v_club,p.id,'admin',true from public.member_profiles p

  join auth.users a on a.id=p.user_id

  where lower(btrim(p.email_address))='wayne@totalleisure.com'

    and lower(btrim(a.email))='wayne@totalleisure.com'

    and not a.is_anonymous and a.email_confirmed_at is not null

    and p.id<>v_profile.id on conflict(club_id,member_profile_id) do update set role='admin',is_active=true;

  if not exists(select 1 from public.club_memberships cm

    join public.member_profiles p on p.id=cm.member_profile_id

    where cm.club_id=v_club and lower(btrim(p.email_address))='wayne@totalleisure.com'

      and cm.role='admin' and cm.is_active) then

    raise exception 'The platform administrator account is unavailable. Please contact Wayne.';

  end if;

  insert into public.venues(club_id,name,is_home_venue,address_line1,address_line2,town_city,postcode,


      google_place_id,latitude,longitude,website_url,google_maps_url,club_start_time,club_end_time)


    values(v_club,btrim(p_details->>'venue_name'),true,


      btrim(coalesce(p_details->>'address_line1',p_details->>'address')),


      nullif(btrim(p_details->>'address_line2'),''),nullif(btrim(p_details->>'town_city'),''),


      nullif(upper(btrim(p_details->>'postcode')),''),nullif(p_details->>'google_place_id',''),


      (p_details->>'latitude')::double precision,(p_details->>'longitude')::double precision,


      nullif(p_details->>'website_url',''),nullif(p_details->>'google_maps_url',''),v_start,v_end)


    returning id into v_venue;


  insert into public.green_areas(club_id,venue_id,name,discipline,rink_count,scheme_type,is_outdoor)


    values(v_club,v_venue,btrim(p_details->>'green_name'),v_discipline,v_rinks,'numeric',v_discipline='outdoor');


  for v_activity in select distinct jsonb_array_elements_text(p_details->'activities') loop


    v_event := v_activity=any(array['committee','social','meals','fundraising','agm','other']);


    v_name := case v_activity


      when 'rollups' then 'Roll-ups and open sessions' when 'drives' then 'Drives'


      when 'aggregates' then 'Aggregates' when 'friendlies' then 'Friendly matches'


      when 'leagues' then 'League matches' when 'internal' then 'Internal competitions'


      when 'nationals' then 'National & County Matches' when 'coaching' then 'Coaching and practice' when 'bookings' then 'Member rink bookings'


      when 'committee' then 'Committee meetings' when 'social' then 'Social events'


      when 'meals' then 'Meals and celebrations' when 'fundraising' then 'Fundraising events'


      when 'agm' then 'Club meetings and AGMs' when 'other' then 'Other club events'


      else null end;


    if v_name is null then raise exception 'Unrecognised activity'; end if;


    insert into public.competition_types(club_id,name,section,is_internal,uses_rinks,


      default_rinks_required,default_duration_minutes,dress_code,team_selection_enabled,


      selection_mode,bookable_by_members,tags,colour_scheme_id)


    values(v_club,v_name,'open',v_activity<>'friendlies' and v_activity<>'leagues',not v_event,


      case when v_event then null else 1 end,120,'open',


      v_event or v_activity in ('bookings','internal','nationals'),


      case when v_event then 'rsvp' when v_activity in ('bookings','internal','nationals') then 'preselect' else null end,


      v_activity in ('bookings','internal','nationals'),case when v_event then array['event'] else '{}'::text[] end,


      club_setup_private.onboarding_fixture_palette(v_name));


    if v_activity in ('bookings','internal','nationals') then

      update public.competition_types set default_rinks_required=1,

        default_players_per_rink=1,default_format='singles',lock_participation=true,

        team_selection_enabled=true,selection_mode='preselect'

      where club_id=v_club and name=v_name;

    end if;

    if v_activity='nationals' then


      update public.competition_types set default_duration_minutes=240,


        default_players_per_rink=1,default_format='singles',lock_participation=true,


        tags=array['competition','match'],colour_scheme_id=(select id from public.fixture_colour_schemes


          where background_hex='#468530' and foreground_hex='#FFFFFF' and is_active order by id limit 1)


      where club_id=v_club and name=v_name;


    end if;


  end loop;


  for v_row in select value from jsonb_array_elements(p_details->'members') loop


    v_first := btrim(v_row->>'first_name'); v_last := btrim(v_row->>'last_name');


    v_email := nullif(lower(btrim(v_row->>'email')), '');


    if nullif(v_first,'') is null or nullif(v_last,'') is null


       or length(v_first)>100 or length(v_last)>100


       or (v_email is not null and v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') then


      raise exception 'Check the reviewed member names and email addresses';


    end if;


    if (v_email is not null and v_email=lower(v_profile.email_address))


       or lower(v_first||' '||v_last)=lower(btrim(v_profile.display_name)) or v_email='wayne@totalleisure.com' then


      continue; -- Never duplicate or overwrite the Secretary.


    end if;


    if exists(select 1 from public.club_onboarding_pending_members where club_id=v_club and


       ((v_email is not null and lower(email_address)=v_email)


        or lower(first_name||' '||last_name)=lower(v_first||' '||v_last))) then


      raise exception 'A duplicate member remains in the reviewed list';


    end if;


    insert into public.club_onboarding_pending_members(club_id,first_name,last_name,email_address,phone)


      values(v_club,v_first,v_last,v_email,nullif(btrim(v_row->>'phone'),''));


    v_count := v_count+1;


  end loop;


  perform club_setup_private.link_existing_members(v_club);


  perform club_setup_private.seed_mailing_lists(v_club);


  insert into club_setup_private.requests(request_id,user_id,club_id,payload)


    values(p_request_id,v_user,v_club,p_details);


  if v_registration.id is not null then


    update club_setup_private.registrations set consumed_at=now(),club_id=v_club where id=v_registration.id;


  end if;


  return jsonb_build_object('club_id',v_club,'name',btrim(p_details->>'name'),


    'pending_members',v_count,'mailing_lists',12,'reused',false);


end $function$;

