# Apple password saving setup — 16 October 2026

## Changes

Runner now declares webcredentials:totalleisure.github.io in its Associated Domains entitlement for Debug, Profile and Release. The separate public repository https://github.com/totalleisure/totalleisure.github.io hosts only verification metadata and an informational page. The existing Google Site stays unchanged.

Association: https://totalleisure.github.io/.well-known/apple-app-site-association
Apple cache: https://app-site-association.cdn-apple.com/a/v1/totalleisure.github.io
App identifier: XX6FPA95YH.com.totalleisure.bowlssaas (from checked-in signing team and bundle ID).

Both endpoints returned HTTP 200 with the expected app identifier on 16 October 2026. Pages serves the extensionless file as application/octet-stream; Apple's CDN successfully accepted it and serves application/json. Preserve .nojekyll in the hosting repository so .well-known remains published.

No database, email, notification, authentication-server or credential-storage changes. The app already requests saving after verified manual sign-in. A new staging regression test verifies that request occurs before login form disposal; it does not prove the native iOS save prompt or persistence.

## Mac and device verification still required

From the existing bowls_staging checkout:

```sh
git switch staging
git pull --ff-only origin staging
flutter pub get
flutter run --debug -t lib/staging_main.dart -d 00008150-000661E801C0401C
```

Stop the previous Flutter run before rebuilding. A hot reload cannot apply native entitlements. Keep the iPhone unlocked and check the staging banner.

If signing reports that the provisioning profile lacks Associated Domains, open ios/Runner.xcworkspace in Xcode, select Runner > Signing & Capabilities and the existing Total Leisure team. Confirm Associated Domains is enabled and let automatic signing refresh the development provisioning profile. Do not change the bundle ID or team to bypass a signing error.

Check the actual signed app after the build:

```sh
codesign -d --entitlements :- build/ios/iphoneos/Runner.app
```

The signed application-identifier must match XX6FPA95YH.com.totalleisure.bowlssaas and com.apple.developer.associated-domains must contain webcredentials:totalleisure.github.io. A different application-identifier prefix requires correcting the hosted file before acceptance.

For a first-save test, use a staging test account with no existing Passwords entry (or remove only its disposable manually created test entry). Enter credentials manually and sign in successfully. Check for a save offer and check Apple Passwords even if no offer appears. Do not manually create an entry to count this as a pass. Then sign out and confirm the saved entry fills the fields and signs in successfully. Incorrect credentials must not create/update an entry.

Native signing and first-time saving must be verified on the Mac/iPhone before production release. Source synchronization is not an App Store deployment. Staging and production currently share a bundle ID, so their installations replace one another on one iPhone.

## Maintenance

Keep the Pages repository/address available for supported app versions. If the Apple signing prefix or bundle ID changes, update the association and verify Apple's cache before release. Do not put passwords, keys, member data or app source in the public verification repository.