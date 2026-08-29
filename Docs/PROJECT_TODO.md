# Total Leisure Bowls App — Project To-Do

Last updated: 29 August 2026

This repository file is the authoritative project task list. Update statuses here as relevant work is completed or new agreed tasks are added.

## Current priority order

- [ ] **1. Add fixture-level overrides for Pre-Select fixtures**
  - [x] Create Fixture: initialise Section, Format, Rinks Required, Players per Rink and Dress Code from the Fixture Type, allow fixture-level overrides, preserve Aussie Pairs, and provide Reset to Fixture Type defaults. Implemented and successfully verified on 22 August 2026.
  - [ ] Fixture Details: add the collapsed Playing format and dress summary/editor with safeguards for saved assignments.
    - Display the fixture-level Dress Code as a pill alongside Format, Section, rink count and green.
    - Hide the pill when Dress Code is empty/open.
    - Format displayed enum values appropriately, for example `blacks` as `BLACKS`.
  - Treat the Fixture Type as a source of defaults rather than permanently locked values.
  - On Create Fixture, expose and allow editing of:
    - section;
    - number of rinks;
    - players per rink;
    - playing format (Singles, Pairs, Triples, Fours, Aussie Pairs, etc.);
    - dress code.
  - Save the chosen values against the individual fixture without changing the Fixture Type.
  - On Fixture Details, add a collapsed **Playing format and dress** section with inline editing.
  - Add a **Reset to Fixture Type defaults** option.
  - Protect existing player/rink assignments from incompatible changes.

- [ ] **2. Simplify the normal member dashboard and RSVP presentation**
  - Make the initial member view personal and action-oriented rather than an operational list.
  - Prioritise:
    - Needs your response;
    - You are selected;
    - Your upcoming fixtures;
    - Club announcements or events.
  - Keep the full fixture list available behind **View all fixtures** or filters.
  - Use compact RSVP cards; after a response, collapse the controls to **Your response: Yes/Maybe/No — Change**.
  - Show only a small number of unanswered requests initially, with **View all requests** for the remainder.
  - Remove expired or completed requests from **Needs your response**.
  - Hide administrative and selection detail from ordinary members unless it is relevant to them.

- [ ] **3. Confirm RSVP visibility policy**
  - Confirm whether committee feedback means:
    - too many RSVP requests are displayed together;
    - ordinary members can see other members' RSVP responses;
    - or both.
  - Proposed default policy:
    - ordinary members see their own response only;
    - captains, vice-captains, selectors and administrators can see the complete response list;
    - optionally show ordinary members an anonymous availability total.

- [ ] **4. Verify the revised experience using a small, realistic set of future fixtures**
  - Test Pre-Select defaults and overrides.
  - Test Fixture Details editing, Save and Cancel.
  - Test capacity reductions after assignments exist.
  - Test the dashboard and RSVP presentation using a normal member account.
  - Present a clean first-login experience suitable for the committee.

- [ ] **5. Clean old test data**
  - Before deletion, produce and review the exact list/count of affected records.
  - Delete all fixtures dated before the agreed cut-off date once confirmed as test data.
  - This supersedes the earlier intention to retain old fixtures for communication testing.
  - Retain useful future fixtures that demonstrate genuine member workflows.
  - Remove test administrators Andrea and Bob when ready; retain Dave and Julie.

- [ ] **6. Rationalise Fixture Types**
  - Keep types currently named **Test - ...** until fixture-level overrides are proven.
  - Inactivate/archive redundant Fixture Types first so they disappear from selection without breaking references.
  - Remove redundant test Fixture Types permanently only after confirming they are unreferenced and no longer needed.
  - Retain a small set of meaningful reusable types such as Competition, National and Internal only where they provide genuinely useful defaults.

