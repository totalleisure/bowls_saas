import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'venue_maintain_screen.dart';

//import 'package:flutter/services.dart';
//import 'package:intl/intl.dart';
//import 'package:share_plus/share_plus.dart';

//import '../../core/utils/date_format.dart';
//import '../../Core/permissions/club_role_resolver.dart';
//import '../../Core/permissions/dashboard_permissions.dart';
//import '../../Core/permissions/fixture_permissions.dart';
//import '../../Core/permissions/fixture_role_resolver.dart';
//import '../../Core/permissions/permission_models.dart';

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

class VenuesScreen extends StatefulWidget {
  final String clubId;
  final String clubName;

  const VenuesScreen({super.key, required this.clubId, required this.clubName});

  @override
  State<VenuesScreen> createState() => _VenuesScreenState();
}

class _VenuesScreenState extends State<VenuesScreen> {
  bool _loadingPermissions = true;
  bool _isSuperuser = false;
  bool _isClubAdmin = false;
  String? _currentMemberId;

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _venues = [];

  List<Map<String, dynamic>> _allVenues = [];
  String _searchText = '';

  bool get _canManage => _isSuperuser || _isClubAdmin;

  String _s(dynamic v) => (v ?? '').toString().trim();

  final Map<String, TextEditingController> _officerNameControllers = {};
  final Map<String, TextEditingController> _officerEmailControllers = {};
  final Map<String, TextEditingController> _officerPhoneControllers = {};

  String _buildAddress(Map<String, dynamic> venue) {
    final parts = [
      _s(venue['address_line1']),
      _s(venue['address_line2']),
      _s(venue['town_city']),
      _s(venue['postcode']),
    ].where((e) => e.isNotEmpty).toList();

    return parts.join(', ');
  }

  Uri? _normaliseWebUri(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    return Uri.tryParse(candidate);
  }

