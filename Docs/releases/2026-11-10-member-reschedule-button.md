# Member Internal Reschedule button

Added a Reschedule booking action to the Fixture Details toolbar for active Member Internal rink bookings using preselection. The button observes existing operational editing/competition booking permissions. Ordinary bookings use the same date/time edit flow as the timing controls, so the existing fixture moves without a cancelled predecessor. The existing confirmation explains that physical rink allocations are cleared and require reassignment. Linked competition bookings use CompetitionFixtureManagementScreen and its availability/booking checks.

Delete and existing timing controls remain available under their existing permissions. The separately suppressed Cancel controls remain hidden. No team-match cancellation behaviour is changed.

Developed and verified in staging before promotion. All 32 timing and personal/internal competition tests pass in staging and production. Shared Dart comparison passes. Source amendment is confined to fixture_details_page.dart; previous production content was checked against its saved hash before copying. Unrelated working changes were preserved. This task adds no database or Edge Function amendment; calendar lifecycle handling remains the already-deployed shared implementation.

Production Windows build status is recorded under tmp/member-reschedule/production-build.log. Restart/hot restart staging to load the new UI; reopen the updated production Windows app after a successful build. No iOS/TestFlight/store release was made.
