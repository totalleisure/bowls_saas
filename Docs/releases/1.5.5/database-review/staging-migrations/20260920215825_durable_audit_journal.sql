-- Durable history deliberately has no foreign keys to mutable/deletable records.
create schema if not exists audit_private;
revoke all on schema audit_private from public, anon, authenticated;
create table public.audit_journal (
 id bigint generated always as identity primary key,
 occurred_at timestamptz not null default clock_timestamp(),
 operation_id bigint not null default txid_current(),
 actor_user_id uuid, actor_name text not null,
 origin text not null, club_id uuid, club_name text,
 record_type text not null, record_id text, record_label text not null,
 fixture_id uuid, action text not null, reason text,
 before_values jsonb, after_values jsonb,
 outcome text not null default 'completed'
);
create index audit_journal_time_idx on public.audit_journal (occurred_at desc,id desc);
create index audit_journal_club_time_idx on public.audit_journal (club_id,occurred_at desc);
create index audit_journal_actor_time_idx on public.audit_journal (actor_user_id,occurred_at desc);
create index audit_journal_record_idx on public.audit_journal (record_type,record_id);
create index audit_journal_fixture_idx on public.audit_journal (fixture_id);
alter table public.audit_journal enable row level security;
revoke all on public.audit_journal from public,anon,authenticated,service_role;
grant select on public.audit_journal to authenticated;
create policy superuser_read on public.audit_journal for select to authenticated
 using (exists(select 1 from public.app_superusers s where s.user_id=(select auth.uid())));

create function audit_private.immutable() returns trigger language plpgsql as $$
begin raise exception 'Audit entries cannot be changed or removed'; end $$;
create trigger immutable_audit before update or delete or truncate on public.audit_journal
 for each statement execute function audit_private.immutable();

-- Explicit allowlists: never copy passwords, tokens, email bodies or arbitrary payloads.
create function audit_private.pick(v jsonb, keys text[]) returns jsonb
language sql immutable set search_path = '' as $$
 select coalesce(jsonb_object_agg(key,value),'{}'::jsonb) from jsonb_each(v) where key=any(keys)
$$;
create function audit_private.capture() returns trigger language plpgsql security definer
set search_path = '' as $$
declare
 b jsonb; a jsonb; r jsonb; keys text[] := string_to_array(TG_ARGV[0],',');
 cid uuid; fid uuid; rid text; actor uuid := auth.uid(); actor_label text;
 label text; club_label text; event text := lower(TG_OP); source text;
