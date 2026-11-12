# Mac handoff — 1.6.7 (33)

Use your existing production checkout, preserving its ignored production secrets and Apple signing setup. Check `git status` before switching branches; do not discard local changes automatically.

```bash
git status
git fetch origin
git switch codex/release-1.6.7-33
git pull --ff-only
git log -1 --oneline
grep '^version:' pubspec.yaml
bash Docs/releases/1.6.7-33/build-ios-release.sh
```

The version must be `1.6.7+33`. The script uses `lib/main.dart` and builds an IPA/archive without uploading. Do not use staging_main.dart or copy staging credentials. Keep the production bundle ID `com.totalleisure.bowlssaas` and existing Apple signing team. No database commands are needed on the Mac.

After successful archive/export, open Xcode Organizer, validate version 1.6.7 build 33, and upload to App Store Connect. The archive is under `build/ios/archive`, with the IPA under `build/ios/ipa`. Wait for processing, then assign build 33 to the sub-committee TestFlight group. Use `whats-new-subcommittee.txt` as the release summary and `testflight-notes.txt` as the testing instructions. External testers may require TestFlight review. This task does not submit the build for public App Store release.

If the Mac reports unstaged changes or a signing/licence error, resolve that specific issue before continuing; do not reset the checkout or delete certificates as a routine build step.
