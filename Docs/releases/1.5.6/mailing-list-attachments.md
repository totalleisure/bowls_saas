# Mailing-list attachments — 6 October 2026

Implemented in staging first, then promoted to production. Shared Dart source comparison passed.

## User workflow
Club administration → Mailing Lists → select a list → compose message → enable email → Add attachments.
The native file chooser supports selecting multiple files, including additions from separate locations on repeated visits.
Each selected filename and size appears with a remove button. Review and Send lists the filenames again.
Attachments go to each queued email, not to app notifications. Existing club-admin/app-superuser authorization remains unchanged.
Up to 10 nonempty files, 2 MiB combined; duplicate filenames (case-insensitive) are rejected.
Subject maximum 255 characters; message maximum 50,000 characters.
Cancellation leaves existing files unchanged. Read/validation failures reject that selection batch, preserving earlier selections.
Files are read into memory before sending; no local path or storage public URL is sent.

## Backend and compatibility
Migration: 20261006153957_mailing_list_attachments.sql, applied to both projects.
New invoker RPC public.queue_mailing_list_message_with_attachments delegates to the guarded private definer mailing_private.queue_with_attachments.
The existing five-argument queue_mailing_list_message is unchanged, including its active-member recipient snapshot and permission checks.
The private routine validates count, names, base64 and actual decoded byte size, calls the original routine, and adds files only to the emails for the newly returned message ID within the same transaction.
No authenticated direct email-queue update access was added. Both new functions deny anonymous execution.
The existing email processor passes attachments to send-graph-email, which forwards them to Microsoft Graph.
No edge function deployment was needed.
Generic binary MIME type is used with the original filename.

Matching live definition MD5:
- private queue_with_attachments: 2cbde76d68f0f7efc99674b16f93b8b9
- public attachment RPC: 404f4cf3f209f593d6b3dec5643e7f14
- unchanged legacy RPC: 7703c5f92b45b661b6e98a8f7a9b137c

## Verification
- Five Dart tests pass in both checkouts: multi-file list/review/payload, removal/picker cancellation, app-only guard/failure retention, no-attachment regression, stream reading/duplicate/empty/count/combined-byte limits.
- Targeted Dart analysis has no issues.
- Mocked Graph transport verifies two attachment filenames, MIME types and exact base64 contents reach the sender.
- test/sql/mailing_list_attachments.sql passes against both live databases in transactions ending ROLLBACK. Verifies queued bytes, invalid-input rejection, permissions, atomic rejection and empty-attachment behavior.
- No member emails were sent by these tests. Native OS file dialogs and actual inbox delivery have not been manually exercised.
- Security advisors show no findings on the new functions/schema. Existing unrelated advisor findings remain.
- App-source comparison passes excluding established environment entry points and secrets.

## Deployment status
Database support is live in staging and production. App changes are in both working checkouts.
No commit, store build, version change or store upload was made for this feature. Existing store version 1.5.6(27) does not contain the new composer.
Restart/rebuild flutter run to test locally, then include this source in the next platform release.

## Recovery
First revert only the attachment composer changes in the next app build, restoring the old RPC call.
The original routine and previously queued emails remain valid. Leave the additive backend functions installed while clients may still use them.
If removal is necessary after retiring those clients, use a new migration:
```sql
drop function public.queue_mailing_list_message_with_attachments(uuid,text,text,boolean,boolean,jsonb);
drop function mailing_private.queue_with_attachments(uuid,text,text,boolean,boolean,jsonb);
notify pgrst, 'reload schema';
```
Do not delete unrelated working changes or queued messages.

