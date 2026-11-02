begin;
do $$
declare c uuid:='f6d357b6-7d72-4639-9064-b9df52ea7738';
begin
 perform set_config('request.jwt.claim.sub','34fc64d9-b1e3-4be7-b09b-439bd999772e',true);
 update public.competition_release_controls set publication_enabled=false where id;
 if public.competition_release_status('8ae87bbe-cb16-4330-a5b0-e62366479f07') then raise exception 'Gate not closed';end if;
 begin perform competition_private.prepare_publication(c,auth.uid());raise exception 'Publication allowed';exception when raise_exception then if sqlerrm<>'Competition publication and emails are disabled while production records are checked' then raise;end if;end;
 if exists(select 1 from public.claim_competition_round_ready_deliveries()) or exists(select 1 from public.claim_competition_deadline_deliveries()) then raise exception 'Delivery claims allowed';end if;
end $$;
rollback;
select 'PASS: disabled gate blocks publication and email claims; staging setting restored' as result;