begin
 if TG_OP<>'INSERT' then b:=audit_private.pick(to_jsonb(old),keys); end if;
 if TG_OP<>'DELETE' then a:=audit_private.pick(to_jsonb(new),keys); end if;
 if TG_OP='UPDATE' and b=a then return new; end if;
 r:=coalesce(a,b); rid:=coalesce(r->>'id',r->>'user_id');
 cid:=(r->>'club_id')::uuid; fid:=(r->>'fixture_id')::uuid;
 if TG_TABLE_NAME='fixtures' then fid:=rid::uuid; end if;
 if TG_TABLE_NAME='clubs' then cid:=rid::uuid; end if;
 if TG_TABLE_NAME='team_members' then
   select t.club_id,t.name into cid,label from public.teams t where t.id=(r->>'team_id')::uuid;
 end if;
 if TG_TABLE_NAME='team_selection_members' then
   select s.fixture_id into fid from public.team_selections s where s.id=(r->>'team_selection_id')::uuid;
 end if;
 if fid is not null then
   select f.club_id,coalesce(nullif(f.team_name,''),'Fixture')||' / '||f.start_at::text
   into cid,label from public.fixtures f where f.id=fid;
 end if;
 cid:=coalesce(cid,(r->>'club_id')::uuid);
 if TG_TABLE_NAME='member_profiles' then label:=concat_ws(' ',r->>'first_name',r->>'last_name'); end if;
 if r->>'member_profile_id' is not null then
   select concat_ws(' / ',label,concat_ws(' ',p.first_name,p.last_name)) into label
   from public.member_profiles p where p.id=(r->>'member_profile_id')::uuid;
 end if;
 label:=coalesce(nullif(label,''),nullif(r->>'name',''),nullif(r->>'title',''),nullif(r->>'team_name',''),TG_TABLE_NAME||' '||rid::text);
 select c.name into club_label from public.clubs c where c.id=cid;
 source:=case when actor is not null then 'app' when coalesce(auth.role(),'')='service_role' then 'service' else 'database maintenance' end;
 -- These fields are populated by verified server workflows, not inferred from the recipient.
 if actor is null and auth.role()='service_role' and TG_TABLE_NAME='member_invitation_attempts' then
   actor:=(coalesce(to_jsonb(new),to_jsonb(old))->>'created_by')::uuid;
 end if;
 select concat_ws(' ',p.first_name,p.last_name) into actor_label from public.member_profiles p where p.user_id=actor limit 1;
 actor_label:=coalesce(nullif(actor_label,''),actor::text,source||' (individual not identified)');
 if TG_TABLE_NAME='fixtures' and TG_OP='UPDATE' then
   if b->>'archived_at' is distinct from a->>'archived_at' then event:=case when a->>'archived_at' is null then 'restored' else 'archived' end;
   elsif b->>'cancelled_at' is distinct from a->>'cancelled_at' and a->>'cancelled_at' is not null then event:='cancelled';
   elsif b->>'rescheduled_at' is distinct from a->>'rescheduled_at' or b->>'rescheduled_to_fixture_id' is distinct from a->>'rescheduled_to_fixture_id' or b->>'start_at' is distinct from a->>'start_at' or b->>'end_at' is distinct from a->>'end_at' then event:='rescheduled'; end if;
 end if;
 if TG_TABLE_NAME='team_selections' and (TG_OP='INSERT' or b->>'status' is distinct from a->>'status') then
   if a->>'status'='published' then event:='published'; elsif b->>'status'='published' then event:='publication withdrawn'; end if;
 end if;
 insert into public.audit_journal(actor_user_id,actor_name,origin,club_id,club_name,record_type,record_id,record_label,fixture_id,action,reason,before_values,after_values,outcome)
 values(actor,actor_label,source,cid,club_label,TG_TABLE_NAME,rid,label,fid,event,
 coalesce(nullif(current_setting('app.audit_reason',true),''),r->>'cancellation_reason'),b,a,
 case when r->>'status' in ('failed','error') then 'failed' else 'completed' end);
 if TG_OP='DELETE' then return old; end if; return new;
end $$;
revoke all on all functions in schema audit_private from public,anon,authenticated,service_role;

do $$ declare t text; fields text; begin
 for t,fields in select * from (values
 ('fixtures','id,club_id,team_id,team_name,start_at,end_at,venue_id,opponent_venue_id,opponent_name,is_home,section,rinks_required,players_per_rink,competition_type_id,captain_member_profile_id,vice_captain_member_profile_id,cancelled_at,cancellation_reason,rescheduled_at,rescheduled_to_fixture_id,rescheduled_from_fixture_id,archived_at,archive_reason'),
 ('teams','id,club_id,name,description,is_active,captain_member_profile_id,vice_captain_member_profile_id,manager_member_profile_id,section'),
 ('team_members','id,team_id,member_profile_id,is_active'),
 ('team_selections','id,fixture_id,status,published_at,captain_member_profile_id,vice_captain_member_profile_id'),
 ('team_selection_members','id,team_selection_id,member_profile_id,is_selected,role,acceptance'),
 ('fixture_rink_assignments','id,fixture_id,fixture_rink_id,member_profile_id,position,display_name'),
 ('club_memberships','id,club_id,member_profile_id,role,is_active,is_coach'),
 ('member_profiles','id,user_id,first_name,last_name,title,email_address,phone,gender,sex_at_birth,outdoor_club'),
 ('app_superusers','user_id'),
 ('clubs','id,name,primary_color_hex,secondary_color_hex'),
 ('club_schedule_items','id,club_id,title,item_type,start_at,end_at,status,linked_fixture_id'),
 ('member_invitation_attempts','id,club_id,membership_id,user_id,status,template_version'),
 ('email_queue','id,fixture_id,member_profile_id,event_type,status,sent_at'),
 ('feature_revision_policy','id,enabled_revision')
 ) x(t,fields) loop
 execute format('create trigger durable_audit before insert or update or delete on public.%I for each row execute function audit_private.capture(%L)',t,fields);
 end loop;
