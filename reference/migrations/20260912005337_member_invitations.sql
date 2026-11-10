-- Invitations are accessed only through the authenticated, club-authorized Edge Function.
create table public.member_invitation_guides (
  club_id uuid not null references public.clubs(id) on delete cascade,
  kind text not null check (kind in ('introduction', 'android')),
  name text not null,
  path text not null,
  updated_at timestamptz not null default now(),
  primary key (club_id, kind)
);

create table public.member_invitation_attempts (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  membership_id uuid not null references public.club_memberships(id) on delete cascade,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  email text not null,
  user_id uuid references auth.users(id) on delete set null,
  first_name text not null,
  subject text not null,
  html text not null,
  preview jsonb not null,
  guides jsonb not null,
  previous_sent_id uuid,
  status text not null default 'pending' check
    (status in ('pending','sending','sent','failed','unknown','superseded'))
);
create index member_invitation_attempts_club on public.member_invitation_attempts(club_id);
create index member_invitation_attempts_membership on public.member_invitation_attempts(membership_id);
-- Protect against concurrent administrators, double clicks and overlapping CSVs.
create unique index member_invitation_one_live_attempt
  on public.member_invitation_attempts(membership_id)
  where status in ('sending','sent','unknown');

alter table public.member_invitation_guides enable row level security;
alter table public.member_invitation_attempts enable row level security;
revoke all on public.member_invitation_guides, public.member_invitation_attempts from public, anon, authenticated;
grant all on public.member_invitation_guides, public.member_invitation_attempts to service_role;

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('MemberInvitationGuides','MemberInvitationGuides',false,1500000,array['application/pdf']);
-- No client storage policies: the function checks club admin access and uploads
-- immutable versioned files. Old versions remain available to pending reviews.

create function public.claim_member_invitation(p_id uuid, p_club uuid, p_caller uuid)
returns boolean language plpgsql security invoker set search_path = '' as $$
declare
  attempt public.member_invitation_attempts;
  previous_id uuid;
  previous_status text;
begin
  select * into attempt from public.member_invitation_attempts
    where id=p_id and club_id=p_club and created_by=p_caller for update;
  if not found or attempt.status <> 'pending' or attempt.created_at < now()-interval '24 hours' then
    return false;
  end if;
  -- Serialize all attempts for the same membership using its existing row.
  perform 1 from public.club_memberships
    where id=attempt.membership_id and club_id=p_club and is_active=true for update;
  if not found then return false; end if;
  select id,status into previous_id,previous_status
    from public.member_invitation_attempts where membership_id=attempt.membership_id
    and status in ('sending','sent','unknown');
  if previous_id is not null then
    if previous_status <> 'sent' or previous_id is distinct from attempt.previous_sent_id then
      return false;
    end if;
    update public.member_invitation_attempts set status='superseded',updated_at=now() where id=previous_id;
  elsif attempt.previous_sent_id is not null then
    return false;
  end if;
  update public.member_invitation_attempts set status='sending',updated_at=now() where id=p_id;
  return true;
end;
$$;
revoke all on function public.claim_member_invitation(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.claim_member_invitation(uuid,uuid,uuid) to service_role;
