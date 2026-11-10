# Branded mailing-list messages

Mailing Lists retains its existing signed-in Club-admin/App-superuser authorization, recipient snapshot, confirmation and attachment workflow. The email worker now formats `mailing_list_message` emails using the invitation email's App design, shared footer and the Club's blue/yellow or other configured colours. Other email event types retain their existing content and action rendering. Credentials and invitation/signup wording are not included in member updates.

Authors can use plain paragraphs, `## Heading` and `- bullet` lines in the existing Message field. HTML is escaped. HTTP/HTTPS links are rendered as links; colour values accept only six-digit hex. The locally updated compose screen explains these formatting options. Existing installed Apps can already use this server-side delivery format without a new store release.

The worker verifies the queued mailing-list message/list relationship before loading Club branding. Existing JWT and worker/superuser checks are preserved. Attachments are passed through unchanged. No database functions or schemas were changed.

Validation:
- 64 email/attachment/invitation/security tests pass in staging and production source.
- 12 Flutter attachment, invitation delivery and queue tests pass in staging; compose-screen analysis has no issues.
- Attachment/permission/atomic-rollback SQL tests pass in both databases. All test writes rolled back.
- Deployed staging source matches the reviewed source. Production worker version 16 uses JWT verification and its four deployed files match the reviewed source.
- Shared Dart source comparison passes. Production-specific configuration and unrelated working changes were preserved.
- Previous production worker metadata/source retained in `production-worker-before.json`; staging recovery source is isolated in `tmp/branded-mail-recovery/staging`.

The announcement is a draft in `output/member-release-announcement/`, with HTML preview, message text, recipient review and the user-supplied two-page installation guide (SHA256 E8CEA094CAC1F60F57C55D8F58C5D8EFB25D1764120979B4A17DF1F972DF4FB4). Production Newsletter Recipients has 333 members: 325 distinct email addresses and 8 without email. No announcement rows were queued or sent. The draft body needs user review before this membership-wide message is sent. App notifications have not been selected or created for this draft.

No commit, push, version bump or store submission was made. The email worker change is live in both environments; the compose helper text is in both local Flutter source trees.
