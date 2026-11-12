-- Disable new amendments; keep existing draw records and audit history.
revoke execute on function public.add_competition_preliminary(uuid,uuid,uuid[],uuid,date,text) from authenticated;
CREATE OR REPLACE FUNCTION public.claim_competition_mail_batch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end $function$;
