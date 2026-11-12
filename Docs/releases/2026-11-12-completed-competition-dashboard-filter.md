# Completed competition Dashboard fixtures

Upcoming competition fixtures exclude draw matches whose status is `completed`, including confirmed walkovers, even when the linked fixture still has a future date. The Dashboard's accepted-fixture section also excludes those linked completed matches so they do not reappear as a duplicate. Pending results remain visible until confirmation. Independently booked ordinary fixtures are unaffected; no booking, score, draw, reminder-source data or history is changed.

Staging first: nine focused tests passed, covering future completed/active/pending matches, walkovers, off-App results without a fixture, duplicate suppression, normal fixtures, acceptance states and competition-card rendering. Shared source comparison passed before edits. Windows builds verify the Dashboard call site; only the reviewed helper, Dashboard call and regression test are promoted. No SQL changes or database deployment are required. No emails, commit, version bump or store upload are part of this amendment.

Production verification: the same nine tests pass after promotion; Compare-AppSources.ps1 reports matching shared Dart sources. Staging Windows Release build passed. Production Windows Release build is verified before delivery.
