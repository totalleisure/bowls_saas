import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MemberEditScreen extends StatefulWidget {
  final String memberProfileId;
  final Map<String, dynamic> initial;

  final String clubId;
  final String initialRole;
  final bool initialActive;
  final bool canManageMembers;

  final bool initialIsCoach;
  final String? initialCoachingAward;

  const MemberEditScreen({
    super.key,
    required this.memberProfileId,
    required this.initial,
    required this.clubId,
    required this.initialRole,
    required this.initialActive,
    required this.canManageMembers,
    required this.initialIsCoach,
    this.initialCoachingAward,
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

  late final TextEditingController _genderSelfDescribed;

  late bool _isCoach;
  late final TextEditingController _coachingAward;

  String? _gender;
  String? _sexAtBirth;
  String? _preferredPosition;

  late String _role;
  late bool _active;

  bool _saving = false;

  bool _hasUnsavedChanges = false;

  String? _originalRole;

  void _markDirty() {
    if (_hasUnsavedChanges) return;
    setState(() => _hasUnsavedChanges = true);
  }

  @override
  void initState() {
    super.initState();
    final i = widget.initial;

    _firstName = TextEditingController(
      text: (i['first_name'] ?? '').toString(),
    );
    _lastName = TextEditingController(text: (i['last_name'] ?? '').toString());
    _email = TextEditingController(text: (i['email_address'] ?? '').toString());
    _phone = TextEditingController(text: (i['phone'] ?? '').toString());

    _a1 = TextEditingController(text: (i['address_line1'] ?? '').toString());
    _a2 = TextEditingController(text: (i['address_line2'] ?? '').toString());
    _town = TextEditingController(text: (i['town_city'] ?? '').toString());
    _county = TextEditingController(text: (i['county'] ?? '').toString());
    _postcode = TextEditingController(text: (i['postcode'] ?? '').toString());
    _gender = i['gender']?.toString();
    _sexAtBirth = i['sex_at_birth']?.toString();
    _preferredPosition = i['preferred_position']?.toString();
    _genderSelfDescribed = TextEditingController(
      text: (i['gender_self_described'] ?? '').toString(),
    );
    _role = widget.initialRole;
    _originalRole = _role;
    _active = widget.initialActive;
    _isCoach = widget.initialIsCoach;
    _coachingAward = TextEditingController(
      text: widget.initialCoachingAward ?? '',
    );
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
    _genderSelfDescribed.dispose();
    _coachingAward.dispose();
    super.dispose();
  }

  String _backgroundAsset(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (width >= 1100) {
      return 'assets/images/blank_bg_desktop_2.png';
    }

    if (width >= 700) {
      return 'assets/images/blank_bg_tablet_2.png';
    }

    return 'assets/images/blank_bg_phone_2.png';
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final client = Supabase.instance.client;

      final first = _firstName.text.trim();
      final last = _lastName.text.trim();
      final displayName = [
        first,
        last,
      ].where((s) => s.isNotEmpty).join(' ').trim();

      final payload = <String, dynamic>{
        'first_name': first.isEmpty ? null : first,
        'last_name': last.isEmpty ? null : last,
        'email_address': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'display_name': displayName.isEmpty ? null : displayName,
        'address_line1': _a1.text.trim().isEmpty ? null : _a1.text.trim(),
        'address_line2': _a2.text.trim().isEmpty ? null : _a2.text.trim(),
        'town_city': _town.text.trim().isEmpty ? null : _town.text.trim(),
        'county': _county.text.trim().isEmpty ? null : _county.text.trim(),
        'postcode': _postcode.text.trim().isEmpty
            ? null
            : _postcode.text.trim(),
        'gender': _gender,
        'gender_self_described': _gender == 'prefer_to_self_describe'
            ? (_genderSelfDescribed.text.trim().isEmpty
                  ? null
                  : _genderSelfDescribed.text.trim())
            : null,
        'sex_at_birth': _sexAtBirth,
        'preferred_position': _preferredPosition,
      };

      //      debugPrint('Saving member_profile_id=${widget.memberProfileId}');
      //      debugPrint('Payload=$payload');

      final updated = await client
          .from('member_profiles')
          .update(payload)
          .eq('id', widget.memberProfileId)
          .select('id, first_name, last_name, email_address, display_name');

      //      debugPrint('Update returned: $updated');

      final check = await client
          .from('member_profiles')
          .select('first_name, last_name, email_address, display_name')
          .eq('id', widget.memberProfileId)
          .maybeSingle();

      if (widget.canManageMembers) {
        await client
            .from('club_memberships')
            .update({
              'role': _role,
              'is_active': _active,
              'is_coach': _isCoach,
              'coaching_award': _coachingAward.text.trim().isEmpty
                  ? null
                  : _coachingAward.text.trim(),
            })
            .eq('club_id', widget.clubId)
            .eq('member_profile_id', widget.memberProfileId);

        final promotedGuestToMember =
            (_originalRole ?? '').toLowerCase() == 'guest' &&
            (_role ?? '').toLowerCase() == 'member';

        if (promotedGuestToMember) {
          // Club name
          final clubRow = await client
              .from('clubs')
              .select('name')
              .eq('id', widget.clubId)
              .single();

          final clubName = (clubRow['name'] ?? 'the club').toString();

          // Current admin profile
          final myProfileId = (await client.rpc(
            'my_member_profile_id',
          )).toString();

          final adminRow = await client
              .from('member_profiles')
              .select('display_name')
              .eq('id', myProfileId)
              .maybeSingle();

          final adminName = (adminRow?['display_name'] ?? 'Club Administrator')
              .toString();

          // Queue notification/event
          await client.from('notification_queue').insert({
            'event_type': 'guest_membership_approved',
            'member_profile_id': myProfileId,
            'target_member_profile_id': widget.memberProfileId,
            'payload': {
              'club_id': widget.clubId,
              'club_name': clubName,
              'approved_by': adminName,
            },
            'status': 'pending',
          });
        }
      }

      //      debugPrint('Post-save row: $check');

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Member updated')));
      setState(() => _hasUnsavedChanges = false);
      Navigator.pop(context, true);
    } catch (e) {
      //      debugPrint('SAVE FAILED: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
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
        onChanged: (_) => _markDirty(),
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
          ),
          floatingLabelStyle: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w700,
          ),
          border: const OutlineInputBorder(),
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.black54),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.black, width: 2),
          ),
          isDense: true,
        ),
      ),
    );
  }

  Widget _dropdownField({
    required String label,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
    String? helperText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        items: items,
        onChanged: onChanged,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          isDense: true,
          labelText: label,
          helperText: helperText,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || !_hasUnsavedChanges) return;

        final leave = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Discard changes?'),
            content: const Text('Your unsaved changes will be lost.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        );

        if (leave == true && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(_backgroundAsset(context)),
            fit: BoxFit.cover,
          ),
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(title: const Text('Edit member')),
          floatingActionButton: _hasUnsavedChanges
              ? FloatingActionButton.extended(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Save'),
                )
              : null,
          body: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.88),
              borderRadius: BorderRadius.circular(20),
            ),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active member'),
                  value: _active,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _active = value;
                    });
                    _markDirty();
                  },
                ),
                Text(
                  'Basic details',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                _field('First name', _firstName),
                _field('Last name (surname)', _lastName),
                _field('Email', _email, type: TextInputType.emailAddress),
                _field('Phone', _phone, type: TextInputType.phone),

                const SizedBox(height: 12),
                Text(
                  'Personal details',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),

                _dropdownField(
                  label: 'Gender',
                  value: _gender,
                  items: const [
                    DropdownMenuItem(value: 'male', child: Text('Male')),
                    DropdownMenuItem(value: 'female', child: Text('Female')),
                    DropdownMenuItem(
                      value: 'non_binary',
                      child: Text('Non-binary'),
                    ),
                    DropdownMenuItem(
                      value: 'prefer_to_self_describe',
                      child: Text('Prefer to self-describe'),
                    ),
                    DropdownMenuItem(
                      value: 'prefer_not_to_say',
                      child: Text('Prefer not to say'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _gender = value;
                      if (_gender != 'prefer_to_self_describe') {
                        _genderSelfDescribed.clear();
                      }
                    });
                    _markDirty();
                  },
                ),

                if (_gender == 'prefer_to_self_describe')
                  _field('Please describe your gender', _genderSelfDescribed),

                _dropdownField(
                  label: 'Sex at birth',
                  value: _sexAtBirth,
                  helperText: 'Optional',
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
                  onChanged: (value) {
                    setState(() {
                      _sexAtBirth = value;
                    });
                    _markDirty();
                  },
                ),

                const SizedBox(height: 12),
                Text('Address', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _field('Address line 1', _a1),
                _field('Address line 2', _a2),
                _field('Town / City', _town),
                _field('County', _county),
                _field('Postcode', _postcode),

                const SizedBox(height: 12),
                Text(
                  'Player details',
                  style: Theme.of(context).textTheme.titleMedium,
                ),

                const SizedBox(height: 8),
                _dropdownField(
                  label: 'Preferred Player Position',
                  value: _preferredPosition,
                  items: const [
                    DropdownMenuItem(value: 'lead', child: Text('Lead')),
                    DropdownMenuItem(value: 'third', child: Text('Third')),
                    DropdownMenuItem(value: 'skip', child: Text('Skip')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _preferredPosition = value;
                    });
                    _markDirty();
                  },
                ),

                if (widget.canManageMembers) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Admin details',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  _dropdownField(
                    label: 'Role',
                    value: _role,
                    items: const [
                      DropdownMenuItem(value: 'guest', child: Text('Guest')),
                      DropdownMenuItem(value: 'member', child: Text('Member')),
                      DropdownMenuItem(
                        value: 'captain',
                        child: Text('Captain'),
                      ),
                      DropdownMenuItem(
                        value: 'selector',
                        child: Text('Selector'),
                      ),
                      DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _role = value;
                      });
                      _markDirty();
                    },
                  ),

                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Coach'),
                    subtitle: const Text(
                      'This member can act as a club coach.',
                    ),
                    value: _isCoach,
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _isCoach = value;
                      });
                      _markDirty();
                    },
                  ),

                  if (_isCoach) _field('Coaching award', _coachingAward),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
