import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MemberEditScreen extends StatefulWidget {
  final String memberProfileId;
  final Map<String, dynamic> initial;

  const MemberEditScreen({
    super.key,
    required this.memberProfileId,
    required this.initial,
  });

  @override
  State<MemberEditScreen> createState() => _MemberEditScreenState();
}

class _MemberEditScreenState extends State<MemberEditScreen> {
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _email;
  late final TextEditingController _phone;

  late final TextEditingController _a1;
  late final TextEditingController _a2;
  late final TextEditingController _town;
  late final TextEditingController _county;
  late final TextEditingController _postcode;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;

    _firstName = TextEditingController(text: (i['first_name'] ?? '').toString());
    _lastName  = TextEditingController(text: (i['last_name'] ?? '').toString());
    _email     = TextEditingController(text: (i['email_address'] ?? '').toString());
    _phone     = TextEditingController(text: (i['phone'] ?? '').toString());

    _a1       = TextEditingController(text: (i['address_line1'] ?? '').toString());
    _a2       = TextEditingController(text: (i['address_line2'] ?? '').toString());
    _town     = TextEditingController(text: (i['town_city'] ?? '').toString());
    _county   = TextEditingController(text: (i['county'] ?? '').toString());
    _postcode = TextEditingController(text: (i['postcode'] ?? '').toString());
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _a1.dispose();
    _a2.dispose();
    _town.dispose();
    _county.dispose();
    _postcode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    try {
      final client = Supabase.instance.client;

      final first = _firstName.text.trim();
      final last  = _lastName.text.trim();

      // Optional: keep display_name in sync if you use it elsewhere
      final displayName = [first, last].where((s) => s.isNotEmpty).join(' ').trim();

      await client
          .from('member_profiles')
          .update({
            'first_name': first.isEmpty ? null : first,
            'last_name': last.isEmpty ? null : last,
            'email_address': _email.text.trim().isEmpty ? null : _email.text.trim(),
            'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            'display_name': displayName.isEmpty ? null : displayName,

            'address_line1': _a1.text.trim().isEmpty ? null : _a1.text.trim(),
            'address_line2': _a2.text.trim().isEmpty ? null : _a2.text.trim(),
            'town_city': _town.text.trim().isEmpty ? null : _town.text.trim(),
            'county': _county.text.trim().isEmpty ? null : _county.text.trim(),
            'postcode': _postcode.text.trim().isEmpty ? null : _postcode.text.trim(),
          })
          .eq('id', widget.memberProfileId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Member updated')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String label, TextEditingController c, {TextInputType? type}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: type,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit member'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('Basic details', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _field('First name', _firstName),
          _field('Last name (surname)', _lastName),
          _field('Email', _email, type: TextInputType.emailAddress),
          _field('Phone', _phone, type: TextInputType.phone),

          const SizedBox(height: 12),
          Text('Address', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _field('Address line 1', _a1),
          _field('Address line 2', _a2),
          _field('Town / City', _town),
          _field('County', _county),
          _field('Postcode', _postcode),

          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            label: const Text('Save'),
          ),
        ],
      ),
    );
  }
}