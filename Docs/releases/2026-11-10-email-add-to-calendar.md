# Add to Calendar in fixture response emails

Fixture emails containing both Accept and Decline now include an Add to Calendar section and a bowls-fixture.ics attachment. The section tells the recipient to accept separately, then open the attachment and add/save it in their calendar. This is an optional calendar import, without an attendee or scheduling request that could be confused with fixture acceptance.

The email worker reads current fixture start/end times, fixture type, club and the appropriate home/away venue when sending. Calendar times use UTC, text is escaped and UTF-8 content lines are folded to RFC 5545 limits. The event UID combines the project and fixture identities, keeping environments separate. Cancelled fixtures receive no calendar attachment. Existing PDF checks, attachment contents, response buttons, token handling and worker authentication remain intact.

Staging deployed and verified first, then the same amendment was promoted to production. All four pre-existing deployed production dependencies matched both checkouts before promotion. Live prepare_team_selection_email_action and issue_email_action_response_token definitions matched between projects. Shared Dart source comparison passed. All 15 calendar/action/authentication tests passed in each checkout; a calendar was also generated from real staging fixture/venue data without sending mail. Production version 20 is active and all five deployed source files were checked against reviewed source. Unauthenticated requests are rejected: staging returns 401 at its gateway and production returns 403 from its existing worker authorization guard.

Source and Edge Function deployment: complete in staging and production. Database: no schema/function amendment required. Store/client build: no change required; no app restart required. Applies to subsequently sent emails; previously delivered emails are unchanged. No test or resend messages were sent as part of this task. Calendar-client import behavior still needs recipient device testing. Automatic calendar update/cancellation dispatch is outside this amendment.

Recovery: tmp/calendar-promotion/live-before contains the production version 19 source bundle, including dependencies. Redeploy that bundle preserving verify_jwt=false and the existing in-handler worker authentication; do not change environment secrets.

