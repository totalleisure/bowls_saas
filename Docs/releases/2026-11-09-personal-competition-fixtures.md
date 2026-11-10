# Personal upcoming competition fixtures

The dashboard now lists linked upcoming competition fixtures for every participant in a published competition, regardless of who booked the fixture. The section is titled **Your upcoming competition fixtures** and displays the member's Pending, Accepted or Declined response from their published selection.

Pending selections remain in **Fixtures needing your Acceptance** as an additional action prompt. Accepted competition fixtures stay in the competition section and are suppressed from the general accepted list. Reminder source data is retained. Past and cancelled fixtures are excluded. The unarranged list continues excluding a match for all participants once its fixture is linked.

Developed and tested in staging before applying the same three source/test files to production. Reviewed against saved production files before copying; shared Dart source comparison passed. The 28 personal/internal competition tests passed in staging. Static analysis reports existing dashboard warnings and style notices, with no errors.

This change requires no database or edge deployment and does not alter bookings or recorded responses. No iOS/TestFlight/store release is included. Production Windows build and production test results are recorded under tmp/competition-list-promotion.

Production verification: all 28 competition tests passed.
