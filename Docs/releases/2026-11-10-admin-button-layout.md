# Member account action layout

The login email, password reset and confirmation resend actions now share a full-width, left-aligned button style with matching minimum heights and padding. Height scales with the configured text size. The main admin member form uses 6-pixel gaps between the three actions. Existing permissions and account operations are unchanged.

Verified in staging before applying the same two source files to production. All 15 confirmation/email/profile tests pass in staging; production checks and build output are recorded under tmp/admin-buttons. Shared Dart source comparison passes. No database or server deployment is required and no iOS/TestFlight/store build was released. The prior files and production hashes were retained under tmp/admin-buttons before copying. Restart staging or reopen the updated production Windows application to load the layout.
