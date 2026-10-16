import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

String generateMemberPassword() {
  const letters = 'abcdefghijklmnopqrstuvwxyz';
  final random = Random.secure();
  final first = letters[random.nextInt(letters.length)].toUpperCase();
  final remaining = List.generate(2, (_) => letters[random.nextInt(letters.length)]).join();
  final digits = List.generate(5, (_) => random.nextInt(10)).join();
  return '$first$remaining$digits';
}

class AdminPasswordResetDialog extends StatefulWidget {
  const AdminPasswordResetDialog({
    super.key,
    required this.clubId,
    required this.memberProfileId,
    required this.memberName,
    this.resetPassword,
  });
  final String clubId;
  final String memberProfileId;
  final String memberName;
  final Future<String> Function(String password)? resetPassword;
  @override
  State<AdminPasswordResetDialog> createState() =>
      _AdminPasswordResetDialogState();
}

class _AdminPasswordResetDialogState extends State<AdminPasswordResetDialog> {
  final _password = TextEditingController(text: generateMemberPassword());
  bool _busy = false;
  bool _visible = false;
  String? _email;
  String? _error;
  String get _message =>
      'Your Bowls Club App login has been updated.\n'
      'Email: $_email\nPassword: ${_password.text}\n'
      'Use these details to sign in.';
  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    if (_busy) return;
    if (_password.text.length < 8 || _password.text.length > 128) {
      setState(() => _error = 'Use a password of 8–128 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.resetPassword != null) {
        final email = await widget.resetPassword!(_password.text);
        if (mounted)
          setState(() {
            _email = email;
            _visible = true;
          });
        return;
      }
      final response = await Supabase.instance.client.functions.invoke(
        'admin-reset-password',
        body: {
          'club_id': widget.clubId,
          'member_profile_id': widget.memberProfileId,
          'password': _password.text,
        },
      );
      final result = Map<String, dynamic>.from(response.data as Map);
      if (result['reset'] != true) throw Exception('Password reset failed.');
      if (mounted)
        setState(() {
          _email = result['email'] as String;
          _visible = true;
        });
    } on FunctionException catch (e) {
      if (mounted)
        setState(
          () => _error = e.details is Map
              ? (e.details['error'] ?? 'Password was not changed.').toString()
              : 'Password was not changed. Please try again.',
        );
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Unable to confirm the reset. Check the connection before trying again.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deliver(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Could not open sharing. You can copy the login details instead.',
        );
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text('Reset password — ${widget.memberName}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _email == null
                    ? 'This replaces the member’s login password for all their clubs. They will not be required to change it.'
                    : 'Password updated for $_email. Copy or share the details before closing.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _password,
                readOnly: _email != null,
                enabled: !_busy,
                obscureText: !_visible,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'New password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _visible ? 'Hide password' : 'Show password',
                    onPressed: () => setState(() => _visible = !_visible),
                    icon: Icon(
                      _visible ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                ),
              ),
              if (_email == null)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(
                          () => _password.text = generateMemberPassword(),
                        ),
                  child: const Text('Generate another password'),
                ),
              if (_email != null)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy login details'),
                      onPressed: () => _deliver(() async {
                        await Clipboard.setData(ClipboardData(text: _message));
                        if (context.mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Login details copied.'),
                            ),
                          );
                      }),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.share),
                      label: const Text('Share'),
                      onPressed: () => _deliver(() async {
                        final box = context.findRenderObject() as RenderBox?;
                        await Share.share(
                          _message,
                          sharePositionOrigin: box == null
                              ? null
                              : box.localToGlobal(Offset.zero) & box.size,
                        );
                      }),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.email_outlined),
                      label: const Text('Email'),
                      onPressed: () => _deliver(() async {
                        final uri = Uri(
                          scheme: 'mailto',
                          path: _email,
                          query:
                              'subject=${Uri.encodeComponent('Bowls Club App login details')}&body=${Uri.encodeComponent(_message)}',
                        );
                        if (!await launchUrl(uri))
                          throw Exception('Email unavailable');
                      }),
                    ),
                  ],
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(_email == null ? 'Cancel' : 'Done'),
        ),
        if (_email == null)
          FilledButton(
            onPressed: _busy ? null : _reset,
            child: Text(_busy ? 'Resetting…' : 'Reset password'),
          ),
      ],
    ),
  );
}
