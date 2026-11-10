import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminEmailChangeDialog extends StatefulWidget {
  const AdminEmailChangeDialog({
    super.key,
    required this.clubId,
    required this.memberProfileId,
    required this.memberName,
    required this.currentEmail,
    this.changeEmail,
  });
  final String clubId, memberProfileId, memberName, currentEmail;
  final Future<String> Function(String email)? changeEmail;
  @override
  State<AdminEmailChangeDialog> createState() => _AdminEmailChangeDialogState();
}

class _AdminEmailChangeDialogState extends State<AdminEmailChangeDialog> {
  final _email = TextEditingController(), _confirm = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _email.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final email = _email.text.trim().toLowerCase(),
        confirm = _confirm.text.trim().toLowerCase();
    if (email.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (email != confirm) {
      setState(() => _error = 'The new email addresses do not match.');
      return;
    }
    if (email == widget.currentEmail.trim().toLowerCase()) {
      setState(() => _error = 'Enter a different email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      String changed;
      if (widget.changeEmail != null) {
        changed = await widget.changeEmail!(email);
      } else {
        final response = await Supabase.instance.client.functions.invoke(
          'admin-change-member-email',
          body: {
            'club_id': widget.clubId,
            'member_profile_id': widget.memberProfileId,
            'expected_email': widget.currentEmail,
            'email': email,
          },
        );
        final data = Map<String, dynamic>.from(response.data as Map);
        if (data['changed'] != true || data['email'] is! String) {
          throw StateError(
            'Email change could not be verified. Refresh the member record.',
          );
        }
        changed = data['email'] as String;
      }
      if (changed.trim().toLowerCase() != email) {
        throw StateError(
          'Email change could not be verified. Refresh the member record.',
        );
      }
      if (mounted) Navigator.pop(context, changed);
    } on FunctionException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.details is Map
              ? (e.details['error'] ?? 'Email was not changed.').toString()
              : 'Unable to verify the change. Refresh the member record.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is StateError
              ? e.message.toString()
              : 'Unable to verify the change. Refresh the member record before trying again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Change member login email'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.memberName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text('Current email: ${widget.currentEmail}'),
            const SizedBox(height: 12),
            const Text(
              'This changes the login and contact email for every club linked to this account. The member will sign in with the new address and their existing password.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textCapitalization: TextCapitalization.none,
              decoration: const InputDecoration(
                labelText: 'New login email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textCapitalization: TextCapitalization.none,
              decoration: const InputDecoration(
                labelText: 'Confirm new email',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Changing…' : 'Change email'),
        ),
      ],
    ),
  );
}
