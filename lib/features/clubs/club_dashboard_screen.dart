import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:async';

import 'club_home_screen.dart';
import 'package:bowls_saas/features/diary/rinks_day_view.dart';
import 'package:bowls_saas/features/diary/month_overview_screen.dart';

import '../members/members_screen.dart';
import '../fixtures/fixture_display.dart';
import '../fixtures/fixture_details_page.dart';
import '../help/player_help_screen.dart';
import '../notifications/notifications_page.dart';
import '../dashboard/dashboard_filter_screen.dart';
import '../fixtures/fixtures_screen.dart';
import '../../core/utils/hex_color.dart';
import '../../core/utils/date_format.dart';
import '../../models/dashboard_fixture_filter.dart';

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
  bool _isFixtureCreator = false; // keep false for now unless you already have this
  String? _currentMemberId;

  bool _loadingPermissions = true;  
  
  bool _loading = true;

  int _unreadNotificationCount = 0; 

  Timer? _notificationTimer;

  String? _error;
  String _myClubName = '';
  
  Map<String, String> _myAvailabilityByFixtureId = {};
    
  List<Map<String, dynamic>> _toRsvp = [];
  List<Map<String, dynamic>> _awaitingSelection = [];
  List<Map<String, dynamic>> _needsAcceptance = [];
  List<Map<String, dynamic>> _upcomingAccepted = [];
  List<Map<String, dynamic>> _openSessionsAndEvents = [];

  // Lookup maps (id -> display data)
  // Map<String, Map<String, String>> _greenById = {};
  // Map<String, Map<String, String>> _formatById = {};
  Map<String, String> _venueNameById = {};
  Map<String, String> _greenNameById = {};
  
  DashboardFixtureFilter _filter = const DashboardFixtureFilter();

  Color? _fixtureTypeBackgroundColor(Map<String, dynamic> fixture) {
    final competitionType = fixture['competition_type'] as Map<String, dynamic>?;
    final colourScheme = competitionType?['colour_scheme'] as Map<String, dynamic>?;

    if (colourScheme == null) return null;

    return colorFromHex(
      colourScheme['background_hex']?.toString(),
      fallback: Colors.grey.shade100,
    );
  }

  Color? _fixtureTypeForegroundColor(Map<String, dynamic> fixture) {
    final competitionType = fixture['competition_type'] as Map<String, dynamic>?;
    final colourScheme = competitionType?['colour_scheme'] as Map<String, dynamic>?;

    if (colourScheme == null) return null;

    return colorFromHex(
      colourScheme['foreground_hex']?.toString(),
      fallback: Colors.black87,
    );
  }

  String _fixtureTypeName(Map<String, dynamic> fixture) {
    final competitionType = fixture['competition_type'] as Map<String, dynamic>?;
    return (competitionType?['name'] ?? '').toString().trim();
  }

  String _selectionMode(Map<String, dynamic> fixture) {
    final competitionType = fixture['competition_type'] as Map<String, dynamic>?;
    return (competitionType?['selection_mode'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
  }

  bool _isOpenSessionFixture(Map<String, dynamic> fixture) {
    return _selectionMode(fixture) == 'open';
  }

  bool _usesRinks(Map<String, dynamic> fixture) {
    final competitionType = fixture['competition_type'] as Map<String, dynamic>?;
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
    if (startAt != null && !_matchesPeriod(startAt.toLocal())) {
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

    _notificationTimer =
        Timer.periodic(const Duration(seconds: 30), (_) {
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

    debugPrint('AUTH user.id       = ${user.id}');
    debugPrint('PROFILE myProfileId = $myProfileId');
    debugPrint('MEMBERSHIP row      = $membership');

    if (membership != null) {
      _currentMemberId = myProfileId;

      final role = (membership['role'] ?? '').toString().trim().toLowerCase();

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

      final myTeamIds = List<Map<String, dynamic>>.from(myTeamRows)
          .map((r) => r['team_id']?.toString())
          .whereType<String>()
          .toSet();
          
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
            'requires_rsvp, team_id, team_name, '
            'venue_id, opponent_venue_id, green_area_id, '
            'venue:venues!fixtures_venue_id_fkey(name), '
            'opponent_venue:venues!fixtures_opponent_venue_id_fkey(name), '
            'team:teams(name), '
            'green_areas(name, discipline, orientation_mode), '
            'ts:team_selections(status), '
            'competition_type_id, '
            'competition_type:competition_types!fixtures_competition_type_id_fkey('
              'id, name, is_internal, selection_mode, uses_rinks, tags, '
              'colour_scheme:fixture_colour_schemes(id, name, background_hex, foreground_hex))'
          )            
          .eq('club_id', widget.clubId)
          .gte('start_at', DateTime.now().toUtc().toIso8601String())
          .order('start_at', ascending: true);
          
      final allFixtures = List<Map<String, dynamic>>.from(fixturesRows);

      debugPrint('DASH sample: ${allFixtures.isNotEmpty ? allFixtures.first : "none"}');

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

      final toRsvp = allFixtures.where((f) {
        if (_isOpenSessionOrEvent(f)) return false;

        final requiresRsvp = f['requires_rsvp'] == true;
        if (!requiresRsvp) return false;

        if (isPublished(f)) return false;

        return _matchesFilter(f);
      }).toList();

      final canManagePreselect = _isSuperuser || _isClubAdmin || _isSelector;

      final awaitingSelection = allFixtures.where((f) {

        final requiresRsvp = f['requires_rsvp'] == true;
        if (requiresRsvp) return false;

        if (isPublished(f)) return false;

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

      final showOpenSessionsAndEvents = _filter.fixtureTypeIds.isNotEmpty;

      final openSessionsAndEvents = showOpenSessionsAndEvents
          ? allFixtures.where((f) {
              if (!_isOpenSessionOrEvent(f)) return false;
              return _matchesFilter(f);
            }).toList()
          : <Map<String, dynamic>>[];

      // Needs my acceptance (published team + pending) for this club only
      final needsRows = await client
        .from('team_selection_members')
        .select(
          'acceptance, role, team_selections(status, fixture:fixtures('
          'id, club_id, start_at, is_home, section, rinks_required, players_per_rink, '
          'requires_rsvp, team_id, team_name, venue_id, opponent_venue_id, green_area_id, '
          'competition_type_id, '
          'competition_type:competition_types!fixtures_competition_type_id_fkey('
            'id, name, is_internal, selection_mode, uses_rinks, tags, '
            'colour_scheme:fixture_colour_schemes(id, name, background_hex, foreground_hex)), '
          'venue:venues!fixtures_venue_id_fkey(name), '
          'opponent_venue:venues!fixtures_opponent_venue_id_fkey(name), '
          'team:teams(name), '
          'green_areas(name, discipline, orientation_mode)'
          '))'
        )
        .eq('member_profile_id', myId)
        .eq('is_selected', true)
        .eq('acceptance', 'pending');
        
      final rawNeeds = List<Map<String, dynamic>>.from(needsRows);

      final needsAcceptance = rawNeeds.where((r) {
        final ts = r['team_selections'] as Map<String, dynamic>?;
        if (ts?['status']?.toString() != 'published') return false;

        final fx = ts?['fixture'] as Map<String, dynamic>?;
        if (fx?['club_id']?.toString() != widget.clubId) return false;
        if (fx == null) return false;

        return _matchesFilter(fx);
      }).toList();

      // Accepted & upcoming (published + I'm selected + accepted)
      final acceptedRows = await client
        .from('team_selection_members')
        .select(
          'team_selections!inner('
          '  status, '
          '  fixture:fixtures!inner('
          '    id, club_id, start_at, is_home, section, rinks_required, players_per_rink, '
          '    requires_rsvp, team_id, team_name, venue_id, opponent_venue_id, green_area_id, '
          '    competition_type_id, '
          '    competition_type:competition_types!fixtures_competition_type_id_fkey('
          '      id, name, is_internal, selection_mode, '
          '      colour_scheme:fixture_colour_schemes('
          '      id, name, background_hex, foreground_hex)'
          '    ), '          
          '    venue:venues!fixtures_venue_id_fkey(name), '
          '    opponent_venue:venues!fixtures_opponent_venue_id_fkey(name), '
          '    team:teams(name), '
          '    green_areas(name, discipline, orientation_mode)'
          '  )'
          ')'
        )
        .eq('member_profile_id', myId)
        .eq('acceptance', 'accepted')
        .eq('is_selected', true)
        .eq('team_selections.status', 'published')
        .eq('team_selections.fixture.club_id', widget.clubId);

      final nowUtcIso = DateTime.now().toUtc().toIso8601String();

      final upcomingAccepted = <Map<String, dynamic>>[];
      for (final r in List<Map<String, dynamic>>.from(acceptedRows)) {
        final ts = r['team_selections'] as Map<String, dynamic>?;
        final fx = ts?['fixture'] as Map<String, dynamic>?;
        if (fx == null) continue;

        final startAt = fx['start_at']?.toString() ?? '';
        if (startAt.compareTo(nowUtcIso) < 0) continue;

        if (!_matchesFilter(fx)) continue;

        upcomingAccepted.add(fx);
      }

      // sort ascending by start_at
      upcomingAccepted.sort(
        (a, b) => (a['start_at'] as String).compareTo(b['start_at'] as String),
      );

      debugPrint(
        'DASH counts: '
        'needs=${needsAcceptance.length}, '
        'rsvp=${toRsvp.length}, '
        'awaiting=${awaitingSelection.length}, '
        'accepted=${upcomingAccepted.length}, '
        'open/events=${openSessionsAndEvents.length}',
      );

      if (!mounted) return;

      setState(() {
        _myClubName = myClubName;

        _venueNameById = venueNameById;
        _greenNameById = greenNameById;

        _toRsvp = toRsvp;
        _awaitingSelection = awaitingSelection;
        _needsAcceptance = needsAcceptance;
        _upcomingAccepted = upcomingAccepted;

        _openSessionsAndEvents = openSessionsAndEvents;

        _myAvailabilityByFixtureId = myAvailabilityByFixtureId;
        
        _loading = false;
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
          'id, club_id, captain_member_profile_id, vice_captain_member_profile_id, start_at, is_home, section, rinks_required, players_per_rink, orientation, '
          'venue:venues!fixtures_venue_id_fkey(name), '
          'opponent_venue:venues!fixtures_opponent_venue_id_fkey(name), '
          'green_areas(name, discipline, orientation_mode)',
        )
        .eq('id', fixtureId)
        .single();

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FixtureDetailsPage(fixtureId: row['id'].toString()),
      )
    );

    await _load();
  }

  Future<void> _setTeamAvailability(String fixtureId, String status) async {
    try {
      final client = Supabase.instance.client;
      final myId = (await client.rpc('my_member_profile_id')).toString();

      await client.from('fixture_rsvps').upsert(
        {
          'fixture_id': fixtureId,
          'member_profile_id': myId,
          'status': status,
        },
        onConflict: 'fixture_id,member_profile_id',
      );

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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Text(
      message,
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }

  Widget _buildFixtureCard({
    required Map<String, dynamic> fixture,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    String? actionHint,
    Widget? trailing,
  }) {
    final backgroundColor = _fixtureTypeBackgroundColor(fixture);
    final foregroundColor = _fixtureTypeForegroundColor(fixture);
    final fixtureTypeName = _fixtureTypeName(fixture);

    final subtitleWidget = actionHint == null || actionHint.trim().isEmpty
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (fixtureTypeName.isNotEmpty) ...[
                Text(
                  fixtureTypeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (fixtureTypeName.isNotEmpty) ...[
                Text(
                  fixtureTypeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
              const SizedBox(height: 2),
              Text(
                actionHint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: foregroundColor,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          );

    return Card(
      color: backgroundColor,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: foregroundColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: subtitleWidget,
        trailing: trailing ??
            Icon(
              Icons.chevron_right,
              color: foregroundColor,
            ),
        onTap: onTap,
      ),
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
    final backgroundColor = _fixtureTypeBackgroundColor(fixture);
    final foregroundColor = _fixtureTypeForegroundColor(fixture);
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: onTap,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: foregroundColor,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_right, color: foregroundColor),
                      ],
                    ),
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
                  Row(
                    children: [
                      Text(
                        'Availability:',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
        side: BorderSide(
          color: isSelected ? selectedColor : Colors.grey,
        ),
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
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
            tooltip: 'Help',
            icon: const Icon(Icons.help_outline),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PlayerHelpScreen(
                    showAdminGuide: _isClubAdmin,
                  ),
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
            tooltip: 'Notifications',            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NotificationsPage(),
                ),
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
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
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

                        final acceptance =
                            (r['acceptance'] ?? '').toString().trim().toLowerCase();

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

                        final title = fixtureTitleUnified(fx, myClubName: _myClubName);
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
                        final title = fixtureTitleUnified(f, myClubName: _myClubName);
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
                    _buildEmptyState('   No upcoming Fixtures awaiting Team Selection.')
                  else
                    ..._awaitingSelection.map((f) {
                      final title = fixtureTitleUnified(f, myClubName: _myClubName);
                      final subtitle = fixtureSubtitleUnified(f);
                      final fixtureId = f['id']?.toString() ?? '';

                      final competitionType = f['competition_type'] as Map<String, dynamic>?;
                      final selectionMode =
                          (competitionType?['selection_mode'] ?? '').toString().toLowerCase().trim();

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
                        onAvailableTap: () => _setTeamAvailability(fixtureId, 'yes'),
                        onNotAvailableTap: () => _setTeamAvailability(fixtureId, 'no'),
                      );
                    }),

                    const SizedBox(height: 12),
                    _buildSectionHeader('Fixtures you have Accepted (upcoming)'),
                    const SizedBox(height: 6),

                    if (_upcomingAccepted.isEmpty)
                      _buildEmptyState('   No upcoming accepted fixtures.')
                    else
                      ..._upcomingAccepted.map((f) {
                        final title = fixtureTitleUnified(f, myClubName: _myClubName);
                        final subtitle = fixtureSubtitleUnified(f);

                        return _buildFixtureCard(
                          fixture: f,
                          title: title,
                          subtitle: subtitle,
                          onTap: () => _openFixtureById(f['id']?.toString() ?? ''),
                        );
                      }),

                      if (_openSessionsAndEvents.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _buildSectionHeader('Open Sessions and Events'),
                        const SizedBox(height: 6),

                        ..._openSessionsAndEvents.map((f) {
                          final title = fixtureTitleUnified(f, myClubName: _myClubName);
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


