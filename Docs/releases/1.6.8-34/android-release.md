# Windows Android release automation

From the production checkout in PowerShell:

    .\scripts\Build-AndroidRelease.ps1

To check prerequisites without building:

    .\scripts\Build-AndroidRelease.ps1 -ValidateOnly

The command verifies the production package and release signing configuration, checks shared staging/production Dart sources, restores packages, runs the full Flutter test suite, builds the signed production App Bundle and verifies its signature. It uses the version/build in pubspec.yaml and the same feature flags as the iPhone release. It does not increment the version, change database settings, commit other changes or upload the bundle.

Each run writes a dated folder under tmp/releases/android/VERSION-BUILD containing the AAB, checksums/source manifest, available release notes and dependency/test/build/signature logs. Signing passwords are read locally by Gradle; they are not copied into release metadata or Git. The signature check proves the bundle is signed, but its upload certificate must also match Google Play's registered upload certificate.

Before upload, confirm the build number has not already been used in Google Play Console. Upload the generated AAB to the intended testing track first. Review the release notes and test on Android before a production rollout.

Google Play upload is currently manual. Automated upload requires separately configured publishing credentials and a chosen testing track; no publishing credentials are included in this script.

## Adding upload and publishing

Enable the Google Play Android Developer API in a Google Cloud project and create a dedicated publishing service account. In Play Console, invite its email under Users and permissions and grant access only to Total Leisure Bowls. Grant app visibility and testing-track release permissions first; grant production release permission only when production promotion is required. Account administration and financial access are not needed for this workflow.

For local Windows automation, keep the service-account JSON credential outside the repositories and restrict its file access. Pass its path through an environment variable; never paste the key into chat, source files or release notes. The Android keystore signs the app; this separate credential authorises the upload to Google Play.

Recommended workflow: a build/upload command targets Internal testing and includes release notes; a separate explicit promotion command promotes the tested version to production with the selected rollout percentage. Confirm version-code availability and that the signing certificate matches Play before upload. Google review, policy declarations and managed publishing settings can still require action in Play Console.

Setup reference: https://developers.google.com/android-publisher/getting_started

Build reference: https://docs.flutter.dev/deployment/android