end $$;

-- All historical entries begin at deployment. Do not manufacture past actors.
alter table public.fixtures add column archived_at timestamptz;
alter table public.fixtures add column archive_reason text;

create function public.archive_fixture(p_fixture_id uuid,p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare f public.fixtures; begin
 if auth.uid() is null or not public.can_manage_fixture(p_fixture_id) then raise exception 'Not authorized'; end if;
 if length(trim(coalesce(p_reason,'')))<5 then raise exception 'Please give a reason (at least five characters)'; end if;
 select * into strict f from public.fixtures where id=p_fixture_id for update;
 if f.archived_at is not null then raise exception 'Already archived'; end if;
 perform set_config('app.audit_reason',trim(p_reason),true);
 -- Published/accepted fixtures must follow the existing cancellation workflow first.
 if f.cancelled_at is null and exists(select 1 from public.team_selections s where s.fixture_id=f.id and s.status::text='published') then
   raise exception 'Cancel this published fixture first so participants are informed';
 end if;
 if f.cancelled_at is null then
   raise exception 'Cancel this fixture first, then archive it. This preserves bookings and communication safeguards';
 end if;
 update public.fixtures set archived_at=clock_timestamp(),archive_reason=trim(p_reason) where id=f.id;
end $$;
create function public.restore_archived_fixture(p_fixture_id uuid,p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.app_superusers where user_id=auth.uid()) then raise exception 'Superuser access required'; end if;
 if length(trim(coalesce(p_reason,'')))<5 then raise exception 'Please give a reason'; end if;
 perform set_config('app.audit_reason',trim(p_reason),true);
 update public.fixtures set archived_at=null,archive_reason=null where id=p_fixture_id and archived_at is not null;
 if not found then raise exception 'Archived fixture not found'; end if;
 -- Deliberately remains cancelled: use normal reschedule to validate rink availability and notify players.
end $$;
create or replace function public.delete_fixture(p_fixture_id uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
begin raise exception 'Permanent deletion is disabled. Cancel and archive this fixture instead'; end $$;
create or replace function public.admin_force_delete_fixture(p_fixture_id uuid,p_confirm text default null)
returns table(item text,deleted_count integer) language plpgsql security definer set search_path = '' as $$
begin raise exception 'Permanent deletion is disabled. Cancel and archive this fixture instead'; end $$;
create function audit_private.guard_fixture_delete() returns trigger language plpgsql set search_path = '' as $$
begin
 if auth.uid() is not null or coalesce(auth.role(),'') in ('authenticated','anon','service_role') then raise exception 'Permanent deletion is disabled. Use cancel and archive'; end if;
 return old;
end $$;
create trigger prevent_app_fixture_delete before delete on public.fixtures for each row execute function audit_private.guard_fixture_delete();
revoke all on function public.archive_fixture(uuid,text),public.restore_archived_fixture(uuid,text) from public,anon;
grant execute on function public.archive_fixture(uuid,text),public.restore_archived_fixture(uuid,text) to authenticated;
revoke all on function audit_private.guard_fixture_delete() from public,anon,authenticated;

-- Archived rows are hidden from all ordinary Data API queries, including old apps.
create policy hide_archived_fixtures on public.fixtures as restrictive for select to authenticated
 using (archived_at is null);
create function public.list_archived_fixtures(p_club_id uuid) returns setof public.fixtures
language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.app_superusers where user_id=auth.uid()) then raise exception 'Superuser access required'; end if;
 return query select f.* from public.fixtures f where f.club_id=p_club_id and f.archived_at is not null order by f.archived_at desc;
end $$;
revoke all on function public.list_archived_fixtures(uuid) from public,anon;
grant execute on function public.list_archived_fixtures(uuid) to authenticated;
create function audit_private.guard_archived_fixture() returns trigger language plpgsql set search_path = '' as $$
begin
 if TG_OP='UPDATE' and old.cancelled_at is null and new.cancelled_at is not null and length(trim(coalesce(new.cancellation_reason,'')))<5 then raise exception 'A cancellation reason of at least five characters is required'; end if;
 if new.archived_at is not null and new.cancelled_at is null then raise exception 'Restore the archived fixture before rescheduling'; end if;
 if new.archived_at is not null and length(trim(coalesce(new.archive_reason,'')))<5 then raise exception 'An archive reason is required'; end if;
 return new;
end $$;
create trigger validate_archived_fixture before insert or update on public.fixtures for each row execute function audit_private.guard_archived_fixture();
revoke all on function audit_private.guard_archived_fixture() from public,anon,authenticated;

create function public.audit_filter_options() returns jsonb language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.app_superusers where user_id=auth.uid()) then raise exception 'Superuser access required'; end if;
 return jsonb_build_object(
 'actors',(select coalesce(jsonb_agg(x),'[]') from (select distinct actor_user_id,actor_name from public.audit_journal where actor_user_id is not null) x),
 'clubs',(select coalesce(jsonb_agg(x),'[]') from (select id,name from public.clubs order by name) x));
