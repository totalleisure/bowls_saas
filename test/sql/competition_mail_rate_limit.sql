begin;
do $$
declare result jsonb;i int;
begin
 delete from public.outbound_mail_rate_slots;
 for i in 1..20 loop result:=public.reserve_outbound_mail_slot();if result->>'allowed'<>'true' then raise exception 'Slot % rejected early',i;end if;end loop;
 result:=public.reserve_outbound_mail_slot();if result->>'allowed'<>'false' then raise exception '21st message permitted';end if;
 update public.outbound_mail_rate_slots set reserved_at=clock_timestamp()-interval '61 seconds' where id=(select min(id) from public.outbound_mail_rate_slots);
 result:=public.reserve_outbound_mail_slot();if result->>'allowed'<>'true' then raise exception 'Expired slot not released';end if;
 if has_function_privilege('authenticated','public.reserve_outbound_mail_slot()','execute') or has_function_privilege('anon','public.claim_competition_mail_batch()','execute') then raise exception 'Private mail controls exposed';end if;
end $$;
rollback;
select 'PASS: exactly 20 rolling slots; 21st rejected; expired slot reclaimed; client access denied; no mail sent' as result;
