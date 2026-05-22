import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const clubOfficerRoles = [
  ['club_president', 'Club President'],
  ['club_secretary', 'Club Secretary'],
  ['membership_secretary', 'Membership Secretary'],
  ['treasurer', 'Treasurer'],
  ['safeguarding_officer', 'Safeguarding Officer'],
  ['club_captain', 'Club Captain'],
  ['mens_captain', 'Club Mens Captain'],
  ['ladies_captain', 'Club Ladies Captain'],
  ['match_fixture_secretary', 'Match / Fixture Secretary'],
  ['competitions_secretary', 'Competitions Secretary'],
  ['green_keeper_facilities_manager', 'Green Keeper / Facilities Manager'],
];

class VenueMaintainScreen extends StatefulWidget {
  final String clubId;
  final Map<String, dynamic>? venue;

  const VenueMaintainScreen({super.key, required this.clubId, this.venue});

  bool get isEdit => venue != null;

  @override
  State<VenueMaintainScreen> createState() => _VenueMaintainScreenState();
}

class _VenueMaintainScreenState extends State<VenueMaintainScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _address1;
  late final TextEditingController _address2;
  late final TextEditingController _town;
  late final TextEditingController _postcode;
  late final TextEditingController _contactName;
  late final TextEditingController _contactPhone;
  late final TextEditingController _contactEmail;
  late final TextEditingController _directionsUrl;

  bool _isHome = false;
  bool _saving = false;

  final Map<String, TextEditingController> _officerNameControllers = {};

  final Map<String, TextEditingController> _officerEmailControllers = {};

  final Map<String, TextEditingController> _officerPhoneControllers = {};

  String _s(dynamic v) => v?.toString() ?? '';

  @override
  void initState() {
    super.initState();

    final v = widget.venue ?? {};

    _name = TextEditingController(text: _s(v['name']));
    _address1 = TextEditingController(text: _s(v['address_line1']));
    _address2 = TextEditingController(text: _s(v['address_line2']));
    _town = TextEditingController(text: _s(v['town_city']));
    _postcode = TextEditingController(text: _s(v['postcode']));

    _contactName = TextEditingController(text: _s(v['contact_name']));

    _contactPhone = TextEditingController(text: _s(v['contact_phone']));

    _contactEmail = TextEditingController(text: _s(v['contact_email']));

    _directionsUrl = TextEditingController(text: _s(v['directions_url']));

    _isHome = v['is_home_venue'] == true;

    final officers =
        (v['club_officers'] as Map?)?.cast<String, dynamic>() ?? {};

    for (final role in clubOfficerRoles) {
      final key = role[0];

      final officer = (officers[key] as Map?)?.cast<String, dynamic>() ?? {};

      _officerNameControllers[key] = TextEditingController(
        text: _s(officer['name']),
      );

      _officerEmailControllers[key] = TextEditingController(
        text: _s(officer['email']),
      );

      _officerPhoneControllers[key] = TextEditingController(
        text: _s(officer['phone']),
      );
    }
  }

  Future<void> _save() async {
    if (_saving) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _saving = true);

    try {
      final officersPayload = <String, dynamic>{};

      for (final role in clubOfficerRoles) {
        final key = role[0];

        officersPayload[key] = {
          'name': _officerNameControllers[key]?.text.trim() ?? '',
          'email': _officerEmailControllers[key]?.text.trim() ?? '',
          'phone': _officerPhoneControllers[key]?.text.trim() ?? '',
        };
      }

      final payload = {
        'club_id': widget.clubId,
        'name': _name.text.trim(),
        'is_home_venue': _isHome,
        'contact_name': _contactName.text.trim(),
        'contact_phone': _contactPhone.text.trim(),
        'contact_email': _contactEmail.text.trim(),
        'address_line1': _address1.text.trim(),
        'address_line2': _address2.text.trim(),
        'town_city': _town.text.trim(),
        'postcode': _postcode.text.trim(),
        'directions_url': _directionsUrl.text.trim(),
        'club_officers': _isHome ? officersPayload : {},
      };

      if (widget.isEdit) {
        await Supabase.instance.client
            .from('venues')
            .update(payload)
            .eq('id', widget.venue!['id']);
      } else {
        await Supabase.instance.client.from('venues').insert(payload);
      }

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _buildField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEdit ? 'Edit Venue' : 'Create Venue'),
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _save,
        icon: const Icon(Icons.save),
        label: Text(_saving ? 'Saving...' : 'Save'),
      ),

      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildField(_name, 'Venue name'),
            _buildField(_address1, 'Address line 1'),
            _buildField(_address2, 'Address line 2'),
            _buildField(_town, 'Town / City'),
            _buildField(_postcode, 'Postcode'),

            const SizedBox(height: 12),

            _buildField(_contactName, 'Contact name'),

            _buildField(_contactPhone, 'Contact telephone'),

            _buildField(_contactEmail, 'Contact email'),

            _buildField(_directionsUrl, 'Directions URL'),

            SwitchListTile(
              value: _isHome,
              onChanged: (v) {
                setState(() {
                  _isHome = v;
                });
              },
              title: const Text('Home venue'),
            ),

            if (_isHome) ...[
              const SizedBox(height: 20),

              const Text(
                'Club Officers & Key Contacts',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 16),

              for (final role in clubOfficerRoles) ...[
                Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            role[1],
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),

                        const SizedBox(height: 12),

                        _buildField(_officerNameControllers[role[0]]!, 'Name'),

                        _buildField(
                          _officerEmailControllers[role[0]]!,
                          'Email',
                        ),

                        _buildField(
                          _officerPhoneControllers[role[0]]!,
                          'Telephone',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],

            const SizedBox(height: 120),
          ],
        ),
      ),
    );
  }
}
