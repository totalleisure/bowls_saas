import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'login_autofill_group.dart';
import 'password_recovery_progress.dart';

/// A separate password-change context, shared by code and link recovery.
class RecoveryPasswordForm extends StatefulWidget {
  const RecoveryPasswordForm({
    super.key,
    required this.email,
    required this.onComplete,
    this.onBusyChanged,
    this.onSaved,
    this.updatePassword,
  });

  final String email;
  final VoidCallback onComplete;
  final ValueChanged<bool>? onBusyChanged;
  final VoidCallback? onSaved;
  final Future<void> Function(String)? updatePassword;

  @override
  State<RecoveryPasswordForm> createState() => _RecoveryPasswordFormState();
}

class _RecoveryPasswordFormState extends State<RecoveryPasswordForm> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.email);
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _saving = false;
  bool _saved = false;
  bool _showPassword = false;
  String? _error;

  bool get _apple => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    // Discard the old sign-in/code context before building the new fields.
    TextInput.finishAutofillContext(shouldSave: false);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _saved || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    widget.onBusyChanged?.call(true);
    try {
      if (widget.updatePassword != null) {
        await widget.updatePassword!(_password.text);
      } else {
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(password: _password.text),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is AuthException && error.code == 'same_password'
            ? 'Choose a password different from your old password.'
            : 'Your password was not changed. Check your connection and try again.';
      });
      widget.onBusyChanged?.call(false);
      return;
    }
    if (!mounted) return;
    // Remove the complete group once. Its disposal commits the verified new
    // credentials without a later cancellation or a competing app dialog.
    setState(() {
      _saved = true;
      _saving = false;
    });
    widget.onSaved?.call();
    widget.onBusyChanged?.call(false);
    // Local recovery bookkeeping must not turn a successful server change into
    // an apparent failure or ask the member to submit the same password again.
    try {
      await PasswordRecoveryProgress.clear();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_saved) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, color: Colors.green, size: 48),
          const SizedBox(height: 16),
          Text(
            'Password changed',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          const Text(
            'Your Bowls account now uses your new password. You are signed in.',
          ),
          const SizedBox(height: 12),
          Text(
            _apple
                ? 'If Apple Passwords asks to update or save this password, accept so it remembers your new password for next time.'
                : 'If your password manager asks to update or save this password, accept so it remembers your new password for next time.',
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: widget.onComplete,
            child: const Text('Continue to the app'),
          ),
        ],
      );
    }
    return LoginAutofillGroup(
      onAutofilled: (hints) {
        // Only a platform fill may also confirm a generated password. Ordinary
        // typing must still be confirmed independently to catch mistakes.
        if (_apple &&
            !_saving &&
            !_saved &&
            hints.contains(AutofillHints.newPassword)) {
          _confirmation.value = _password.value;
        }
      }, // Suggestions never submit a password change.
      shouldSaveOnDispose: () => _saved,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Choose a new password with at least 8 characters, then enter it again to confirm. You do not need your old password.',
            ),
            if (_apple) ...[
              const SizedBox(height: 12),
              const Text(
                'You can use a strong password suggested by your iPhone, or type your own new password. Do not select your old saved login.',
              ),
            ],
            const SizedBox(height: 20),
            TextFormField(
              controller: _email,
              readOnly: true,
              autofillHints: const [AutofillHints.username],
              decoration: const InputDecoration(
                labelText: 'Account email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              readOnly: _saving,
              obscureText: !_showPassword,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'New password',
                helperText: 'At least 8 characters',
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value?.length ?? 0) < 8
                  ? 'Enter at least 8 characters.'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _confirmation,
              readOnly: _saving,
              obscureText: !_showPassword,
              autocorrect: false,
              enableSuggestions: false,
              // Give iOS a single account/password pair to save. This field
              // checks typing only; it must not become a second credential.
              autofillHints: _apple ? null : const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Confirm new password',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  value != _password.text || (value?.isEmpty ?? true)
                  ? 'Enter the same new password in both boxes.'
                  : null,
              onFieldSubmitted: (_) => _save(),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show passwords'),
              value: _showPassword,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _showPassword = value!),
            ),
            if (_error != null) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Changing password…' : 'Save new password'),
            ),
          ],
        ),
      ),
    );
  }
}
