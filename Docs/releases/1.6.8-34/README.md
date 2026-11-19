# Total Leisure Bowls 1.6.8 (34)

Prepared 19 November 2026. Production entry point: lib/main.dart. This candidate includes the changes since 1.6.7 (33) and the booking-screen refinements accepted in staging. See whats-new.txt.

The release is supplied through Git branch `codex/release-1.6.8-34` in the production repository. Existing production amendments since 1.6.7 (33), including player replacement and competition accessibility fixes, are retained alongside the booking, marker and scorecard changes. No database deployment is run by the Mac build script.

## Mac handoff

Use the existing production checkout on the signing Mac. Review and back up local edits first. Preserve the Mac's production secrets, signing configuration, bundle identifier com.totalleisure.bowlssaas and Apple team XX6FPA95YH. Do not use staging_main.dart.

    git status --short
    git fetch origin
    git switch --track origin/codex/release-1.6.8-34
    grep '^version:' pubspec.yaml
    bash Docs/releases/1.6.8-34/build-ios-release.sh

If the local branch already exists, switch to it and use `git pull --ff-only`. If local changes block switching, stop and preserve those specific files; do not reset or discard them. A local ios/Podfile.lock change should be backed up and reviewed before deciding whether it should be retained.

The version must read 1.6.8+34. The script builds only. Before upload, check App Store Connect that version/build 1.6.8 (34) is unused; if it has already been used independently, select a new higher build consistently. Windows cannot verify Apple signing or produce a signed iOS archive. Validate the archive in Xcode Organizer, upload for TestFlight, and perform the device checks in testflight-notes.txt. Public Store submission is a separate step.

No database push is required from the Mac. Do not run a blanket migration push: staging and production retain their environment-specific mailbox/worker configuration and migration histories. Production leased-delivery safeguards remain in place. Keep production Rinks and Participation locks unchanged until the new App is available, as agreed with the user.

Reusable iPhone build/upload/review automation is documented in ios-automation.md. The original build-ios-release.sh remains the historical version-specific build command; use scripts/release_ios.py for future automated releases after the Mac/API key setup has been verified.

## Android

Android release signing is configured with the existing release key. The verified production bundle for 1.6.8 (34) was built, uploaded through Play Console and submitted for Production review on 19 November 2026. See android-release.md for the one-command build, upload and optional review submission workflow for future releases. Version code 34 must not be reused.

## Validation and deployment

See verification.txt for the original preparation checks, database comparison and configuration differences. Desktop release builds are prepared separately from Store distribution. Subsequent Apple API verification on 19 November shows iPhone 1.6.8 waiting for review with automatic release after approval, and build 34 already assigned to external TestFlight group LCPIBC Testing while beta review is pending; see apple-distribution-status.md. Android 1.6.8 (34) has been submitted for review, with availability not yet confirmed. Windows 1.6.8.0 has been submitted for certification with automatic publication after approval; see windows-store-release.md.
