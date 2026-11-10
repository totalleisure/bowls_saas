-- Narrow audited write for the same operational users permitted by the App.
-- Do not broaden table-level RLS or permit changes to timing, captaincy or teams.
create function public.save_fixture_label_safe(
 p_fixture_id uuid, p_label text, p_expected_label text, p_dress_code text[] default null
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare f public.fixtures;
begin
 if auth.uid() is null then raise exception 'Sign in required' using errcode='42501';end if;
 select * into f from public.fixtures where id=p_fixture_id for update;
 if not found then raise exception 'Fixture not found';end if;
 if not (public.can_manage_fixture(f.id) or public.is_active_fixture_creator(f.id)) then
  raise exception 'You do not have permission to save this fixture label' using errcode='42501';
 end if;
 if f.cancelled_at is not null or f.archived_at is not null then raise exception 'Cancelled or archived fixtures cannot be edited';end if;
 if f.team_id is not null then raise exception 'Use the team selection to change a team fixture name';end if;
 if coalesce(f.team_name,'') is distinct from coalesce(p_expected_label,'') then
  raise exception 'The fixture label has changed. Refresh before saving again';end if;
 if length(coalesce(p_label,''))>500 then raise exception 'Fixture label must be 500 characters or fewer';end if;
 if p_dress_code is not null and exists(select 1 from unnest(p_dress_code) code where code is null or code not in ('whites','greys','blacks','jackets')) then
  raise exception 'Invalid dress code';end if;
 update public.fixtures set team_name=nullif(btrim(p_label),''),
  dress_code=coalesce(p_dress_code::public.dress_code[],dress_code) where id=f.id
  returning * into f;
 return jsonb_build_object('id',f.id,'team_name',f.team_name,'dress_code',f.dress_code);
end $$;
revoke all on function public.save_fixture_label_safe(uuid,text,text,text[]) from public,anon;
grant execute on function public.save_fixture_label_safe(uuid,text,text,text[]) to authenticated;
notify pgrst,'reload schema';
