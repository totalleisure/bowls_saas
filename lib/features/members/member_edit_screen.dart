import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/account_security_screen.dart';

class MemberEditScreen extends StatefulWidget {
  final String memberProfileId;
  final Map<String, dynamic> initial;

  final String clubId;
  final String initialRole;
  final bool initialActive;
  final bool canManageMembers;

  final bool initialIsCoach;
  final String? initialCoachingAward;

  final bool isOwnRecord;

  const MemberEditScreen({
    super.key,
    required this.memberProfileId,
    required this.initial,
    required this.clubId,
    required this.initialRole,
    required this.initialActive,
    required this.canManageMembers,
    required this.initialIsCoach,
    required this.isOwnRecord,
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

  late final TextEditingController _homePhone;
  late final TextEditingController _officePhone;

  bool _showMobileInDirectory = true;
  bool _showHomePhoneInDirectory = false;
  bool _showOfficePhoneInDirectory = false;
  bool _showEmailInDirectory = true;
  bool _showAddressInDirectory = false;

  String? _gender;
  String? _sexAtBirth;
  String? _preferredPosition;

  late String _role;
  late bool _active;

  bool _saving = false;

  bool _hasUnsavedChanges = false;

  bool get _canEditMobile => widget.canManageMembers || widget.isOwnRecord;

  bool get _canSeeAdminFields => widget.canManageMembers;
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

    _homePhone = TextEditingController(
      text: (i['home_phone'] ?? '').toString(),
    );
    _officePhone = TextEditingController(
      text: (i['office_phone'] ?? '').toString(),
    );

    _showMobileInDirectory = i['show_mobile_in_directory'] != false;
    _showHomePhoneInDirectory = i['show_home_phone_in_directory'] == true;
    _showOfficePhoneInDirectory = i['show_office_phone_in_directory'] == true;
    _showEmailInDirectory = i['show_email_in_directory'] != false;
    _showAddressInDirectory = i['show_address_in_directory'] == true;

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
    _homePhone.dispose();
    _officePhone.dispose();
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
        'home_phone': _homePhone.text.trim().isEmpty
            ? null
            : _homePhone.text.trim(),
        'office_phone': _officePhone.text.trim().isEmpty
            ? null
            : _officePhone.text.trim(),
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
        'show_mobile_in_directory': _showMobileInDirectory,
        'show_home_phone_in_directory': _showHomePhoneInDirectory,
        'show_office_phone_in_directory': _showOfficePhoneInDirectory,
        'show_email_in_directory': _showEmailInDirectory,
        'show_address_in_directory': _showAddressInDirectory,
      };

      if (_canEditMobile) {
        payload['phone'] = _phone.text.trim().isEmpty
            ? null
            : _phone.text.trim();
      }

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

  Widget _field(
    String label,
    TextEditingController c, {
    TextInputType? type,
    bool enabled = true,
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: type,
        enabled: enabled,
        readOnly: readOnly,
        onChanged: readOnly ? null : (_) => _markDirty(),
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

  Widget _fieldWithDirectoryOption({
    required String label,
    required TextEditingController controller,
    required bool showInDirectory,
    required ValueChanged<bool> onDirectoryChanged,
    TextInputType? type,
    bool enabled = true,
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _field(
              label,
              controller,
              type: type,
              enabled: enabled,
              readOnly: readOnly,
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: showInDirectory,
                  onChanged: (v) {
                    if (v == null) return;
                    onDirectoryChanged(v);
                  },
                ),
                Icon(Icons.groups, size: 18, color: Colors.green.shade700),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openEmailAction() async {
    if (widget.isOwnRecord) {
      final changedEmail = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const AccountSecurityScreen()),
      );

      if (changedEmail != null && changedEmail.trim().isNotEmpty && mounted) {
        // AccountSecurityScreen returns the exact email confirmed by Supabase.
        // Update this controller directly instead of immediately querying the
        // profile row and risking a stale value during the route transition.
        setState(() {
          _email.text = changedEmail.trim();
        });
      }
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.security_outlined, size: 44),
        title: const Text('Assist with email change'),
        content: const Text(
          'A member’s login email belongs to their platform account and may '
          'cover more than one club. Ask the member to open Account and Security '
          'and use Change login email. If they cannot access their old email, '
          'the change must be handled through the protected platform recovery process.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
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
                  onChanged: widget.canManageMembers
                      ? (value) {
                          if (value == null) return;
                          setState(() {
                            _active = value;
                          });
                          _markDirty();
                        }
                      : null,
                ),
                Text(
                  'Basic details',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                _field('First name', _firstName),
                _field('Last name (surname)', _lastName),

                Row(
                  children: [
                    Icon(Icons.groups, size: 20, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Club Member Directory: Tick the boxes to control which details are visible to other club members.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                _fieldWithDirectoryOption(
                  label: 'Login email (read only)',
                  controller: _email,
                  type: TextInputType.emailAddress,
                  readOnly: true,
                  showInDirectory: _showEmailInDirectory,
                  onDirectoryChanged: (v) {
                    setState(() => _showEmailInDirectory = v);
                    _markDirty();
                  },
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _openEmailAction,
                    icon: const Icon(Icons.alternate_email),
                    label: Text(
                      widget.isOwnRecord
                          ? 'Change login email'
                          : 'Assist with email change',
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                _fieldWithDirectoryOption(
                  label: 'Mobile phone',
                  controller: _phone,
                  type: TextInputType.phone,
                  enabled: _canEditMobile,
                  showInDirectory: _showMobileInDirectory,
                  onDirectoryChanged: (v) {
                    setState(() => _showMobileInDirectory = v);
                    _markDirty();
                  },
                ),

                _fieldWithDirectoryOption(
                  label: 'Home phone',
                  controller: _homePhone,
                  type: TextInputType.phone,
                  showInDirectory: _showHomePhoneInDirectory,
                  onDirectoryChanged: (v) {
                    setState(() => _showHomePhoneInDirectory = v);
                    _markDirty();
                  },
                ),

                _fieldWithDirectoryOption(
                  label: 'Office phone',
                  controller: _officePhone,
                  type: TextInputType.phone,
                  showInDirectory: _showOfficePhoneInDirectory,
                  onDirectoryChanged: (v) {
                    setState(() => _showOfficePhoneInDirectory = v);
                    _markDirty();
                  },
                ),

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

                Row(
                  children: [
                    Text(
                      'Address',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    Checkbox(
                      value: _showAddressInDirectory,
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _showAddressInDirectory = v);
                        _markDirty();
                      },
                    ),
                    Icon(Icons.groups, size: 18, color: Colors.green.shade700),
                  ],
                ),
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

                if (_canSeeAdminFields) ...[
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
