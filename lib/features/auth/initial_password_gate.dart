import '../clubs/club_online_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'recovery_password_form.dart';

/// Staging-only first-login choice; club invitation acceptance stays separate.
class InitialPasswordGate extends StatefulWidget {
  const InitialPasswordGate({
    super.key,
    required this.child,
    this.loadChoice,
    this.decide,
    this.updatePassword,
    this.email,
  });
  final Widget child;
  final Future<bool> Function()? loadChoice;
  final Future<void> Function(String)? decide;
  final Future<void> Function(String)? updatePassword;
  final String? email;
  @override
  State<InitialPasswordGate> createState() => _InitialPasswordGateState();
}

class _InitialPasswordGateState extends State<InitialPasswordGate> {
  bool _loading = true,
      _checked = false,
      _done = false,
      _changing = false,
      _busy = false,
      _passwordChanged = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // A restored access token can outlive its revoked server-side session.
      // Validate it before offering to change the password.
      if (widget.loadChoice == null) {
        await Supabase.instance.client.auth.getUser();
      }
      final needed =
          await (widget.loadChoice?.call() ??
              Supabase.instance.client
                  .rpc('staging_initial_password_choice')
                  .then((value) => value == true));
      if (mounted) {
        setState(() {
          _done = !needed;
          _checked = true;
          _loading = false;
        });
      }
    } catch (error) {
      if (widget.loadChoice == null && passwordChangeRequiresSignIn(error)) {
        await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
        return;
      }
      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              'Your password choice could not be checked. Please try again.';
        });
      }
    }
  }

  Future<void> _finish(String choice) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.decide != null) {
        await widget.decide!(choice);
      } else {
        await Supabase.instance.client.rpc(
          'complete_staging_initial_password_choice',
          params: {'p_choice': choice},
        );
      }
      if (mounted) {
        setState(() {
          _done = true;
          _busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Your choice could not be saved. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    if (_loading) {
      return const ClubOnlineScaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_checked) {
      return ClubOnlineScaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error ?? 'Your password choice could not be checked.'),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    return ClubOnlineScaffold(
      constrainBody: false,
      appBar: AppBar(
        backgroundColor: const Color(0xff624591),
        foregroundColor: Colors.white,
        title: const Text('Your password'),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: _busy
                ? null
                : () => Supabase.instance.client.auth.signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Material(
                color: Colors.transparent,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) ...[
                      Text(_error!),
                      const SizedBox(height: 16),
                    ],
                    if (_error != null && !_changing && !_busy)
                      TextButton(
                        onPressed: _load,
                        child: const Text('Try again'),
                      ),
                    if (_changing) ...[
                      RecoveryPasswordForm(
                        email:
                            widget.email ??
                            Supabase.instance.client.auth.currentUser!.email!,
                        updatePassword: widget.updatePassword,
                        onBusyChanged: (value) {
                          if (mounted) setState(() => _busy = value);
                        },
                        onSaved: () {
                          if (mounted) {
                            setState(() => _passwordChanged = true);
                          }
                        },
                        onComplete: () => _finish('changed'),
                      ),
                      if (!_passwordChanged)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _changing = false),
                          child: const Text('Back to password choices'),
                        ),
                    ] else ...[
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: const BoxDecoration(
                            color: Color(0xffffe7a0),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.key_outlined,
                            size: 40,
                            color: Color(0xff624591),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Make your password your own',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: const Color(0xff624591),
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'An administrator has provided an initial password. You can change it now, or keep it and continue. The choice is yours.',
                      ),
                      const SizedBox(height: 12),
                      const SizedBox(height: 24),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xff69509b),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: _busy
                            ? null
                            : () => setState(() => _changing = true),
                        child: const Text('Change my password'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: const Color(0xffe8f3e7),
                          foregroundColor: const Color(0xff28642f),
                          side: const BorderSide(color: Color(0xff83ad80)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: _busy ? null : () => _finish('kept'),
                        child: const Text('Keep this password and continue'),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'You can save your login when your device offers. If you change your password, you can save the new one too.',
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'If you have a club invitation, accept it separately in My clubs. Your password choice does not activate club membership.',
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
