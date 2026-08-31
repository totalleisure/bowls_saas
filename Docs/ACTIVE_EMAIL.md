# Active Email selection responses

This document records the external configuration required by the deployed Active Email implementation. Secret values must never be committed to this repository.

## Deployed Edge Functions

- `process-email-queue` version 8 sends queued email and renders an actionable Accept/Decline block when the queue payload contains `action_block`.
- `process-email-responses` version 1 reads mailbox changes through Microsoft Graph delta queries and submits matching responses to `apply_email_action_response`.
- Both deployed functions have JWT verification enabled.

The exact deployed TypeScript is stored under `supabase/functions/`.

## Actionable selection emails

Active Email action blocks support:

- Pre-Select players whose email event is `fixture_selected`.
- Ordinary players named when a team is published, whose email event is `team_published_player`.
- Players promoted from reserve after publication, whose email event is `reserve_promoted`.
- Named Pre-Select markers whose email event is `fixture_selected`, whose selection role is `marker`, and who have the canonical fixture-rink position `201` assignment.

Player replies use action type `team_selection`. Named-marker replies use action type `marker_assignment`. Both update the existing `team_selection_members` acceptance, `responded_at`, and `acceptance_by` fields. Declining a named-marker assignment records the declined response but retains the position-201 assignment so the captain or selector can review and replace it explicitly.

Reserve-selection emails and open marker-request broadcasts remain informational. Open marker requests continue to direct volunteers to the fixture captain; they do not create an email action request. Direct team-sheet emails are also unchanged.

## Post-publication selection transitions

Manage Team uses narrow transactional database operations for selection changes:

- A newly selected or reactivated player is reset to `pending`, has previous response attribution cleared, and receives one `fixture_selected` event when the selection is already published.
- Promoting a reserve resets the response fields and creates one `reserve_promoted` event for a published selection.
- Moving an existing active player between rink positions preserves their response and creates no new selection event.
- Demoting a player to reserve removes their playing-position assignment and invalidates an outstanding player action. The reserve email remains informational.
- Removing a selected player retains the historical response fields, marks the selection inactive, removes the playing-position assignment, and cancels outstanding actionable or unsent player communications.
- Draft-selection changes update selection state without creating publication communications.
- Repeating an already completed transition is a no-op and does not reset acceptance or duplicate a notification.

Outbound notification preparation and email sending remain manual through the Communications Control Centre. The inbound `process-email-responses` schedule remains active and checks the restricted mailbox every two minutes.

## Microsoft Graph

The Microsoft Entra application uses application permissions with administrator consent:

- `Mail.Send`, required to send queued email through Microsoft Graph.
- `Mail.Read`, required to read inbox messages and maintain the delta cursor.

Access must be restricted to the application mailbox:

```text
bowls@totalleisure.com
```

Configure the Microsoft 365/Exchange application-access restriction so the app registration cannot read or send as unrelated mailboxes. Set the Edge Function `MS_MAILBOX` environment variable to the same address. The functions also require `MS_TENANT_ID`, `MS_CLIENT_ID`, and `MS_CLIENT_SECRET`; values must remain in managed Edge Function secrets and must not be committed.

## Supabase internal authentication

Vault contains a secret named:

```text
edge_internal_auth_token
```

The secret value is intentionally not recorded here. The scheduled database call reads it from Vault at execution time and passes it as the Edge Function authorization and API key credential.

## Inbox schedule

The active Supabase Cron job is:

```text
Name:     bowls-process-email-responses
Schedule: */2 * * * *
Target:   /functions/v1/process-email-responses
```

It runs every two minutes. The cron command, Vault secret and mailbox/application restrictions are environment configuration and are not created by the portable schema migration.

## Safety model

- The three Active Email tables have Row Level Security enabled and no client policies.
- Table access is reserved for `service_role`.
- `apply_email_action_response` is `SECURITY DEFINER`, has a fixed search path, and is executable only by `service_role`.
- Response codes are stored as SHA-256 hashes; plaintext codes exist only in the outgoing action payload.
- Graph message IDs provide idempotency for processed replies.
- The first inbox delta synchronization establishes a cursor without processing historical mail.
