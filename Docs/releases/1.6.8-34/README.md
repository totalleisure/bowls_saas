# Total Leisure Bowls 1.6.8 (34)

Prepared 19 November 2026. Production entry point: lib/main.dart. This candidate includes the changes since 1.6.7 (33) and the booking-screen refinements accepted in staging. See whats-new.txt.

The release is supplied through Git branch `codex/release-1.6.8-34` in the production repository. Existing production amendments since 1.6.7 (33), including player replacement and competition accessibility fixes, are retained alongside the booking, marker and scorecard changes. No database deployment is run by the Mac build script.

## Mac handoff

Use the existing production checkout on the signing Mac. Review and back up local edits first. Preserve the Mac's production secrets, signing configuration, bundle identifier com.totalleisure.bowlssaas and Apple team XX6FPA95YH. Do not use staging_main.dart.

    git status --short
    git fetch origin
    git switch --track origin/codex/release-1.6.8-34
    grep '^version:' pubspec.yaml
    bash docs/releases/1.6.8-34/build-ios-release.sh

If the local branch already exists, switch to it and use `git pull --ff-only`. If local changes block switching, stop and preserve those specific files; do not reset or discard them. A local ios/Podfile.lock change should be backed up and reviewed before deciding whether it should be retained.

The version must read 1.6.8+34. The script builds only. Before upload, check App Store Connect that version/build 1.6.8 (34) is unused; if it has already been used independently, select a new higher build consistently. Windows cannot verify Apple signing or produce a signed iOS archive. Validate the archive in Xcode Organizer, upload for TestFlight, and perform the device checks in testflight-notes.txt. Public Store submission is a separate step.

No database push is required from the Mac. Do not run a blanket migration push: staging and production retain their environment-specific mailbox/worker configuration and migration histories. Production leased-delivery safeguards remain in place. Keep production Rinks and Participation locks unchanged until the new App is available, as agreed with the user.

## Android

The current Android release configuration uses the debug signing key. No Google Play release bundle has been prepared. Production Android signing must be configured with the existing authorised release key before a Store build.

## Validation and deployment

See verification.txt for completed checks, database definition comparison, configuration differences and artifact status. Desktop release builds are prepared separately from Store distribution. No Apple or Google Store upload is included in this preparation.
