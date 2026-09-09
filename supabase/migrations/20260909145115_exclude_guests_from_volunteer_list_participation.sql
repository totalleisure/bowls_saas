create or replace function public.set_my_mailing_list_membership(
  p_mailing_list_id uuid,
  p_join boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_member_profile_id uuid;
  v_club_id uuid;
  v_list_name text;
  v_is_active boolean;
  v_allow_self_subscription boolean;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  select public.my_member_profile_id()
  into v_member_profile_id;

  if v_member_profile_id is null then
    raise exception 'No member profile was found for the signed-in user.';
  end if;

  select
    ml.club_id,
    ml.name,
    ml.is_active,
    ml.allow_self_subscription
  into
    v_club_id,
    v_list_name,
    v_is_active,
    v_allow_self_subscription
  from public.mailing_lists ml
  where ml.id = p_mailing_list_id;

  if not found then
    raise exception 'Mailing list not found.';
  end if;

  if not v_is_active then
    raise exception 'This mailing list is inactive.';
  end if;

  if not v_allow_self_subscription then
    raise exception 'This mailing list is managed by the club administrator.';
  end if;

  if not exists (
    select 1
    from public.club_memberships cm
    where cm.club_id = v_club_id
      and cm.member_profile_id = v_member_profile_id
      and cm.is_active = true
      and lower(cm.role::text) <> 'guest'
  ) then
    raise exception 'You are not eligible to join mailing or volunteer lists.';
  end if;

  if coalesce(p_join, false) then
    insert into public.mailing_list_members (
      mailing_list_id,
      member_profile_id,
      is_active,
      added_by_member_profile_id,
      added_at,
      removed_at
    )
    values (
      p_mailing_list_id,
      v_member_profile_id,
      true,
      v_member_profile_id,
      now(),
      null
    )
    on conflict (mailing_list_id, member_profile_id)
    do update set
      is_active = true,
      added_by_member_profile_id = excluded.added_by_member_profile_id,
      added_at = now(),
      removed_at = null;
  else
    delete from public.mailing_list_members mlm
    where mlm.mailing_list_id = p_mailing_list_id
      and mlm.member_profile_id = v_member_profile_id;
  end if;

  return jsonb_build_object(
    'mailing_list_id', p_mailing_list_id,
    'mailing_list_name', v_list_name,
    'member_profile_id', v_member_profile_id,
    'is_joined', coalesce(p_join, false)
  );
end;
$function$;
