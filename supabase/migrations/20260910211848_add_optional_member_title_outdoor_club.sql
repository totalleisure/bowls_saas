-- Review only: apply before the updated import function and Flutter application.
-- Neither field exists in the inspected public.member_profiles schema.
alter table public.member_profiles
  add column title text,
  add column outdoor_club text;

comment on column public.member_profiles.title is 'Optional member title. NULL means not supplied.';
comment on column public.member_profiles.outdoor_club is 'Optional outdoor club. NULL is valid, including members with no outdoor club.';

-- gender already permits NULL and has no default; retain its existing constraint.
