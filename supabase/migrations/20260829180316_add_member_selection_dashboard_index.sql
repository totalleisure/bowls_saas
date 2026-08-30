-- Speeds up the member dashboard's pending and accepted selection lookups.
create index if not exists idx_team_selection_members_member_selected_acceptance
on public.team_selection_members (member_profile_id, is_selected, acceptance);
