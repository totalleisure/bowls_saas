# Password recovery usability — 16 October 2026

Status: revised after Wayne's iPhone test found that reset succeeded but Apple only updated the saved password at the next manual login. The revised native field configuration is regression-tested; immediate Apple update remains pending iPhone verification.

Both recovery routes use one RecoveryPasswordForm with a read-only account email, new-password and confirmation fields, visible eight-character guidance, inline validation, and a Show passwords checkbox. iPhone guidance distinguishes a new strong-password suggestion from the old saved login.

The form clears the previous native AutoFill context on entry. On iOS it exposes only the account and one new-password field to AutoFill; the confirmation field is excluded from native AutoFill but still validates manual typing. A platform-filled password also fills confirmation, without submitting. Other platforms retain both new-password hints. Fields stay registered while the server request runs. Only a successful account update removes the group with a single commit; failures and abandoned forms cancel. A persistent confirmation screen replaces the modal dialog and explains accepting the password manager's update/save offer before Continue to the app. Local bookkeeping errors do not report that an already successful password change failed.

Rationale: Flutter issue https://github.com/flutter/flutter/issues/148151 reports inconsistent iOS save/update prompts with multiple password fields. This is a plausible cause, not a confirmed diagnosis for this device. The change uses Flutter's documented null autofillHints exclusion: https://api.flutter.dev/flutter/material/TextField/autofillHints.html. No native prompt can be verified by the widget suite.

The code-entry field also declares its one-time-code purpose. No email templates, live accounts, database settings, password policies or backend functions were changed.

Validation: staging 254 and production 381 Flutter tests passed, four skipped in each. Shared Dart source comparison passed. Five recovery widget tests cover the single native credential pair, generated-password confirmation without submission, independent manual confirmation, invalid inputs, an asynchronous successful update with exactly one native save, and a rejected password followed by cancellation. Targeted staging static analysis passed. The small-phone layout is exercised in these tests. Native Apple prompt choice/wording remains controlled by iOS and must be checked on the actual iPhone.

Retest: request and verify a recovery code; confirm the correct account email; choose a new password (or accept an iPhone-generated one), confirm it, save, accept Apple's update/save offer, continue, then sign out and reuse the saved login. Confirm that a mismatch is explained beside the field and never submits an update. Do not create a Passwords entry manually to pass this test.
