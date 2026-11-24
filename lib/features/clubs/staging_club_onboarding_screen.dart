import 'onboarding_manual_downloads.dart';
import 'club_online_scaffold.dart';
import 'opponent_discovery_screen.dart';
import 'my_clubs_screen.dart';
import '../members/inactive_member_invitations_screen.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../secrets.dart';
import 'club_start_screen.dart';
import 'onboarding_activities_screen.dart';
import 'onboarding_member_import.dart';
import 'onboarding_members_screen.dart';

/// Authenticated staging pilot. Never uses the rehearsal's simulated identity checks.
class StagingClubOnboardingScreen extends StatefulWidget {
  const StagingClubOnboardingScreen({
    super.key,
    this.secretaryLoader,
    this.creator,
    this.clubBuilder,
    this.lookup,
    this.placeLookup,
  });
  final Future<OnboardingMember> Function()? secretaryLoader;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)?
  creator;
  final Widget Function(String, String)? clubBuilder;
  final Future<Map<String, dynamic>> Function(String, String)? lookup;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)?
  placeLookup;
  @override
  State<StagingClubOnboardingScreen> createState() =>
      _StagingClubOnboardingScreenState();
}

class _StagingClubOnboardingScreenState
    extends State<StagingClubOnboardingScreen> {
  String _requestId = const Uuid().v4();
  SharedPreferences? _draftPreferences;
  String? _draftKey;
  Timer? _draftTimer;
  bool _discardedDraft = false;
  Timer? _clubSearchTimer, _venueSearchTimer;
  int _clubSearchVersion = 0, _venueSearchVersion = 0;
  bool _findingClubs = false, _findingVenues = false;
  String? _clubSearchMessage, _venueSearchMessage, _venueDecisionKey;
  List<Map<String, dynamic>> _nameVenueMatches = [];
  final _name = TextEditingController(text: '');
  final _venue = TextEditingController(text: 'Club home venue');
  final _address = TextEditingController();
  final _address2 = TextEditingController();
  final _town = TextEditingController();
  final _postcode = TextEditingController();
  final _placeQuery = TextEditingController();
  bool _venueEdited = false, _looking = false;
  Map<String, dynamic> _placeMetadata = {};
  Map<String, dynamic>? _registration;
  List<Map<String, dynamic>> _clubMatches = [],
      _venueMatches = [],
      _googleMatches = [];
  String? _lookupMessage;
  final _green = TextEditingController(text: 'Main green');
  final _rinks = TextEditingController(text: '6');
  final _start = TextEditingController(text: '09:00');
  final _end = TextEditingController(text: '22:00');
  String _discipline = 'indoor';
  Set<String> _activities = {
    for (final activity in onboardingActivities) activity.id,
  };
  List<OnboardingMember> _members = [];
  bool _loading = true, _saving = false;
  bool _canLeave = false;
  int _step = 0;
  String? _error;
  Map<String, dynamic>? _created;
  Map<String, dynamic>? _submitted;
  final _scroll = ScrollController();
  final _titles = const [
    'Welcome to your club setup',
    'Your club',
    'Your home venue',
    'Your greens and rinks',
    'When your club is open',
    'The activities you offer',
    'Your members',
    'Your teams can wait',
    'A gentle first check',
    'Review and create your club',
  ];

  static const _cardTitles = [
    'Start at your own pace',
    'Check your club’s name',
    'Confirm where your club plays',
    'Make the rink diary match your green',
    'Set the times members can book',
    'Choose the activities your club offers',
    'Review members before inviting anyone',
    'Your teams can wait until later',
    'Check your starting settings',
    'Check the summary before creating your club',
  ];
  static const _cardColours = [
    Color(0xffe7f1fc),
    Color(0xffe7f1fc),
    Color(0xffe7f1fc),
    Color(0xffe6f3e9),
    Color(0xffe7f1fc),
    Color(0xffe6f3e9),
    Color(0xffffefdc),
    Color(0xffe6f3e9),
    Color(0xffffefdc),
    Color(0xffe6f3e9),
  ];

  Widget _notice(
    String message, {
    String? title,
    Color background = const Color(0xffe7f1fc),
    Color foreground = const Color(0xff183b59),
    IconData icon = Icons.info_outline,
  }) => Card(
    margin: const EdgeInsets.symmetric(vertical: 8),
    color: background,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: foreground.withValues(alpha: .18)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foreground, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: DefaultTextStyle.merge(
              style: TextStyle(color: foreground),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(message),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _clubSearchTimer?.cancel();
    _venueSearchTimer?.cancel();
    for (final c in [
      _name,
      _venue,
      _address,
      _address2,
      _town,
      _postcode,
      _placeQuery,
      _green,
      _rinks,
      _start,
      _end,
    ]) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      if (widget.secretaryLoader != null) {
        _members = [await widget.secretaryLoader!()];
        if (mounted) setState(() => _loading = false);
        return;
      }
      if (!const {
        'egxdkaotepgfjmszxlyn.supabase.co',
        'xfjelvvfoguzukgvxchh.supabase.co',
      }.contains(Uri.parse(Secrets.supabaseUrl).host)) {
        throw StateError('Club setup is unavailable for this environment.');
      }
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null || user.isAnonymous) {
        throw StateError('Please sign in first.');
      }
      final allowed = await client
          .from('app_superusers')
          .select('user_id')
          .eq('user_id', user.id)
          .maybeSingle();
      final registration = await client.rpc('my_staging_club_registration');
      if (registration is Map)
        _registration = Map<String, dynamic>.from(registration);
      if (allowed == null && _registration == null) {
        throw StateError('Verify your club and email before starting setup.');
      }
      if (_registration != null)
        await client.rpc('prepare_staging_club_secretary');
      final p = await client
          .from('member_profiles')
          .select('first_name,last_name,display_name,email_address,phone')
          .eq('user_id', user.id)
          .single();
      final display = '${p['display_name'] ?? ''}'.trim().split(RegExp(r'\s+'));
      _members = [
        OnboardingMember(
          firstName: '${p['first_name'] ?? display.first}',
          surname: '${p['last_name'] ?? display.skip(1).join(' ')}',
          email: '${p['email_address'] ?? user.email ?? ''}',
          phone: '${p['phone'] ?? ''}',
          role: 'admin',
          active: true,
        ),
      ];
      _draftPreferences = await SharedPreferences.getInstance();
      _draftKey = _registration == null
          ? 'bowls-staging-club-setup-draft-v1-${user.id}'
          : 'bowls-staging-verified-setup-${user.id}-${_registration!['id']}';
      final raw = _draftPreferences!.getString(_draftKey!);
      if (raw != null) {
        try {
          final draft = Map<String, dynamic>.from(jsonDecode(raw) as Map);
          for (final entry in <String, TextEditingController>{
            'name': _name,
            'venue_name': _venue,
            'address_line1': _address,
            'address_line2': _address2,
            'town_city': _town,
            'postcode': _postcode,
            'green_name': _green,
            'rink_count': _rinks,
            'start_time': _start,
            'end_time': _end,
            'place_query': _placeQuery,
          }.entries) {
            if (draft[entry.key] != null) {
              entry.value.text = '${draft[entry.key]}';
            }
          }
          _venueEdited = draft['venue_edited'] == true;
          if (['indoor', 'outdoor'].contains(draft['discipline'])) {
            _discipline = draft['discipline'] as String;
          }
          _activities = (draft['activities'] as List? ?? [])
              .whereType<String>()
              .where((id) => onboardingActivities.any((a) => a.id == id))
              .toSet();
          for (final r in draft['members'] as List? ?? []) {
            _members.add(
              OnboardingMember(
                firstName: '${r['first_name'] ?? ''}',
                surname: '${r['last_name'] ?? ''}',
                email: '${r['email'] ?? ''}',
                phone: '${r['phone'] ?? ''}',
              ),
            );
          }
          _step = (int.tryParse('${draft['step']}') ?? 0).clamp(0, 9);
          if (RegExp(
            r'^[0-9a-fA-F-]{36}$',
          ).hasMatch('${draft['request_id']}')) {
            _requestId = draft['request_id'] as String;
          }
          if (draft['submitted'] is Map) {
            _submitted = Map<String, dynamic>.from(draft['submitted'] as Map);
            _step = 9;
          }
          if (draft['place_metadata'] is Map) {
            _placeMetadata = Map<String, dynamic>.from(
              draft['place_metadata'] as Map,
            );
          }
          _lookupMessage =
              'Your saved draft has been restored. No club has been created from this draft yet.';
        } catch (_) {
          _lookupMessage =
              'The previous draft could not be restored. Please check the fields below.';
        }
      }
      if (_registration != null) {
        final place = Map<String, dynamic>.from(_registration!['place'] as Map);
        _name.text = '${place['name']}';
        _venue.text = _name.text;
        _address.text = '${place['addressLine1'] ?? ''}';
        _address2.text = '${place['addressLine2'] ?? ''}';
        _town.text = '${place['townCity'] ?? ''}';
        _postcode.text = '${place['postcode'] ?? ''}';
        _venueEdited = true;
        _placeMetadata = {
          if (place['source'] != 'website') 'google_place_id': place['placeId'],
          'latitude': place['latitude'],
          'longitude': place['longitude'],
          'website_url': place['websiteUrl'],
          'google_maps_url': place['googleMapsUrl'],
        };
      }
      if (mounted) {
        setState(() => _loading = false);
        if (_step == 2 && _registration == null)
          _scheduleVenueSearch(immediate: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Unable to start setup: $e';
        });
      }
    }
  }

  int? _minute(String text) {
    if (!RegExp(r'^\d{2}:\d{2}$').hasMatch(text)) {
      return null;
    }
    final p = text.split(':').map(int.parse).toList();
    return p[0] < 24 && p[1] < 60 ? p[0] * 60 + p[1] : null;
  }

  Future<void> _persistDraft() async {
    if (_discardedDraft ||
        _draftKey == null ||
        _draftPreferences == null ||
        _created != null) {
      return;
    }
    try {
      await _draftPreferences!.setString(
        _draftKey!,
        jsonEncode({
          'request_id': _requestId,
          'name': _name.text,
          'venue_name': _venue.text,
          'address_line1': _address.text,
          'address_line2': _address2.text,
          'town_city': _town.text,
          'postcode': _postcode.text,
          'green_name': _green.text,
          'rink_count': _rinks.text,
          'start_time': _start.text,
          'end_time': _end.text,
          'discipline': _discipline,
          'activities': _activities.toList(),
          'venue_edited': _venueEdited,
          'place_query': _placeQuery.text,
          'place_metadata': _placeMetadata,
          'step': _step,
          'submitted': _submitted,
          'members': [
            for (final m in _members.where((m) => m.role != 'admin'))
              {
                'first_name': m.firstName,
                'last_name': m.surname,
                'email': m.email,
                'phone': m.phone,
              },
          ],
        }),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Your draft could not be saved on this device. Keep this page open until you finish.',
        );
      }
    }
  }

  void _saveDraftSoon() {
    _draftTimer?.cancel();
    _draftTimer = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_persistDraft()),
    );
  }

  Map<int, String> get _missing => {
    if (_name.text.trim().isEmpty) 1: 'Enter your club name',
    if (_venue.text.trim().isEmpty || _address.text.trim().isEmpty)
      2: 'Enter your venue name and address',
    if (_green.text.trim().isEmpty ||
        (int.tryParse(_rinks.text) ?? 0) < 1 ||
        (int.tryParse(_rinks.text) ?? 41) > 40)
      3: 'Enter your green name and 1–40 rinks',
    if (_minute(_start.text) == null ||
        _minute(_end.text) == null ||
        (_minute(_start.text) ?? 1440) >= (_minute(_end.text) ?? 0))
      4: 'Set opening and closing times in HH:MM order',
    if (_activities.isEmpty) 5: 'Choose at least one activity',
  };
  void _go(int step) {
    if (step == 2 && !_venueEdited) _venue.text = _name.text.trim();
    if (step == 2 && _placeQuery.text.isEmpty) {
      _placeQuery.text = _name.text.trim();
    }
    setState(() {
      _step = step;
      _error = null;
      _lookupMessage = null;
    });
    if (_scroll.hasClients) {
      _scroll.jumpTo(0);
    }
    unawaited(_persistDraft());
    if (step == 2 && _registration == null)
      _scheduleVenueSearch(immediate: true);
  }

  Widget _field(String label, TextEditingController c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: TextField(
      controller: c,
      enabled:
          !_saving &&
          !_looking &&
          _submitted == null &&
          !(_registration != null &&
              [
                _name,
                _venue,
                _address,
                _address2,
                _town,
                _postcode,
                _placeQuery,
              ].contains(c)),
      onChanged: (_) => setState(() {
        _error = null;
        if (c == _venue) _venueEdited = true;
        if ([_venue, _address, _address2, _town, _postcode].contains(c)) {
          _placeMetadata = {};
        }
        if (c == _name) {
          _clubMatches = [];
          _scheduleClubSearch();
        }
        if ([_venue, _address, _address2, _town, _postcode].contains(c)) {
          _venueDecisionKey = null;
        }
        if (c == _venue || c == _postcode) _scheduleVenueSearch();
        _saveDraftSoon();
      }),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
  Future<void> _chooseActivities() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OnboardingActivitiesScreen(
          initial: _activities,
          rehearsal: false,
          onSave: (v) => setState(() => _activities = v),
        ),
      ),
    );
    await _persistDraft();
  }

  Future<void> _chooseMembers() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OnboardingMembersScreen(
          initial: _members,
          rehearsal: false,
          memberLookup: (members) async {
            final result = await Supabase.instance.client.rpc(
              'lookup_staging_onboarding_members',
              params: {
                'p_members': [
                  for (var i = 0; i < members.length; i++)
                    {'row': i, 'email': members[i].email},
                ],
              },
            );
            return (result as List)
                .map((r) => Map<String, dynamic>.from(r as Map))
                .toList();
          },
          onSave: (v) => setState(() => _members = v),
        ),
      ),
    );
    await _persistDraft();
  }

  Future<Map<String, dynamic>> _lookup(String name, String postcode) async =>
      widget.lookup != null
      ? widget.lookup!(name, postcode)
      : Map<String, dynamic>.from(
          await Supabase.instance.client.rpc(
                'lookup_staging_onboarding',
                params: {'p_name': name, 'p_postcode': postcode},
              )
              as Map,
        );

  Future<bool> _checkClub() async {
    _clubSearchTimer?.cancel();
    final version = ++_clubSearchVersion;
    final name = _name.text.trim();
    setState(() {
      _looking = true;
      _findingClubs = false;
      _error = null;
    });
    try {
      final result = await _lookup(name, '');
      if (!mounted ||
          version != _clubSearchVersion ||
          name != _name.text.trim()) {
        return false;
      }
      _clubMatches = (result['clubs'] as List? ?? [])
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      final duplicate = _clubMatches.any((c) => c['same_name'] == true);
      setState(
        () => _lookupMessage = duplicate
            ? 'This club is already registered. Open it instead of creating it again.'
            : _clubMatches.isEmpty
            ? 'No registered club with this name was found.'
            : 'Possible matches are shown below. Check these before continuing.',
      );
      return !duplicate;
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The existing-club check could not finish. Your draft is kept. Please try again.',
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _looking = false);
    }
  }

  String get _venueQueryKey =>
      '${_venue.text.trim().toLowerCase()}|${_postcode.text.replaceAll(RegExp(r'\s'), '').toLowerCase()}';
  void _scheduleClubSearch() {
    _clubSearchTimer?.cancel();
    ++_clubSearchVersion;
    _nameVenueMatches = [];
    _clubSearchMessage = null;
    _findingClubs = false;
    if (_name.text.trim().length < 3) return;
    _clubSearchTimer = Timer(const Duration(milliseconds: 450), () async {
      final version = ++_clubSearchVersion;
      final name = _name.text.trim();
      if (!mounted) return;
      setState(() => _findingClubs = true);
      try {
        final result = await _lookup(name, '');
        if (!mounted ||
            version != _clubSearchVersion ||
            name != _name.text.trim()) {
          return;
        }
        setState(() {
          _clubMatches = (result['clubs'] as List? ?? [])
              .map((r) => Map<String, dynamic>.from(r as Map))
              .toList();
          _nameVenueMatches = (result['venues'] as List? ?? [])
              .map((r) => Map<String, dynamic>.from(r as Map))
              .toList();
          _clubSearchMessage = _clubMatches.any((c) => c['same_name'] == true)
              ? 'This club is already registered. Open it instead of creating it again.'
              : _clubMatches.isEmpty && _nameVenueMatches.isEmpty
              ? 'No matching registered club or saved venue found.'
              : 'Matching records are shown below. A saved opponent venue is an address suggestion, not a club registration.';
        });
      } catch (_) {
        if (mounted && version == _clubSearchVersion) {
          setState(
            () => _clubSearchMessage =
                'The automatic check could not finish. We will check again when you continue.',
          );
        }
      } finally {
        if (mounted && version == _clubSearchVersion) {
          setState(() => _findingClubs = false);
        }
      }
    });
  }

  void _scheduleVenueSearch({bool immediate = false}) {
    _venueSearchTimer?.cancel();
    ++_venueSearchVersion;
    _venueMatches = [];
    _venueSearchMessage = null;
    _findingVenues = false;
    if (_venue.text.trim().length < 3 &&
        _postcode.text.replaceAll(RegExp(r'\s'), '').length < 5) {
      return;
    }
    _venueSearchTimer = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 450),
      () => unawaited(_searchVenues()),
    );
  }

  Future<bool> _searchVenues({bool blocking = false}) async {
    _venueSearchTimer?.cancel();
    final version = ++_venueSearchVersion;
    final queryKey = _venueQueryKey;
    final name = _venue.text.trim(), postcode = _postcode.text.trim();
    if (name.length < 3 && postcode.replaceAll(RegExp(r'\s'), '').length < 5) {
      return false;
    }
    setState(() {
      _findingVenues = true;
      if (blocking) _looking = true;
    });
    try {
      final result = await _lookup(name, postcode);
      if (!mounted ||
          version != _venueSearchVersion ||
          queryKey != _venueQueryKey) {
        return false;
      }
      setState(() {
        _venueMatches = (result['venues'] as List? ?? [])
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
        _venueSearchMessage = _venueMatches.isEmpty
            ? 'No existing venue matched. Your entered address is unchanged.'
            : 'Choose a venue to copy its address. Its existing record will not be changed or moved.';
      });
      return _venueMatches.isNotEmpty;
    } catch (_) {
      if (mounted && version == _venueSearchVersion) {
        setState(
          () => _venueSearchMessage =
              'Venue lookup is unavailable. Your entered address is unchanged.',
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          if (version == _venueSearchVersion) _findingVenues = false;
          if (blocking) _looking = false;
        });
      }
    }
  }

  Future<void> _continue() async {
    if (_step == 1 && _name.text.trim().isNotEmpty && !await _checkClub()) {
      return;
    }
    if (!mounted) return;
    if (_step == 2) {
      final found = await _searchVenues(blocking: true);
      if (!mounted) return;
      if (found && _venueDecisionKey != _venueQueryKey) {
        setState(
          () => _venueSearchMessage =
              'We found saved venues. Choose the correct address below, or keep your entered address.',
        );
        return;
      }
    }
    if (_missing.containsKey(_step)) {
      setState(() => _error = _missing[_step]);
      return;
    }
    _go(_step + 1);
  }

  Widget _venueSuggestions(List<Map<String, dynamic>> venues) => Column(
    children: [
      for (final v in venues)
        Card(
          color: const Color(0xffe7f1fc),
          surfaceTintColor: Colors.transparent,
          child: ListTile(
            title: Text('${v['name']}'),
            subtitle: Text(
              '${v['address_line1'] ?? ''} · ${v['town_city'] ?? ''} · ${v['postcode'] ?? ''}\n'
              '${v['is_home_venue'] == true ? 'Home venue' : 'Opponent venue'} in ${v['source_club_name']}',
            ),
            trailing: TextButton(
              onPressed: _looking ? null : () => _useVenue(v),
              child: const Text('Use address'),
            ),
          ),
        ),
    ],
  );

  Future<Map<String, dynamic>> _places(Map<String, dynamic> body) async {
    if (widget.placeLookup != null) return widget.placeLookup!(body);
    final response = await Supabase.instance.client.functions.invoke(
      'staging-onboarding-places',
      body: body,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> _findGoogle() async {
    setState(() {
      _looking = true;
      _lookupMessage = null;
      _error = null;
    });
    try {
      final result = await _places({
        'action': 'search',
        'query': _placeQuery.text.trim(),
      });
      if (!mounted) return;
      setState(() {
        _googleMatches = (result['places'] as List? ?? [])
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
        _lookupMessage = _googleMatches.isEmpty
            ? 'No bowls club was found on Google. Your manual address is unchanged. '
                  'Please contact Wayne if the club cannot be confirmed. Your entered address has been kept.'
            : 'Choose the correct club to review and fill its address. A Google match does not create or join that club.';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _lookupMessage =
              'Google lookup is unavailable or its daily limit has been reached. '
              'Your entered address is unchanged. You can retry later.',
        );
      }
    } finally {
      if (mounted) setState(() => _looking = false);
    }
  }

  Future<void> _selectGoogle(Map<String, dynamic> candidate) async {
    setState(() => _looking = true);
    try {
      final response = await _places({
        'action': 'details',
        'placeId': candidate['placeId'],
      });
      if (!mounted) return;
      final p = Map<String, dynamic>.from(response['place'] as Map);
      _useVenue({
        'name': p['name'],
        'address_line1': p['addressLine1'],
        'address_line2': p['addressLine2'],
        'town_city': p['townCity'],
        'postcode': p['postcode'],
        'google_place_id': p['placeId'],
        'latitude': p['latitude'],
        'longitude': p['longitude'],
        'website_url': p['websiteUrl'],
        'google_maps_url': p['googleMapsUrl'],
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _lookupMessage =
              'The Google address could not be loaded. Your previous address is unchanged.',
        );
      }
    } finally {
      if (mounted) setState(() => _looking = false);
    }
  }

  void _useVenue(Map<String, dynamic> v) {
    _venueSearchTimer?.cancel();
    ++_venueSearchVersion;
    _findingVenues = false;
    setState(() {
      _error = null;
      _venue.text = '${v['name'] ?? _venue.text}';
      _venueEdited = true;
      _address.text = '${v['address_line1'] ?? ''}';
      _address2.text = '${v['address_line2'] ?? ''}';
      _town.text = '${v['town_city'] ?? ''}';
      _postcode.text = '${v['postcode'] ?? ''}';
      _placeMetadata = {
        for (final k in [
          'google_place_id',
          'latitude',
          'longitude',
          'website_url',
          'google_maps_url',
        ])
          if (v[k] != null) k: v[k],
      };
      _venueDecisionKey = _venueQueryKey;
      _lookupMessage =
          'Address filled in for review. Check it before continuing. '
          '${v['registered_club_id'] != null ? 'This home venue is already used by ${v['source_club_name']}; check that you are not registering the same club again.' : 'No existing venue record has been changed.'}';
    });
    unawaited(_persistDraft());
  }

  Widget _clubMatchesView() => Column(
    children: [
      for (final c in _clubMatches)
        Card(
          color: c['same_name'] == true
              ? const Color(0xfffce8e6)
              : const Color(0xffffefdc),
          surfaceTintColor: Colors.transparent,
          child: ListTile(
            title: Text('${c['name']}'),
            subtitle: Text(
              c['same_name'] == true
                  ? 'Already registered — do not create again'
                  : 'Possible registered club match',
            ),
            trailing: c['can_open'] == true
                ? TextButton(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (_) => ClubStartScreen(
                          clubId: '${c['id']}',
                          clubName: '${c['name']}',
                          userId: Supabase.instance.client.auth.currentUser!.id,
                        ),
                      ),
                    ),
                    child: const Text('Open existing club'),
                  )
                : null,
          ),
        ),
    ],
  );

  Future<void> _create() async {
    if (_missing.isNotEmpty) {
      _go(_missing.keys.first);
      setState(() => _error = _missing.values.first);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Retain the exact payload and request ID after a network failure: retry cannot create a second club.
      _submitted ??= {
        if (_registration != null) 'registration_id': _registration!['id'],
        'name': _name.text.trim(),
        'venue_name': _venue.text.trim(),
        'address_line1': _address.text.trim(),
        'address_line2': _address2.text.trim(),
        'town_city': _town.text.trim(),
        'postcode': _postcode.text.trim().toUpperCase(),
        ..._placeMetadata,
        'green_name': _green.text.trim(),
        'rink_count': int.parse(_rinks.text),
        'discipline': _discipline,
        'start_time': _start.text,
        'end_time': _end.text,
        'activities': _activities.toList()..sort(),
        'members': [
          for (final m in _members.where((m) => m.role != 'admin'))
            {
              'first_name': m.firstName,
              'last_name': m.surname,
              'email': m.email,
              'phone': m.phone,
            },
        ],
      };
      await _persistDraft();
      final result = widget.creator != null
          ? await widget.creator!(_requestId, _submitted!)
          : await Supabase.instance.client.rpc(
              'create_staging_club_onboarding',
              params: {'p_request_id': _requestId, 'p_details': _submitted},
            );
      if (mounted) {
        setState(() => _created = Map<String, dynamic>.from(result as Map));
      }
      if (_draftKey != null) await _draftPreferences?.remove(_draftKey!);
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _submitted = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The result could not be confirmed. Keep this page open and retry. '
              'The same request will be checked before anything is created again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
      if (_created == null) await _persistDraft();
    }
  }

  Future<void> _leave() async {
    final leave = await showDialog<String>(
      context: context,
      builder: (context) => ClubOnlineDialog(
        title: const Text('Leave club setup?'),
        content: const Text(
          'Save this unfinished setup to continue later, or discard it if you no longer need it. Discarding removes only this draft, never an existing club or its members. No invitations have been sent.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'keep'),
            child: const Text('Keep setting up'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('Discard draft and leave'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Save draft and leave'),
          ),
        ],
      ),
    );
    if ((leave == 'save' || leave == 'discard') && mounted) {
      _draftTimer?.cancel();
      if (leave == 'discard') {
        _discardedDraft = true;
        try {
          if (_draftKey != null && _draftPreferences != null) {
            final removed = await _draftPreferences!.remove(_draftKey!);
            if (!removed) throw StateError('Draft removal failed');
          }
        } catch (_) {
          _discardedDraft = false;
          if (mounted)
            setState(
              () => _error =
                  'Your draft could not be discarded. Please try again.',
            );
          return;
        }
      } else {
        await _persistDraft();
      }
      if (!mounted) return;
      setState(() => _canLeave = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (_registration != null && !Navigator.of(context).canPop()) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(builder: (_) => const MyClubsScreen()),
            );
          } else {
            Navigator.of(context).pop();
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_created case final created?) {
      return ClubOnlineScaffold(
        appBar: AppBar(
          title: const Text('Club setup complete'),
          automaticallyImplyLeading: false,
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xff315c47),
                    size: 64,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Your club setup is complete',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Text(
                    '${created['name']}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Your club, venue, greens, rinks, activities and mailing lists are now saved.  '
                    'You are its first active member and administrator.',
                  ),
                  Text(
                    '${created['pending_members'] ?? _members.length - 1} member contacts are saved awaiting separate invitations. '
                    'No invitations have been sent.',
                  ),
                  if (_registration != null)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'For future sign-ins, use your existing password. If this is your first account, choose Forgotten password on the welcome screen to set your own password.',
                      ),
                    ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.travel_explore),
                    label: const Text('Find opponent clubs (optional)'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => OpponentDiscoveryScreen(
                          clubId: '${created['club_id']}',
                        ),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.mail_outline),
                    label: const Text('Review invitations (optional)'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => InactiveMemberInvitationsScreen(
                          clubId: '${created['club_id']}',
                        ),
                      ),
                    ),
                  ),
                  const Text(
                    'You can also invite members later from Membership. Creating the club sends nothing.',
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.home_outlined),
                    label: const Text('Go to my club'),
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            widget.clubBuilder?.call(
                              '${created['club_id']}',
                              '${created['name']}',
                            ) ??
                            ClubStartScreen(
                              clubId: '${created['club_id']}',
                              clubName: '${created['name']}',
                              userId:
                                  Supabase.instance.client.auth.currentUser!.id,
                            ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return PopScope(
      canPop: _canLeave,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_saving && _submitted == null) _leave();
      },
      child: ClubOnlineScaffold(
        appBar: AppBar(
          title: const Text('Get your club ready'),
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Leave setup',
            onPressed: _saving || _submitted != null ? null : _leave,
          ),
        ),
        bottomNavigationBar: _loading || _members.isEmpty
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    children: [
                      if (_step > 0)
                        OutlinedButton(
                          onPressed: _saving || _looking || _submitted != null
                              ? null
                              : () => _go(_step - 1),
                          child: const Text('Back'),
                        ),
                      if (_step < 9)
                        FilledButton(
                          onPressed: _saving || _looking ? null : _continue,
                          child: Text(_step == 0 ? 'Let’s begin' : 'Continue'),
                        ),
                      if (_step == 9)
                        FilledButton(
                          onPressed: _saving ? null : _create,
                          child: Text(
                            _saving
                                ? 'Creating your club…'
                                : _missing.isEmpty
                                ? 'Create club and finish'
                                : 'Show me what is missing',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 780),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Step ${_step + 1} of 10'),
                        LinearProgressIndicator(value: (_step + 1) / 10),
                        const SizedBox(height: 20),
                        Text(
                          _titles[_step],
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 16),
                        _notice(
                          'Your club is saved only when you choose Create club and finish. '
                          'Invitations are sent separately after setup. Other members remain inactive until they accept.',
                          title: _cardTitles[_step],
                          background: _cardColours[_step],
                          foreground:
                              _cardColours[_step] == const Color(0xffe6f3e9)
                              ? const Color(0xff214c33)
                              : _cardColours[_step] == const Color(0xffffefdc)
                              ? const Color(0xff70400c)
                              : const Color(0xff183b59),
                          icon: _step == 9
                              ? Icons.fact_check_outlined
                              : _step == 6 || _step == 8
                              ? Icons.checklist_outlined
                              : Icons.info_outline,
                        ),
                        if (_error != null)
                          _notice(
                            _error!,
                            title: 'Please check this before continuing',
                            background: const Color(0xfffce8e6),
                            foreground: const Color(0xff842c28),
                            icon: Icons.error_outline,
                          ),
                        if (_looking) const LinearProgressIndicator(),
                        if (_lookupMessage != null)
                          _notice(
                            _lookupMessage!,
                            title: 'Club and venue check',
                          ),
                        if (_step == 0 && _members.isNotEmpty)
                          const OnboardingManualDownloads(),
                        if (_members.isNotEmpty) ...[
                          if (_step == 0)
                            const Text(
                              'Make a small start. We will guide you through the essentials and show '
                              'everything before saving. Your signed-in account becomes the Secretary and administrator.',
                            ),
                          if (_step == 1) ...[
                            _field('Club name', _name),
                            const Text(
                              'Existing clubs and saved venues are checked as you type.',
                            ),
                            if (_findingClubs) const LinearProgressIndicator(),
                            if (_clubSearchMessage != null)
                              Text(_clubSearchMessage!),
                            _clubMatchesView(),
                            if (_registration == null)
                              _venueSuggestions(_nameVenueMatches),
                            Text(
                              'Secretary: ${_members.first.name} · ${_members.first.email}',
                            ),
                          ],
                          if (_step == 2) ...[
                            _field('Venue name', _venue),
                            const Text(
                              'The venue is automatically your home venue. Keep the club name unless the playing venue has a different name.',
                            ),
                            if (_registration != null) ...[
                              Text(
                                _registration!['place']['source'] == 'website'
                                    ? 'Your club and address were confirmed from its website. Contact Wayne if a correction is needed.'
                                    : 'Your club and address were confirmed from Google. Contact Wayne if a correction is needed.',
                              ),
                              _field('Address line 1', _address),
                              _field('Address line 2', _address2),
                              _field('Town / city', _town),
                              _field('Postcode', _postcode),
                            ] else ...[
                              const Text(
                                'Matching saved venues appear automatically below as you type the name or postcode.',
                              ),
                              if (_findingVenues)
                                const LinearProgressIndicator(),
                              if (_venueSearchMessage != null)
                                Text(_venueSearchMessage!),
                              _venueSuggestions(_venueMatches),
                              if (_venueMatches.isNotEmpty &&
                                  _venueDecisionKey != _venueQueryKey)
                                TextButton(
                                  onPressed: _looking
                                      ? null
                                      : () {
                                          setState(
                                            () => _venueDecisionKey =
                                                _venueQueryKey,
                                          );
                                          _continue();
                                        },
                                  child: const Text('Keep my entered address'),
                                ),
                              _field('Address line 1', _address),
                              _field('Address line 2 (optional)', _address2),
                              _field('Town / city', _town),
                              _field('Postcode', _postcode),
                              const Divider(height: 28),
                              _field('Google club search', _placeQuery),
                              const Text(
                                'Only the search text above is sent to Google when you press Search. Your typed address is not sent automatically.',
                              ),
                              OutlinedButton(
                                onPressed: _looking || _saving
                                    ? null
                                    : _findGoogle,
                                child: const Text('Search Google for a club'),
                              ),
                              for (final p in _googleMatches)
                                Card(
                                  color: const Color(0xffe6f3e9),
                                  surfaceTintColor: Colors.transparent,
                                  child: ListTile(
                                    title: Text('${p['name']}'),
                                    subtitle: Text(
                                      '${p['formattedAddress'] ?? ''}',
                                    ),
                                    trailing: TextButton(
                                      onPressed: _looking
                                          ? null
                                          : () => _selectGoogle(p),
                                      child: const Text('Use Google address'),
                                    ),
                                  ),
                                ),
                            ],
                          ],
                          if (_step == 3) ...[
                            _field('Green name', _green),
                            _field('Number of rinks (1–40)', _rinks),
                            _notice(
                              'Enter the maximum number of rinks you use on this green at any time of year. '
                              'If you sometimes use narrower rinks to accommodate more fixtures, include that layout in this number.',
                              title: 'Allow for your busiest layout',
                              background: const Color(0xffe7f1fc),
                              foreground: const Color(0xff23496b),
                              icon: Icons.lightbulb_outline,
                            ),
                            DropdownButtonFormField<String>(
                              initialValue: _discipline,
                              decoration: const InputDecoration(
                                labelText: 'Discipline',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'indoor',
                                  child: Text('Indoor'),
                                ),
                                DropdownMenuItem(
                                  value: 'outdoor',
                                  child: Text('Outdoor'),
                                ),
                              ],
                              onChanged: _saving || _submitted != null
                                  ? null
                                  : (v) => setState(() => _discipline = v!),
                            ),
                            const Text(
                              'Rinks will be numbered from 1. You can change labels later in the club settings.',
                            ),
                          ],
                          if (_step == 4) ...[
                            _field('Club opens (HH:MM)', _start),
                            _field('Club closes (HH:MM)', _end),
                          ],
                          if (_step == 5) ...[
                            const Text(
                              'All choices here can be changed later. Once your general club settings '
                              'are set up, you can review and edit all these settings in Fixture Types.',
                            ),
                            for (final a in onboardingActivities.where(
                              (a) => _activities.contains(a.id),
                            ))
                              Text('• ${a.name}'),
                            OutlinedButton(
                              onPressed: _saving || _submitted != null
                                  ? null
                                  : _chooseActivities,
                              child: const Text('Choose your fixture types'),
                            ),
                            const Text(
                              'Open sessions, Drives, Aggregates and Coaching use Open participation. '
                              'Friendly matches and Team Trials use RSVP; League matches use Team selection. '
                              'Practice and member bookings use Pre-Select. Participation can be changed for a fixture.',
                            ),
                          ],
                          if (_step == 6) ...[
                            Text(
                              'Secretary: ${_members.first.name} · Administrator',
                            ),
                            Text(
                              '${_members.length - 1} reviewed contacts awaiting invitations',
                            ),
                            OutlinedButton(
                              onPressed: _saving || _submitted != null
                                  ? null
                                  : _chooseMembers,
                              child: const Text('Review or import members'),
                            ),
                          ],
                          if (_step == 7)
                            const Text(
                              'You can add teams and player pools later from your club. They are not required to finish setup.',
                            ),
                          if (_step == 8)
                            const Text(
                              'Your club will start with 12 general-purpose mailing lists, including Committee, Markers, '
                              'Newsletter Recipients and volunteer groups. All imported members are automatically marked for '
                              'Newsletter Recipients and will join that group when they accept their club invitation. '
                              'Until then, they remain inactive and receive no newsletters. Other lists start empty. '
                              'After setup, you can edit the lists and choose their members in Mailing Lists. '
                              'Check the diary, rink labels and fixture type defaults before inviting your pilot group. '
                              'Nothing is sent by completing setup.',
                            ),
                          if (_step == 9) ...[
                            for (final item in _missing.entries)
                              OutlinedButton(
                                onPressed: _saving ? null : () => _go(item.key),
                                child: Text(
                                  'Step ${item.key + 1}: ${item.value}',
                                ),
                              ),
                            Text(
                              'Club: ${_name.text}\nVenue: ${_venue.text}\n'
                              'Address line 1: ${_address.text}\nAddress line 2: ${_address2.text}\n'
                              'Town / city: ${_town.text}\nPostcode: ${_postcode.text}\n'
                              'Green: ${_green.text} · $_discipline · ${_rinks.text} rinks\nHours: ${_start.text}–${_end.text}',
                            ),
                            const SizedBox(height: 12),
                            for (final a in onboardingActivities.where(
                              (a) => _activities.contains(a.id),
                            ))
                              Text('• ${a.name}'),
                            Text(
                              'Secretary: ${_members.first.name} · Active member and administrator\n'
                              'Other contacts: ${_members.length - 1} · Awaiting invitations\n'
                              'Mailing lists: 12 empty general-purpose lists\nInvitations to be sent now: 0',
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