end $$;
revoke all on function public.audit_filter_options() from public,anon;
grant execute on function public.audit_filter_options() to authenticated;

create function public.record_audit_export(p_row_count integer) returns void
language plpgsql security definer set search_path = '' as $$
declare actor_label text; begin
 if auth.uid() is null or not exists(select 1 from public.app_superusers where user_id=auth.uid()) then raise exception 'Superuser access required'; end if;
 if p_row_count<0 then raise exception 'Invalid row count'; end if;
 select concat_ws(' ',p.first_name,p.last_name) into actor_label from public.member_profiles p where p.user_id=auth.uid() limit 1;
 insert into public.audit_journal(actor_user_id,actor_name,origin,record_type,record_label,action,after_values)
 values(auth.uid(),coalesce(actor_label,auth.uid()::text),'app','audit_journal','Audit CSV export','export requested',jsonb_build_object('row_count',p_row_count));
end $$;
revoke all on function public.record_audit_export(integer) from public,anon;
grant execute on function public.record_audit_export(integer) to authenticated;

create table audit_private.import_runs (
 id uuid primary key default gen_random_uuid(), actor uuid not null, club_id uuid not null,
 filename text not null, new_members_active boolean not null, started_at timestamptz not null default now(),
 finished_at timestamptz
);
create function public.audit_member_import(p_actor uuid,p_club uuid,p_filename text,p_active boolean,p_run uuid default null,p_summary jsonb default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare run_id uuid; actor_label text; club_label text; summary jsonb;
begin
 if not exists(select 1 from public.app_superusers where user_id=p_actor) and not exists(
   select 1 from public.club_memberships m join public.member_profiles p on p.id=m.member_profile_id
   where p.user_id=p_actor and m.club_id=p_club and m.is_active and m.role::text='admin'
 ) then raise exception 'Import administrator required'; end if;
 if p_run is null then
   insert into audit_private.import_runs(actor,club_id,filename,new_members_active)
   values(p_actor,p_club,left(p_filename,250),p_active) returning id into run_id;
 else
   update audit_private.import_runs set finished_at=now() where id=p_run and actor=p_actor and club_id=p_club and finished_at is null returning id into run_id;
   if run_id is null then raise exception 'Import audit run not found'; end if;
 end if;
 summary:=audit_private.pick(coalesce(p_summary,'{}'),array['created','linked','existing_memberships','errors','manual_review','total']);
 select concat_ws(' ',first_name,last_name) into actor_label from public.member_profiles where user_id=p_actor limit 1;
 select name into club_label from public.clubs where id=p_club;
 insert into public.audit_journal(actor_user_id,actor_name,origin,club_id,club_name,record_type,record_id,record_label,action,after_values,outcome)
 values(p_actor,coalesce(actor_label,p_actor::text),'import',p_club,club_label,'member_import',run_id::text,left(p_filename,250),
 case when p_run is null then 'started' else 'finished' end,
 summary||jsonb_build_object('new_members_active',p_active),case when p_run is null then 'started' when coalesce((summary->>'errors')::integer,0)>0 then 'completed with errors' else 'completed' end);
 return run_id;
end $$;
revoke all on function public.audit_member_import(uuid,uuid,text,boolean,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.audit_member_import(uuid,uuid,text,boolean,uuid,jsonb) to service_role;
