# Admin member login email change

Implemented in staging first and promoted to production on 9 November 2026.

Admins can open Members, edit another member and choose **Change member login email**. Enter the new address twice and confirm. The existing password and member identity are retained. A shared login changes across all linked clubs. Self-service account email changes keep their existing flow.

The server validates the signed-in actor, club membership, administrator permissions, target privileges, expected current address and duplicate addresses. Only the server calls Auth administration. The existing Auth trigger synchronizes the member profile; completion verifies both records. Prepared and completed changes are audited, including the administrator responsible. Recovery SQL can pause new changes without deleting audit records.

Shared source comparison passed. Production and staging definitions match for both new database functions and the existing email synchronization function. Both projects have the migration and JWT-protected edge function deployed. Production additionally records the source migration version alongside the connector deployment version. Environment-specific configuration and secrets were preserved.

Validation: 23 Node handler tests and 12 Flutter dialog/profile tests passed in production. Synthetic database authorization, duplicate, concurrency, synchronization and audit checks passed in both deployed projects; all synthetic records rolled back. Production security advisors introduced no new notices. The actual Auth API call is covered with a mock; a real member change remains the user's live test.

Richard Allen's address has not been changed by this task. No emails were resent. Resending remains on hold pending the login change and regeneration of the fixture response request for the new address.

Source, database and edge deployment are complete in both environments. The production Windows release build completed successfully from the updated source. No iOS/TestFlight or store release was made; iPhone 1.6.6(31) does not acquire this UI without a new build.

