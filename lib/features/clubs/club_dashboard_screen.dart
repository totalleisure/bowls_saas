// Dashboard venue navigation + approximate distance: 20260730-phase2d2-distance.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:async';

import 'club_home_screen.dart';
import 'package:bowls_saas/features/diary/rinks_day_view.dart';
import 'package:bowls_saas/features/diary/month_overview_screen.dart';

import '../members/members_screen.dart';
import '../communications/member_options_menu.dart';
import '../fixtures/fixture_display.dart';
import '../fixtures/fixture_details_page.dart';
import '../help/player_help_screen.dart';
import '../notifications/notifications_page.dart';
import '../dashboard/dashboard_filter_screen.dart';
import '../fixtures/fixtures_screen.dart';
import '../../core/utils/hex_color.dart';
import '../../core/utils/date_format.dart';
import '../../models/dashboard_fixture_filter.dart';
import '../../services/device_location_service.dart';
import '../../services/venue_actions_service.dart';

class ClubDashboardScreen extends StatefulWidget {
  final String clubId;
  final String clubName;

  const ClubDashboardScreen({
    super.key,
    required this.clubId,
    required this.clubName,
  });

  @override
  State<ClubDashboardScreen> createState() => _ClubDashboardScreenState();
}

class _ClubDashboardScreenState extends State<ClubDashboardScreen> {
  bool _isSuperuser = false;
  bool _isClubAdmin = false;
  bool _isSelector = false;
  bool _isFixtureCreator =
      false; // keep false for now unless you already have this

  bool _hasClubMembership = false;
  bool _isGuest = false;

  String? _currentMemberId;
  String? _mySexAtBirth;

  bool _loadingPermissions = true;

  bool _loading = true;

  int _unreadNotificationCount = 0;

  Timer? _notificationTimer;

  String? _error;
  String _myClubName = '';

  Map<String, String> _myAvailabilityByFixtureId = {};

  Map<String, dynamic>? _nextMatch;
  Map<String, dynamic>? _secondMatch;

  DeviceLocationPoint? _deviceLocation;
  bool _loadingDeviceLocation = false;
  bool _locationAttempted = false;
  String? _locationUnavailableReason;

  bool _shownNextFixturePopup = false;

  List<Map<String, dynamic>> _toRsvp = [];
  List<Map<String, dynamic>> _awaitingSelection = [];
  List<Map<String, dynamic>> _needsAcceptance = [];
  List<Map<String, dynamic>> _upcomingAccepted = [];
  List<Map<String, dynamic>> _fixturesManaging = [];
  List<Map<String, dynamic>> _openSessionsAndEvents = [];

  // Lookup maps (id -> display data)
  // Map<String, Map<String, String>> _greenById = {};
  // Map<String, Map<String, String>> _formatById = {};
  Map<String, String> _venueNameById = {};
  Map<String, String> _greenNameById = {};

  DashboardFixtureFilter _filter = const DashboardFixtureFilter();

  Color? _fixtureTypeBackgroundColor(Map<String, dynamic> fixture) {
    final competitionType =
        fixture['competition_type'] as Map<String, dynamic>?;
    final colourScheme =
        competitionType?['colour_scheme'] as Map<String, dynamic>?;

    if (colourScheme == null) return null;

    return colorFromHex(
      colourScheme['background_hex']?.toString(),
      fallback: Colors.grey.shade100,
    );
  }

  Color? _fixtureTypeForegroundColor(Map<String, dynamic> fixture) {
    final competitionType =
        fixture['competition_type'] as Map<String, dynamic>?;
    final colourScheme =
        competitionType?['colour_scheme'] as Map<String, dynamic>?;

    if (colourScheme == null) return null;

    return colorFromHex(
      colourScheme['foreground_hex']?.toString(),
      fallback: Colors.black87,
    );
  }

  String _fixtureTypeName(Map<String, dynamic> fixture) {
    final competitionType =
        fixture['competition_type'] as Map<String, dynamic>?;
    return (competitionType?['name'] ?? '').toString().trim();
  }

  bool _shouldShowFixtureTypeLine({
    required String title,
    required String fixtureTypeName,
  }) {
    final t = title.trim().toLowerCase();
    final ft = fixtureTypeName.trim().toLowerCase();

    if (ft.isEmpty) return false;
    if (t == ft) return false;
    if (t == 'home - $ft') return false;
    if (t == 'home — $ft') return false;
    if (t == 'away - $ft') return false;
    if (t == 'away — $ft') return false;

    return true;
  }

