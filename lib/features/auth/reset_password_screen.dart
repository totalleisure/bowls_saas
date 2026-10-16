import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'password_recovery_progress.dart';
import 'recovery_password_form.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.onComplete});
  final VoidCallback onComplete;
  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  bool _saving = false;
  bool _saved = false;

  Future<void> _cancelRecovery() async {
    await Supabase.instance.client.auth.signOut();
    await PasswordRecoveryProgress.clear();
    if (mounted) widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_saved ? 'Password changed' : 'Choose a new password'),
          actions: [
            if (!_saved)
              TextButton(
                onPressed: _saving ? null : _cancelRecovery,
                child: const Text('Cancel'),
              ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: RecoveryPasswordForm(
                      email:
                          Supabase.instance.client.auth.currentUser?.email ??
                          '',
                      onBusyChanged: (busy) {
                        if (mounted) setState(() => _saving = busy);
                      },
                      onSaved: () {
                        if (mounted) setState(() => _saved = true);
                      },
                      onComplete: widget.onComplete,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
