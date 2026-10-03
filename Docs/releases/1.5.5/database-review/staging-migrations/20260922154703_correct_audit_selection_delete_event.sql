-- Preserve a DELETE action when removing a published selection.
create or replace function audit_private.capture() returns trigger language plpgsql security definer
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
 if TG_TABLE_NAME='team_selections' and TG_OP in ('INSERT','UPDATE') and (TG_OP='INSERT' or b->>'status' is distinct from a->>'status') then
   if a->>'status'='published' then event:='published'; elsif b->>'status'='published' then event:='publication withdrawn'; end if;
 end if;
 insert into public.audit_journal(actor_user_id,actor_name,origin,club_id,club_name,record_type,record_id,record_label,fixture_id,action,reason,before_values,after_values,outcome)
 values(actor,actor_label,source,cid,club_label,TG_TABLE_NAME,rid,label,fid,event,
 coalesce(nullif(current_setting('app.audit_reason',true),''),r->>'cancellation_reason'),b,a,
 case when r->>'status' in ('failed','error') then 'failed' else 'completed' end);
 if TG_OP='DELETE' then return old; end if; return new;
end $$;
