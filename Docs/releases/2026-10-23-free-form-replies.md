# Free-form selection replies enabled — 23 October 2026

Production activation completed for bowls@totalleisure.com at 10:14:33 UTC (11:14:33 BST). This supersedes earlier release notes saying production written-reply review was disabled. No Flutter store release is required for this server-side feature.

## Behaviour

Eligible new written replies to sent, pending, published selection emails are correlated with the original email and response credentials. The original recipient must still be an active non-guest member of that request's Club with the same current email address. Production uses `sender_scope=active_members`, so newly added members do not need a manually maintained email allowlist.

The reply excerpt is recorded, authorised reviewers receive an App notification, and a review email is queued for the highest-priority reachable captain, vice-captain, publisher or Club administrator. The member receives a one-time reminder with the original Accept/Decline controls. Acceptance and request status remain pending; prose is never interpreted as an acceptance or decline. Published pending reserves are supported without a rink assignment.

Existing conservative eligibility remains: the message must genuinely reply to the original selection email. Historical, automatic, support/technical, ambiguous and question-form messages are excluded by the existing candidate filter. Cancelled, archived, expired or already answered selections are excluded. Original attachments are not forwarded; a credential-redacted excerpt of up to 1,500 characters is used. Duplicate message IDs do not generate duplicate review emails, and a member is not repeatedly sent the reminder for the same selection target. These checks are not intended to process every ordinary inbox message.

Production's existing inbox cursor, ordinary explicit Accept/Decline processing, Vault credentials, mailbox and scheduler settings were preserved. Staging retains its existing five-address allowlist and staging-only test controls; it was not opened to general membership.

## Deployment and verification

- Shared corrective migration source: `20261023081013_activate_member_written_replies.sql`.
- Staging ledger: `20261023081013`; production ledger: `20261023081910`, both named `activate_member_written_replies`. Do not replay the canonical file because the production timestamp differs.
- Live claim function MD5 in both projects: `a2b7ba8d892011748a279b1a6b49ab07`.
- Production process-email-responses v4 ACTIVE, JWT verification retained. All four deployed source files match reviewed production source.
- Staging process-email-responses v11 ACTIVE, JWT verification retained. All five deployed source files match reviewed staging source.
- Worker tests: 83 passed in staging (79 plus four routing checks), 91 passed in production. Ordinary explicit replies, disabled/missing written-reply settings, caller authorization and unsupported production test modes remain covered.
- Transactional database tests: 32 passed in each environment. All synthetic records, notifications and queued messages rolled back before a worker could see them.
- Read-only production mailbox verification returned HTTP 200. This probe did not scan or process messages.
- First observed scheduled run after activation succeeded at 10:16:00 UTC; inbox state reported no error.
- Shared Flutter source comparison passed. No Flutter UI, store build, signing, credentials, legacy maintenance routines, unrelated SQL definitions, cron settings, commit or push changed in this task.
- Production security advisors have the same finding names/counts as the earlier audit; no broader grants were introduced.

No test emails were sent to members or captains. Actual receipt of a real member's written reply and its captain review email has not been manually rehearsed; automated tests verify the processing and queued email content with synthetic data.

## Recovery

Disable future captures by setting `email_written_reply_settings.enabled=false` for the production mailbox. This does not remove previously queued review emails. Retain the additive column and existing records; use a new corrective migration if restoring a previous routine definition.

Evidence, original function/Edge source, activation settings, test results and a disable script are in `C:/src/bowls_staging/outputs/written-replies-production-20261023`. Production/staging worker source differs deliberately in environment restrictions and staging test modes; never replace the whole production worker with staging source.
