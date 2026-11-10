# Cancelled fixture operational fields are read-only

Some operational permission getters checked administrator/superuser authority without checking cancellation. This left preselected players/markers and Fixture Settings editable even though timing, rink maintenance and the team section already had cancellation checks.

Fixture Details now requires an active fixture for editing its label/team, dress code, instructions/information, RSVP, administrative fixture details, preselected players/opponents/markers and team management. Administrative authority is retained separately for read-only attendance summaries. Settings and existing assignments remain visible for authorised admins/captains on cancelled fixtures. Existing explicit deletion and copying/repeat actions keep their own rules; this correction does not change administrative cleanup routines or database policies.

Manage Team independently treats a cancelled fixture snapshot as read-only even if its caller omits readOnly. This also disables selection changes, reminders, publishing and force-acceptance through its existing action guards.

Verified staging first, then promoted the two reviewed shared Dart files and a new UI regression test to production. Tests exercise the actual FixtureDetailsPage with authenticated admin/superuser clients, comparing active and cancelled fixtures. Cancelled settings fields, player/marker buttons and marker toggles are disabled while settings and the assignments card remain visible. Active controls remain editable. Direct entry to a cancelled ManageTeamScreen does not create a draft or expose publishing. Targeted team/preselect/cancellation suite: 13 passed in staging and 13 in production. Shared App source comparison passed. Existing unrelated lint/deprecation notices were not reformatted or repaired.

Source-only App change: no database or Edge deployment, store release, commit, push or version change. Restart the local Flutter App for review. Installed store builds need a later release.
