import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/navigation_service.dart';

// Stable venue UI baseline: Phase 2D.3, 2026-07-28.
const String venueMaintainRevision = '20260728-phase2d3-stable';

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

enum _GoogleVenueSearchMode { bowlsClub, nearbyBowlsClubs, general }

class VenueMaintainScreen extends StatefulWidget {
  final String clubId;
  final Map<String, dynamic>? venue;
  final bool canEdit;
  final bool startInEditMode;

  const VenueMaintainScreen({
    super.key,
    required this.clubId,
    this.venue,
    this.canEdit = false,
    this.startInEditMode = false,
  });

  bool get isExisting => venue != null;

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

  final Map<String, TextEditingController> _officerNameControllers = {};
  final Map<String, TextEditingController> _officerEmailControllers = {};
  final Map<String, TextEditingController> _officerPhoneControllers = {};

  bool _isHome = false;
  bool _editing = false;
  bool _saving = false;
  bool _findingOnGoogle = false;

  String _s(dynamic value) => (value ?? '').toString().trim();

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

    _name = TextEditingController();
    _address1 = TextEditingController();
    _address2 = TextEditingController();
    _town = TextEditingController();
    _postcode = TextEditingController();
    _contactName = TextEditingController();
    _contactPhone = TextEditingController();
    _contactEmail = TextEditingController();
    _directionsUrl = TextEditingController();
    _websiteUrl = TextEditingController();
    _googleMapsUrl = TextEditingController();
    _googlePlaceId = TextEditingController();
    _latitude = TextEditingController();
    _longitude = TextEditingController();

    for (final role in clubOfficerRoles) {
      _officerNameControllers[role[0]] = TextEditingController();
      _officerEmailControllers[role[0]] = TextEditingController();
      _officerPhoneControllers[role[0]] = TextEditingController();
    }

