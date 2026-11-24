-- Imported club members remain Members, regardless of pre-existing Auth accounts.
do $patch$
declare f text; old_link text := 'case when exists(select 1 from public.club_memberships where member_profile_id=p and club_id<>p_club) then ''guest''::public.club_role else ''member''::public.club_role end'; old_finish text;
begin
 select pg_get_functiondef('club_setup_private.link_existing_members(uuid)'::regprocedure) into f;
 if position(old_link in f)=0 then raise exception 'Unreviewed member-link definition'; end if;
 execute replace(f,old_link,'''member''::public.club_role');
 select pg_get_functiondef('club_setup_private.finish_invitation_contact(uuid,uuid,uuid)'::regprocedure) into f;
 old_finish:=substring(f from 'target_role:=case when exists[\s\S]*?then ''guest''::public.club_role else ''member''::public.club_role end;');
 if old_finish is null then raise exception 'Unreviewed invitation provisioning definition'; end if;
 execute replace(f,old_finish,'target_role:=''member''::public.club_role;');
end $patch$;
-- Change only the role of imported contacts. Acceptance and other clubs stay intact.
update public.club_memberships cm set role='member'
where cm.role='guest'
 and exists(select 1 from public.club_onboarding_pending_members x where x.club_id=cm.club_id and x.member_profile_id=cm.member_profile_id)
 and exists(select 1 from club_setup_private.requests r where r.club_id=cm.club_id);


