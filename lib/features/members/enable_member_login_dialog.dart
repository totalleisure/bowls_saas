import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EnableMemberLoginDialog extends StatefulWidget {
  const EnableMemberLoginDialog({super.key, required this.clubId,
    required this.memberProfileId, this.enableLogin});
  final String clubId;
  final String memberProfileId;
  final Future<Map<String, dynamic>> Function(String email)? enableLogin;
  @override
  State<EnableMemberLoginDialog> createState() => _EnableMemberLoginDialogState();
}
class _EnableMemberLoginDialogState extends State<EnableMemberLoginDialog> {
  final _email = TextEditingController();
  bool _busy = false;
  bool _enabled = false;
  bool _sent = false;
  String? _error;
  @override
  void dispose() { _email.dispose(); super.dispose(); }
  Future<void> _enable() async {
    if (_busy) return;
    final email = _email.text.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _error = 'Enter the member’s unique email address.'); return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final result = widget.enableLogin != null ? await widget.enableLogin!(email)
        : Map<String, dynamic>.from((await Supabase.instance.client.functions.invoke(
          'enable-member-login', body: {'club_id': widget.clubId,
            'member_profile_id': widget.memberProfileId, 'email': email})).data as Map);
      if (result['enabled'] != true) throw Exception('App access was not enabled.');
      if (mounted) setState(() { _enabled = true; _sent = result['setup_sent'] == true; });
    } on FunctionException catch (e) {
      if (mounted) setState(() => _error = e.details is Map
        ? e.details['error']?.toString() : 'Could not enable app access. Refresh and check before retrying.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to confirm app access. Refresh and check before retrying.');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !_busy && !_enabled, child: AlertDialog(
    title: Text(_enabled ? 'App login enabled' : 'Enable app login'),
    content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(
      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (!_enabled) ...[
        const Text('Add a unique email for this member. Their existing membership, selections and history will be kept. This sends a code so they can choose their own password.'),
        const SizedBox(height: 12),
        TextField(controller: _email, enabled: !_busy, keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Member email address')),
      ] else ...[
        Text(_sent ? 'A password-setup code has been sent to ${_email.text.trim()}.'
          : 'Their login is enabled, but the setup email could not be confirmed. Their membership has been kept.'),
        const SizedBox(height: 12),
        const Text('Ask the member to open Forgotten password on the Bowls sign-in screen, enter this email, request a fresh code and follow the steps to choose a password. They do not need to register again.'),
      ],
      if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (_busy) const LinearProgressIndicator(),
    ]))),
    actions: [
      if (!_enabled) TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
      if (!_enabled) FilledButton(onPressed: _busy ? null : _enable, child: const Text('Enable login and send code')),
      if (_enabled) FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Done')),
    ],
  ));
}
