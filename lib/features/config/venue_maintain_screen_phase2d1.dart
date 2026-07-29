import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/navigation_service.dart';

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
  late final TextEditingController _websiteUrl;
  late final TextEditingController _googleMapsUrl;
  late final TextEditingController _googlePlaceId;
  late final TextEditingController _latitude;
  late final TextEditingController _longitude;

  bool _isHome = false;
  bool _saving = false;
  bool _findingOnGoogle = false;

  final Map<String, TextEditingController> _officerNameControllers = {};
  final Map<String, TextEditingController> _officerEmailControllers = {};
  final Map<String, TextEditingController> _officerPhoneControllers = {};

  String _s(dynamic value) => value?.toString() ?? '';

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return <String, dynamic>{};
  }

  @override
  void initState() {
    super.initState();

    final v = widget.venue ?? <String, dynamic>{};

    _name = TextEditingController(text: _s(v['name']));
    _address1 = TextEditingController(text: _s(v['address_line1']));
    _address2 = TextEditingController(text: _s(v['address_line2']));
    _town = TextEditingController(text: _s(v['town_city']));
    _postcode = TextEditingController(text: _s(v['postcode']));
    _contactName = TextEditingController(text: _s(v['contact_name']));
    _contactPhone = TextEditingController(text: _s(v['contact_phone']));
    _contactEmail = TextEditingController(text: _s(v['contact_email']));
    _directionsUrl = TextEditingController(text: _s(v['directions_url']));
    _websiteUrl = TextEditingController(text: _s(v['website_url']));
    _googleMapsUrl = TextEditingController(text: _s(v['google_maps_url']));
    _googlePlaceId = TextEditingController(text: _s(v['google_place_id']));
    _latitude = TextEditingController(text: _s(v['latitude']));
    _longitude = TextEditingController(text: _s(v['longitude']));

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

  @override
  void dispose() {
    for (final controller in [
      _name,
      _address1,
      _address2,
      _town,
      _postcode,
      _contactName,
      _contactPhone,
      _contactEmail,
      _directionsUrl,
      _websiteUrl,
      _googleMapsUrl,
      _googlePlaceId,
      _latitude,
      _longitude,
      ..._officerNameControllers.values,
      ..._officerEmailControllers.values,
      ..._officerPhoneControllers.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<Map<String, dynamic>> _invokeVenuePlaces(
    Map<String, dynamic> body,
  ) async {
    final response = await Supabase.instance.client.functions.invoke(
      'venue-places',
      body: body,
    );

    if (response.status < 200 || response.status >= 300) {
      final data = _asMap(response.data);
      final message = data['error']?.toString().trim();
      throw Exception(
        message?.isNotEmpty == true
            ? message
            : 'Google venue search failed (HTTP ${response.status}).',
      );
    }

    return _asMap(response.data);
  }

  Future<void> _findAndUpdateFromGoogle() async {
    if (_findingOnGoogle) return;

    final queryController = TextEditingController(
      text: [
        _name.text.trim(),
        _town.text.trim(),
        _postcode.text.trim(),
      ].where((value) => value.isNotEmpty).join(' '),
    );

    var searching = false;
    var searchAllVenues = false;
    String? error;
    List<Map<String, dynamic>> places = [];

    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setStateDialog) {
          Future<void> search() async {
            final query = queryController.text.trim();
            if (query.length < 3) {
              setStateDialog(() {
                error = 'Enter at least three characters.';
                places = [];
              });
              return;
            }

            setStateDialog(() {
              searching = true;
              error = null;
            });

            try {
              final data = await _invokeVenuePlaces({
                'action': 'search',
                'clubId': widget.clubId,
                'query': query,
                'mode': searchAllVenues ? 'general' : 'bowls_club',
              });
              final rawPlaces = data['places'];

              if (!dialogContext.mounted) return;
              setStateDialog(() {
                places = rawPlaces is List
                    ? rawPlaces
                          .map(_asMap)
                          .where((place) => place.isNotEmpty)
                          .toList()
                    : <Map<String, dynamic>>[];
                error = places.isEmpty
                    ? 'No matching places were found.'
                    : null;
              });
            } catch (e) {
              if (!dialogContext.mounted) return;
              setStateDialog(() {
                error = e.toString().replaceFirst('Exception: ', '');
                places = [];
              });
            } finally {
              if (dialogContext.mounted) {
                setStateDialog(() => searching = false);
              }
            }
          }

          Future<void> choosePlace(Map<String, dynamic> place) async {
            final placeId = place['placeId']?.toString().trim() ?? '';
            if (placeId.isEmpty) return;

            setStateDialog(() {
              searching = true;
              error = null;
            });

            try {
              final data = await _invokeVenuePlaces({
                'action': 'details',
                'clubId': widget.clubId,
                'placeId': placeId,
              });
              final details = _asMap(data['place']);

              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop(details);
            } catch (e) {
              if (!dialogContext.mounted) return;
              setStateDialog(() {
                searching = false;
                error = e.toString().replaceFirst('Exception: ', '');
              });
            }
          }

          return AlertDialog(
            title: const Text('Find this venue on Google'),
            content: SizedBox(
              width: 620,
              height: 500,
              child: Column(
                children: [
                  TextField(
                    controller: queryController,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: searchAllVenues
                          ? 'Venue or place'
                          : 'Bowls club or area',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: 'Search',
                        onPressed: searching ? null : search,
                        icon: const Icon(Icons.search),
                      ),
                    ),
                    onSubmitted: (_) {
                      if (!searching) search();
                    },
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: searching
                          ? null
                          : () {
                              setStateDialog(() {
                                searchAllVenues = !searchAllVenues;
                                places = [];
                                error = null;
                              });
                            },
                      icon: Icon(
                        searchAllVenues ? Icons.sports : Icons.public,
                      ),
                      label: Text(
                        searchAllVenues
                            ? 'Search bowls clubs only'
                            : 'Search all venues instead',
                      ),
                    ),
                  ),
                  if (searching) const LinearProgressIndicator(),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Expanded(
                    child: places.isEmpty
                        ? Center(
                            child: Text(
                              searching
                                  ? 'Searching…'
                                  : 'Search and select the matching venue.',
                            ),
                          )
                        : ListView.separated(
                            itemCount: places.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, index) {
                              final place = places[index];
                              return ListTile(
                                leading: const Icon(
                                  Icons.location_on_outlined,
                                ),
                                title: Text(
                                  place['name']?.toString() ?? 'Unnamed place',
                                ),
                                subtitle: Text(
                                  place['formattedAddress']?.toString() ?? '',
                                ),
                                onTap: searching
                                    ? null
                                    : () => choosePlace(place),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: searching
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );

    queryController.dispose();
    if (selected == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Update from Google?'),
        content: Text(
          'Use the Google details for "${selected['name'] ?? _name.text}"?\n\n'
          'The existing venue record will be updated; no new venue will be created. '
          'You can review and edit the fields before saving.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Use these details'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _findingOnGoogle = true;
      _name.text = _s(selected['name']);
      _address1.text = _s(selected['addressLine1']);
      _town.text = _s(selected['townCity']);
      _postcode.text = _s(selected['postcode']);

      final phone = _s(selected['phone']);
      if (phone.isNotEmpty) _contactPhone.text = phone;

      _websiteUrl.text = _s(selected['websiteUrl']);
      _googleMapsUrl.text = _s(selected['googleMapsUrl']);
      _googlePlaceId.text = _s(selected['placeId']);
      _directionsUrl.text = _s(selected['googleMapsUrl']);
      _latitude.text = _s(selected['latitude']);
      _longitude.text = _s(selected['longitude']);
      _findingOnGoogle = false;
    });
  }

  Uri? _normaliseWebUri(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    return Uri.tryParse(candidate);
  }

  Future<void> _openWebsite() async {
    final uri = _normaliseWebUri(_websiteUrl.text);
    if (uri == null) return;

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open the venue website.')),
      );
    }
  }

  Future<void> _openDirections() async {
    await NavigationService.navigateToVenue(
      context: context,
      venue: {
        'name': _name.text.trim(),
        'address_line1': _address1.text.trim(),
        'address_line2': _address2.text.trim(),
        'town_city': _town.text.trim(),
        'postcode': _postcode.text.trim(),
        'google_place_id': _googlePlaceId.text.trim(),
        'latitude': _latitude.text.trim(),
        'longitude': _longitude.text.trim(),
      },
    );
  }

  double? _parseCoordinate(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : double.tryParse(value);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    final latitude = _parseCoordinate(_latitude);
    final longitude = _parseCoordinate(_longitude);

    if (_latitude.text.trim().isNotEmpty && latitude == null ||
        _longitude.text.trim().isNotEmpty && longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Latitude and longitude must be numbers.')),
      );
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
        'website_url': _websiteUrl.text.trim(),
        'google_maps_url': _googleMapsUrl.text.trim(),
        'google_place_id': _googlePlaceId.text.trim(),
        'latitude': latitude,
        'longitude': longitude,
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
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildField(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        readOnly: readOnly,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          filled: readOnly,
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
            if (widget.isEdit) ...[
              FilledButton.tonalIcon(
                onPressed: _findingOnGoogle ? null : _findAndUpdateFromGoogle,
                icon: const Icon(Icons.travel_explore),
                label: Text(
                  _findingOnGoogle
                      ? 'Checking Google…'
                      : 'Refresh from Google',
                ),
              ),
              const SizedBox(height: 16),
            ],
            _buildField(_name, 'Venue name'),
            _buildField(_address1, 'Address line 1'),
            _buildField(_address2, 'Address line 2'),
            _buildField(_town, 'Town / City'),
            _buildField(_postcode, 'Postcode'),
            const SizedBox(height: 12),
            _buildField(_contactName, 'Contact name'),
            _buildField(
              _contactPhone,
              'Contact telephone',
              keyboardType: TextInputType.phone,
            ),
            _buildField(
              _contactEmail,
              'Contact email',
              keyboardType: TextInputType.emailAddress,
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextFormField(
                controller: _websiteUrl,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'Website URL',
                  border: const OutlineInputBorder(),
                  suffixIcon: _websiteUrl.text.trim().isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Open website',
                          icon: const Icon(Icons.open_in_new),
                          onPressed: _openWebsite,
                        ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _websiteUrl.text.trim().isEmpty
                      ? null
                      : _openWebsite,
                  icon: const Icon(Icons.language),
                  label: const Text('Open website'),
                ),
                OutlinedButton.icon(
                  onPressed: _openDirections,
                  icon: const Icon(Icons.directions),
                  label: const Text('Directions'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _isHome,
              onChanged: (value) => setState(() => _isHome = value),
              title: const Text('Home venue'),
            ),
            if (_isHome) ...[
              const SizedBox(height: 20),
              const Text(
                'Club Officers & Key Contacts',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              for (final role in clubOfficerRoles)
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
                          keyboardType: TextInputType.emailAddress,
                        ),
                        _buildField(
                          _officerPhoneControllers[role[0]]!,
                          'Telephone',
                          keyboardType: TextInputType.phone,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 120),
          ],
        ),
      ),
    );
  }
}
