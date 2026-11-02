begin;
create table public.outbound_mail_rate_slots(id bigint generated always as identity primary key,reserved_at timestamptz not null default clock_timestamp());
create index outbound_mail_rate_slots_time on public.outbound_mail_rate_slots(reserved_at);
alter table public.outbound_mail_rate_slots enable row level security;
revoke all on public.outbound_mail_rate_slots from public,anon,authenticated;
create function public.reserve_outbound_mail_slot() returns jsonb language plpgsql security definer set search_path='' as $$
declare earliest timestamptz;n int;t timestamptz;
begin
 perform pg_advisory_xact_lock(742091163);
 t:=clock_timestamp();
 delete from public.outbound_mail_rate_slots where reserved_at<=t-interval '60 seconds';
 select count(*),min(reserved_at) into n,earliest from public.outbound_mail_rate_slots;
 if n>=20 then return jsonb_build_object('allowed',false,'retry_after_seconds',greatest(1,ceil(extract(epoch from earliest+interval '60 seconds'-t))::int));end if;
 insert into public.outbound_mail_rate_slots(reserved_at) values(t);
 return jsonb_build_object('allowed',true);
end $$;
revoke all on function public.reserve_outbound_mail_slot() from public,anon,authenticated;
grant execute on function public.reserve_outbound_mail_slot() to service_role;
create table public.competition_mail_batch_control(id boolean primary key default true check(id),next_batch_at timestamptz not null default '-infinity');
insert into public.competition_mail_batch_control(id) values(true);
alter table public.competition_mail_batch_control enable row level security;
revoke all on public.competition_mail_batch_control from public,anon,authenticated;
alter table public.competition_publication_deliveries add column attempt_count int not null default 0,add column next_attempt_at timestamptz not null default now(),add column last_error text;
alter table public.competition_round_ready_deliveries add column attempt_count int not null default 0,add column next_attempt_at timestamptz not null default now(),add column last_error text;
alter table public.competition_deadline_deliveries add column attempt_count int not null default 0,add column next_attempt_at timestamptz not null default now(),add column last_error text;
create function public.claim_competition_mail_batch() returns jsonb language plpgsql security definer set search_path='' as $$
declare r record;item jsonb;items jsonb:='[]';next_time timestamptz;
begin
 if not competition_private.publication_enabled() then return items;end if;
 select next_batch_at into strict next_time from public.competition_mail_batch_control where id for update;
 if next_time>clock_timestamp() then return items;end if;
 for r in select * from (
  select 'publication' as kind,d.id,e.created_at from public.competition_publication_deliveries d join public.competition_publication_events e on e.id=d.event_id where d.status='pending' and d.next_attempt_at<=now()
  union all select 'round_ready',d.id,e.created_at from public.competition_round_ready_deliveries d join public.competition_round_ready_events e on e.id=d.event_id where d.status='pending' and d.next_attempt_at<=now()
  union all select 'deadline',d.id,e.created_at from public.competition_deadline_deliveries d join public.competition_deadline_events e on e.id=d.event_id where d.status='pending' and d.next_attempt_at<=now()
 ) candidates order by created_at,id limit 20 loop
  item:=null;
  if r.kind='publication' then
   update public.competition_publication_deliveries d set status='claimed',claimed_at=clock_timestamp(),attempt_count=attempt_count+1,claimed_by=(select actor_user_id from public.competition_publication_events e where e.id=d.event_id) where d.id=r.id and d.status='pending' returning to_jsonb(d) into item;
  elsif r.kind='round_ready' then
   update public.competition_round_ready_deliveries d set status='claimed',claimed_at=clock_timestamp(),attempt_count=attempt_count+1 where d.id=r.id and d.status='pending' returning to_jsonb(d) into item;
  else
   update public.competition_deadline_deliveries d set status='claimed',claimed_at=clock_timestamp(),attempt_count=attempt_count+1 where d.id=r.id and d.status='pending' returning to_jsonb(d) into item;
  end if;
  if item is not null then items:=items||jsonb_build_array(jsonb_build_object('kind',r.kind,'delivery',item));end if;
 end loop;
 if jsonb_array_length(items)>0 then update public.competition_mail_batch_control set next_batch_at=clock_timestamp()+interval '60 seconds' where id;end if;
 return items;
end $$;
revoke all on function public.claim_competition_mail_batch() from public,anon,authenticated;
grant execute on function public.claim_competition_mail_batch() to service_role;
commit;
