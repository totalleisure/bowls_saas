#!/usr/bin/env bash
set -euo pipefail
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'Run this on the signing Mac with Xcode installed.' >&2
  exit 1
fi
grep -q '^version: 1.6.7+33$' pubspec.yaml || { echo 'Wrong source version.' >&2; exit 1; }
xcodebuild -version
flutter --version
flutter pub get
(cd ios && pod install)
flutter build ipa --release --target=lib/main.dart --build-name=1.6.7 --build-number=33 \
  --dart-define=ACCOUNT_USERNAME_ENABLED=false \
  --dart-define=PROFILE_PHOTOS_ENABLED=false \
  --dart-define=QUICK_UNLOCK_ENABLED=false
echo 'Archive: build/ios/archive; IPA: build/ios/ipa. Validate in Xcode before upload.'
