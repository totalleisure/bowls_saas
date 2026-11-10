-- Caller owns the transaction; all fixtures, emails and snapshots roll back.
do $$
declare f uuid:=gen_random_uuid(); replacement uuid:=gen_random_uuid(); q uuid; changed uuid; cancelled uuid;
 club uuid; venue uuid; green uuid; member uuid; version integer; previous_version integer; data jsonb; num integer;
begin
 select club_id,venue_id,green_area_id into strict club,venue,green from public.fixtures where venue_id is not null limit 1;
 green:=null;
 select id into strict member from public.member_profiles where email_address is not null limit 1;
 insert into public.fixtures(id,club_id,venue_id,green_area_id,start_at,end_at,is_home,fixture_type,section,rinks_required,players_per_rink)
 values(f,club,venue,green,'2042-01-01 10:00Z','2042-01-01 12:30Z',true,'friendly','open',1,1);
 insert into public.email_queue(member_profile_id,fixture_id,event_type,recipient_email,subject,body,status,sent_at,payload)
 values(member,f,'acceptance_reminder','calendar-test@example.invalid','Synthetic calendar test','Test','sent',now(),
 jsonb_build_object('action_block',jsonb_build_object('version',2))) returning id into q;
 set constraints queue_fixture_calendar immediate;
 -- Initial insertion was processed before the simulated email; clear its synthetic update.
 delete from public.email_queue where payload->>'calendar_root_id'=f::text;
 set constraints queue_fixture_calendar deferred;
 select revision into previous_version from calendar_private.fixture_events where fixture_id=f;
 update public.fixtures set notes='No calendar change' where id=f;
 set constraints queue_fixture_calendar immediate;
 if exists(select 1 from public.email_queue where payload->>'calendar_root_id'=f::text) then raise exception 'Unrelated update sent calendar';end if;
 set constraints queue_fixture_calendar deferred;
 update public.fixtures set start_at=start_at+interval '1 day',end_at=end_at+interval '1 day' where id=f;
 set constraints queue_fixture_calendar immediate;
 select id into strict changed from public.email_queue where event_type='fixture_calendar_updated' and payload->>'calendar_root_id'=f::text;
 data:=public.fixture_calendar_email_state(changed);
 if data->>'root_id'<>f::text or (data->>'revision')::integer<=previous_version or (data->>'stale')::boolean then raise exception 'In-place update state invalid';end if;
 set constraints queue_fixture_calendar deferred;
 update public.fixtures set cancelled_at=now() where id=f;
 -- A standard reschedule creates a replacement within the same transaction.
 insert into public.fixtures(id,club_id,venue_id,green_area_id,start_at,end_at,is_home,fixture_type,section,rinks_required,players_per_rink,rescheduled_from_fixture_id)
 values(replacement,club,venue,green,'2042-01-03 10:00Z','2042-01-03 12:30Z',true,'friendly','open',1,1,f);
 update public.fixtures set rescheduled_to_fixture_id=replacement where id=f;
 set constraints queue_fixture_calendar immediate;
 select count(*) into num from public.email_queue where status='pending' and payload->>'calendar_root_id'=f::text;
 if num<>1 then raise exception 'Reschedule should send one update, got %',num;end if;
 if not (public.fixture_calendar_email_state(changed)->>'stale')::boolean then raise exception 'Obsolete message not stale';end if;
 select id into strict changed from public.email_queue where status='pending' and payload->>'calendar_root_id'=f::text;
 data:=public.fixture_calendar_email_state(changed);
 if data->>'root_id'<>f::text or data->'fixture'->>'id'<>replacement::text or data->'fixture'->>'cancelled_at' is not null then raise exception 'Replacement identity invalid';end if;
 -- Historical predecessor cleanup must not cancel the active replacement.
 perform set_config('app.audit_delete_mode','ordinary',true);
 perform set_config('app.audit_reason','Synthetic rollback predecessor deletion',true);
 delete from public.fixtures where id=f;
 set constraints queue_fixture_calendar immediate;
 data:=public.fixture_calendar_email_state(changed);
 if data->'fixture'->>'cancelled_at' is not null then raise exception 'Predecessor deletion cancelled live event';end if;
 set constraints queue_fixture_calendar deferred;
 perform set_config('app.audit_delete_mode','ordinary',true);
 perform set_config('app.audit_reason','Synthetic rollback calendar deletion',true);
 delete from public.fixtures where id=replacement;
 set constraints queue_fixture_calendar immediate;
 select id into strict cancelled from public.email_queue where status='pending' and payload->>'calendar_root_id'=f::text;
 data:=public.fixture_calendar_email_state(cancelled);
 if data->'fixture'->>'cancelled_at' is null or data->>'root_id'<>f::text then raise exception 'Deleted cancellation lost identity';end if;
 if has_function_privilege('authenticated','public.fixture_calendar_email_state(uuid)','execute') or
 has_function_privilege('anon','public.fixture_calendar_email_state(uuid)','execute') then raise exception 'Calendar state publicly callable';end if;
 -- A fixture that never had a calendar email must not manufacture recipients.
 replacement:=gen_random_uuid();
 insert into public.fixtures(id,club_id,venue_id,green_area_id,start_at,end_at,is_home,fixture_type,section,rinks_required,players_per_rink)
 values(replacement,club,venue,green,'2042-02-01 10:00Z','2042-02-01 12:30Z',true,'friendly','open',1,1);
 update public.fixtures set cancelled_at=now() where id=replacement;
 set constraints queue_fixture_calendar immediate;
 if exists(select 1 from public.email_queue where payload->>'calendar_root_id'=replacement::text) then raise exception 'Unexpected recipient for never mailed fixture';end if;
end $$;
