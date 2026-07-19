import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccountSecurityScreen extends StatefulWidget {
  const AccountSecurityScreen({super.key});

  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  bool _working = false;

  String get _currentEmail =>
      Supabase.instance.client.auth.currentUser?.email?.trim() ?? '';

  bool _looksLikeEmail(String value) {
    final text = value.trim();
    final at = text.indexOf('@');
    final dot = text.lastIndexOf('.');
    return at > 0 && dot > at + 1 && dot < text.length - 1;
  }

  String _friendlyAuthError(Object error) {
    final text = error.toString().toLowerCase();

    if (text.contains('invalid login credentials') ||
        text.contains('invalid credentials')) {
      return 'The current password was not recognised.';
    }

    if (text.contains('email exists') ||
        text.contains('already registered') ||
        text.contains('already been registered')) {
      return 'That email address is already registered to another account.';
    }

    if (text.contains('expired') ||
        text.contains('invalid') ||
        text.contains('otp')) {
      return 'That confirmation code is invalid or has expired.';
    }

    return error.toString();
  }

  Future<void> _changePassword() async {
    final currentPassword = TextEditingController();
    final newPassword = TextEditingController();
    final confirmPassword = TextEditingController();
    bool showPasswords = false;

    final values = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change password'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: currentPassword,
                  obscureText: !showPasswords,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(
                    labelText: 'Current password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newPassword,
                  obscureText: !showPasswords,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: const InputDecoration(
                    labelText: 'New password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmPassword,
                  obscureText: !showPasswords,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: const InputDecoration(
                    labelText: 'Confirm new password',
                    border: OutlineInputBorder(),
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: showPasswords,
                  title: const Text('Show passwords'),
                  onChanged: (value) {
                    setDialogState(() => showPasswords = value == true);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final current = currentPassword.text;
                final next = newPassword.text;
                final confirm = confirmPassword.text;

                if (current.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter your current password.'),
                    ),
                  );
                  return;
                }

                if (next.length < 8) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Please use a new password of at least 8 characters.',
                      ),
                    ),
                  );
                  return;
                }

                if (next != confirm) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('The two new passwords do not match.'),
                    ),
                  );
                  return;
                }

                Navigator.of(dialogContext).pop([current, next]);
              },
              child: const Text('Change password'),
            ),
          ],
        ),
      ),
    );

    currentPassword.dispose();
    newPassword.dispose();
    confirmPassword.dispose();

    if (values == null || !mounted) return;

    final email = _currentEmail;
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your login email is not available.')),
      );
      return;
    }

    setState(() => _working = true);

    try {
      final client = Supabase.instance.client;

      // Reauthenticate explicitly before changing a sensitive credential.
      await client.auth.signInWithPassword(email: email, password: values[0]);

      await client.auth.updateUser(UserAttributes(password: values[1]));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your password has been changed.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyAuthError(error))));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _changeEmail() async {
    final currentPassword = TextEditingController();
    final newEmail = TextEditingController();
    final confirmEmail = TextEditingController();

    final requested = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change login email'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Current login email: ${_currentEmail.isEmpty ? '(not available)' : _currentEmail}',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: currentPassword,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(
                  labelText: 'Current password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newEmail,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'New email address',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmEmail,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Confirm new email address',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'A one-time code will be sent to the new address. The email '
                'will not change until that code is entered in the app.',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final password = currentPassword.text;
              final first = newEmail.text.trim();
              final second = confirmEmail.text.trim();

              if (password.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter your current password.'),
                  ),
                );
                return;
              }

              if (!_looksLikeEmail(first)) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid email address.'),
                  ),
                );
                return;
              }

              if (first.toLowerCase() != second.toLowerCase()) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('The two email addresses do not match.'),
                  ),
                );
                return;
              }

              if (first.toLowerCase() == _currentEmail.toLowerCase()) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('That is already your login email address.'),
                  ),
                );
                return;
              }

              Navigator.of(dialogContext).pop([password, first]);
            },
            child: const Text('Send code'),
          ),
        ],
      ),
    );

    currentPassword.dispose();
    newEmail.dispose();
    confirmEmail.dispose();

    if (requested == null || !mounted) return;

    final oldEmail = _currentEmail;
    final proposedEmail = requested[1];

    setState(() => _working = true);

    try {
      final client = Supabase.instance.client;

      await client.auth.signInWithPassword(
        email: oldEmail,
        password: requested[0],
      );

      // The Supabase Change Email template must contain {{ .Token }} rather
      // than a clickable confirmation link. Secure email change should be
      // disabled so a single code is sent to the new address.
      await client.auth.updateUser(UserAttributes(email: proposedEmail));

      if (!mounted) return;
      setState(() => _working = false);

      await _verifyEmailChangeCode(proposedEmail);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyAuthError(error))));
    } finally {
      if (mounted && _working) setState(() => _working = false);
    }
  }

  Future<void> _verifyEmailChangeCode(String newEmail) async {
    final code = TextEditingController();

    final enteredCode = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm new email'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter the confirmation code sent to $newEmail.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: code,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: const InputDecoration(
                  labelText: 'Confirmation code',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = code.text.trim();
              if (value.length < 6) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter the code from the email.'),
                  ),
                );
                return;
              }
              Navigator.of(dialogContext).pop(value);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    code.dispose();

    if (enteredCode == null || !mounted) return;

    setState(() => _working = true);

    try {
      final client = Supabase.instance.client;

      final response = await client.auth.verifyOTP(
        email: newEmail,
        token: enteredCode,
        type: OtpType.emailChange,
      );

      final confirmedEmail = (response.user?.email ?? newEmail).trim();

      // auth.users is the master value. The database trigger normally mirrors
      // it into member_profiles immediately. Also perform the same mirror here
      // after successful OTP verification so the current UI and member list do
      // not depend on trigger timing. This does not change the login identity;
      // it only copies the already-confirmed Auth email into the profile row.
      final userId = response.user?.id ?? client.auth.currentUser?.id;
      if (userId != null && confirmedEmail.isNotEmpty) {
        try {
          await client
              .from('member_profiles')
              .update({'email_address': confirmedEmail})
              .eq('user_id', userId);
        } catch (error) {
          // The database trigger remains the authoritative synchronisation
          // route. Do not report the confirmed Auth change as failed merely
          // because this immediate UI mirror was blocked or delayed.
          debugPrint('Immediate profile email mirror failed: $error');
        }
      }

      if (!mounted) return;
      setState(() {});

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(
            Icons.check_circle_outline,
            color: Colors.green.shade700,
            size: 48,
          ),
          title: const Text('Email address changed'),
          content: Text(
            'Your login email is now $newEmail. Use that address the next time you sign in.',
            textAlign: TextAlign.center,
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      // Return the exact confirmed email to the opening screen. Passing the
      // value itself avoids another immediate database read returning the old
      // cached/controller value while the screen transition is taking place.
      if (mounted) {
        Navigator.of(context).pop(confirmedEmail);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyAuthError(error))));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = _currentEmail;

    return Scaffold(
      appBar: AppBar(title: const Text('Account and Security')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Login email',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: ValueKey(email),
                    initialValue: email,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Current email address',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This is your platform login email. Changing it affects '
                    'every bowls club connected to this account.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _working ? null : _changeEmail,
                    icon: const Icon(Icons.alternate_email),
                    label: const Text('Change login email'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_reset_outlined),
              title: const Text('Change password'),
              subtitle: const Text(
                'Verify your current password and choose a new one in the app',
              ),
              trailing: _working
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _working ? null : _changePassword,
            ),
          ),
        ],
      ),
    );
  }
}
