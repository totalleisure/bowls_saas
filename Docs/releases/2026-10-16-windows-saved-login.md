# Windows saved login — 16 October 2026

Implemented and tested in staging, then synced to production source. Interactive member acceptance testing is pending. No database, email, notification, Apple entitlement or App Store changes.

The native Windows app now offers to save a verified login and provides Use saved login on the sign-in screen. Password recovery offers to update the stored password immediately after the server accepts it, before leaving the recovery screen. Declining or failure to store never reverses a successful password change. Recovery feedback distinguishes a saved password from one that was not saved.

Storage uses Windows Credential Manager (CredReadW/CredWriteW, generic credentials, current Windows user, local-machine persistence). No password is written to app preferences or files. Native dialogs request consent to save, replace or use a login. Identical credentials do not prompt again. Passwords are never displayed in dialogs or diagnostics. Native temporary buffers are cleared before release where owned by this code. This is a Bowls app integration, not Microsoft account sign-in, Edge synchronization, or Windows Hello authentication.

One login is retained per Windows user per app environment. Saving a different account explicitly asks to replace the previous account. The namespace contains the configured backend hostname, so staging and production never share saved passwords. Successful username sign-in saves the canonical account email when available, matching password recovery. The record can be removed in Control Panel > Credential Manager > Windows Credentials under TotalLeisure.Bowls/<environment>/saved-login. The app only reads its exact target; it does not enumerate unrelated credentials.

Validation:
- Staging: 261 Flutter tests passed; four skipped.
- Production: 388 Flutter tests passed; four skipped.
- Staging Windows debug app built successfully from lib/staging_main.dart.
- Native synthetic-credential smoke test passed save/read/update/environment separation/invalid-value rejection/delete; its temporary records were removed.
- Targeted analysis of service, recovery form and tests passed. Broader auth_screen analysis still reports 15 existing unused/deprecation/style findings; the new code adds none.
- Shared Dart source comparison passed; Windows runner baselines matched before promotion. Environment entry points, executable names and secrets were retained.
- Apple save/update behavior remains on the existing iOS path. Wayne confirmed immediate password-update offers working in staging before this Windows change.

Acceptance on Windows staging:
1. Restart the rebuilt staging app and sign out if already signed in.
2. Sign in manually; accept the save offer. Sign out and choose Use saved login; confirm the account and check successful sign-in.
3. Use Forgotten password, verify the code, and choose a different password. Accept the update offer immediately after success.
4. Sign out and use the saved login; confirm the new password works without typing it.
5. Check that declining a save/update does not block account access. An outdated saved password can be corrected manually on sign-in.
6. On a separate run, check no saved login and Cancel from the account confirmation leave manual sign-in available.

Developer native test (after configuring the Windows build): build target saved_login_store_test in Debug with CMake, then run build/windows/x64/runner/Debug/saved_login_store_test.exe. This target is excluded from normal builds and installation.

References: https://learn.microsoft.com/en-us/windows/win32/api/wincred/nf-wincred-credwritew and https://learn.microsoft.com/en-us/windows/win32/api/wincred/nf-wincred-credreadw.
