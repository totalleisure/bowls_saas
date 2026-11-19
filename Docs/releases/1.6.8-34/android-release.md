# Windows Android build and Google Play publishing

Run from C:\src\bowls_saas in PowerShell.

## Next release: one command

Set the version in pubspec.yaml, with a build number greater than every version code already uploaded to Play. Build 34 is already used. Write plain English release notes (1-500 characters, no language tags) in Docs/releases/VERSION-BUILD/play-release-notes.txt and review them before running:

```powershell
.\scripts\Release-Android.ps1 -ReleaseNotesPath .\Docs\releases\VERSION-BUILD\play-release-notes.txt -SubmitForReview
```

Replace VERSION-BUILD with the real folder, for example 1.6.9-35. The script reads the actual version from pubspec.yaml; it never increments it automatically. This command builds, tests, uploads directly to Production and requests review/full rollout after Google approval. Internal testing remains unchanged.

Omit -SubmitForReview to save a Production draft instead. Google approval, policy declarations and managed publishing settings can still require Console action. The script refuses to cancel an existing review. Wait until the current 1.6.8 review finishes before publishing another release. Avoid editing Play Console while automation runs.

## Separate build and upload, or resume after build

```powershell
.\scripts\Build-AndroidRelease.ps1
.\scripts\Publish-AndroidRelease.ps1 -ManifestPath PATH\manifest.json -ReleaseNotesPath PATH\play-release-notes.txt -SubmitForReview
```

Use the manifest from the exact dated output folder printed by the build. Omit -SubmitForReview for a draft. Optional -Track internal explicitly selects Internal testing.

Local checks without Google requests:

```powershell
.\scripts\Build-AndroidRelease.ps1 -ValidateOnly
.\scripts\Publish-AndroidRelease.ps1 -ManifestPath PATH\manifest.json -ReleaseNotesPath PATH\play-release-notes.txt -ValidateOnly
.\scripts\Test-AndroidPublishing.ps1
```

Build checks include production identity/release signing, shared staging/production Dart comparison, full Flutter tests, signature verification and checksum. Uses production lib/main.dart with ACCOUNT_USERNAME_ENABLED, PROFILE_PHOTOS_ENABLED and QUICK_UNLOCK_ENABLED all false, matching iPhone. The uploader checks manifest and exact bundle hash, rejects reused/lower version codes and unfinished target releases, uploads en-GB notes, validates the edit, then commits with ERROR_IF_IN_REVIEW. Play checks the signing certificate on upload. Drafts retain the current completed release; full rollout replaces it.

Build outputs are under tmp/releases/android/VERSION-BUILD/date-time. Publishing writes play-production.json (or play-internal.json). A receipt prevents blind duplicate commits. If it says commit_started, the result may be uncertain: inspect Play Console before retrying. Never delete a receipt without checking whether upload/submission succeeded. Failed edits are removed where possible. Uploads/commits are not automatically retried. Policy failures are reported, never bypassed or retried in a way that cancels another review.

## Sign-in (already configured)

Uses Google Cloud CLI and short-lived service account impersonation; no JSON private key. CLI lookup checks PATH then LOCALAPPDATA\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd. If sign-in expires:

```powershell
& "$env:LOCALAPPDATA\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd" auth login wayne.s.sayers@gmail.com
```

IAM Service Account Credentials API and Google Play Android Developer API must remain enabled in project project-b887e914-dd44-4a28-9ec. Wayne has Service Account Token Creator on bowls-play-publisher@project-b887e914-dd44-4a28-9ec.iam.gserviceaccount.com. That service account has app-specific publishing permissions for totalleisuresolutions.bowls. Tokens stay in memory. Android signing credentials stay local. Organisation policy disabling private key creation remains enabled.

This automation changes no application source or databases. Existing fixture-type configuration differences between staging and production are separate from store publication.

References: [bundle upload](https://developers.google.com/android-publisher/api-ref/rest/v3/edits.bundles/upload), [track releases](https://developers.google.com/android-publisher/api-ref/rest/v3/edits.tracks), [commit and review guard](https://developers.google.com/android-publisher/api-ref/rest/v3/edits/commit).
