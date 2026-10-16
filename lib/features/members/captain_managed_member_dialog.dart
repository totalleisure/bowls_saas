import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CaptainManagedMemberDialog extends StatefulWidget {
  final String clubId;
  final Future<void> Function(Map<String, dynamic>)? saveMember;
  const CaptainManagedMemberDialog({
    super.key,
    required this.clubId,
    this.saveMember,
  });

  @override
  State<CaptainManagedMemberDialog> createState() =>
      _CaptainManagedMemberDialogState();
}

class _CaptainManagedMemberDialogState
    extends State<CaptainManagedMemberDialog> {
  final _form = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _phone = TextEditingController();
  String? _sex;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final params = <String, dynamic>{
        'p_club_id': widget.clubId,
        'p_first_name': _first.text.trim(),
        'p_last_name': _last.text.trim(),
        'p_phone': _phone.text.trim(),
        'p_sex_at_birth': _sex,
      };
      if (widget.saveMember != null) {
        await widget.saveMember!(params);
      } else {
        await Supabase.instance.client.rpc(
          'create_captain_managed_member',
          params: params,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is PostgrestException
              ? e.message
              : 'Could not add the member. Please try again.';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('Add captain-managed member'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'For members contacted by telephone. No login, email or invitation is created. Captains manage availability and acceptance.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _first,
                  enabled: !_saving,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'First name'),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Enter first name' : null,
                ),
                TextFormField(
                  controller: _last,
                  enabled: !_saving,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Last name'),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Enter last name' : null,
                ),
                TextFormField(
                  controller: _phone,
                  enabled: !_saving,
                  maxLength: 40,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Mobile / telephone number',
                  ),
                  validator: (v) {
                    final length = (v ?? '')
                        .replaceAll(RegExp(r'[^0-9]'), '')
                        .length;
                    return length < 7 || length > 15
                        ? 'Enter a valid telephone number'
                        : null;
                  },
                ),
                DropdownButtonFormField<String>(
                  initialValue: _sex,
                  decoration: const InputDecoration(
                    labelText: 'Sex at birth (for match eligibility)',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'male', child: Text('Male')),
                    DropdownMenuItem(value: 'female', child: Text('Female')),
                    DropdownMenuItem(
                      value: 'intersex',
                      child: Text('Intersex'),
                    ),
                    DropdownMenuItem(
                      value: 'prefer_not_to_say',
                      child: Text('Prefer not to say'),
                    ),
                  ],
                  onChanged: _saving ? null : (v) => setState(() => _sex = v),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Telephone number is visible in the club directory. You can change directory visibility in the member record.',
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
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Adding…' : 'Add member'),
        ),
      ],
    ),
  );
}
