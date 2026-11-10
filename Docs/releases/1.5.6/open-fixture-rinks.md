# Open fixture rink requirements — 5 October 2026

Adds an Edit control above the rink availability panel for authorised Open-fixture managers. The dialog changes reserved capacity. Long-press Unassign continues to release a physical rink without changing capacity. To reduce below the assigned count, unassign a rink first.

The RPC removes only empty, unassigned fixture_rinks rows, preserving the IDs and physical labels of all remaining rows. Increases create new unassigned rows. The requirement and row changes commit atomically through existing capacity validation and fixture auditing.

Guards: authenticated fixture manager/active creator, Open selection mode with rinks enabled, active fixture, positive bounded count, matching expected count and slot snapshot, row locks, and rejection of player/marker records, draft selection members or published teams. No automatic removal of assigned rinks. Existing non-Open workflows are unchanged.

## Deployment

Applied to staging egxdkaotepgfjmszxlyn first, then production xfjelvvfoguzukgvxchh:

- 20261005222629_edit_open_fixture_rink_requirements.sql
- 20261005223338_guard_open_fixture_selection_members.sql

The second migration adds protection for legacy draft selection members. Applied migrations were not rewritten.

Shared app source and migrations copied to both checkouts. Environment entry points and secrets preserved. Changes are not committed or pushed by this task. Existing store packages do not contain this new UI; rebuild the local app to use it immediately. A future store build is needed for installed mobile/Store clients. No version bump or store submission was performed.

## Verification

- SQL regression suite uses the real new migration code against synthetic PGlite storage: preserving assigned rows, reduction, increase, stale counts and labels, atomic rollback on capacity failure, limits, authorization, non-Open modes, archived/cancelled fixtures, player/marker records, publication, draft selection members, anonymous access.
- Three Flutter dialog tests passed; four existing peak usage tests passed.
- Authenticated transactions in both live databases exercised unassignment followed by reduction, preserved assigned rows, and rejected stale edits. Both transactions ended with ROLLBACK; no fixture change was retained.
- Deployed function definitions and ACLs matched; anonymous execution denied. Security advisors had no findings for the new objects; unrelated existing findings were not modified.
- Compare-AppSources.ps1 passed. Dart analysis had no errors; fixture_details_page.dart retains existing warnings and lint notices. New dialog analysis clean.
- Native Windows debug build was attempted but blocked by an MSBuild FileTracker access-denied error while configuring NuGet. Run flutter run -d windows from the production checkout in the normal user terminal to rebuild and exercise the control.

## Recovery

Older clients remain compatible. To withdraw the new control, revert only the Open-rink UI additions and remove the new dialog import/file. To disable its backend, revoke EXECUTE on public.set_open_fixture_rinks_required(uuid,integer,integer,jsonb) and open_fixture_private.set_rinks_required(uuid,integer,integer,jsonb) from authenticated. This does not reverse deliberate user edits; use the fixture audit to review any such changes. Do not bulk restore fixture records.
