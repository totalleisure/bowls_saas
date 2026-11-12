# Admin booking on behalf of competition entrants

From Club competitions, open a published, playable draw match and select **Arrange fixture for these players** beneath its participant card. This opens the existing competition arrangement screen, including copied entrants/rules, date/time, rink availability and final confirmation. No rink availability query runs before a date/time is chosen. Returning reloads the draw record, so a completed booking removes the create action.

The action is restricted to Club Admins and unarranged matches with both entries confirmed. It is hidden for drafts, byes, unresolved opponents, pending/completed results and an existing fixture. Player Dashboard/My Fixtures routes are unchanged.

No database/schema or Edge Function amendment is required. Live `arrange_competition_match` definitions match across staging and production, normalized MD5 `6d21317864bbd4a6a59a79f721e1fd17`. The existing procedure permits a non-playing Admin to book, preserves all drawn entrants, records the Admin as captain/organiser and returns the existing fixture on retry. It does not add that Admin to player positions.

Validation: 19 focused Flutter tests pass in staging, covering Admin navigation, excluded states, refresh after return, existing rink selection/booking conflicts, results and preliminary amendments. A synthetic non-playing Admin booking test passes in both live databases inside a rolled-back transaction; it checks organiser identity, four entrants, retry idempotency and no email/notification queue additions. All synthetic users, memberships, fixture and draw records roll back. No real competition booking was made.

Source promotion and Windows build status are recorded below after verification. No commit, version bump or store/TestFlight submission is part of this amendment.

Final status: reviewed source matches across both environments (Compare-AppSources.ps1 passes). All 19 focused Flutter tests pass against each source tree. Staging and production Windows Release builds succeeded. No database or Edge Function definitions were changed, no real booking was created and no member messages were sent. Production executable: C:/src/bowls_saas/build/windows/x64/runner/Release/bowls_saas.exe. Store/mobile packages remain unchanged.
