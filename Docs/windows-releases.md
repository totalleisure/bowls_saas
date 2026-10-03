# Windows releases

## Release identities

The recorded member release is **1.5.2+23**, source commit
`7fb06ad3641e52e9eb3e6d3d54ca14c943fd1447`.

The local audit development code is now **1.5.3+24**. Changing the version does
not make it compatible with an older production database. Do not distribute
that version until the seven migrations listed in `audit-journal-review.md`
have been reviewed, applied and verified in production, and the affected
fixture and administration workflows have been tested. Deploy the matching
member-import Edge Function after its audit procedure exists if releasing
that server change as well.

`flutter run -d windows` runs the current checkout in debug mode. It does not
retrieve a released version, choose a database by version number, or isolate
development data. `lib/secrets.dart` determines the backend. The current
production working folder's configuration points at production; use the
separate staging project and its staging configuration to test audit changes.

## Building the member release

Export the exact recorded release commit into a separate build folder; do not
reset the development checkout. Supply only the intended client configuration
in the ignored `lib/secrets.dart`. Never use a service-role or server secret key
in the application. Retain the committed dependency lockfile.

Run `flutter pub get`, `flutter test --no-pub`, and
`flutter build windows --release --no-pub --dart-define=QUICK_LOGINS=false`.
Check that the resulting executable has version `1.5.2.23` and package the
whole Release directory, including plugins, assets and data.

`windows/installer/bowls-windows.iss` builds a per-user x64 Windows installer
using Inno Setup 6.7.3. Supply compiler defines `ReleaseDir`, `RuntimeDir` and
`OutputDir`; `RuntimeDir` must contain the redistributable x64 Visual C++ CRT
matching the compiler. `AppVersion` and `BuildNumber` default to 1.5.2 and 23.
Keep the installer AppId stable across future updates. The installer adds a
Start menu shortcut, an optional desktop shortcut and a Windows uninstaller.
It preserves application settings on uninstall and uses app-local runtime DLLs.

Verify installation, launching, upgrading and uninstalling before distribution.
An unsigned installer can produce Windows publisher/SmartScreen warnings;
use a trusted code-signing certificate for a signed distribution when available.

Do not change production minimum-version policy simply because a package was
built. Follow the tester distribution and policy order in
`../lib/docs/production_readiness.md`. Record the commit, build tools, installer
SHA-256 and test results alongside every distributed package. Future changes
must receive a new version/build number rather than reusing a released identity.
