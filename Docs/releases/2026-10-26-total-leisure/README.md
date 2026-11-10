# Total Leisure messages and reconciled report refresh

Implemented and verified in staging, then promoted to production on 26 October 2026. No member announcement was sent by this task. No App release, version change, commit or push.

## App controls

- Superuser > Messages from Total Leisure opens the selected Club's mailing lists. Use list options to compose a message; Total Leisure branding is selected by default on this route. Existing Club messages remain available. Subject, message, attachments, recipient summary and final send confirmation use the existing mailing-list workflow.
- Server enforces superuser sender identity; a private record stores actor, message, request ID and result. Identical retry requests return the original result. Branding uses the existing App mailbox and shared footer; mailbox credentials/display-name configuration were not changed.
- Membership > Reports supplies membership, bookings and App usage, Top Users and Guest App role reports. Refresh existing reconciled workbook reads a selected .xlsx and saves a refreshed copy. Extra member columns/notes, original Club Source and mismatch highlighting are retained. Removed App rows are kept separately. Shared email addresses never combine member identities. Later refreshes retain identity by profile ID.
- Workbooks with custom formulas in member data rows are rejected rather than silently moved. Downloaded workbooks are snapshots, not permanently connected files.
- Login recording is already live. Screen-view and App-visit recording require the updated App. Historical explicit starting-view choices cannot be recovered from device-only settings.

## Deployment

Staging migration 20261026224056_total_leisure_member_messages; production ledger version 20261026225710. Existing mail-queue functions and superuser helper definitions were compared live and remain unchanged. New live function definitions match in both projects:

- queue_total_leisure_message: 429d553bf9e2de09deef6f562c2294b6
- mailing_list_email_identity: fd8e668c6a4458613c40fe67b2ca7165

Production process-email-queue version 17, JWT verification retained. All four downloaded deployed files verified against reviewed source in both projects. Recovery worker version 16 is retained in production-worker-before.json. To disable the new sender feature, restore that worker first. Retain private identity records for audit; do not drop them after real messages have been sent.

## Validation

- Full Flutter suite: staging 364 passed / 4 skipped; production 491 passed / 4 skipped.
- Changed App files: analysis clean. Shared App source comparison passed.
- Email renderer/worker tests: 8 passed, including fail-closed identity lookup and attachment retention.
- Rolled-back database tests passed in both projects: superuser-only sender, recorded actor, identical retry, mismatched request rejection, privilege checks and attachments. No test emails persisted.
- Real reconciled workbook round trip: 333 App rows, 317 confirmed source matches, 330 original Club rows, 139 interim Top Users and zero Guest roles retained. Artifact import, formula-error scan and rendered mismatch highlighting verified.

Source changes and live backend changes are present in both environments. Store builds still remain at 1.6.0+29; the new App controls have not been published to any store.