  String _selectionMode(Map<String, dynamic> fixture) {
    final competitionType =
        fixture['competition_type'] as Map<String, dynamic>?;
    return (competitionType?['selection_mode'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
  }

  String _timeUntilFixture(String isoUtc) {
    final start = parseClubTime(isoUtc);
    final diff = start.difference(DateTime.now());

    if (diff.inDays >= 2) return '${diff.inDays} days time';
    if (diff.inDays == 1) return '1 day time';

    final hours = diff.inHours;
    final mins = diff.inMinutes.remainder(60);

    if (hours > 0) return '$hours hours $mins mins time';
    return '$mins mins time';
  }

  bool _isOpenSessionFixture(Map<String, dynamic> fixture) {
    return _selectionMode(fixture) == 'open';
  }

  bool _usesRinks(Map<String, dynamic> fixture) {
    final competitionType =
        fixture['competition_type'] as Map<String, dynamic>?;
    final raw = competitionType?['uses_rinks'];

    if (raw == null) return true;
    return raw == true;
  }

  bool _isEventStyleFixture(Map<String, dynamic> fixture) {
    return !_usesRinks(fixture);
  }

  bool _isOpenSessionOrEvent(Map<String, dynamic> fixture) {
    return _isOpenSessionFixture(fixture) || _isEventStyleFixture(fixture);
  }

  String _dashboardCardTitle(Map<String, dynamic> fixture) {
    final fixtureLabel = (fixture['team_name'] ?? '').toString().trim();
    final typeName = _fixtureTypeName(fixture);

    if (_isEventStyleFixture(fixture)) {
      if (fixtureLabel.isNotEmpty) return fixtureLabel;
      if (typeName.isNotEmpty) return typeName;
      return 'Event';
    }

    if (_isOpenSessionFixture(fixture)) {
      if (fixtureLabel.isNotEmpty) return fixtureLabel;
      if (typeName.isNotEmpty) return typeName;
      return 'Open Session';
    }

    return fixtureTitleUnified(fixture, myClubName: _myClubName);
  }

  String _dashboardCardSubtitle(Map<String, dynamic> fixture) {
    final subtitle = fixtureSubtitleUnified(fixture);

    if (_isEventStyleFixture(fixture)) {
      final typeName = _fixtureTypeName(fixture);
      return typeName.isEmpty ? subtitle : '$subtitle • $typeName';
    }

    return subtitle;
  }

  bool _matchesFilter(Map<String, dynamic> f) {
    if (_filter.sections.isNotEmpty) {
      final section = (f['section'] ?? '').toString().toLowerCase().trim();
      if (!_filter.sections.contains(section)) return false;
    }

    final startAt = DateTime.tryParse((f['start_at'] ?? '').toString());

    if (startAt != null &&
        !_matchesPeriod(parseClubTime(startAt.toIso8601String()))) {
      return false;
    }

    if (_filter.categories.isNotEmpty) {
      final competitionType = f['competition_type'] as Map<String, dynamic>?;
      final tags = (competitionType?['tags'] as List<dynamic>? ?? const [])
          .map((e) => e.toString().toLowerCase().trim())
          .toSet();

      final isInternal = competitionType?['is_internal'] == true;

      bool matched = false;

      for (final selected in _filter.categories) {
        if (selected == 'internal') {
          if (isInternal) {
            matched = true;
            break;
          }
        } else {
          if (tags.contains(selected)) {
            matched = true;
            break;
          }
        }
      }

      if (!matched) return false;
    }

    if (_filter.fixtureTypeIds.isNotEmpty) {
      final typeId = (f['competition_type_id'] ?? '').toString();
      if (!_filter.fixtureTypeIds.contains(typeId)) return false;
    }

    return true;
  }

  bool get _canRsvpFromDashboard {
    return _hasClubMembership && !_isGuest;
  }

  bool _isEligibleForFixtureSection(Map<String, dynamic> fixture) {
    final section = (fixture['section'] ?? '').toString().trim().toLowerCase();

    if (section.isEmpty || section == 'mixed' || section == 'open') {
      return true;
    }

    final sex = (_mySexAtBirth ?? '').trim().toLowerCase();

    final isMale = sex == 'male' || sex == 'm';
    final isFemale = sex == 'female' || sex == 'f';

    if (section == 'mens' || section == 'men' || section == 'male') {
      return isMale;
    }

    if (section == 'ladies' || section == 'women' || section == 'female') {
      return isFemale;
    }

    return false;
  }

  bool _matchesPeriod(DateTime date) {
    final now = DateTime.now();

    if (_filter.period == 'all') return true;

    if (_filter.period == 'this_month') {
      return date.month == now.month && date.year == now.year;
    }

    if (_filter.period == 'next_month') {
      final next = DateTime(now.year, now.month + 1);
      return date.month == next.month && date.year == next.year;
    }

    if (_filter.period == 'three_months') {
      final end = DateTime(now.year, now.month + 3);
      return date.isBefore(end);
    }

    return true;
  }

  List<String> _activeFilterLabels() {
    final labels = <String>[];

    for (final s in _filter.sections) {
      switch (s) {
        case 'mens':
          labels.add('Men');
          break;
        case 'ladies':
          labels.add('Ladies');
          break;
        case 'mixed':
          labels.add('Mixed');
          break;
      }
    }

    for (final c in _filter.categories) {
      switch (c) {
        case 'match':
          labels.add('Matches');
          break;
        case 'league':
          labels.add('Leagues');
          break;
        case 'competition':
          labels.add('Competitions');
          break;
        case 'drive':
          labels.add('Drives');
          break;
        case 'rollup':
          labels.add('Roll-Ups');
          break;
        case 'event':
          labels.add('Events');
          break;
        case 'friendly':
          labels.add('Friendly');
          break;
        case 'cup':
          labels.add('Cup');
          break;
        case 'social':
          labels.add('Social');
          break;
        case 'training':
          labels.add('Training');
          break;
        case 'internal':
          labels.add('Internal');
          break;
      }
    }

    switch (_filter.period) {
      case 'this_month':
        labels.add('This month');
        break;
      case 'next_month':
        labels.add('Next month');
        break;
      case 'three_months':
        labels.add('Next 3 months');
        break;
    }

    if (_filter.fixtureTypeIds.isNotEmpty) {
      final count = _filter.fixtureTypeIds.length;
      labels.add('$count fixture type${count == 1 ? '' : 's'}');
    }

    return labels;
  }

  Map<String, dynamic>? _asVenueMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  bool _fixtureIsHome(Map<String, dynamic> fixture) {
    final raw = fixture['is_home'];

    if (raw is bool) return raw;
    if (raw is num) return raw != 0;

    final value = (raw ?? '').toString().trim().toLowerCase();
    if (value == 'true' || value == '1' || value == 'yes') return true;
    if (value == 'false' || value == '0' || value == 'no') return false;

    return true;
  }

  bool _venueHasIdentity(Map<String, dynamic>? venue) {
    if (venue == null) return false;

    return VenueActionsService.text(venue['id']).isNotEmpty ||
        VenueActionsService.text(venue!['name']).isNotEmpty ||
        VenueActionsService.hasAddress(venue) ||
        VenueActionsService.canNavigate(venue);
  }

  Map<String, dynamic>? _physicalVenueForFixture(Map<String, dynamic> fixture) {
    final homeVenue = _asVenueMap(fixture['venue']);
    final opponentVenue = _asVenueMap(fixture['opponent_venue']);

    if (_isEventStyleFixture(fixture) || _fixtureIsHome(fixture)) {
      return _venueHasIdentity(homeVenue) ? homeVenue : null;
    }

    if (_venueHasIdentity(opponentVenue)) return opponentVenue;
    return _venueHasIdentity(homeVenue) ? homeVenue : null;
  }

  bool _fixtureHasCoordinates(Map<String, dynamic> fixture) {
    final venue = _physicalVenueForFixture(fixture);
    return venue != null && DeviceLocationService.hasCoordinates(venue);
  }

  String? _distanceTextForFixture(Map<String, dynamic> fixture) {
    final current = _deviceLocation;
    final venue = _physicalVenueForFixture(fixture);

    if (current == null || venue == null) return null;

    final miles = DeviceLocationService.distanceMilesToVenue(
      currentLocation: current,
      venue: venue,
    );

    if (miles == null) return null;
    return 'Approx. ${DeviceLocationService.formatMiles(miles)} away';
  }

  Future<void> _loadDeviceLocationIfUseful({bool forceRefresh = false}) async {
    if (_loadingDeviceLocation) return;
    if (_locationAttempted && !forceRefresh) return;

    final candidates = <Map<String, dynamic>>[
      if (_nextMatch != null) _nextMatch!,
      if (_secondMatch != null) _secondMatch!,
      ..._upcomingAccepted,
    ];

    if (!candidates.any(_fixtureHasCoordinates)) return;

    _locationAttempted = true;

    if (mounted) {
      setState(() {
        _loadingDeviceLocation = true;
        _locationUnavailableReason = null;
      });
    }

    try {
      final location = await DeviceLocationService.currentLocation(
        forceRefresh: forceRefresh,
      );

      if (!mounted) return;
      setState(() {
        _deviceLocation = location;
        _loadingDeviceLocation = false;
        _locationUnavailableReason = null;
      });
    } on DeviceLocationException catch (error) {
      debugPrint('Dashboard distance unavailable: ${error.message}');

      if (!mounted) return;
      setState(() {
        _deviceLocation = null;
        _loadingDeviceLocation = false;
        _locationUnavailableReason = error.message;
      });
    } catch (error, stackTrace) {
      debugPrint('Dashboard distance load failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;
      setState(() {
        _deviceLocation = null;
        _loadingDeviceLocation = false;
        _locationUnavailableReason = 'Current location is unavailable.';
      });
    }
  }

  Future<void> _navigateToFixtureVenue(Map<String, dynamic> fixture) async {
    final venue = _physicalVenueForFixture(fixture);

    if (venue == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No usable venue is available for this fixture.'),
        ),
      );
      return;
    }

    await VenueActionsService.navigate(context: context, venue: venue);
  }

  Widget _buildFixtureTravelActions({
    required Map<String, dynamic> fixture,
    required Color foregroundColor,
  }) {
    final venue = _physicalVenueForFixture(fixture);
    if (venue == null) return const SizedBox.shrink();

    final distanceText = _distanceTextForFixture(fixture);
    final canNavigate = VenueActionsService.canNavigate(venue);

    if (distanceText == null && !canNavigate) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (_loadingDeviceLocation &&
            _deviceLocation == null &&
            DeviceLocationService.hasCoordinates(venue))
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foregroundColor,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                'Calculating distance...',
                style: TextStyle(color: foregroundColor),
              ),
            ],
          )
        else if (distanceText != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.near_me_outlined, size: 18, color: foregroundColor),
              const SizedBox(width: 6),
              Text(
                distanceText,
                style: TextStyle(
                  color: foregroundColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        if (canNavigate)
          OutlinedButton.icon(
            onPressed: () => _navigateToFixtureVenue(fixture),
            icon: Icon(Icons.directions, color: foregroundColor),
            label: Text(
              'Navigate',
              style: TextStyle(
                color: foregroundColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: foregroundColor.withOpacity(0.45)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
      ],
    );
  }

  Widget _buildActiveFilterSummary() {
    if (_filter.isDefault) return const SizedBox.shrink();

    final labels = _activeFilterLabels();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Active filters',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: labels
                .map(
                  (label) => Chip(
                    label: Text(label),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    _initDashboard();

    _notificationTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadUnreadNotificationCount();
    });
  }

  @override
  void dispose() {
    _notificationTimer?.cancel();
    super.dispose();
  }

  Future<void> _initDashboard() async {
    try {
      await _loadUserPermissions();
      await _loadSavedFilter();
      await _load();
      await _loadUnreadNotificationCount();
    } catch (e, st) {
      debugPrint('Dashboard init failed: $e');
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

  Future<void> _openMemberOptions() async {
    await showMemberOptionsMenu(
      context: context,
      clubId: widget.clubId,
      clubName: widget.clubName,
      openMembershipDetails: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MembersScreen(clubId: widget.clubId),
          ),
        );
      },
    );
  }

  Future<void> _openFilter() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DashboardFilterScreen(
          initialFilter: _filter,
          clubId: widget.clubId,
        ),
      ),
    );

    if (result is DashboardFixtureFilter && result != _filter) {
      setState(() {
        _filter = result;
      });

      await _saveFilterPreference();
      await _load();
    }
  }

  Future<void> _clearFilter() async {
    final oldFilter = _filter;

    setState(() {
      _filter = DashboardFixtureFilter.empty;
    });

    await _saveFilterPreference();
    await _load();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Filters cleared'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            setState(() {
              _filter = oldFilter;
            });
            await _saveFilterPreference();
            await _load();
          },
        ),
      ),
    );
  }

  Future<void> _loadSavedFilter() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null) return;

    try {
      final row = await client
          .from('user_club_dashboard_filters')
          .select('filter_json')
          .eq('user_id', user.id)
          .eq('club_id', widget.clubId)
          .maybeSingle();

      if (row != null && row['filter_json'] is Map<String, dynamic>) {
        final loaded = DashboardFixtureFilter.fromJson(
          Map<String, dynamic>.from(row['filter_json']),
        );

        _filter = loaded.isDefault ? DashboardFixtureFilter.empty : loaded;

        debugPrint('Loaded dashboard filter: $_filter');
        debugPrint('Loaded dashboard filter isDefault: ${_filter.isDefault}');
      } else {
        _filter = DashboardFixtureFilter.empty;
      }
    } catch (e) {
      debugPrint('Failed to load saved dashboard filter: $e');
      _filter = DashboardFixtureFilter.empty;
    }
  }

  Future<void> _saveFilterPreference() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null) return;

    try {
      if (_filter.isDefault) {
        await client
            .from('user_club_dashboard_filters')
            .delete()
            .eq('user_id', user.id)
            .eq('club_id', widget.clubId);
      } else {
        await client.from('user_club_dashboard_filters').upsert({
          'user_id': user.id,
          'club_id': widget.clubId,
          'filter_json': _filter.toJson(),
        });
      }
    } catch (e) {
      debugPrint('Failed to save dashboard filter: $e');
    }
  }

  Future<void> _loadUserPermissions() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      throw Exception('No logged-in user');
    }

    final myProfileId = (await supabase.rpc('my_member_profile_id')).toString();

    // 1) Global superuser
    final superuserRow = await supabase
        .from('app_superusers')
        .select('user_id')
        .eq('user_id', user.id)
        .maybeSingle();

    _isSuperuser = superuserRow != null;

    // 2) Club membership for this club, using member_profile_id
    final membership = await supabase
        .from('club_memberships')
        .select('id, club_id, member_profile_id, role')
        .eq('member_profile_id', myProfileId)
        .eq('club_id', widget.clubId)
        .maybeSingle();

    final profile = await supabase
        .from('member_profiles')
        .select('sex_at_birth')
        .eq('id', myProfileId)
        .maybeSingle();

    _mySexAtBirth = profile?['sex_at_birth']?.toString().trim().toLowerCase();

    debugPrint('AUTH user.id       = ${user.id}');
    debugPrint('PROFILE myProfileId = $myProfileId');
    debugPrint('MEMBERSHIP row      = $membership');

    if (membership != null) {
      _hasClubMembership = true;
      _currentMemberId = myProfileId;

      final role = (membership['role'] ?? '').toString().trim().toLowerCase();

      _isGuest = role == 'guest';

      debugPrint('MEMBERSHIP role raw = ${membership['role']}');
      debugPrint('MEMBERSHIP role norm= $role');

      _isClubAdmin = role == 'admin';
      _isSelector = role == 'selector';

      _isFixtureCreator = _isSuperuser || _isClubAdmin || _isSelector;
    } else {
      _currentMemberId = myProfileId;
      _isClubAdmin = false;
      _isSelector = false;
      _isFixtureCreator = _isSuperuser;
      _hasClubMembership = false;
      _isGuest = false;
    }

    debugPrint(
      'Dashboard perms: super=$_isSuperuser '
      'admin=$_isClubAdmin '
      'selector=$_isSelector '
      'fixtureCreator=$_isFixtureCreator '
      'memberId=$_currentMemberId',
    );

    if (mounted) {
      setState(() {
        _loadingPermissions = false;
      });
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      final myId = (await client.rpc('my_member_profile_id')).toString();

      final myTeamRows = await client
          .from('team_members')
          .select('team_id')
          .eq('member_profile_id', myId)
          .eq('is_active', true);

      final myTeamIds = List<Map<String, dynamic>>.from(
        myTeamRows,
      ).map((r) => r['team_id']?.toString()).whereType<String>().toSet();

      final myAvailabilityRows = await client
          .from('fixture_rsvps')
          .select('fixture_id, status')
          .eq('member_profile_id', myId);

      final myAvailabilityByFixtureId = <String, String>{};
      for (final r in List<Map<String, dynamic>>.from(myAvailabilityRows)) {
        final fixtureId = r['fixture_id']?.toString();
        final status = r['status']?.toString();
        if (fixtureId != null && status != null) {
          myAvailabilityByFixtureId[fixtureId] = status;
        }
      }

      // 1) Load my club name
      final clubRow = await client
          .from('clubs')
          .select('name, primary_color_hex, secondary_color_hex')
          .eq('id', widget.clubId)
          .single();

      final myClubName = (clubRow['name'] ?? '').toString();

      // Lookup maps (ids -> names) so dashboard can show venue/green/opponent names
      final venuesRows = await client
          .from('venues')
          .select('id, name')
          .eq('club_id', widget.clubId);

      final venueNameById = {
        for (final v in List<Map<String, dynamic>>.from(venuesRows))
          v['id'].toString(): (v['name'] ?? '').toString(),
      };

      final greensRows = await client
          .from('green_areas')
          .select('id, name')
          .eq('club_id', widget.clubId);

      final greenNameById = {
        for (final g in List<Map<String, dynamic>>.from(greensRows))
          g['id'].toString(): (g['name'] ?? '').toString(),
      };

      // Fixtures (future only)
      final fixturesRows = await client
          .from('fixtures')
          .select(
            'id, club_id, start_at, is_home, section, rinks_required, players_per_rink, '
            'requires_rsvp, team_id, team_name, cancelled_at, '
            'rescheduled_from_fixture_id, rescheduled_to_fixture_id, rescheduled_at, '
            'captain_member_profile_id, vice_captain_member_profile_id, '
            'venue_id, opponent_venue_id, green_area_id, '
            'venue:venues!fixtures_venue_id_fkey(id, name, address_line1, address_line2, town_city, postcode, contact_name, contact_phone, contact_email, website_url, directions_url, google_maps_url, google_place_id, latitude, longitude), '
            'opponent_venue:venues!fixtures_opponent_venue_id_fkey(id, name, address_line1, address_line2, town_city, postcode, contact_name, contact_phone, contact_email, website_url, directions_url, google_maps_url, google_place_id, latitude, longitude), '
            'team:teams(name), '
            'green_areas(name, discipline, orientation_mode), '
            'ts:team_selections(status), '
            'competition_type_id, '
            'competition_type:competition_types!fixtures_competition_type_id_fkey('
            'id, name, is_internal, selection_mode, uses_rinks, tags, '
            'colour_scheme:fixture_colour_schemes(id, name, background_hex, foreground_hex))',
          )
          .eq('club_id', widget.clubId)
          .gte('start_at', DateTime.now().toUtc().toIso8601String())
          .order('start_at', ascending: true);

      final allFixtures = List<Map<String, dynamic>>.from(fixturesRows);

      debugPrint(
        'DASH sample: ${allFixtures.isNotEmpty ? allFixtures.first : "none"}',
      );

      bool isPublished(Map<String, dynamic> f) {
        final ts = f['ts'];
        if (ts == null) return false;
        if (ts is List && ts.isEmpty) return false;

        if (ts is List) {
          final status = ts.first?['status']?.toString();
          return status == 'published';
        }

        final status = (ts as Map?)?['status']?.toString();
        return status == 'published';
      }

      bool isRescheduled(Map<String, dynamic> f) {
        final fromId = f['rescheduled_from_fixture_id']?.toString();
        return fromId != null && fromId.isNotEmpty;
      }

      final toRsvp = allFixtures.where((f) {
        if (!_canRsvpFromDashboard) return false;
        if (_isOpenSessionOrEvent(f)) return false;

        final requiresRsvp = f['requires_rsvp'] == true;
        if (!requiresRsvp) return false;

        final rescheduled = isRescheduled(f);

        // Normal published RSVP fixture is closed.
        // Rescheduled published RSVP fixture reopens availability.
        if (isPublished(f) && !rescheduled) return false;

        if (!_isEligibleForFixtureSection(f)) return false;

        return _matchesFilter(f);
      }).toList();

      final canManagePreselect = _isSuperuser || _isClubAdmin || _isSelector;

      final awaitingSelection = allFixtures.where((f) {
        final requiresRsvp = f['requires_rsvp'] == true;
        if (requiresRsvp) return false;

        final rescheduled =
            f['rescheduled_from_fixture_id']?.toString().isNotEmpty == true;

        if (isPublished(f) && !rescheduled) return false;

        final selectionMode = _selectionMode(f);

        if (_isOpenSessionOrEvent(f)) return false;

        if (selectionMode == 'preselect') return false;
        if (selectionMode == 'open') return false;

        final teamId = f['team_id']?.toString();

        final visible = (teamId != null && teamId.isNotEmpty)
            ? myTeamIds.contains(teamId)
            : true;

        if (!visible) return false;

        return _matchesFilter(f);
      }).toList();

      /*
      final showOpenSessionsAndEvents = _filter.fixtureTypeIds.isNotEmpty;

      final openSessionsAndEvents = showOpenSessionsAndEvents
          ? allFixtures.where((f) {
              if (!_isOpenSessionOrEvent(f)) return false;
              return _matchesFilter(f);
            }).toList()
          : <Map<String, dynamic>>[];
*/

      final openSessionsAndEvents = allFixtures.where((f) {
        if (!_isOpenSessionOrEvent(f)) return false;
        return _matchesFilter(f);
      }).toList();

      // Needs my acceptance (published team + pending) for this club only
      final needsRows = await client
          .from('team_selection_members')
          .select(
            'acceptance, role, team_selections(status, fixture:fixtures('
            'id, club_id, start_at, is_home, section, rinks_required, players_per_rink, '
            'requires_rsvp, team_id, team_name, cancelled_at, '
            'captain_member_profile_id, vice_captain_member_profile_id, '
            'fixture_rinks(format, players_per_rink), '
            'competition_type:competition_types!fixtures_competition_type_id_fkey('
            'id, name, is_internal, selection_mode, uses_rinks, tags, '
            'colour_scheme:fixture_colour_schemes(id, name, background_hex, foreground_hex)), '
            'venue:venues!fixtures_venue_id_fkey(id, name, address_line1, address_line2, town_city, postcode, contact_name, contact_phone, contact_email, website_url, directions_url, google_maps_url, google_place_id, latitude, longitude), '
            'opponent_venue:venues!fixtures_opponent_venue_id_fkey(id, name, address_line1, address_line2, town_city, postcode, contact_name, contact_phone, contact_email, website_url, directions_url, google_maps_url, google_place_id, latitude, longitude), '
            'team:teams(name), '
            'green_areas(name, discipline, orientation_mode)'
            '))',
          )
          .eq('member_profile_id', myId)
          .eq('is_selected', true)
          .eq('acceptance', 'pending');

      final rawNeeds = List<Map<String, dynamic>>.from(needsRows);

      final nowUtcIso = DateTime.now().toUtc().toIso8601String();
      final needsAcceptance = rawNeeds.where((r) {
        final ts = r['team_selections'] as Map<String, dynamic>?;
        if (ts?['status']?.toString() != 'published') return false;

        final fx = ts?['fixture'] as Map<String, dynamic>?;
        if (fx == null) return false;

        if (fx['club_id']?.toString() != widget.clubId) return false;

        final startAt = fx['start_at']?.toString() ?? '';
        if (startAt.isEmpty) return false;
        if (startAt.compareTo(nowUtcIso) < 0) return false;

        return _matchesFilter(fx);
      }).toList();

      needsAcceptance.sort((a, b) {
        final aFx =
            (a['team_selections'] as Map<String, dynamic>?)?['fixture']
                as Map<String, dynamic>?;
        final bFx =
            (b['team_selections'] as Map<String, dynamic>?)?['fixture']
                as Map<String, dynamic>?;

        final aStart = aFx?['start_at']?.toString() ?? '';
        final bStart = bFx?['start_at']?.toString() ?? '';

        return aStart.compareTo(bStart);
      });

      // Accepted & upcoming (published + I'm selected + accepted)
      final acceptedRows = await client
          .from('team_selection_members')
          .select(
            'team_selections!inner('
            '  status, '
            '  fixture:fixtures!inner('
            '    id, club_id, start_at, is_home, section, rinks_required, players_per_rink, cancelled_at, '
            '    requires_rsvp, team_id, team_name, venue_id, opponent_venue_id, green_area_id, '
            '    fixture_rinks(format, players_per_rink), '
            '    competition_type_id, '
            '    competition_type:competition_types!fixtures_competition_type_id_fkey('
            '      id, name, is_internal, selection_mode, uses_rinks, '
            '      colour_scheme:fixture_colour_schemes('
            '      id, name, background_hex, foreground_hex)'
            '    ), '
            '    venue:venues!fixtures_venue_id_fkey(id, name, address_line1, address_line2, town_city, postcode, contact_name, contact_phone, contact_email, website_url, directions_url, google_maps_url, google_place_id, latitude, longitude), '
            '    opponent_venue:venues!fixtures_opponent_venue_id_fkey(id, name, address_line1, address_line2, town_city, postcode, contact_name, contact_phone, contact_email, website_url, directions_url, google_maps_url, google_place_id, latitude, longitude), '
            '    team:teams(name), '
            '    green_areas(name, discipline, orientation_mode)'
            '  )'
            ')',
          )
          .eq('member_profile_id', myId)
          .eq('acceptance', 'accepted')
          .eq('is_selected', true)
          .eq('team_selections.status', 'published')
          .eq('team_selections.fixture.club_id', widget.clubId);

      final upcomingAcceptedAll = <Map<String, dynamic>>[];
      final upcomingAccepted = <Map<String, dynamic>>[];

      for (final r in List<Map<String, dynamic>>.from(acceptedRows)) {
        final ts = r['team_selections'] as Map<String, dynamic>?;
        final fx = ts?['fixture'] as Map<String, dynamic>?;
        if (fx == null) continue;

        final startAt = fx['start_at']?.toString() ?? '';
        if (startAt.compareTo(nowUtcIso) < 0) continue;

        // Unfiltered list for next match popup
        upcomingAcceptedAll.add(fx);

        // Filtered list for dashboard section
        if (_matchesFilter(fx)) {
          upcomingAccepted.add(fx);
        }
      }

      // sort ascending by start_at
      upcomingAcceptedAll.sort(
        (a, b) => (a['start_at'] as String).compareTo(b['start_at'] as String),
      );

      upcomingAccepted.sort(
        (a, b) => (a['start_at'] as String).compareTo(b['start_at'] as String),
      );

      String fixtureIdFromNeedsRow(Map<String, dynamic> row) {
        final ts = row['team_selections'] as Map<String, dynamic>?;
        final fx = ts?['fixture'] as Map<String, dynamic>?;
        return fx?['id']?.toString() ?? '';
      }

      String fixtureId(Map<String, dynamic> fixture) {
        return fixture['id']?.toString() ?? '';
      }

      final alreadyShownFixtureIds = <String>{
        for (final row in needsAcceptance)
          if (fixtureIdFromNeedsRow(row).isNotEmpty) fixtureIdFromNeedsRow(row),
        for (final fixture in toRsvp)
          if (fixtureId(fixture).isNotEmpty) fixtureId(fixture),
        for (final fixture in awaitingSelection)
          if (fixtureId(fixture).isNotEmpty) fixtureId(fixture),
        for (final fixture in upcomingAccepted)
          if (fixtureId(fixture).isNotEmpty) fixtureId(fixture),
        for (final fixture in openSessionsAndEvents)
          if (fixtureId(fixture).isNotEmpty) fixtureId(fixture),
      };

      final fixturesManaging =
          allFixtures.where((f) {
            final id = fixtureId(f);
            if (id.isEmpty) return false;
            if (alreadyShownFixtureIds.contains(id)) return false;

            final captainId = f['captain_member_profile_id']?.toString();
            final viceCaptainId = f['vice_captain_member_profile_id']
                ?.toString();

            final isResponsible = captainId == myId || viceCaptainId == myId;

            if (!isResponsible) return false;

            return _matchesFilter(f);
          }).toList()..sort(
            (a, b) =>
                (a['start_at'] as String).compareTo(b['start_at'] as String),
          );

      final nextMatch = upcomingAcceptedAll.isNotEmpty
          ? upcomingAcceptedAll.first
          : null;

      /*      Map<String, dynamic>? secondMatch;
      if (upcomingAcceptedAll.length > 1) {
        final candidate = upcomingAcceptedAll[1];
        final startAt = parseClubTime(candidate['start_at'].toString());
        final diff = startAt.difference(DateTime.now());

        if (!diff.isNegative && diff.inDays < 3) {
          secondMatch = candidate;
        }
      }
*/

      Map<String, dynamic>? secondMatch;

      if (upcomingAcceptedAll.length > 1) {
        secondMatch = upcomingAcceptedAll[1];
      }

      debugPrint(
        'DASH counts: '
        'needs=${needsAcceptance.length}, '
        'rsvp=${toRsvp.length}, '
        'awaiting=${awaitingSelection.length}, '
        'accepted=${upcomingAccepted.length}, '
        'managing=${fixturesManaging.length}, '
        'open/events=${openSessionsAndEvents.length}',
      );

      if (!mounted) return;

      final hasDashboardContent =
          needsAcceptance.isNotEmpty ||
          toRsvp.isNotEmpty ||
          awaitingSelection.isNotEmpty ||
          upcomingAccepted.isNotEmpty ||
          fixturesManaging.isNotEmpty ||
          openSessionsAndEvents.isNotEmpty;

      if (_isGuest && !hasDashboardContent) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => MonthOverviewScreen(
                clubId: widget.clubId,
                clubName: widget.clubName,
                initialDate: DateTime.now(),
              ),
            ),
          );
        });
      }

      setState(() {
        _myClubName = myClubName;

        _venueNameById = venueNameById;
        _greenNameById = greenNameById;

        _toRsvp = toRsvp;
        _awaitingSelection = awaitingSelection;
        _needsAcceptance = needsAcceptance;
        _upcomingAccepted = upcomingAccepted;
        _fixturesManaging = fixturesManaging;

        _nextMatch = nextMatch;
        _secondMatch = secondMatch;

        _openSessionsAndEvents = openSessionsAndEvents;

        _myAvailabilityByFixtureId = myAvailabilityByFixtureId;

        _loading = false;
      });

      // Ask only for foreground location, and only when an upcoming accepted
      // fixture has stored coordinates. The reading stays in memory and is
      // never written to Supabase.
      await _loadDeviceLocationIfUseful();

      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_shownNextFixturePopup && mounted) {
          _shownNextFixturePopup = true;
          _showNextFixturePopup();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openFixtureById(String fixtureId) async {
    final client = Supabase.instance.client;

    final row = await client
        .from('fixtures')
        .select(
          'id, club_id, captain_member_profile_id, vice_captain_member_profile_id, start_at, is_home, cancelled_at, section, rinks_required, players_per_rink, orientation, '
          'venue:venues!fixtures_venue_id_fkey(id, name, address_line1, address_line2, town_city, postcode, contact_name, contact_phone, contact_email, website_url, directions_url, google_maps_url, google_place_id, latitude, longitude), '
          'opponent_venue:venues!fixtures_opponent_venue_id_fkey(id, name, address_line1, address_line2, town_city, postcode, contact_name, contact_phone, contact_email, website_url, directions_url, google_maps_url, google_place_id, latitude, longitude), '
          'green_areas(name, discipline, orientation_mode)',
        )
        .eq('id', fixtureId)
        .single();

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FixtureDetailsPage(fixtureId: row['id'].toString()),
      ),
    );

    await _load();
  }

  Future<void> _setTeamAvailability(String fixtureId, String status) async {
    try {
      final client = Supabase.instance.client;
      final myId = (await client.rpc('my_member_profile_id')).toString();

      await client.from('fixture_rsvps').upsert({
        'fixture_id': fixtureId,
        'member_profile_id': myId,
        'status': status,
      }, onConflict: 'fixture_id,member_profile_id');

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save availability: $e')),
      );
    }
  }

  Future<void> _loadUnreadNotificationCount() async {
    try {
      final client = Supabase.instance.client;
      final myId = (await client.rpc('my_member_profile_id')).toString();

      final rows = await client
          .from('app_notifications')
          .select('id')
          .eq('member_profile_id', myId)
          .eq('is_read', false);

      if (!mounted) return;

      setState(() {
        _unreadNotificationCount = rows.length;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _unreadNotificationCount = 0;
      });
    }
  }

  Future<void> _showNextFixturePopup() async {
    if (!mounted) return;

    final fixture = _nextMatch;

    if (fixture == null) {
      if (_toRsvp.isEmpty) return;

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Fixtures available'),
          content: Text(
            'You have ${_toRsvp.length} fixture(s) available to RSVP to.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final isCancelled = fixture['cancelled_at'] != null;

    final bg = isCancelled
        ? Colors.grey.shade300
        : (_fixtureTypeBackgroundColor(fixture) ?? Colors.white);

    final fg = isCancelled
        ? Colors.grey.shade800
        : (_fixtureTypeForegroundColor(fixture) ?? Colors.black87);

    final title = fixtureTitleUnified(fixture, myClubName: _myClubName);

    final startsIn = _timeUntilFixture(fixture['start_at'].toString());

    final startAt = parseClubTime(fixture['start_at'].toString());

    final formattedStart = DateFormat(
      'EEEE d MMMM yyyy • HH:mm',
    ).format(startAt);

    final venue = _physicalVenueForFixture(fixture);
    final venueName = VenueActionsService.text(venue?['name']);
    final address = venue == null ? '' : VenueActionsService.address(venue);

    final hasVenue = venueName.isNotEmpty || address.isNotEmpty;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: bg,
                borderRadius: BorderRadius.circular(28),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isCancelled) ...[
                        Text(
                          'CANCELLED',
                          style: TextStyle(
                            color: Colors.grey.shade900,
                            fontWeight: FontWeight.w900,
                            fontSize: 26,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'This fixture was due in $startsIn',
                          style: TextStyle(
                            color: fg,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                      ] else
                        Text(
                          'Your next match is in $startsIn',
                          style: TextStyle(
                            color: fg,
                            fontWeight: FontWeight.w800,
                            fontSize: 26,
                          ),
                        ),

                      const SizedBox(height: 18),

                      Text(
                        title,
                        style: TextStyle(
                          color: fg,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(formattedStart, style: TextStyle(color: fg)),

                      if (!isCancelled) ...[
                        const SizedBox(height: 14),
                        Text(
                          'Special instructions: none at the moment',
                          style: TextStyle(color: fg),
                        ),
                      ],

                      if (hasVenue) ...[
                        const SizedBox(height: 18),
                        Text(
                          'Location',
                          style: TextStyle(
                            color: fg,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),

                        if (venueName.isNotEmpty)
                          Text(
                            venueName,
                            style: TextStyle(
                              color: fg,
                              fontWeight: FontWeight.w600,
                            ),
                          ),

                        if (address.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(address, style: TextStyle(color: fg)),
                        ],

                        if (!isCancelled) ...[
                          const SizedBox(height: 12),
                          _buildFixtureTravelActions(
                            fixture: fixture,
                            foregroundColor: fg,
                          ),
                        ],
                      ],

                      const SizedBox(height: 18),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () async {
                              Navigator.pop(dialogContext);

                              await _openFixtureById(
                                fixture['id']?.toString() ?? '',
                              );
                            },
                            child: Text(
                              'View fixture',
                              style: TextStyle(
                                color: fg,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: Text('OK', style: TextStyle(color: fg)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              if (_secondMatch != null)
                _buildSecondMatchPopupCard(_secondMatch!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecondMatchPopupCard(Map<String, dynamic> fixture) {
    final isCancelled = fixture['cancelled_at'] != null;

    final bg = isCancelled
        ? Colors.grey.shade300
        : (_fixtureTypeBackgroundColor(fixture) ?? Colors.grey.shade100);

    final fg = isCancelled
        ? Colors.grey.shade800
        : (_fixtureTypeForegroundColor(fixture) ?? Colors.black87);

    final title = fixtureTitleUnified(fixture, myClubName: _myClubName);

    final startsIn = _timeUntilFixture(fixture['start_at'].toString());

    final startAt = parseClubTime(fixture['start_at'].toString());

    final formattedStart = DateFormat(
      'EEEE d MMMM yyyy • HH:mm',
    ).format(startAt);

    final venue = _physicalVenueForFixture(fixture);
    final venueName = VenueActionsService.text(venue?['name']);

    return SizedBox(
      width: double.infinity,
      child: Card(
        color: bg,
        elevation: 4,
        margin: const EdgeInsets.only(top: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () async {
            Navigator.of(context).pop();

            await _openFixtureById(fixture['id']?.toString() ?? '');
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isCancelled) ...[
                  Text(
                    'CANCELLED',
                    style: TextStyle(
                      color: Colors.grey.shade900,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'This fixture was due in $startsIn',
                    style: TextStyle(color: fg, fontWeight: FontWeight.w700),
                  ),
                ] else
                  Text(
                    'Also coming up in $startsIn',
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),

                const SizedBox(height: 8),

                Text(
                  title,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w700),
                ),

                const SizedBox(height: 6),

                Text(formattedStart, style: TextStyle(color: fg)),

                if (venueName.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(venueName, style: TextStyle(color: fg)),
                ],

                if (!isCancelled) ...[
                  const SizedBox(height: 10),
                  _buildFixtureTravelActions(
                    fixture: fixture,
                    foregroundColor: fg,
                  ),
                ],

                if (isCancelled) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Tap to view cancellation details',
                    style: TextStyle(color: fg, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Widget _buildEmptyState(String message) {
    return Text(message, style: Theme.of(context).textTheme.bodyMedium);
  }

  Widget _buildFixtureCard({
    required Map<String, dynamic> fixture,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    String? actionHint,
    Widget? trailing,
  }) {
    return UnifiedFixtureCard(
      fixture: fixture,
      myClubName: _myClubName,
      actionHint: actionHint,
      trailing: trailing,
      onTap: onTap,
      margin: const EdgeInsets.symmetric(vertical: 4),
    );
  }

  Widget _buildAvailabilityFixtureCard({
    required Map<String, dynamic> fixture,
    required String title,
    required String subtitle,
    required String? myStatus,
    required VoidCallback onTap,
    required VoidCallback onAvailableTap,
    required VoidCallback onNotAvailableTap,
    Widget? trailing,
  }) {
    final isCancelled = fixture['cancelled_at'] != null;

    final normalBackgroundColor = _fixtureTypeBackgroundColor(fixture);
    final normalForegroundColor = _fixtureTypeForegroundColor(fixture);

    final backgroundColor = isCancelled
        ? Colors.grey.shade300
        : normalBackgroundColor;

    final foregroundColor = isCancelled
        ? Colors.grey.shade800
        : normalForegroundColor;

    final fixtureTypeName = _fixtureTypeName(fixture);

    return Card(
      color: backgroundColor,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isCancelled) ...[
                      Text(
                        'CANCELLED',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Colors.grey.shade900,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                      ),
                      const SizedBox(height: 6),
                    ],

                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: foregroundColor,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_right, color: foregroundColor),
                      ],
                    ),

                    const SizedBox(height: 4),

                    if (fixtureTypeName.isNotEmpty) ...[
                      Text(
                        fixtureTypeName,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: foregroundColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],

                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: foregroundColor),
                    ),

                    const SizedBox(height: 8),

                    if (isCancelled)
                      Text(
                        'Availability closed — fixture cancelled',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: foregroundColor,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      Row(
                        children: [
                          Text(
                            'Availability:',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: foregroundColor,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildAvailabilityButton(
                                  label: 'Available',
                                  isSelected: myStatus == 'yes',
                                  selectedColor: Colors.green,
                                  onTap: onAvailableTap,
                                ),
                                _buildAvailabilityButton(
                                  label: 'Not available',
                                  isSelected: myStatus == 'no',
                                  selectedColor: Colors.red,
                                  onTap: onNotAvailableTap,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),

            if (trailing != null) ...[
              const SizedBox(width: 8),
              Center(child: trailing),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAvailabilityButton({
    required String label,
    required bool isSelected,
    required Color selectedColor,
    required VoidCallback onTap,
  }) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: isSelected ? selectedColor : null,
        foregroundColor: isSelected ? Colors.white : null,
        side: BorderSide(color: isSelected ? selectedColor : Colors.grey),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: Text(label),
    );
  }

  Widget _buildResponsePill({
    required String label,
    required Color backgroundColor,
    required Color foregroundColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foregroundColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingPermissions) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final canAccessAdmin =
        _isSuperuser || _isClubAdmin || _isSelector || _isFixtureCreator;

    //    debugPrint('Dashboard build filter: $_filter');
    //    debugPrint('Dashboard build filter isDefault: ${_filter.isDefault}');

    return Scaffold(
      floatingActionButton: GestureDetector(
        onLongPress: _filter.isDefault ? null : _clearFilter,
        child: FloatingActionButton.extended(
          backgroundColor: _filter.isDefault ? Colors.grey : Colors.red,
          icon: const Icon(Icons.filter_alt),
          label: Text(_filter.isDefault ? 'Filter' : 'Filtered'),
          onPressed: _openFilter,
        ),
      ),
      appBar: AppBar(
        title: Text(widget.clubName),
        actions: [
          IconButton(
            tooltip: 'User Guide',
            icon: const Icon(Icons.fiber_manual_record_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      PlayerHelpScreen(showAdminGuide: _isClubAdmin),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Month Overview',
            icon: const Icon(Icons.calendar_month),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MonthOverviewScreen(
                    clubId: widget.clubId,
                    clubName: widget.clubName ?? 'Club Diary',
                    initialDate: DateTime.now(),
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Next match',
            icon: const Icon(Icons.info_outline),
            onPressed: _showNextFixturePopup,
          ),
          IconButton(
            tooltip: 'My fixture bookings',
            icon: const Icon(Icons.event_available),
            onPressed: () async {
              final changed = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => FixturesScreen(
                    clubId: widget.clubId,
                    clubName: widget.clubName,
                    memberBookingsOnly: true,
                  ),
                ),
              );

              if (changed == true) {
                await _load();
              }
            },
          ),

          IconButton(
            icon: const Icon(Icons.groups),
            tooltip: 'Membership and Volunteer Lists',
            onPressed: _openMemberOptions,
          ),

          if (canAccessAdmin)
            IconButton(
              tooltip: 'Admin',
              icon: const Icon(Icons.settings),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ClubHomeScreen(
                      clubId: widget.clubId,
                      clubName: widget.clubName,
                    ),
                  ),
                );
              },
            ),
          IconButton(
            tooltip: 'Notifications',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsPage()),
              );
              await _loadUnreadNotificationCount();
            },
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications),
                if (_unreadNotificationCount > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      child: Text(
                        _unreadNotificationCount > 99
                            ? '99+'
                            : '$_unreadNotificationCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              children: [
                _buildActiveFilterSummary(),
                _buildSectionHeader('Fixture Needing your Acceptance:'),
                const SizedBox(height: 6),
                if (_needsAcceptance.isEmpty)
                  _buildEmptyState('   Nothing waiting for you.')
                else
                  ..._needsAcceptance.map((r) {
                    final ts = r['team_selections'] as Map<String, dynamic>?;
                    final fx = ts?['fixture'] as Map<String, dynamic>?;

                    if (fx == null) return const SizedBox.shrink();

                    final acceptance = (r['acceptance'] ?? '')
                        .toString()
                        .trim()
                        .toLowerCase();

                    Widget trailing;
                    if (acceptance == 'accepted') {
                      trailing = _buildResponsePill(
                        label: 'Accepted',
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      );
                    } else if (acceptance == 'declined') {
                      trailing = _buildResponsePill(
                        label: 'Declined',
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      );
                    } else {
                      trailing = _buildResponsePill(
                        label: 'Pending',
                        backgroundColor: Colors.orange.shade100,
                        foregroundColor: Colors.orange.shade900,
                      );
                    }

                    final title = fixtureTitleUnified(
                      fx,
                      myClubName: _myClubName,
                    );
                    final subtitle = fixtureSubtitleUnified(fx);

                    return _buildFixtureCard(
                      fixture: fx,
                      title: title,
                      subtitle: subtitle,
                      actionHint: 'Tap to accept or decline',
                      trailing: trailing,
                      onTap: () => _openFixtureById(fx['id']?.toString() ?? ''),
                    );
                  }),

                const SizedBox(height: 12),
                _buildSectionHeader('Fixtures you can RSVP to:'),
                const SizedBox(height: 6),
                if (_toRsvp.isEmpty)
                  _buildEmptyState('   No upcoming fixtures to RSVP.')
                else
                  ..._toRsvp.map((f) {
                    final title = fixtureTitleUnified(
                      f,
                      myClubName: _myClubName,
                    );
                    final subtitle = fixtureSubtitleUnified(f);
                    final fixtureId = f['id']?.toString() ?? '';
                    final myStatus = _myAvailabilityByFixtureId[fixtureId];

                    Widget trailing;
                    if (myStatus == 'yes') {
                      trailing = _buildResponsePill(
                        label: 'Yes',
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      );
                    } else if (myStatus == 'maybe') {
                      trailing = _buildResponsePill(
                        label: 'Maybe',
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black87,
                      );
                    } else if (myStatus == 'no') {
                      trailing = _buildResponsePill(
                        label: 'No',
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      );
                    } else {
                      trailing = _buildResponsePill(
                        label: 'Pending',
                        backgroundColor: Colors.grey.shade300,
                        foregroundColor: Colors.black87,
                      );
                    }
                    return _buildFixtureCard(
                      fixture: f,
                      title: title,
                      subtitle: subtitle,
                      actionHint: 'Tap to RSVP',
                      trailing: trailing,
                      onTap: () => _openFixtureById(fixtureId),
                    );
                  }),

                const SizedBox(height: 12),
                _buildSectionHeader('Fixtures Awaiting Team Selection'),
                const SizedBox(height: 6),

                if (_awaitingSelection.isEmpty)
                  _buildEmptyState(
                    '   No upcoming Fixtures awaiting Team Selection.',
                  )
                else
                  ..._awaitingSelection.map((f) {
                    final title = fixtureTitleUnified(
                      f,
                      myClubName: _myClubName,
                    );
                    final subtitle = fixtureSubtitleUnified(f);
                    final fixtureId = f['id']?.toString() ?? '';

                    final competitionType =
                        f['competition_type'] as Map<String, dynamic>?;
                    final selectionMode =
                        (competitionType?['selection_mode'] ?? '')
                            .toString()
                            .toLowerCase()
                            .trim();

                    final myStatus = _myAvailabilityByFixtureId[fixtureId];

                    Widget trailing;
                    if (myStatus == 'yes') {
                      trailing = _buildResponsePill(
                        label: 'Available',
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      );
                    } else if (myStatus == 'no') {
                      trailing = _buildResponsePill(
                        label: 'Not available',
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      );
                    } else {
                      trailing = _buildResponsePill(
                        label: 'No reply',
                        backgroundColor: Colors.grey.shade300,
                        foregroundColor: Colors.black87,
                      );
                    }

                    return _buildAvailabilityFixtureCard(
                      fixture: f,
                      title: title,
                      subtitle: subtitle,
                      myStatus: myStatus,
                      trailing: trailing,
                      onTap: () => _openFixtureById(fixtureId),
                      onAvailableTap: () =>
                          _setTeamAvailability(fixtureId, 'yes'),
                      onNotAvailableTap: () =>
                          _setTeamAvailability(fixtureId, 'no'),
                    );
                  }),

                const SizedBox(height: 12),
                _buildSectionHeader('Fixtures you have Accepted (upcoming)'),
                const SizedBox(height: 6),

                if (_upcomingAccepted.isEmpty)
                  _buildEmptyState('   No upcoming accepted fixtures.')
                else
                  ..._upcomingAccepted.map((f) {
                    final title = fixtureTitleUnified(
                      f,
                      myClubName: _myClubName,
                    );
                    final subtitle = fixtureSubtitleUnified(f);
                    final venue = _physicalVenueForFixture(f);
                    final distanceText = _distanceTextForFixture(f);
                    final canNavigate =
                        venue != null && VenueActionsService.canNavigate(venue);
                    final foregroundColor =
                        _fixtureTypeForegroundColor(f) ?? Colors.black87;

                    return _buildFixtureCard(
                      fixture: f,
                      title: title,
                      subtitle: subtitle,
                      actionHint: distanceText,
                      trailing: canNavigate
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip:
                                      'Navigate to ${VenueActionsService.text(venue['name'])}',
                                  onPressed: () => _navigateToFixtureVenue(f),
                                  icon: Icon(
                                    Icons.directions,
                                    color: foregroundColor,
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  color: foregroundColor,
                                ),
                              ],
                            )
                          : null,
                      onTap: () => _openFixtureById(f['id']?.toString() ?? ''),
                    );
                  }),

                if (_fixturesManaging.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildSectionHeader('Fixtures you are managing'),
                  const SizedBox(height: 6),

                  ..._fixturesManaging.map((f) {
                    final title = fixtureTitleUnified(
                      f,
                      myClubName: _myClubName,
                    );
                    final subtitle = fixtureSubtitleUnified(f);
                    final fixtureId = f['id']?.toString() ?? '';

                    final captainId = f['captain_member_profile_id']
                        ?.toString();
                    final viceCaptainId = f['vice_captain_member_profile_id']
                        ?.toString();

                    final roleLabel = captainId == _currentMemberId
                        ? (_isEventStyleFixture(f) ? 'Organiser' : 'Captain')
                        : viceCaptainId == _currentMemberId
                        ? (_isEventStyleFixture(f)
                              ? 'Deputy organiser'
                              : 'Vice-captain')
                        : 'Managing';

                    return _buildFixtureCard(
                      fixture: f,
                      title: title,
                      subtitle: subtitle,
                      actionHint: roleLabel,
                      trailing: _buildResponsePill(
                        label: roleLabel,
                        backgroundColor: Colors.blue.shade100,
                        foregroundColor: Colors.blue.shade900,
                      ),
                      onTap: () => _openFixtureById(fixtureId),
                    );
                  }),
                ],

                if (_openSessionsAndEvents.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildSectionHeader('Open Sessions and Events'),
                  const SizedBox(height: 6),

                  ..._openSessionsAndEvents.map((f) {
                    final title = fixtureTitleUnified(
                      f,
                      myClubName: _myClubName,
                    );
                    final subtitle = fixtureSubtitleUnified(f);
                    final fixtureId = f['id']?.toString() ?? '';

                    return _buildFixtureCard(
                      fixture: f,
                      title: title,
                      subtitle: subtitle,
                      actionHint: 'Tap to view details',
                      trailing: null,
                      onTap: () => _openFixtureById(fixtureId),
                    );
                  }),
                ],
              ],
            ),
    );
  }
}
