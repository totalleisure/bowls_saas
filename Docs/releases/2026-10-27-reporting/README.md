# Future explicit starting views in reports

Staging-first change promoted to production on 27 October 2026. Source and live database definitions verified separately; no store release, commit or push.

## Behaviour

The existing login, App-visit and seven named-screen counters were already integrated in both source folders. Rechecked navigation tests, live function parity and rolled-back database permission tests in both environments.

Future explicit starting-view selections now enqueue a separate, account/Club-scoped report event after saving the existing local preference. The automatic Dashboard fallback is explicitly excluded. Old saved device preferences are neither changed nor inferred to be explicit choices. Clearing a preference is a separate recorded state. No cross-device preference synchronisation is introduced.

Pending latest choices persist locally; a failed transmission retries on the next Club entry with the same UUID. A different signed-in account cannot flush another account's pending choice. Reporting failure never prevents navigation or successful local preference use. If another device submits an older offline choice later, Reports shows the latest server-recorded choice; it is not guaranteed to be the chronologically latest selection across devices. Recording timestamps are server times, not device selection times.

The private RLS table is writable only through an active-membership-checked function. User and time come from the server. Anonymous execution and direct client table access are denied. The security advisor's RLS-without-policies notice is intentional for this private table: clients access guarded functions only. Existing report authorization remains Club-admin/superuser only.

Reports and Excel include explicit view, server-recorded UTC time, and status (Not recorded / Explicit choice / Cleared), plus the number of active members with a current recorded explicit view. This is a current snapshot outside the report's activity date filter. Earlier unknown choices are not counted as people who never chose.

Legacy reconciled workbooks gain the three fields after their existing custom columns, with expanded table ranges and readable column widths. Existing notes, imported original Club data and mismatch highlighting remain. Native exports and Guest Members include the new fields too.

## Deployment and recovery

- Source/staging migration: 20261027222630_report_explicit_start_choices.
- Production ledger: 20261027223106_report_explicit_start_choices.
- get_club_admin_report hash: c81f30e715f136d4465b0c9c6d4a4b8a.
- record_club_start_choice hash: 2610cbae5f164b78411557d12cd264e6.
- Existing record_club_usage unchanged: b6e9af23c7aec7b7a21c392c287b8072.
- Prior report definition and optional recovery SQL retained alongside this file. Recovery preserves recorded choice data.

## Validation

- Staging full Flutter suite: 368 passed, 4 skipped. Production full suite: 495 passed, 4 skipped.
- Additional final export/refresh tests passed after column sizing changes; source analysis clean.
- New tests cover automatic defaults, legacy reads, explicit choices, clearing, failed transmission retry and account isolation.
- Rolled-back SQL tests on both databases cover authorization, Club isolation, allowed values, deduplication, report fields and clearing.
- Real reconciled workbook re-import/formula scan preserved all 333 App rows, 330 original Club rows, 317 source matches and mismatch highlights; new Members table A6:AI339 includes all 35 columns. Original Source sheet remains byte-identical.

Members need an updated App binary to transmit App visits, screen views and explicit choices. The existing released 1.6.0+29 binaries remain unchanged. Login recording already works server-side.
