#!/usr/bin/env bash
set -euo pipefail
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'This build must run on the signing Mac with Xcode installed.' >&2
  exit 1
fi
grep -q '^version: 1.6.6+32$' pubspec.yaml || { echo 'Wrong source version.' >&2; exit 1; }
xcodebuild -version
flutter --version
flutter pub get
(cd ios && pod install)
flutter build ipa --release --target=lib/main.dart --build-name=1.6.6 --build-number=32 \
  --dart-define=ACCOUNT_USERNAME_ENABLED=false \
  --dart-define=PROFILE_PHOTOS_ENABLED=false \
  --dart-define=QUICK_UNLOCK_ENABLED=false
echo 'Archive: build/ios/archive; IPA: build/ios/ipa. Validate in Xcode before upload.'
