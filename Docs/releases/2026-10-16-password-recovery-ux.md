# Password recovery usability — 16 October 2026

Status: implemented and regression-tested; awaiting Wayne's staging iPhone UX retest.

Both recovery routes use one RecoveryPasswordForm with a read-only account email, new-password and confirmation fields, visible eight-character guidance, inline validation, and a Show passwords checkbox. iPhone guidance distinguishes a new strong-password suggestion from the old saved login.

The form clears the previous native AutoFill context on entry and groups the account and both new-password fields together. AutoFill never submits the change. Fields stay registered while the server request runs. Only a successful account update removes the group with a single commit; failures and abandoned forms cancel. A persistent confirmation screen replaces the modal dialog and explains accepting the password manager's update/save offer before Continue to the app. Local bookkeeping errors do not report that an already successful password change failed.

The code-entry field also declares its one-time-code purpose. No email templates, live accounts, database settings, password policies or backend functions were changed.

Validation: staging 253 Flutter tests passed, four skipped; production 380 passed, four skipped. Targeted static analysis passed. Four new widget tests cover paired field configuration and no auto-submit, invalid inputs, an asynchronous successful update with exactly one native save, and a rejected password followed by cancellation. The small-phone layout is exercised in these tests. Native Apple prompt choice/wording remains controlled by iOS and must be checked on the actual iPhone.

Retest: request and verify a recovery code; confirm the correct account email; choose a new password (or accept an iPhone-generated one), confirm it, save, accept Apple's update/save offer, continue, then sign out and reuse the saved login. Confirm that a mismatch is explained beside the field and never submits an update. Do not create a Passwords entry manually to pass this test.