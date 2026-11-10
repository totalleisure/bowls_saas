# Email queue worker authentication — 6 October 2026

Resolved the caller credential mismatch observed during the captain email test.
The current configured server key still uses its existing path. Alternate worker credentials are verified by Supabase against the service-only email_written_reply_settings table using a zero-row SELECT. The caller's own bearer token is sent to PostgREST; decoded JWT claims are never trusted.
Both environments explicitly deny SELECT on that probe table to anon/authenticated. Network errors and unexpected responses fail closed with HTTP 503. Existing signed-in app-superuser single-email access is preserved.
Gateway JWT verification remains enabled.

Deployed process-email-queue: staging version 5, production version 13.
The pre-change deployed source was compared between environments; only trailing whitespace differed. Production local source matched its deployed source before modification. Environment keys/mailbox values were not copied.
Nine authorization tests passed in both source checkouts.

Real staging queue test:
- Subject: [STAGING QUEUE TEST] Captain written-reply notification
- Recipient: wayne@totalleisure.com only
- Queue row: 1a6235a3-5f6f-4372-9601-3332da297ca7
- Request 4720 returned HTTP 200, processed 1, failed 0.
- Queue status sent, 2026-10-06 21:36:09.965 UTC.
- This used the normal queue worker, not the special synthetic email sender.

Production authentication verification used a confirmed nonexistent queue ID, so it could not send any mail.
No cron settings, written-reply activation settings, database functions or app versions were changed.
Production written replies remain disabled. An actual incoming-member-reply rehearsal remains distinct from these database and outbound-delivery tests.
No commits or store builds made.

Recovery: revert the worker_auth import and verification call to the original exact-key comparison, remove worker_auth.ts from the deployment, then redeploy the prior index.ts with verify_jwt=true. That restores the previous mismatch for alternate credentials, so use only if necessary.

