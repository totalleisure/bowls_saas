-- Keep calendar identity and cancellation snapshots after fixture deletion.
create schema if not exists calendar_private;
revoke all on schema calendar_private from public,anon,authenticated;
create sequence calendar_private.revision_sequence as integer;
create table calendar_private.fixture_events (
 fixture_id uuid primary key, root_id uuid not null, revision integer not null,
 snapshot jsonb not null, updated_at timestamptz not null default now()
);
create index fixture_events_root_idx on calendar_private.fixture_events(root_id,revision desc);
alter table calendar_private.fixture_events enable row level security;
revoke all on calendar_private.fixture_events from public,anon,authenticated;

create function calendar_private.fixture_snapshot(p_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',f.id,'start_at',f.start_at,'end_at',f.end_at,
 'is_home',f.is_home,'cancelled_at',f.cancelled_at,'fixture_type',f.fixture_type,
 'opponent_name',f.opponent_name,'club',jsonb_build_object('name',c.name),
 'competition_type',jsonb_build_object('name',t.name),
 'venue',jsonb_build_object('name',v.name,'address_line1',v.address_line1,
 'address_line2',v.address_line2,'town_city',v.town_city,'postcode',v.postcode),
 'opponent_venue',jsonb_build_object('name',o.name,'address_line1',o.address_line1,
 'address_line2',o.address_line2,'town_city',o.town_city,'postcode',o.postcode))
 from public.fixtures f join public.clubs c on c.id=f.club_id
 left join public.competition_types t on t.id=f.competition_type_id
 left join public.venues v on v.id=f.venue_id
 left join public.venues o on o.id=f.opponent_venue_id where f.id=p_id;
$$;

-- Backfill identity only. No historical emails are dispatched.
with recursive ancestry as (
 select id as fixture_id,id as ancestor,rescheduled_from_fixture_id as parent,array[id] as path
 from public.fixtures
 union all
 select a.fixture_id,f.id,f.rescheduled_from_fixture_id,a.path||f.id
 from ancestry a join public.fixtures f on f.id=a.parent where not f.id=any(a.path)
), roots as (select distinct on(fixture_id) fixture_id,ancestor from ancestry
 order by fixture_id,cardinality(path) desc)
insert into calendar_private.fixture_events(fixture_id,root_id,revision,snapshot)
select f.id,r.ancestor,nextval('calendar_private.revision_sequence'),calendar_private.fixture_snapshot(f.id)
from public.fixtures f join roots r on r.fixture_id=f.id
order by f.created_at,f.id;

create function calendar_private.capture_fixture_event() returns trigger
language plpgsql security definer set search_path='' as $$
declare root uuid; data jsonb;
begin
 if tg_op='DELETE' then
  update public.email_queue set payload=payload||jsonb_build_object('calendar_fixture_id',old.id)
    where fixture_id=old.id and sent_at is not null and
    (payload ? 'action_block' or event_type in ('fixture_calendar_updated','fixture_calendar_cancelled'));
  -- Deleting an archived predecessor must not cancel its live replacement.
  if exists(select 1 from calendar_private.fixture_events e
    join calendar_private.fixture_events current_event on current_event.root_id=e.root_id
    where e.fixture_id=old.id and current_event.revision>e.revision) then return old;end if;
  update calendar_private.fixture_events set revision=nextval('calendar_private.revision_sequence'),
    snapshot=jsonb_set(snapshot,'{cancelled_at}',to_jsonb(now())),updated_at=now()
    where fixture_id=old.id;
  return old;
 end if;
 if tg_op='UPDATE' and row(new.start_at,new.end_at,new.venue_id,new.opponent_venue_id,
   new.is_home,new.cancelled_at,new.opponent_name,new.competition_type_id,new.green_area_id)
   is not distinct from row(old.start_at,old.end_at,old.venue_id,old.opponent_venue_id,
   old.is_home,old.cancelled_at,old.opponent_name,old.competition_type_id,old.green_area_id) then return new; end if;
 select root_id into root from calendar_private.fixture_events where fixture_id=new.id;
 if root is null and new.rescheduled_from_fixture_id is not null then
  select root_id into root from calendar_private.fixture_events where fixture_id=new.rescheduled_from_fixture_id;
 end if;
 data:=calendar_private.fixture_snapshot(new.id);
 insert into calendar_private.fixture_events(fixture_id,root_id,revision,snapshot)
 values(new.id,coalesce(root,new.id),nextval('calendar_private.revision_sequence'),data)
 on conflict(fixture_id) do update set revision=excluded.revision,snapshot=excluded.snapshot,updated_at=now();
 return new;
end $$;
create trigger capture_fixture_calendar after insert or update on public.fixtures
for each row execute function calendar_private.capture_fixture_event();
create trigger capture_deleted_fixture_calendar before delete on public.fixtures
for each row execute function calendar_private.capture_fixture_event();

