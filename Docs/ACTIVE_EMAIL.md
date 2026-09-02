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

New action blocks include a single-use, high-entropy response token bound to the Action Request. The sending Edge Function generates the token immediately before delivery, stores only its SHA-256 hash through a service-role-only RPC, and adds the plaintext token only to the rendered outbound email. This token allows a valid response to be processed even when a mail client chooses a different configured sending account. The intended recipient and the actual inbound sender are both retained for audit. Older outstanding action emails without a token continue to require an exact sender-address match.

The inbox processor fetches the complete Microsoft Graph message body as normalized plain text. A response is actionable only when one complete `ACCEPT BWL-... RSP-...` or `DECLINE BWL-... RSP-...` command is the first newly authored non-empty line. A command found only in the subject, signature, forwarded content or quoted reply history is not actionable. Multiple authored commands, or disagreement between the prepared subject and body, is rejected as ambiguous.

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

## Confirmed published-team changes

For ordinary Team and RSVP fixtures, composition changes made after publication are staged locally in Manage Team. Nothing is written until **Confirm Team Changes** is pressed. Confirmation sends the complete desired member and assignment state to one version-checked database transaction.

The operational states are derived rather than stored:

- **Selected** is an active player selection-member without a valid player-position assignment. Selected members are not awaiting acceptance and receive no selection communication.
- **Player** is an active player selection-member occupying a valid player position. Acceptance and actionable communication begin when confirmation first creates this state.
- **Reserve** is an active reserve without a player-position assignment. Reserve publication messages remain informational.

Confirmation compares the final authoritative state with the state at the start of the transaction. New positioned players receive one `fixture_selected`; reserves promoted into a position receive one `reserve_promoted`; position-only moves preserve responses and send nothing. Removed, demoted, or unpositioned former players retain response history while obsolete unsent player communications and Action Requests are cancelled.

An exact retry is an authoritative no-op, even when the caller supplies the pre-confirmation version after losing the original success response. It does not advance the version, reset acceptance, or create another communication. A stale version with a different desired state remains a conflict and must be reloaded.

`team_selections.composition_version` prevents one editor overwriting another editor's confirmed changes. Pre-Select and draft workflows are unchanged. The legacy Rink Assignments screen is read-only for published Team/RSVP composition changes.

Outbound notification preparation and email sending remain manual through the Communications Control Centre. The inbound `process-email-responses` schedule remains active and checks the restricted mailbox every two minutes.

## Versioned Team Sheet attachments

Publication and post-publication player-entry communications that promise a Team Sheet carry one PDF attachment for the current `team_selections.composition_version`. The PDF is generated in Flutter from the server-authorised Team Sheet dataset and is submitted through an authorised attachment RPC. The RPC locks and validates the current published selection version, and the queue and email processors block missing, empty, oversized or stale attachments rather than sending without the promised sheet.

This version check protects freshness and makes retries idempotent, but it does not cryptographically prove that the submitted PDF bytes represent the authoritative dataset. That trust boundary is acceptable for the current manager-authorised workflow. Server-side rendering or a signed content digest would be required if untrusted callers, evidential integrity or independent content verification become requirements.

Microsoft Graph's direct file-attachment route requires files smaller than 3 MB. The application applies a conservative maximum of 2,000,000 decoded PDF bytes, before Base64 encoding, to leave encoding and transport headroom. Composition metadata remains internal queue metadata and is stripped from the attachment object sent to Microsoft Graph.

After **Confirm Team Changes**, Phase II sends the revised Team Sheet only to newly positioned, replacement or promoted players who receive a new player-entry communication. Unchanged existing participants do not currently receive an informational revised Team Sheet. That remains future affected-team/rink communication work rather than completed Phase II behaviour.

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
- Token-bearing Action Requests store only a SHA-256 token hash. The plaintext response token exists only in Edge Function memory and the delivered email; it is never persisted in `email_queue`. It is covered by the existing expiry and cancellation rules and can be used only while that request remains active.
- For token-bearing responses, possession of the delivered action email authorises the response; the actual inbound sender is recorded but is not used as the sole identity check. Forwarded action emails therefore transfer the ability to respond until the request is used, cancelled or expires.
- Legacy action emails without a token retain exact sender-address validation.
- Graph message IDs provide idempotency for processed replies.
- The first inbox delta synchronization establishes a cursor without processing historical mail.
