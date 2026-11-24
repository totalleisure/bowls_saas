Total Leisure Bowls 1.6.10 (36)

Production source and live database workflow integration verified 24 November 2026.
Shared Dart comparison passed. 88 targeted workflow tests passed in each checkout.
Live rolled-back tests passed in both projects: new-club Friendly defaults, deferred Newsletter enrolment, overlapping availability and rescheduling, selection/acceptance preservation, administrator/member two-rink Internal bookings, and a four-rink Friendly alongside two occupied rinks.
The three Production migrations are 20261124140629, 20261124140641 and 20261124140643. Staging retains its own applied migration history. Only the three project-specific email scheduling functions differ after full live function comparison. No Production-only function amendment was lost. Staging test mail restrictions and Production mailbox/credentials remain separate. Existing security advisory category counts did not increase.
The five previously deployed onboarding/password/email services were checked against their reviewed deployed sources and remain unchanged. No further service upload is needed.
Source recovery, deployed definitions, before/after fingerprints, test logs and environment checksums are retained in staging tmp/release-readiness-2026-11-24. Production manuals retain their non-staging editions.

Public notes include guided new-club setup for Club Secretaries. Committee/TestFlight notes cover other improvements and booking checks, and intentionally omit onboarding.
No blanket database push is needed from any build machine. Preserve Mac signing configuration, ios/Podfile.lock and local scripts/ios/Gemfile.lock.
Store availability must be recorded separately from source and database readiness. Version 1.6.9+35 must not be reused.