create unique index email_queue_calendar_revision_idx on public.email_queue
 ((payload->>'calendar_root_id'),(payload->>'calendar_revision'),recipient_email)
 where event_type in ('fixture_calendar_updated','fixture_calendar_cancelled');

create function calendar_private.queue_fixture_event() returns trigger
language plpgsql security definer set search_path='' as $$
declare state calendar_private.fixture_events%rowtype; latest calendar_private.fixture_events%rowtype;
 fid uuid; kind text;
begin
 if tg_op='UPDATE' and row(new.start_at,new.end_at,new.venue_id,new.opponent_venue_id,
   new.is_home,new.cancelled_at,new.opponent_name,new.competition_type_id,new.green_area_id)
   is not distinct from row(old.start_at,old.end_at,old.venue_id,old.opponent_venue_id,
   old.is_home,old.cancelled_at,old.opponent_name,old.competition_type_id,old.green_area_id) then return null; end if;
 fid:=case when tg_op='DELETE' then old.id else new.id end;
 select * into state from calendar_private.fixture_events where fixture_id=fid;
 if not found then return null; end if;
 select * into latest from calendar_private.fixture_events where root_id=state.root_id order by revision desc limit 1;
 if latest.fixture_id<>fid then return null; end if;
 kind:=case when latest.snapshot->>'cancelled_at' is not null then 'fixture_calendar_cancelled' else 'fixture_calendar_updated' end;
 -- Cancel obsolete unsent calendar messages; ordinary fixture notifications are unchanged.
 update public.email_queue set status='cancelled' where event_type in ('fixture_calendar_updated','fixture_calendar_cancelled')
 and payload->>'calendar_root_id'=state.root_id::text
 and payload->>'calendar_revision'<>latest.revision::text and status in ('pending','failed') and sent_at is null;
 insert into public.email_queue(member_profile_id,event_type,recipient_email,subject,body,fixture_id,payload)
 select distinct q.member_profile_id,kind,coalesce(nullif(trim(m.email_address),''),q.recipient_email),
 case when kind='fixture_calendar_cancelled' then 'Fixture cancelled - calendar update' else 'Fixture changed - calendar update' end,
 case when kind='fixture_calendar_cancelled' then 'This fixture has been cancelled. Open the attached cancellation to update your calendar. If you never added the event, there is nothing to remove.'
 else 'This fixture has changed. Open the attached calendar update to apply its latest details. If you never added the event, you can add it now. Check the Bowls App for any acceptance required.' end,
 (select id from public.fixtures where id=fid),
 jsonb_build_object('calendar_fixture_id',fid,'calendar_root_id',state.root_id,'calendar_revision',latest.revision)
 from public.email_queue q left join public.member_profiles m on m.id=q.member_profile_id
 where q.sent_at is not null and q.status='sent' and
 (q.payload ? 'action_block' or q.event_type in ('fixture_calendar_updated','fixture_calendar_cancelled'))
 and exists(select 1 from calendar_private.fixture_events e where e.root_id=state.root_id
   and (e.fixture_id=q.fixture_id or e.fixture_id::text=q.payload->>'deleted_fixture_id' or e.fixture_id::text=q.payload->>'calendar_fixture_id'))
 on conflict do nothing;
 return null;
end $$;
-- Deferred until replacement fixtures and deletion cleanup have completed.
create constraint trigger queue_fixture_calendar after insert or update or delete on public.fixtures
deferrable initially deferred for each row execute function calendar_private.queue_fixture_event();

create function public.fixture_calendar_email_state(p_email_queue_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare q public.email_queue%rowtype; state calendar_private.fixture_events%rowtype; latest calendar_private.fixture_events%rowtype;
begin
 select * into q from public.email_queue where id=p_email_queue_id;
 if not found then return null; end if;
 select * into state from calendar_private.fixture_events where fixture_id=coalesce(q.fixture_id,
   nullif(q.payload->>'calendar_fixture_id','')::uuid,nullif(q.payload->>'deleted_fixture_id','')::uuid);
 if not found then return null; end if;
 select * into latest from calendar_private.fixture_events where root_id=state.root_id order by revision desc limit 1;
 return jsonb_build_object('fixture',latest.snapshot,'root_id',latest.root_id,'revision',latest.revision,
  'stale',q.event_type in ('fixture_calendar_updated','fixture_calendar_cancelled') and
    q.payload->>'calendar_revision' is distinct from latest.revision::text,
  'has_prior_calendar',exists(select 1 from public.email_queue h where h.sent_at is not null and
    h.status='sent' and h.member_profile_id=q.member_profile_id and h.payload ? 'action_block'
    and exists(select 1 from calendar_private.fixture_events e where e.root_id=state.root_id
      and (e.fixture_id=h.fixture_id or e.fixture_id::text=h.payload->>'deleted_fixture_id'))));
end $$;
revoke all on all functions in schema calendar_private from public,anon,authenticated;
revoke all on function public.fixture_calendar_email_state(uuid) from public,anon,authenticated;
grant execute on function public.fixture_calendar_email_state(uuid) to service_role;
notify pgrst,'reload schema';
