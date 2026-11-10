import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

ButtonStyle memberAccountActionStyle(BuildContext context) =>
    OutlinedButton.styleFrom(
      minimumSize: const Size(0, 40),
      fixedSize: Size(300, MediaQuery.textScalerOf(context).scale(14) * 2 + 12),
      alignment: Alignment.centerLeft,
      textStyle: const TextStyle(fontSize: 14, height: 1),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    );

class AdminConfirmationEmailAction extends StatefulWidget {
  const AdminConfirmationEmailAction({
    super.key,
    required this.clubId,
    required this.memberProfileId,
    this.request,
  });
  final String clubId;
  final String memberProfileId;
  final Future<Map<String, dynamic>> Function(String action, String? email)?
  request;

  @override
  State<AdminConfirmationEmailAction> createState() =>
      _AdminConfirmationEmailActionState();
}

class _AdminConfirmationEmailActionState
    extends State<AdminConfirmationEmailAction> {
  bool _busy = true;
  bool _eligible = false;
  String? _email;
  String? _error;
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<Map<String, dynamic>> _request(String action, [String? email]) async {
    if (widget.request != null) return widget.request!(action, email);
    final response = await Supabase.instance.client.functions.invoke(
      'admin-resend-confirmation',
      body: {
        'club_id': widget.clubId,
        'member_profile_id': widget.memberProfileId,
        'action': action,
        'expected_email': ?email,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  String _message(Object error) {
    if (error is FunctionException && error.details is Map) {
      return (error.details as Map)['error']?.toString() ??
          'Unable to contact the confirmation email service.';
    }
    return 'Unable to contact the confirmation email service. Please try again.';
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final state = await _request('status');
      if (!mounted) return;
      setState(() {
        _eligible = state['eligible'] == true;
        _email = state['email'] as String?;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_busy || !_eligible || _email == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resend confirmation email?'),
        content: Text(
          'Send a new registration confirmation email to $_email? The member must follow its link before signing in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send confirmation'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _request('resend', _email);
      if (!mounted) return;
      if (result['reason'] == 'confirmed') {
        setState(() => _eligible = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This login email is already confirmed.'),
          ),
        );
      } else if (result['sent'] == true && result['email'] == _email) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Confirmation email sent to $_email')),
        );
      } else {
        setState(
          () => _error =
              'The resend was not confirmed. Refresh the member record before trying again.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_busy && !_eligible && _error == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        OutlinedButton.icon(
          style: memberAccountActionStyle(context),
          onPressed: _busy
              ? null
              : _error != null && !_eligible
              ? _check
              : _resend,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                child: Icon(Icons.hourglass_empty, size: 16),
                )
              : const Icon(Icons.mark_email_unread_outlined),
          label: Text(
            _busy
                ? 'Checking confirmation…'
                : _error != null && !_eligible
                ? 'Check confirmation status'
                : 'Resend confirmation email',
          ),
        ),
      ],
    );
  }
}