    _restoreOriginalValues();
    _editing = !widget.isExisting ||
        (widget.canEdit && widget.startInEditMode);
  }

  void _restoreOriginalValues() {
    final venue = widget.venue ?? <String, dynamic>{};

    _name.text = _s(venue['name']);
    _address1.text = _s(venue['address_line1']);
    _address2.text = _s(venue['address_line2']);
    _town.text = _s(venue['town_city']);
    _postcode.text = _s(venue['postcode']);
    _contactName.text = _s(venue['contact_name']);
    _contactPhone.text = _s(venue['contact_phone']);
    _contactEmail.text = _s(venue['contact_email']);
    _directionsUrl.text = _s(venue['directions_url']);
    _websiteUrl.text = _s(venue['website_url']);
    _googleMapsUrl.text = _s(venue['google_maps_url']);
    _googlePlaceId.text = _s(venue['google_place_id']);
    _latitude.text = _s(venue['latitude']);
    _longitude.text = _s(venue['longitude']);
    _isHome = venue['is_home_venue'] == true;

    final officers =
        (venue['club_officers'] as Map?)?.cast<String, dynamic>() ?? {};

    for (final role in clubOfficerRoles) {
      final key = role[0];
      final officer = (officers[key] as Map?)?.cast<String, dynamic>() ?? {};
      _officerNameControllers[key]!.text = _s(officer['name']);
      _officerEmailControllers[key]!.text = _s(officer['email']);
      _officerPhoneControllers[key]!.text = _s(officer['phone']);
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
      final message = _s(data['error']);
      throw Exception(
        message.isNotEmpty
            ? message
            : 'Google venue search failed (HTTP ${response.status}).',
      );
    }

    return _asMap(response.data);
  }

  Future<String> _defaultNearbyArea() async {
    final enteredArea = [
      _town.text.trim(),
      _postcode.text.trim(),
    ].where((part) => part.isNotEmpty).join(' ');

    if (enteredArea.isNotEmpty) return enteredArea;

    try {
      final homeVenue = await Supabase.instance.client
          .from('venues')
          .select('town_city, postcode')
          .eq('club_id', widget.clubId)
          .eq('is_home_venue', true)
          .maybeSingle();

      if (homeVenue != null) {
        return [
          _s(homeVenue['town_city']),
          _s(homeVenue['postcode']),
        ].where((part) => part.isNotEmpty).join(' ');
      }
    } catch (error, stackTrace) {
      debugPrint('Unable to load home venue for nearby search: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    return '';
  }

  Future<void> _openGoogleVenueAssist(
    _GoogleVenueSearchMode mode,
  ) async {
    if (_findingOnGoogle || !_editing) return;

    setState(() => _findingOnGoogle = true);

    final defaultQuery = mode == _GoogleVenueSearchMode.nearbyBowlsClubs
        ? await _defaultNearbyArea()
        : [
            _name.text.trim(),
            _town.text.trim(),
            _postcode.text.trim(),
          ].where((part) => part.isNotEmpty).join(' ');

    if (!mounted) return;

    final queryController = TextEditingController(text: defaultQuery);
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(620.0, math.max(280.0, screenSize.width - 48));
    final dialogHeight =
        math.min(500.0, math.max(320.0, screenSize.height - 180));

    var searching = false;
    String? error;
    List<Map<String, dynamic>> places = [];

    try {
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> search() async {
              final enteredQuery = queryController.text.trim();
              if (enteredQuery.length < 2) {
                setDialogState(() {
                  error = mode == _GoogleVenueSearchMode.nearbyBowlsClubs
                      ? 'Enter a town, area or postcode.'
                      : 'Enter at least two characters.';
                  places = [];
                });
                return;
              }

              final searchQuery =
                  mode == _GoogleVenueSearchMode.nearbyBowlsClubs
                      ? 'bowls clubs near $enteredQuery'
                      : enteredQuery;

              setDialogState(() {
                searching = true;
                error = null;
              });

              try {
                final data = await _invokeVenuePlaces({
                  'action': 'search',
                  'clubId': widget.clubId,
                  'query': searchQuery,
                  'mode': mode == _GoogleVenueSearchMode.general
                      ? 'general'
                      : 'bowls_club',
                });

                final rawPlaces = data['places'];
                if (!dialogContext.mounted) return;

                setDialogState(() {
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
              } catch (exception) {
                if (!dialogContext.mounted) return;
                setDialogState(() {
                  error = exception
                      .toString()
                      .replaceFirst('Exception: ', '');
                  places = [];
                });
              } finally {
                if (dialogContext.mounted) {
                  setDialogState(() => searching = false);
                }
              }
            }

            Future<void> choosePlace(Map<String, dynamic> place) async {
              final placeId = _s(place['placeId']);
              if (placeId.isEmpty) return;

              setDialogState(() {
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
              } catch (exception) {
                if (!dialogContext.mounted) return;
                setDialogState(() {
                  searching = false;
                  error = exception
                      .toString()
                      .replaceFirst('Exception: ', '');
                });
              }
            }

            final title = switch (mode) {
              _GoogleVenueSearchMode.bowlsClub => 'Find a bowls club',
              _GoogleVenueSearchMode.nearbyBowlsClubs =>
                'Find nearby bowls clubs',
              _GoogleVenueSearchMode.general => 'Search all venues',
            };

            final queryLabel = switch (mode) {
              _GoogleVenueSearchMode.bowlsClub => 'Bowls club or area',
              _GoogleVenueSearchMode.nearbyBowlsClubs =>
                'Town, area or postcode',
              _GoogleVenueSearchMode.general => 'Venue or place',
            };

            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: dialogWidth,
                height: dialogHeight,
                child: Column(
                  children: [
                    TextField(
                      controller: queryController,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        labelText: queryLabel,
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
                    if (mode ==
                        _GoogleVenueSearchMode.nearbyBowlsClubs) ...[
                      const SizedBox(height: 8),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'The search is centred on the entered area. '
                          'Your club home venue is used as the default where available.',
                        ),
                      ),
                    ],
                    if (searching) ...[
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
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
                                    _s(place['name']).isEmpty
                                        ? 'Unnamed place'
                                        : _s(place['name']),
                                  ),
                                  subtitle: Text(
                                    _s(place['formattedAddress']),
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

      if (selected == null || !mounted) return;

      final venueName = _s(selected['name']).isEmpty
          ? _name.text.trim()
          : _s(selected['name']);

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(widget.isExisting
              ? 'Refresh venue from Google?'
              : 'Use these Google details?'),
          content: Text(
            widget.isExisting
                ? 'Use the Google details for "$venueName"?\n\n'
                    'The current venue will not be changed until you press Save.'
                : 'Use the Google details for "$venueName"?\n\n'
                    'The form will be populated for you to review before saving.',
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
      _applyGoogleDetails(selected);
    } finally {
      queryController.dispose();
      if (mounted) setState(() => _findingOnGoogle = false);
    }
  }

  void _applyGoogleDetails(Map<String, dynamic> selected) {
    setState(() {
      final name = _s(selected['name']);
      if (name.isNotEmpty) _name.text = name;

      final address1 = _s(selected['addressLine1']);
      final address2 = _s(selected['addressLine2']);
      final town = _s(selected['townCity']);
      final postcode = _s(selected['postcode']);

      if (address1.isNotEmpty) _address1.text = address1;
      if (address2.isNotEmpty) _address2.text = address2;
      if (town.isNotEmpty) _town.text = town;
      if (postcode.isNotEmpty) _postcode.text = postcode;

      final phone = _s(selected['phone']);
      if (phone.isNotEmpty) _contactPhone.text = phone;

      final website = _s(selected['websiteUrl']);
      if (website.isNotEmpty) _websiteUrl.text = website;

      _googleMapsUrl.text = _s(selected['googleMapsUrl']);
      _googlePlaceId.text = _s(selected['placeId']);
      _directionsUrl.text = _s(selected['googleMapsUrl']);
      _latitude.text = _s(selected['latitude']);
      _longitude.text = _s(selected['longitude']);
    });
  }

  Uri? _normaliseWebUri(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(candidate);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return uri;
  }

  Future<void> _openWebsite() async {
    final uri = _normaliseWebUri(_websiteUrl.text);
    if (uri == null) return;

    var opened = false;
    try {
      opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (error, stackTrace) {
      debugPrint('Venue website launch failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open the venue website.')),
      );
    }
  }

  Map<String, dynamic> _venueForNavigation() {
    return {
      'name': _name.text.trim(),
      'address_line1': _address1.text.trim(),
      'address_line2': _address2.text.trim(),
      'town_city': _town.text.trim(),
      'postcode': _postcode.text.trim(),
      'google_place_id': _googlePlaceId.text.trim(),
      'latitude': _latitude.text.trim(),
      'longitude': _longitude.text.trim(),
    };
  }

  Future<void> _openDirections() async {
    await NavigationService.navigateToVenue(
      context: context,
      venue: _venueForNavigation(),
    );
  }

  double? _parseCoordinate(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : double.tryParse(value);
  }

  Future<void> _save({bool allowPossibleDuplicate = false}) async {
    if (_saving || !_editing) return;
    if (!_formKey.currentState!.validate()) return;

    final latitudeText = _latitude.text.trim();
    final longitudeText = _longitude.text.trim();
    final latitude = _parseCoordinate(_latitude);
    final longitude = _parseCoordinate(_longitude);

    if (latitudeText.isEmpty != longitudeText.isEmpty) {
      _showMessage('Latitude and longitude must be supplied together.');
      return;
    }

    if ((latitudeText.isNotEmpty && latitude == null) ||
        (longitudeText.isNotEmpty && longitude == null)) {
      _showMessage('Latitude and longitude must be numbers.');
      return;
    }

    if ((latitude != null && (latitude < -90 || latitude > 90)) ||
        (longitude != null && (longitude < -180 || longitude > 180))) {
      _showMessage('Latitude or longitude is outside its valid range.');
      return;
    }

    setState(() => _saving = true);

    try {
      final officersPayload = <String, dynamic>{};
      for (final role in clubOfficerRoles) {
        final key = role[0];
        officersPayload[key] = {
          'name': _officerNameControllers[key]!.text.trim(),
          'email': _officerEmailControllers[key]!.text.trim(),
          'phone': _officerPhoneControllers[key]!.text.trim(),
        };
      }

      String? optional(TextEditingController controller) {
        final value = controller.text.trim();
        return value.isEmpty ? null : value;
      }

      final commonParams = <String, dynamic>{
        'p_club_id': widget.clubId,
        'p_name': _name.text.trim(),
        'p_is_home_venue': _isHome,
        'p_town_city': optional(_town),
        'p_postcode': _postcode.text.trim().isEmpty
            ? null
            : _postcode.text.trim().toUpperCase(),
        'p_contact_name': optional(_contactName),
        'p_contact_phone': optional(_contactPhone),
        'p_contact_email': optional(_contactEmail),
        'p_address_line1': optional(_address1),
        'p_address_line2': optional(_address2),
        'p_directions_url': optional(_directionsUrl),
        'p_website_url': optional(_websiteUrl),
        'p_google_maps_url': optional(_googleMapsUrl),
        'p_google_place_id': optional(_googlePlaceId),
        'p_latitude': latitude,
        'p_longitude': longitude,
        'p_club_officers': _isHome ? officersPayload : <String, dynamic>{},
      };

      if (widget.isExisting) {
        final venueId = _s(widget.venue?['id']);
        if (venueId.isEmpty) {
          throw const FormatException('The venue record has no venue ID.');
        }

        await Supabase.instance.client.rpc(
          'update_club_venue_full',
          params: {
            ...commonParams,
            'p_venue_id': venueId,
          },
        );
      } else {
        await Supabase.instance.client.rpc(
          'create_club_venue_full',
          params: {
            ...commonParams,
            'p_allow_possible_duplicate': allowPossibleDuplicate,
          },
        );
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (exception) {
      if (!mounted) return;

      final message = exception.toString();
      final duplicate = !widget.isExisting &&
          !allowPossibleDuplicate &&
          (message.toLowerCase().contains('possible duplicate') ||
              message.toLowerCase().contains('similar venue'));

      if (duplicate) {
        setState(() => _saving = false);
        final createAnyway = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Possible duplicate venue'),
            content: const Text(
              'A similar venue may already exist for this club.\n\n'
              'Please check the venue list before creating another record.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Return to form'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Create anyway'),
              ),
            ],
          ),
        );

        if (createAnyway == true && mounted) {
          await _save(allowPossibleDuplicate: true);
        }
        return;
      }

      _showMessage(
        message.replaceFirst('PostgrestException(message: ', 'Save failed: '),
      );
    } finally {
      if (mounted && _saving) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _cancelEditing() {
    if (!widget.isExisting) {
      Navigator.pop(context);
      return;
    }

    _restoreOriginalValues();
    setState(() => _editing = false);
  }

  Widget _buildField(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildGoogleAssistCard() {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isExisting
                  ? 'Google venue assistance'
                  : 'Find and add a venue',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              widget.isExisting
                  ? 'Refresh or complete this venue using Google Places. '
                      'Nothing is saved until you press Save.'
                  : 'Search Google first, then review and amend the details '
                      'before securely creating the venue.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _findingOnGoogle
                      ? null
                      : () => _openGoogleVenueAssist(
                            _GoogleVenueSearchMode.bowlsClub,
                          ),
                  icon: const Icon(Icons.sports),
                  label: Text(
                    widget.isExisting
                        ? 'Refresh / match bowls club'
                        : 'Find a bowls club',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _findingOnGoogle
                      ? null
                      : () => _openGoogleVenueAssist(
                            _GoogleVenueSearchMode.nearbyBowlsClubs,
                          ),
                  icon: const Icon(Icons.near_me_outlined),
                  label: const Text('Nearby bowls clubs'),
                ),
                OutlinedButton.icon(
                  onPressed: _findingOnGoogle
                      ? null
                      : () => _openGoogleVenueAssist(
                            _GoogleVenueSearchMode.general,
                          ),
                  icon: const Icon(Icons.public),
                  label: const Text('Search all venues'),
                ),
              ],
            ),
            if (_findingOnGoogle) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 12),
            const Text(
              'Alternatively, enter or amend the details manually below.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          _buildGoogleAssistCard(),
          _buildField(
            _name,
            'Venue name',
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Venue name is required.'
                : null,
            onChanged: (_) => setState(() {}),
          ),
          _buildField(
            _address1,
            'Address line 1',
            onChanged: (_) => setState(() {}),
          ),
          _buildField(
            _address2,
            'Address line 2',
            onChanged: (_) => setState(() {}),
          ),
          _buildField(
            _town,
            'Town / City',
            onChanged: (_) => setState(() {}),
          ),
          _buildField(
            _postcode,
            'Postcode',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
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
                onPressed:
                    _websiteUrl.text.trim().isEmpty ? null : _openWebsite,
                icon: const Icon(Icons.language),
                label: const Text('Open website'),
              ),
              OutlinedButton.icon(
                onPressed: NavigationService.canNavigate(
                  _venueForNavigation(),
                )
                    ? _openDirections
                    : null,
                icon: const Icon(Icons.directions),
                label: const Text('Directions'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
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
                      _buildField(
                        _officerNameControllers[role[0]]!,
                        'Name',
                      ),
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
        ],
      ),
    );
  }

  Widget _buildReadOnlyDetails() {
    final address = [
      _address1.text.trim(),
      _address2.text.trim(),
      _town.text.trim(),
      _postcode.text.trim(),
    ].where((part) => part.isNotEmpty).join(', ');

    final hasContact = _contactName.text.trim().isNotEmpty ||
        _contactPhone.text.trim().isNotEmpty ||
        _contactEmail.text.trim().isNotEmpty;
    final hasWebsite = _websiteUrl.text.trim().isNotEmpty;
    final canNavigate = NavigationService.canNavigate(_venueForNavigation());

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Chip(
            label: Text(_isHome ? 'Home venue' : 'Opponent venue'),
          ),
        ),
        if (address.isNotEmpty) ...[
          const SizedBox(height: 16),
          _detailSection('Address', [address]),
        ],
        if (hasContact) ...[
          const SizedBox(height: 20),
          _detailSection(
            'Contact',
            [
              _contactName.text.trim(),
              _contactPhone.text.trim(),
              _contactEmail.text.trim(),
            ].where((line) => line.isNotEmpty).toList(),
          ),
        ],
        if (hasWebsite) ...[
          const SizedBox(height: 20),
          Text(
            'Website',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: _openWebsite,
            child: Text(
              _websiteUrl.text.trim(),
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            if (hasWebsite)
              OutlinedButton.icon(
                onPressed: _openWebsite,
                icon: const Icon(Icons.language),
                label: const Text('Open website'),
              ),
            FilledButton.icon(
              onPressed: canNavigate ? _openDirections : null,
              icon: const Icon(Icons.directions),
              label: const Text('Directions'),
            ),
          ],
        ),
        if (_isHome) ...[
          const SizedBox(height: 28),
          Text(
            'Club Officers & Key Contacts',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 10),
          _buildReadOnlyOfficers(),
        ],
      ],
    );
  }

  Widget _detailSection(String heading, List<String> lines) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 6),
        for (final line in lines) SelectableText(line),
      ],
    );
  }

  Widget _buildReadOnlyOfficers() {
    final cards = <Widget>[];

    for (final role in clubOfficerRoles) {
      final key = role[0];
      final name = _officerNameControllers[key]!.text.trim();
      final email = _officerEmailControllers[key]!.text.trim();
      final phone = _officerPhoneControllers[key]!.text.trim();

      if (name.isEmpty && email.isEmpty && phone.isEmpty) continue;

      cards.add(
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  role[1],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                if (name.isNotEmpty) SelectableText(name),
                if (email.isNotEmpty) SelectableText(email),
                if (phone.isNotEmpty) SelectableText(phone),
              ],
            ),
          ),
        ),
      );
    }

    if (cards.isEmpty) {
      return const Text('No officer details have been recorded.');
    }

    return Column(children: cards);
  }

  String get _screenTitle {
    if (!widget.isExisting) return 'Create Venue';
    if (_editing) return 'Edit ${_name.text.trim()}';
    return _name.text.trim().isEmpty ? 'Venue details' : _name.text.trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_screenTitle),
        actions: [
          if (widget.isExisting && !_editing && widget.canEdit)
            IconButton(
              tooltip: 'Edit venue',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => setState(() => _editing = true),
            ),
          if (_editing && widget.isExisting)
            IconButton(
              tooltip: 'Cancel editing',
              icon: const Icon(Icons.close),
              onPressed: _saving ? null : _cancelEditing,
            ),
        ],
      ),
      floatingActionButton: _editing
          ? FloatingActionButton.extended(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save),
              label: Text(_saving ? 'Saving…' : 'Save'),
            )
          : null,
      body: SafeArea(
        child: _editing ? _buildEditForm() : _buildReadOnlyDetails(),
      ),
    );
  }
}
