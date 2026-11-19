# iPhone release automation on the signing Mac

Status: prepared and tested offline on Windows. Xcode signing, fastlane installation, Apple key access and a live upload still require verification on Wayne's Mac. The existing iPhone 1.6.8 release is untouched. Do not upload version/build 1.6.8 (34) again.

The new scripts/release_ios.py reads the version/build from pubspec.yaml, runs Flutter tests, builds and exports the production IPA, verifies its identity/version and the archive signature/team, uploads to App Store Connect, waits for processing, writes release notes, selects the exact build and optionally submits for review/automatic release. The production identifier is com.totalleisure.bowlssaas; signing team XX6FPA95YH. Feature flags match Android and the existing iPhone build script. It does not change databases, increment versions, discard local Mac changes, expire older builds or cancel an existing review.

## One-time setup

Use TeamViewer and Terminal on the signing Mac. SSH is optional: it is needed if the Windows agent is to start the Mac command directly in future. No remote Mac connection is currently configured by this task.

1. In App Store Connect, open Users and Access > Integrations > App Store Connect API > Team Keys. Request API access if necessary. Generate a key named Bowls App Store Publisher with App Manager access. Team keys apply across the account's apps; the script explicitly targets only Total Leisure Bowls. Note Key ID and Issuer ID. Download the .p8 once and keep it outside every checkout, for example under ~/.config/bowls. Do not paste the private key into chat or commit it.
2. Preserve existing Mac edits (including ios/Podfile.lock). Fetch and fast-forward the existing codex/release-1.6.8-34 branch; do not reset the checkout. Confirm git status first. The Mac production checkout is /Users/wayne/develop/bowls_saas.
3. Ensure Python 3.9+, Flutter, CocoaPods, Xcode, a supported Ruby (3.2+) and Bundler are installed. If Homebrew is already installed, the following installs Ruby/Python and the isolated publishing dependencies. It does not change Xcode signing credentials:

```bash
cd /Users/wayne/develop/bowls_saas
brew install ruby python
export PATH="$(brew --prefix ruby)/bin:$PATH"
gem install bundler --no-document
BUNDLE_GEMFILE="$PWD/scripts/ios/Gemfile" BUNDLE_PATH="$HOME/.local/share/bowls/gems" bundle install
```

Keep the Homebrew Ruby bin directory on Terminal's PATH for future sessions. Review the generated scripts/ios/Gemfile.lock and commit it after the first successful Mac dependency installation to pin the tested fastlane version. It cannot be generated/verified by the current Windows session.

4. Configure the downloaded key using its real path and IDs:

```bash
python3 scripts/release_ios.py --configure-key "$HOME/.config/bowls/AuthKey_KEYID.p8" --key-id KEYID --issuer-id ISSUERID
```

This creates ~/.config/bowls/app-store-connect.json with mode 600 and will not overwrite existing credentials. It keeps a private copy of the key inside that configuration; retain the original securely. Existing Apple signing certificates/profiles and Xcode account remain required on the Mac.

5. Verify locally, then check Apple read access without changing a release:

```bash
python3 scripts/release_ios.py --notes Docs/releases/1.6.8-34/play-release-notes.txt --validate-only
python3 scripts/release_ios.py --notes Docs/releases/1.6.8-34/play-release-notes.txt --check-apple-access
```

## Future release

Prepare/review source changes in staging, compare staging/production using scripts/Compare-AppSources.ps1 on Windows, preserve production-only amendments, and transfer the reviewed production commit to the Mac. Set the version/build consistently across Android and iPhone, using an unused higher build. Prepare plain English release notes (1-4000 characters) in a release folder. Existing production secrets and Mac signing configuration remain local.

```bash
cd /Users/wayne/develop/bowls_saas
python3 scripts/release_ios.py --notes Docs/releases/1.6.9-35/app-store-release-notes.txt --submit-for-review
```

The example requires the actual new version/build to be set in pubspec.yaml. Omit --submit-for-review to upload and prepare an App Store draft without submitting. Existing screenshots/review details are reused; missing Apple declarations, agreements, review login details or other required metadata can still stop submission and need attention. Automatic release is requested only with --submit-for-review. Apple decides processing/review time and availability.

Each version/build has one attempt folder under tmp/releases/ios/VERSION-BUILD with the IPA, checksum, source commit/local-change inventory, release notes, log and receipt.json. Receipt states record progress before network writes. Any existing attempt blocks blind re-upload. If upload_started or store_update_started remains after an error, inspect App Store Connect: an operation may have succeeded remotely. Do not delete the receipt and retry blindly. A failed upload never proceeds to submission. Build/test failures cannot upload. No automatic retry changes an existing review.

Offline tests: python3 -m unittest discover -s scripts -p test_release_ios.py -v. These cover draft/submission command flow, exact build selection, duplicate receipts, build/upload failures, identity/version checks, key setup and read-only checks. They do not substitute for verification on the signing Mac.

References: [Apple API keys](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/), [fastlane authentication](https://docs.fastlane.tools/app-store-connect-api/), [upload/processing](https://docs.fastlane.tools/actions/upload_to_testflight/), [App Store submission](https://docs.fastlane.tools/actions/upload_to_app_store/).
