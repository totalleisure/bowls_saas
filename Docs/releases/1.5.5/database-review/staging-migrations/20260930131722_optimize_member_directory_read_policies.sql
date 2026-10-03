-- Member directory: calculate caller identity and permitted profile sets once per statement.
-- Applied directly to staging egxdkaotepgfjmszxlyn on 2026-09-30; production not applied.
-- Existing authenticated active-club membership policy retains admin membership access.
-- Existing SELECT policy unions retain self, active same-club, and club-admin profile access.
-- No INSERT/UPDATE/DELETE policies, grants, helpers, indexes or Flutter code changed.
-- Validated: 13 before/after visibility scenarios and 168 capacity measurements (601-6000 members).
-- Rollback evidence: outputs/capacity-tests/membership-policy-rollback.sql in the Codex task workspace.

-- Removed OR branches are already covered by the other authenticated SELECT policies.
-- Equivalent SELECT policy predicates; no write policies or grants changed.
ALTER POLICY "club_memberships select self or admin" ON public.club_memberships
 USING (member_profile_id = (SELECT public.my_member_profile_id()));
ALTER POLICY "memberships visible to self" ON public.club_memberships
 USING (member_profile_id = (SELECT public.my_member_profile_id()));
ALTER POLICY "club members can read profiles in their club" ON public.member_profiles
 USING (id IN (SELECT cm.member_profile_id FROM public.club_memberships cm
 WHERE cm.is_active AND cm.club_id IN (SELECT public.my_active_club_ids())));
ALTER POLICY "member_profiles select (self or same club)" ON public.member_profiles
 USING (user_id = (SELECT auth.uid()));
ALTER POLICY "member_profiles select self or club admin" ON public.member_profiles
 USING (id = (SELECT public.my_member_profile_id()) OR id IN (
 SELECT cm.member_profile_id FROM public.club_memberships cm
 WHERE cm.club_id IN (SELECT mine.club_id FROM public.club_memberships mine
 WHERE mine.member_profile_id = (SELECT public.my_member_profile_id())
 AND mine.is_active AND mine.role = 'admin')));
ALTER POLICY "read own profile" ON public.member_profiles
 USING (user_id = (SELECT auth.uid()));
