-- Staging-only preview/test delivery audit. No queue triggers or automatic sends.
create table public.competition_publication_previews (
 id uuid primary key default gen_random_uuid(), club_id uuid not null references public.clubs(id),
 actor_user_id uuid not null references auth.users(id), represented_member_id uuid not null references public.member_profiles(id),
 subject text not null, html text not null, content jsonb not null, created_at timestamptz not null default now(),
 expires_at timestamptz not null default now()+interval '30 minutes'
);
create table public.competition_publication_test_deliveries (
 id uuid primary key default gen_random_uuid(), preview_id uuid not null references public.competition_publication_previews(id),
 recipient text not null check(recipient in ('wayne@totalleisure.com','wayne.s.sayers@gmail.com','wayne.streem@gmail.com','wayne.sayers@telius.co.uk','wayne.sayers@icloud.com','wayne.sayers@me.com','suesayers9@gmail.com')),
 status text not null default 'claimed' check(status in ('claimed','sent','uncertain')), actor_user_id uuid not null references auth.users(id),
 created_at timestamptz not null default now(), unique(preview_id,recipient)
);
alter table public.competition_publication_previews enable row level security;
alter table public.competition_publication_test_deliveries enable row level security;
revoke all on public.competition_publication_previews,public.competition_publication_test_deliveries from public,anon,authenticated;
grant all on public.competition_publication_previews,public.competition_publication_test_deliveries to service_role;