  Future<void> _openWebsiteForVenue(Map<String, dynamic> venue) async {
    final uri = _normaliseWebUri(_s(venue['website_url']));
    if (uri == null) return;

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open the venue website.')),
      );
    }
  }

  Future<void> _openMapForVenue(Map<String, dynamic> venue) async {
    Uri? uri;

    final googleMapsUrl = _s(venue['google_maps_url']);
    final directionsUrl = _s(venue['directions_url']);
    final latitude = double.tryParse(_s(venue['latitude']));
    final longitude = double.tryParse(_s(venue['longitude']));

    if (googleMapsUrl.isNotEmpty) {
      uri = Uri.tryParse(googleMapsUrl);
    } else if (directionsUrl.isNotEmpty) {
      uri = Uri.tryParse(directionsUrl);
    } else if (latitude != null && longitude != null) {
      uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude',
      );
    } else {
      final address = _buildAddress(venue);
      final destination = address.isNotEmpty ? address : _s(venue['name']);
      if (destination.isNotEmpty) {
        uri = Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(destination)}',
        );
      }
    }

    if (uri == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No directions information is available.')),
        );
      }
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open directions.')),
      );
    }
  }

  Future<void> _showVenueDetails(Map<String, dynamic> venue) async {
    final address = _buildAddress(venue);

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(_s(venue['name'])),
        content: SizedBox(
          width: 700,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Chip(
                        label: Text(
                          venue['is_home_venue'] == true
                              ? 'Home venue'
                              : 'Opponent venue',
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (address.isNotEmpty) ...[
                        const Text(
                          'Address',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(address),
                        const SizedBox(height: 16),
                      ],
                      if (_s(venue['contact_name']).isNotEmpty ||
                          _s(venue['contact_phone']).isNotEmpty ||
                          _s(venue['contact_email']).isNotEmpty) ...[
                        const Text(
                          'Contact',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        if (_s(venue['contact_name']).isNotEmpty)
                          Text(_s(venue['contact_name'])),
                        if (_s(venue['contact_phone']).isNotEmpty)
                          Text(_s(venue['contact_phone'])),
                        if (_s(venue['contact_email']).isNotEmpty)
                          Text(_s(venue['contact_email'])),
                      ],
                      if (_s(venue['website_url']).isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Website',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () => _openWebsiteForVenue(venue),
                          child: Text(
                            _s(venue['website_url']),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          if (_s(venue['website_url']).isNotEmpty)
                            OutlinedButton.icon(
                              onPressed: () => _openWebsiteForVenue(venue),
                              icon: const Icon(Icons.language),
                              label: const Text('Open website'),
                            ),
                          FilledButton.icon(
                            onPressed: () => _openMapForVenue(venue),
                            icon: const Icon(Icons.directions),
                            label: const Text('Directions'),
                          ),
                        ],
                      ),
                      if (venue['is_home_venue'] == true) ...[
                        const SizedBox(height: 24),

                        const Text(
                          'Club Officers & Key Contacts',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),

                        const SizedBox(height: 12),

                        _buildClubOfficersSection(venue),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Container(
                  height: 260,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.map_outlined, size: 40),
                      const SizedBox(height: 12),
                      const Text('Map preview area'),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () => _openMapForVenue(venue),
                        icon: const Icon(Icons.directions),
                        label: const Text('Directions'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (_canManage)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                final changed = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VenueMaintainScreen(
                      clubId: widget.clubId,
                      venue: venue,
                    ),
                  ),
                );
                if (changed == true) await _load();
              },
              child: const Text('Edit'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildClubOfficersSection(Map<String, dynamic> venue) {
    final officers =
        (venue['club_officers'] as Map?)?.cast<String, dynamic>() ?? {};

    const roles = [
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

    return Column(
      children: roles.map((roleData) {
        final key = roleData[0];
        final label = roleData[1];

        final officer = (officers[key] as Map?)?.cast<String, dynamic>() ?? {};

        final name = _s(officer['name']);
        final email = _s(officer['email']);
        final phone = _s(officer['phone']);

        if (name.isEmpty && email.isEmpty && phone.isEmpty) {
          return const SizedBox.shrink();
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 6),

                if (name.isNotEmpty) Text(name),
                if (email.isNotEmpty) Text(email),
                if (phone.isNotEmpty) Text(phone),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  void _applyFilter() {
    final q = _searchText.trim().toLowerCase();

    setState(() {
      if (q.isEmpty) {
        _venues = List<Map<String, dynamic>>.from(_allVenues);
        return;
      }

      _venues = _allVenues.where((v) {
        final name = (v['name'] ?? '').toString().toLowerCase();
        final town = (v['town_city'] ?? '').toString().toLowerCase();
        final postcode = (v['postcode'] ?? '').toString().toLowerCase();

        return name.contains(q) || town.contains(q) || postcode.contains(q);
      }).toList();
    });
  }

  Future<void> _initScreen() async {
    try {
      await _loadUserPermissions();
      await _load();
    } catch (e, st) {
      debugPrint('Venues init failed: $e');
      debugPrintStack(stackTrace: st);

      if (mounted) {
        setState(() {
          _loadingPermissions = false;
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _loadUserPermissions() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      throw Exception('No logged-in user');
    }

    final myProfileId = (await supabase.rpc('my_member_profile_id')).toString();

    final superuserRow = await supabase
        .from('app_superusers')
        .select('user_id')
        .eq('user_id', user.id)
        .maybeSingle();

    _isSuperuser = superuserRow != null;

    final membership = await supabase
        .from('club_memberships')
        .select('id, club_id, member_profile_id, role')
        .eq('member_profile_id', myProfileId)
        .eq('club_id', widget.clubId)
        .maybeSingle();

    debugPrint('VENUES user.id       = ${user.id}');
    debugPrint('VENUES myProfileId   = $myProfileId');
    debugPrint('VENUES membership    = $membership');

    _currentMemberId = myProfileId;

    if (membership != null) {
      final role = (membership['role'] ?? '').toString().trim().toLowerCase();
      _isClubAdmin = role == 'admin';
    } else {
      _isClubAdmin = false;
    }

    debugPrint(
      'Venues perms: super=$_isSuperuser '
      'admin=$_isClubAdmin '
      'memberId=$_currentMemberId',
    );

    if (mounted) {
      setState(() {
        _loadingPermissions = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _initScreen();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await Supabase.instance.client
          .from('venues')
          .select(
            'id, club_id, name, is_home_venue, '
            'contact_name, contact_phone, contact_email, '
            'address_line1, address_line2, town_city, postcode, directions_url, '
            'website_url, google_maps_url, google_place_id, latitude, longitude, '
            'venue_master_id, club_officers',
          )
          .eq('club_id', widget.clubId)
          .order('name');

      _allVenues = List<Map<String, dynamic>>.from(rows)
        ..sort((a, b) => _s(a['name']).toLowerCase().compareTo(
          _s(b['name']).toLowerCase(),
        ));
      _applyFilter();
    } catch (e) {
      _error = '$e';
      _allVenues = [];
      _venues = [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createVenue() async {
    final name = TextEditingController();
    final contactName = TextEditingController();
    final contactPhone = TextEditingController();
    final contactEmail = TextEditingController();
    final address1 = TextEditingController();
    final address2 = TextEditingController();
    final town = TextEditingController();
    final postcode = TextEditingController();
    final directionsUrl = TextEditingController();

    bool isHome = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Create venue'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Venue name'),
                  ),
                  TextField(
                    controller: address1,
                    decoration: const InputDecoration(
                      labelText: 'Address line 1',
                    ),
                  ),
                  TextField(
                    controller: address2,
                    decoration: const InputDecoration(
                      labelText: 'Address line 2 (optional)',
                    ),
                  ),
                  TextField(
                    controller: town,
                    decoration: const InputDecoration(labelText: 'Town/City'),
                  ),
                  TextField(
                    controller: postcode,
                    decoration: const InputDecoration(labelText: 'Postcode'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: contactName,
                    decoration: const InputDecoration(
                      labelText: 'Contact name (optional)',
                    ),
                  ),
                  TextField(
                    controller: contactPhone,
                    decoration: const InputDecoration(
                      labelText: 'Contact phone (optional)',
                    ),
                  ),
                  TextField(
                    controller: contactEmail,
                    decoration: const InputDecoration(
                      labelText: 'Contact email (optional)',
                    ),
                  ),
                  TextField(
                    controller: directionsUrl,
                    decoration: const InputDecoration(
                      labelText: 'Directions URL (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: isHome,
                    onChanged: (v) => setStateDialog(() => isHome = v),
                    title: const Text('Home venue'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    final venueName = name.text.trim();
    if (venueName.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Venue name is required.')),
        );
      }
      return;
    }

    try {
      if (isHome) {
        final existing = _allVenues
            .where((v) => v['is_home_venue'] == true)
            .toList();

        if (existing.isNotEmpty) {
          final replace = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Replace Home Venue?'),
              content: Text(
                '${existing.first['name']} is already Home.\n'
                'Replace it with this one?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Replace'),
                ),
              ],
            ),
          );

          if (replace != true) return;

          await Supabase.instance.client
              .from('venues')
              .update({'is_home_venue': false})
              .eq('club_id', widget.clubId)
              .eq('is_home_venue', true);
        }
      }

      await Supabase.instance.client.rpc(
        'create_club_venue',
        params: {
          'p_club_id': widget.clubId,
          'p_name': venueName,
          'p_is_home_venue': isHome,
          'p_contact_name': contactName.text.trim(),
          'p_contact_phone': contactPhone.text.trim(),
          'p_contact_email': contactEmail.text.trim(),
          'p_address_line1': address1.text.trim(),
          'p_address_line2': address2.text.trim(),
          'p_town_city': town.text.trim(),
          'p_postcode': postcode.text.trim(),
          'p_directions_url': directionsUrl.text.trim(),
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Venue created ✅')));
      }

      await _load();
    } on PostgrestException catch (e) {
      if (mounted) {
        final msg = e.message.contains('already exists for this club')
            ? 'A venue with this name already exists for this club.'
            : 'Create venue error: ${e.message}';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Create venue error: $e')));
      }
    }
  }

  Future<void> _editVenue(Map<String, dynamic> venue) async {
    final id = venue['id']?.toString();
    if (id == null || id.isEmpty) return;

    final name = TextEditingController(text: (venue['name'] ?? '').toString());
    final contactName = TextEditingController(
      text: (venue['contact_name'] ?? '').toString(),
    );
    final contactPhone = TextEditingController(
      text: (venue['contact_phone'] ?? '').toString(),
    );
    final contactEmail = TextEditingController(
      text: (venue['contact_email'] ?? '').toString(),
    );
    final address1 = TextEditingController(
      text: (venue['address_line1'] ?? '').toString(),
    );
    final address2 = TextEditingController(
      text: (venue['address_line2'] ?? '').toString(),
    );
    final town = TextEditingController(
      text: (venue['town_city'] ?? '').toString(),
    );
    final postcode = TextEditingController(
      text: (venue['postcode'] ?? '').toString(),
    );
    final directionsUrl = TextEditingController(
      text: (venue['directions_url'] ?? '').toString(),
    );

    bool isHome = venue['is_home_venue'] == true;

    final officers =
        (venue['club_officers'] as Map?)?.cast<String, dynamic>() ?? {};

    final officerNameControllers = <String, TextEditingController>{};
    final officerEmailControllers = <String, TextEditingController>{};
    final officerPhoneControllers = <String, TextEditingController>{};

    for (final role in clubOfficerRoles) {
      final key = role[0];
      final officer = (officers[key] as Map?)?.cast<String, dynamic>() ?? {};

      officerNameControllers[key] = TextEditingController(
        text: _s(officer['name']),
      );
      officerEmailControllers[key] = TextEditingController(
        text: _s(officer['email']),
      );
      officerPhoneControllers[key] = TextEditingController(
        text: _s(officer['phone']),
      );
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Edit venue'),
          content: SizedBox(
            width: 720,
            height: MediaQuery.of(context).size.height * 0.75,
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: 'Venue name',
                      ),
                    ),
                    TextField(
                      controller: address1,
                      decoration: const InputDecoration(
                        labelText: 'Address line 1',
                      ),
                    ),
                    TextField(
                      controller: address2,
                      decoration: const InputDecoration(
                        labelText: 'Address line 2 (optional)',
                      ),
                    ),
                    TextField(
                      controller: town,
                      decoration: const InputDecoration(labelText: 'Town/City'),
                    ),
                    TextField(
                      controller: postcode,
                      decoration: const InputDecoration(labelText: 'Postcode'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: contactName,
                      decoration: const InputDecoration(
                        labelText: 'Contact name (optional)',
                      ),
                    ),
                    TextField(
                      controller: contactPhone,
                      decoration: const InputDecoration(
                        labelText: 'Contact phone (optional)',
                      ),
                    ),
                    TextField(
                      controller: contactEmail,
                      decoration: const InputDecoration(
                        labelText: 'Contact email (optional)',
                      ),
                    ),
                    TextField(
                      controller: directionsUrl,
                      decoration: const InputDecoration(
                        labelText: 'Directions URL (optional)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: isHome,
                      onChanged: (v) => setStateDialog(() => isHome = v),
                      title: const Text('Home venue'),
                    ),
                    if (isHome) ...[
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 8),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Club Officers & Key Contacts',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      for (final role in clubOfficerRoles) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            role[1],
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        TextField(
                          controller: officerNameControllers[role[0]],
                          decoration: const InputDecoration(labelText: 'Name'),
                        ),
                        TextField(
                          controller: officerEmailControllers[role[0]],
                          decoration: const InputDecoration(labelText: 'Email'),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        TextField(
                          controller: officerPhoneControllers[role[0]],
                          decoration: const InputDecoration(
                            labelText: 'Telephone',
                          ),
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    final venueName = name.text.trim();
    if (venueName.isEmpty) return;

    try {
      final officersPayload = <String, dynamic>{};

      for (final role in clubOfficerRoles) {
        final key = role[0];

        officersPayload[key] = {
          'name': officerNameControllers[key]?.text.trim() ?? '',
          'email': officerEmailControllers[key]?.text.trim() ?? '',
          'phone': officerPhoneControllers[key]?.text.trim() ?? '',
        };
      }

      if (isHome) {
        final existing = _allVenues
            .where(
              (v) => v['is_home_venue'] == true && v['id'].toString() != id,
            )
            .toList();

        if (existing.isNotEmpty) {
          final replace = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Replace Home Venue?'),
              content: Text(
                '${existing.first['name']} is already marked Home.\n'
                'Make this the new Home venue instead?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Replace'),
                ),
              ],
            ),
          );

          if (replace != true) return;

          await Supabase.instance.client
              .from('venues')
              .update({'is_home_venue': false})
              .eq('club_id', widget.clubId)
              .eq('is_home_venue', true);
        }
      }

      await Supabase.instance.client
          .from('venues')
          .update({
            'name': venueName,
            'is_home_venue': isHome,
            'contact_name': contactName.text.trim(),
            'contact_phone': contactPhone.text.trim(),
            'contact_email': contactEmail.text.trim(),
            'address_line1': address1.text.trim(),
            'address_line2': address2.text.trim(),
            'town_city': town.text.trim(),
            'postcode': postcode.text.trim(),
            'directions_url': directionsUrl.text.trim(),
            'club_officers': isHome ? officersPayload : {},
          })
          .eq('id', id);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Venue updated ✅')));
      }

      await _load();
    } on PostgrestException catch (e) {
      if (mounted) {
        final msg = e.message.contains('already exists for this club')
            ? 'A venue with this name already exists for this club.'
            : 'Edit venue error: ${e.message}';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Edit venue error: $e')));
      }
    }
  }

  Future<void> _deleteVenue(Map<String, dynamic> venue) async {
    final id = venue['id']?.toString();
    final name = (venue['name'] ?? '').toString();

    if (id == null || id.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete venue'),
        content: Text(
          'Are you sure you want to delete "$name"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final fixtureLinks = await Supabase.instance.client
          .from('fixtures')
          .select('id')
          .or('venue_id.eq.$id,opponent_venue_id.eq.$id')
          .limit(1);

      if ((fixtureLinks as List).isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'This venue cannot be deleted because it is linked to existing fixtures.',
              ),
            ),
          );
        }
        return;
      }

      await Supabase.instance.client.from('venues').delete().eq('id', id);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Venue deleted ✅')));
      }

      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Delete venue error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Venues — ${widget.clubName}'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton(
              onPressed: () async {
                final changed = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VenueMaintainScreen(clubId: widget.clubId),
                  ),
                );

                if (changed == true) {
                  await _load();
                }
              },
              child: const Icon(Icons.add),
            )
          : null,
      body: (_loading || _loadingPermissions)
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : _allVenues.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _canManage
                      ? 'No venues yet.\nTap + to add one.'
                      : 'No venues available.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search venues...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchText.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchText = '';
                                _applyFilter();
                              },
                            ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (value) {
                      _searchText = value;
                      _applyFilter();
                    },
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _venues.length,
                    itemBuilder: (_, i) {
                      final v = _venues[i];
                      final name = (v['name'] ?? '').toString();
                      final isHome = v['is_home_venue'] == true;
                      final town = (v['town_city'] ?? '').toString().trim();
                      final pc = (v['postcode'] ?? '').toString().trim();

                      return ListTile(
                        onTap: () async {
                          final changed = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => VenueMaintainScreen(
                                clubId: widget.clubId,
                                venue: v,
                              ),
                            ),
                          );

                          if (changed == true) {
                            await _load();
                          }
                        },
                        tileColor: isHome
                            ? Colors.green.withOpacity(0.08)
                            : Colors.orange.withOpacity(0.08),
                        title: Text(name),
                        subtitle: Text(
                          [
                            if (isHome) 'Home venue' else 'Opponent venue',
                            if (town.isNotEmpty) town,
                            if (pc.isNotEmpty) pc,
                          ].join(' • '),
                        ),
                        trailing: _canManage
                            ? IconButton(
                                tooltip: 'Delete venue',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _deleteVenue(v),
                              )
                            : null,
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