- [ ] **7. Add collapse/expand control to the Dashboard section “Open Sessions and Events”**
  - Add a clear collapse/expand control to the section header.
  - When collapsed, hide the session and event cards while retaining the section heading.
  - Use an appropriate chevron or disclosure icon so the current state is obvious.
  - Decide whether the chosen state should persist when the user leaves and returns to the Dashboard.

- [ ] **8. Warn and require confirmation for past-dated fixtures**
  - Continue to permit an administrator to create or reschedule a fixture with a date or time in the past; this may be necessary when retrospectively recording a rearranged fixture or entering scoring/history discovered later.
  - Do not accept a past date silently: show a clear warning that the fixture is in the past and require explicit confirmation before saving.
  - Apply the same protection to both fixture creation and rescheduling.
  - Review whether retrospective fixtures should suppress inappropriate RSVP, selection or communication activity while remaining available for results and historical records.

- [ ] **9. Prevent publication repair from processing unrelated notifications**
  - Audit `repair_fixture_publication_communications`, which currently invokes `process_notification_queue(200)` internally.
  - `process_notification_queue(200)` can drain unrelated pending notification work as a side effect of repairing one fixture's publication communications.
  - Remove that possibility and keep fixture repair targeted to the selected fixture.
  - Preserve the central communications-processing architecture: repair should only enqueue its own corrective events and leave dispatch to the central processor schedule.
  - Verify that repair actions do not send or prepare communications for other clubs, fixtures or recipients.

- [ ] **10. Add an email-safe Unified Fixture Card to fixture communications**
  - Standardise fixture-related emails on a reusable HTML card that follows the visual language and information hierarchy of the App's Unified Fixture Card.
  - Implement an email-specific renderer rather than attempting to embed the Flutter widget directly.
  - Use email-safe HTML with inline styling, accessible text, sensible mobile behaviour and a plain-text fallback; do not make the card a single image.
  - Include, where relevant:
    - a clear status banner such as **Selected**, **Rescheduled** or **Cancelled**;
    - Fixture Type colours, fixture title, London-local date and time;
    - Home/Away, opponent and venue;
    - format, dress code and rink/team information;
    - recipient-specific player, marker, manager or availability wording.
  - Preserve existing recipients, event types, queue semantics and suppression rules; this is initially a presentation-only enhancement.
  - Introduce the card first for fixture selection, rescheduling and cancellation, then extend it to reminders and Team Update messages.
  - Test in Outlook, Gmail and common mobile email clients before general rollout.
  - Consider an **Open Fixture** deep-link button only after App deep-link behaviour is proven reliable.
  - Allow approximately two focused development days for implementation and cross-client testing.

- [ ] **11. Measure and reduce the remaining normal-member dashboard startup time**
  - Keep the completed first-stage optimisation: parallel dashboard reads, reuse of the resolved member profile ID, notification loading outside the visible-dashboard critical path, and the member-led `team_selection_members` index.
  - Current measured improvement on the test device is approximately 8 seconds to 4 seconds from club selection to a usable dashboard.
  - The new `team_selection_members (member_profile_id, is_selected, acceptance)` index produced no clearly measurable additional reduction after the reads were parallelised.
  - Add temporary per-request timing logs around the parallel dashboard queries and repeat normal-member testing to identify the actual critical-path request.
  - Investigate the general future-fixtures query first; it currently loads all future club fixtures with several nested relationships and applies dashboard filters afterward in Flutter.
  - Only after measurement, make the smallest targeted change, such as limiting the date range, reducing the selected payload, or introducing a purpose-built dashboard RPC.
  - Re-test cold and warm starts using both normal-member and administrator accounts and record median timings.

## Agreed design principle

> A Fixture Type supplies reusable default values. The values saved on an individual fixture are authoritative and may override those defaults, including for Pre-Select fixtures.

## Decisions still required

- [ ] Confirm precisely what users meant by “seeing all the RSVPs at the same time”.
- [ ] Decide whether ordinary members should see an anonymous RSVP availability count.
- [ ] Agree the exact deletion cut-off and preview the affected fixtures immediately before deletion.
