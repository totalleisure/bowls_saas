# Published competition: add an omitted entry

Developed in staging for David Singer using existing Club Admin access. Open the affected main-draw match (Ladies Pairs: Quarter-final 4), choose **Add preliminary match**, select the existing entry as challengers, select exactly one omitted entry in the member picker, then review and confirm. Existing entrants are excluded by the picker and checked again server-side. No direct database editing is required by the administrator.

This revision converts an existing opening-round bye into a playable preliminary, retaining its ID, match number, source link, date and rule overrides. It does not rebuild the bracket, renumber matches or add a whole round. The target match keeps its other side and replaces the moved entry with the preliminary winner. A confirmed result uses existing winner progression. The existing entry is side A and is explicitly marked as challenger.

The server serializes on the competition, verifies Club Admin access and the reviewed source link, and refuses duplicate entrants, booked target matches and pending/confirmed results. A reason and immutable before/after audit are stored. The operation is atomic; retrying a successful amendment is rejected because the source is no longer a bye.

Amendment email snapshots cover both preliminary pairs and the waiting main-draw pair. The latter is told to await an opponent. Only this affected part of the competition is included. A new amendment queue shares the existing batch control and global mail transport throttle: at most 20 competition messages per minute, with existing retry/uncertain handling. Staging recipient restrictions remain in place. No email is sent merely by opening the review screen.

Validation: rollback-only staging SQL tests cover access denial, existing-player duplication, pending-result rejection, preservation of every other match, audit and winner progression. Flutter tests cover Admin-only navigation, required selections and eligibility. Node tests cover both preliminary and waiting recipients, environment restrictions and existing throttling/round-ready behavior. Staging Windows release build succeeded. The new screen analyzes cleanly.

Deployment completed after explicit user approval:

- Staging database and `competition-round-ready` worker deployed; staging Windows build prepared.
- No actual competition amended; tests rolled back, including queued mail. Production Ladies Pairs remains published and staging remains a draft.
- Production database migration and competition-round-ready worker version 3 deployed after explicit user approval. Live amendment and batch definitions match staging (normalized MD5: 888e4d9865336d0d17370c03bc4f3b1d and 4e3413475fa31e88098508be28a11f60). Migration history records staging version 20261110174019 and production orchestration version 20261110175200; applied history was not rewritten.
- Reviewed source and focused tests promoted to production. Compare-AppSources.ps1 passes; nine Flutter and nine Node tests pass. Synthetic database transactions pass in both projects and roll back all rows and queued deliveries. No commit, push, version bump or store/TestFlight submission performed. Current source version is 1.6.6+32.

Recovery: `scripts/recovery_competition_amendment.sql` disables new calls and restores the prior batch function without deleting saved draws/audits. A worker/source rollback must be coordinated with any already queued amendment deliveries.

Final production verification: Ladies Pairs still has 10 entries; draw fingerprint excluding the newly added nullable column remains 6b6750419952ccb397e1e6b096ff4cfa, identical to before deployment. Amendment events=0, amendment deliveries=0, synthetic competitions=0. The actual amendment is expressly left for the user to test using their Admin account.

Security review: anonymous execution is revoked. Two expected advisory additions were inspected: the service-only delivery outbox has RLS with no client policy, and the authenticated SECURITY DEFINER RPC performs an explicit Club Admin check. These are intentional access patterns; no new anonymous exposure was introduced. Existing unrelated advisories remain.

Production Windows Release build succeeded at C:/src/bowls_saas/build/windows/x64/runner/Release/bowls_saas.exe. Restart this updated build to access the Admin control. Mobile/TestFlight installations need a newly packaged App; this deployment does not update installed binaries.
