# Bowls Club Auth and Email Patch — OTP Version

This replaces clickable Supabase recovery and email-change links with numeric codes entered inside the app. It avoids localhost, mobile deep-link registration, embedded browser behaviour, and security products that pre-scan one-time links.

## Files to overlay

Copy the `lib` folder into the project, preserving paths.

The patch includes:

- `lib/features/auth/auth_screen.dart`
- `lib/features/auth/auth_gate.dart`
- `lib/features/auth/forgot_password_screen.dart`
- `lib/features/auth/account_security_screen.dart`
- `lib/features/communications/member_options_menu.dart`
- `lib/features/members/member_edit_screen.dart`
- `lib/features/members/members_screen.dart`
- `supabase/migrations/20260718_sync_auth_email_to_member_profiles.sql`

The Android and iOS files are retained from the previous patch, but custom URL handling is no longer required for password recovery or the new code-based email-change flow.

## Supabase dashboard changes

### 1. Reset password template

Go to:

`Authentication -> Emails -> Reset password`

Replace the body with:

```html
<h2>Reset your password</h2>
<p>Enter this one-time code in the Bowls Club app:</p>
<p style="font-size: 28px; font-weight: bold; letter-spacing: 6px;">
  {{ .Token }}
</p>
<p>This code is valid for a limited time and can only be used once.</p>
<p>If you did not request this, you can ignore this email.</p>
```

Do not include `{{ .ConfirmationURL }}` in this template.

### 2. Change email address template

Go to:

`Authentication -> Emails -> Change email address`

Replace the body with:

```html
<h2>Confirm your new email address</h2>
<p>You requested to change your Bowls Club login email to:</p>
<p><strong>{{ .NewEmail }}</strong></p>
<p>Enter this one-time code in the Bowls Club app:</p>
<p style="font-size: 28px; font-weight: bold; letter-spacing: 6px;">
  {{ .Token }}
</p>
<p>This code is valid for a limited time and can only be used once.</p>
<p>If you did not request this change, you can ignore this email.</p>
```

Do not include `{{ .ConfirmationURL }}` in this template.

### 3. Use one confirmation for email changes

Go to:

`Authentication -> Sign In / Providers -> Email`

Turn off **Secure email change** / **Confirm email changes on both addresses**.

The app compensates by requiring the user's current password before requesting the change, then requiring a code sent to the new address.

### 4. Security notifications

Under:

`Authentication -> Emails -> Security`

Enable:

- Password changed
- Email address changed

This gives the old email address a warning after a credential changes.

### 5. URL Configuration

These code-based flows do not use redirect URLs.

The **Site URL** should eventually be a normal public `https://` address, such as the Bowls website. Do not use `localhost` or a custom app scheme as the production Site URL. A custom mobile scheme may remain in Redirect URLs for any other auth flows that still use links.

## Database migration

Run:

`supabase/migrations/20260718_sync_auth_email_to_member_profiles.sql`

This keeps `member_profiles.email_address` aligned with the confirmed Auth email.

## Behaviour

### Forgotten password

1. User enters email.
2. Supabase emails a numeric recovery code.
3. User enters the code in the app.
4. The app verifies it with `OtpType.recovery`.
5. User chooses a new password.

### Signed-in password change

1. User enters current password.
2. App verifies it by signing in again.
3. User chooses and confirms a new password.
4. No email link is involved.

### Signed-in email change

1. User enters current password and the new email twice.
2. App verifies the current password.
3. Supabase sends a code to the new email.
4. User enters the code in the app.
5. The Auth email changes and the SQL trigger synchronises the member profile.

## Test order

1. Run `flutter pub get`.
2. Run `flutter analyze`.
3. Run on Windows or web.
4. Test forgotten password using a newly generated code.
5. Test direct signed-in password change.
6. Test email change using a disposable real email address.
7. Confirm `auth.users.email` and `member_profiles.email_address` match after the email change.
