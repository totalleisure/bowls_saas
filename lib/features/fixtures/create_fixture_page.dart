import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:convert';

import 'package:bowls_saas/services/team_sheet_builder_service.dart';
import 'package:bowls_saas/services/team_sheet_pdf.dart';
import 'package:bowls_saas/services/fixture_communications_service.dart';

import '../../core/utils/hex_color.dart';
import '../../core/utils/date_format.dart';

import 'package:bowls_saas/core/helpers/member_picker_helpers.dart';
import 'package:bowls_saas/core/widgets/club_member_picker_page.dart';

import 'fixture_details_page.dart';
import 'repeat_fixture_planner_page.dart';

enum FixtureLocationType { home, away }

enum FixtureWorkflowType { rsvp, team }

enum VenueCreationType { home, external }

enum GoogleVenueSearchMode { bowlsClub, general }

class InitialRinkBookingContext {
  const InitialRinkBookingContext({
    required this.greenAreaId,
    required this.greenName,
    required this.rinkLabel,
    required this.startAt,
    required this.latestEndAt,
    this.suggestedEndAt,
  });

  final String greenAreaId;
  final String greenName;
  final String rinkLabel;

  /// Suggested booking start time in club time.
  final DateTime startAt;

  /// Hard latest finish time from the available slot / sunset cutoff.
  final DateTime latestEndAt;

  /// Suggested booking end time in club time.
  final DateTime? suggestedEndAt;
}

class CreateFixturePage extends StatefulWidget {
  final String clubId;
  final String clubName;
  final bool memberBookingMode;
  final InitialRinkBookingContext? initialRinkBooking;

  const CreateFixturePage({
    super.key,
    required this.clubId,
    required this.clubName,
    this.memberBookingMode = false,
    this.initialRinkBooking,
  });

  @override
  State<CreateFixturePage> createState() => _CreateFixturePageState();
}

class _CreateFixturePageState extends State<CreateFixturePage> {
  String? _currentMemberId;

  bool _isSuperuser = false;
  bool _isClubAdmin = false;
  bool _isSelector = false;
  bool _isFixtureCreator = false;
  bool _isFixtureCaptain = false;
  bool _isFixtureViceCaptain = false;

  bool _loadingPermissions = true;

  bool _loading = false;
  String? _error;

  bool _isHome = true;
  bool _isTeamFixture = false;
  bool _isPreselectFixture = false;

  bool _hasUnsavedChanges = false;

  bool _initialRinkBookingApplied = false;

  bool _bookerAutoPlacedInFirstPlayerSlot = false;

  void _markDirty() {
    if (_hasUnsavedChanges) return;
    setState(() {
      _hasUnsavedChanges = true;
    });
  }

  final _teamNameCtrl = TextEditingController();

  final _notesCtrl = TextEditingController();

  DateTime? _startAtLocal;
  DateTime? _endAtLocal;

  FixtureLocationType _fixtureLocation = FixtureLocationType.home;
  FixtureWorkflowType _workflowType = FixtureWorkflowType.rsvp;

  // Venues
  List<Map<String, dynamic>> _homeVenues = [];
  List<Map<String, dynamic>> _opponentVenues = [];
  String? _homeVenueId;
  String? _opponentVenueId;

  String? _eventVenueId;

  // Club Events reuse the fixture captain fields as organiser roles.
  String? _eventOrganiserMemberProfileId;
  String? _eventViceOrganiserMemberProfileId;

  // Players, Opponents, Markers
  List<Map<String, dynamic>> _clubMembers = [];
  final Map<String, String?> _playerSelections = {};
  final Map<String, String?> _opponentSelections = {};
  final Map<String, String> _opponentExternalNames = {};
  final Map<String, String?> _markerSelections = {};

  // Marker state is maintained independently for each fixture rink/team.
  final Map<int, bool> _markerRequiredByTeam = {};
  final Map<int, bool> _markerRequestByTeam = {};

  // Teams (for team fixtures)
  List<Map<String, dynamic>> _teams = [];
  String? _teamId;

  // Greens (green_areas) - belong to a venue
  List<Map<String, dynamic>> _greenAreas = [];
  String? _greenAreaId;

  // Orientation (stored lowercase, e.g. north_south / east_west)
  String? _orientation;

  // Fixture meta
  String _section = 'mixed';

  // Defaults requested
  int _rinksRequired = 6;
  int _playersPerRink = 4;
  String _format = 'rinks';
  String _dressCode = 'open';
  int _rinksRequiredFieldVersion = 0;

  // Fixture types
  List<Map<String, dynamic>> _fixtureTypes = [];
  String? _fixtureTypeId;
  bool _workflowLockedByFixtureType = false;

  bool _loadingRinkAvailability = false;
  String? _rinkAvailabilityError;
  List<Map<String, dynamic>> _rinkAvailability = [];

  Map<String, dynamic>? _selectedBookedRink;

  final Set<String> _draftSelectedRinkLabels = {};

  bool _shownInsufficientRinksWarning = false;

  String? _opponentVenueName(String? opponentVenueId) {
    if (opponentVenueId == null || opponentVenueId.isEmpty) return null;

    for (final venue in _opponentVenues) {
      if (venue['id'].toString() == opponentVenueId) {
        return (venue['name'] ?? '').toString();
      }
    }

    return null;
  }

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _teamNameCtrl.addListener(_markDirty);
    _notesCtrl.addListener(_markDirty);
    _load();
  }

  @override
  void dispose() {
    _teamNameCtrl.removeListener(_markDirty);
    _notesCtrl.removeListener(_markDirty);
    _teamNameCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _loadVenues();
      await _loadUserPermissions();
      await _loadFixtureTypes();
      await _loadTeams();

      // Only load greens once we have a home venue selected
      await _loadGreenAreas();

      _applyInitialRinkBookingContext();

      await _loadClubMembers();

      _defaultBookerIntoFirstPlayerSlot();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadRinkAvailability() async {
    debugPrint(
      'RINK AVAILABILITY CHECK: '
      'green=$_greenAreaId '
      'start=$_startAtLocal '
      'end=$_endAtLocal',
    );

    if (!_selectedFixtureUsesRinks) {
      setState(() {
        _loadingRinkAvailability = false;
        _rinkAvailabilityError = null;
        _rinkAvailability = [];
      });
      return;
    }

    if (_greenAreaId == null || _startAtLocal == null || _endAtLocal == null) {
      setState(() {
        _rinkAvailability = [];
        _rinkAvailabilityError = null;
        _loadingRinkAvailability = false;
      });
      return;
    }

    setState(() {
      _loadingRinkAvailability = true;
      _rinkAvailabilityError = null;
    });

    try {
      final rows = await _rpcWithSingleRetry(
        'get_green_rink_availability',
        params: {
          'p_green_area_id': _greenAreaId,
          'p_start_at': clubTimeToUtc(_startAtLocal!).toIso8601String(),
          'p_end_at': clubTimeToUtc(_endAtLocal!).toIso8601String(),
        },
      );

      debugPrint('RINK AVAILABILITY RPC rows=$rows');
      debugPrint('RINK AVAILABILITY RPC type=${rows.runtimeType}');

      if (!mounted) return;

      setState(() {
        _rinkAvailability = List<Map<String, dynamic>>.from(rows);
      });

      if (_isHome &&
          _greenAreaId != null &&
          _rinksRequired > 0 &&
          !_hasEnoughRinkCapacity &&
          !_shownInsufficientRinksWarning) {
        _shownInsufficientRinksWarning = true;
        await _showInsufficientRinksDialog();
      }

      if (_hasEnoughRinkCapacity) {
        _shownInsufficientRinksWarning = false;
      }
    } catch (e) {
      if (!mounted) return;

      final isNetwork = _looksLikeTransientNetworkError(e);

      setState(() {
        _rinkAvailability = [];
        _rinkAvailabilityError = isNetwork
            ? 'Could not load rink availability. Please check your connection and try again.'
            : 'Could not load rink availability: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingRinkAvailability = false;
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

  Future<bool> _confirmCreateRepeatFixtures(
    List<RepeatFixtureDate> dates,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Create ${dates.length} fixtures?'),
          content: SizedBox(
            width: 520,
            child: ListView(
              shrinkWrap: true,
              children: dates.map((d) {
                final dateText = MaterialLocalizations.of(
                  context,
                ).formatFullDate(d.date);

                final opponentName = _opponentVenueName(d.opponentVenueId);

                return ListTile(
                  title: Text(dateText),
                  subtitle: Text(
                    _isEventStyleFixture
                        ? 'Club event'
                        : opponentName == null
                        ? 'Internal fixture'
                        : '${d.isHome ? 'Home' : 'Away'} against $opponentName',
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Back'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create fixtures'),
            ),
          ],
        );
      },
    );

    return confirmed == true;
  }

  Future<void> _openRepeatPlanner() async {
    if (_startAtLocal == null) return;

    while (mounted) {
      final selectionMode = _selectedFixtureSelectionMode.trim().toLowerCase();

      final requiresOpponent =
          !_isEventStyleFixture &&
          selectionMode != 'preselect' &&
          selectionMode != 'open' &&
          selectionMode != 'opensession' &&
          selectionMode != 'open_session' &&
          selectionMode != 'open-session';

      final result = await Navigator.of(context).push<List<RepeatFixtureDate>>(
        MaterialPageRoute(
          builder: (_) => RepeatFixturePlannerPage(
            startDateTime: _startAtLocal!,
            requiresOpponent: requiresOpponent,
            opponentVenues: requiresOpponent ? _opponentVenues : const [],
          ),
        ),
      );

      if (result == null) return;

      final selectedDates = result.where((d) => d.enabled).toList();

      if (selectedDates.isEmpty) {
        await _showSaveErrorDialog('No repeat dates were selected.');
        continue;
      }

      final confirmed = await _confirmCreateRepeatFixtures(selectedDates);

      if (!confirmed) {
        continue; // returns to Repeat Fixture Planner
      }

      await _createRepeatFixtures(
        selectedDates,
        preferredRinkLabels: _selectedRepeatRinkLabels(),
      );

      debugPrint('Repeat count: ${selectedDates.length}');
      return;
    }
  }

  Future<void> _loadFixtureTypes() async {
    final rows = await _client
        .from('competition_types')
        .select('''
          id,
          name,
          is_internal,
          section,
          default_rinks_required,
          default_players_per_rink,
          default_format,
          dress_code,
          team_selection_enabled,
          selection_mode,
          uses_rinks,
          bookable_by_members,
          team_id,
          is_active,
          colour_scheme:fixture_colour_schemes(
            id,
            name,
            background_hex,
            foreground_hex
          )
        ''')
        .eq('club_id', widget.clubId)
        .eq('is_active', true)
        .order('name');

    rows.sort((a, b) {
      final nameA = (a['name'] ?? '').toString().toLowerCase();
      final nameB = (b['name'] ?? '').toString().toLowerCase();
      return nameA.compareTo(nameB);
    });

    final loaded = List<Map<String, dynamic>>.from(rows);

    _fixtureTypes = _canSeeAllFixtureTypes
        ? loaded
        : loaded.where((t) => t['bookable_by_members'] == true).toList();
  }

  DateTime _combineRepeatDateWithOriginalTime(DateTime repeatDate) {
    return DateTime(
      repeatDate.year,
      repeatDate.month,
      repeatDate.day,
      _startAtLocal!.hour,
      _startAtLocal!.minute,
    );
  }

  Future<String> _createFixtureWithSetupRpc({
    required DateTime startAtLocal,
    required DateTime endAtLocal,
    required bool isHome,
    required String venueId,
    required String? opponentVenueId,
    required bool usesRinks,
    required String? greenAreaId,
    required String? orientation,
    required String? fixtureLabel,
    required String? captainMemberProfileId,
    required String? viceCaptainMemberProfileId,
    required bool createTeamSelection,
    required List<Map<String, dynamic>> homeRinkLabels,
    required List<Map<String, dynamic>> rinkAssignments,
    required List<Map<String, dynamic>> teamSelectionMembers,
  }) async {
    final result = await _client.rpc(
      'create_fixture_with_setup_v2',
      params: {
        'p_club_id': widget.clubId,
        'p_start_at': clubTimeToUtc(startAtLocal).toIso8601String(),
        'p_end_at': clubTimeToUtc(endAtLocal).toIso8601String(),
        'p_is_home': isHome,
        'p_section': _section.isEmpty ? 'open' : _section,
        'p_rinks_required': usesRinks ? _rinksRequired : 0,
        'p_players_per_rink': usesRinks ? _playersPerRink : 1,
        'p_format': usesRinks ? _format : 'singles',
        'p_competition_type_id': _fixtureTypeId,
        'p_dress_code': _dressCode,
        'p_team_id': _isTeamFixture ? _teamId : null,
        'p_team_name': fixtureLabel?.trim().isEmpty == true
            ? null
            : fixtureLabel?.trim(),
        // Every non-rink Club Event collects Yes / No / Maybe responses.
        // Existing rink-based RSVP workflows retain their current behaviour.
        'p_requires_rsvp':
            !usesRinks || (!_isTeamFixture && !_isPreselectFixture),
        'p_venue_id': venueId,
        'p_opponent_venue_id': opponentVenueId,
        'p_green_area_id': usesRinks && isHome ? greenAreaId : null,
        'p_orientation': orientation,
        'p_captain_member_profile_id': captainMemberProfileId,
        'p_vice_captain_member_profile_id': viceCaptainMemberProfileId,
        'p_notes': _notesCtrl.text.trim().isEmpty
            ? null
            : _notesCtrl.text.trim(),
        'p_create_team_selection': createTeamSelection,
        'p_team_selection_status': 'published',
        'p_home_rink_labels': homeRinkLabels,
        'p_rink_assignments': rinkAssignments,
        'p_team_selection_members': teamSelectionMembers,
      },
    );

    return result.toString();
  }

  Future<RepeatFixtureCreateOutcome> _createSingleRepeatFixture(
    RepeatFixtureDate repeatDate, {
    required List<String> preferredRinkLabels,
  }) async {
    if (_fixtureTypeId == null || _fixtureTypeId!.trim().isEmpty) {
      throw Exception('Please choose a Fixture Type.');
    }

    if (_section.trim().isEmpty) {
      throw Exception('Section is missing for the selected Fixture Type.');
    }

    if (_startAtLocal == null || _endAtLocal == null) {
      throw Exception('Please select a start and end time.');
    }

    final selectedFixtureType = _fixtureTypeById(_fixtureTypeId);
    final isInternalFixtureType = selectedFixtureType?['is_internal'] == true;
    final usesRinks = selectedFixtureType?['uses_rinks'] != false;

    final startAt = _combineRepeatDateWithOriginalTime(repeatDate.date);
    final duration = _endAtLocal!.difference(_startAtLocal!);
    final endAt = startAt.add(duration);

    if (!usesRinks) {
      if (_teamNameCtrl.text.trim().isEmpty) {
        throw Exception('Please enter an event name.');
      }

      if (_eventVenueId == null || _eventVenueId!.trim().isEmpty) {
        throw Exception('Please select an event venue.');
      }

      if (_eventOrganiserMemberProfileId == null ||
          _eventOrganiserMemberProfileId!.trim().isEmpty) {
        throw Exception('Please select an organiser.');
      }

      final fixtureId = await _createFixtureWithSetupRpc(
        startAtLocal: startAt,
        endAtLocal: endAt,
        isHome: true,
        venueId: _eventVenueId!,
        opponentVenueId: null,
        usesRinks: false,
        greenAreaId: null,
        orientation: null,
        fixtureLabel: _teamNameCtrl.text.trim(),
        captainMemberProfileId: _eventOrganiserMemberProfileId,
        viceCaptainMemberProfileId: _eventViceOrganiserMemberProfileId,
        createTeamSelection: false,
        homeRinkLabels: const [],
        rinkAssignments: const [],
        teamSelectionMembers: const [],
      );

      return RepeatFixtureCreateOutcome(
        fixtureId: fixtureId,
        message: 'Event created successfully',
      );
    }

    if (_homeVenueId == null) {
      throw Exception('Please select a home venue.');
    }

    if (!isInternalFixtureType &&
        (repeatDate.opponentVenueId == null ||
            repeatDate.opponentVenueId!.trim().isEmpty)) {
      throw Exception('Please select an opponent venue.');
    }

    final isHome = isInternalFixtureType ? true : repeatDate.isHome;

    if (isHome && _greenAreaId == null) {
      throw Exception('Please select a green area.');
    }

    final String venueId = isHome ? _homeVenueId! : repeatDate.opponentVenueId!;

    final String? opponentVenueId = isInternalFixtureType
        ? null
        : (isHome ? repeatDate.opponentVenueId! : _homeVenueId!);

    final fixtureLabel = _isTeamFixture
        ? (_selectedTeamName() ?? '')
        : _teamNameCtrl.text.trim();

    if (_isTeamFixture && _teamId == null) {
      throw Exception('Please select a team.');
    }

    final availabilityRows = await _rpcWithSingleRetry(
      'get_green_rink_availability',
      params: {
        'p_green_area_id': isHome ? _greenAreaId : null,
        'p_start_at': clubTimeToUtc(startAt).toIso8601String(),
        'p_end_at': clubTimeToUtc(endAt).toIso8601String(),
      },
    );

    final availablePreferredLabels = <String>[];
    final unavailablePreferredLabels = <String>[];

    if (isHome) {
      final availability = List<Map<String, dynamic>>.from(availabilityRows);

      if (preferredRinkLabels.isNotEmpty) {
        for (final label in preferredRinkLabels) {
          final matching = availability.firstWhere((r) {
            final rinkLabel = (r['rink_label'] ?? r['label'] ?? r['name'] ?? '')
                .toString();
            return rinkLabel == label;
          }, orElse: () => <String, dynamic>{});

          final isBooked = matching['is_booked'] == true;

          if (matching.isNotEmpty && !isBooked) {
            availablePreferredLabels.add(label);
          } else {
            unavailablePreferredLabels.add(label);
          }
        }
      }

      int asInt(dynamic v, int fallback) {
        if (v is int) return v;
        return int.tryParse((v ?? '').toString()) ?? fallback;
      }

      if (availability.isEmpty) {
        throw Exception('No rink availability returned for this green.');
      }

      final first = availability.first;
      final totalRinks = asInt(first['total_rinks'], availability.length);
      final freeRinks = asInt(first['free_capacity_rinks'], totalRinks);

      if (freeRinks < _rinksRequired) {
        throw Exception(
          'Not enough rinks available: $freeRinks free, $_rinksRequired required.',
        );
      }
    }

    final homeRinkLabels = <Map<String, dynamic>>[];

    for (var i = 1; i <= _rinksRequired; i++) {
      final preferredLabelIndex = i - 1;
      final homeRinkLabel =
          preferredLabelIndex < availablePreferredLabels.length
          ? availablePreferredLabels[preferredLabelIndex]
          : null;

      if (homeRinkLabel != null && homeRinkLabel.isNotEmpty) {
        homeRinkLabels.add({'team_no': i, 'home_rink_label': homeRinkLabel});
      }
    }

    final fixtureId = await _createFixtureWithSetupRpc(
      startAtLocal: startAt,
      endAtLocal: endAt,
      isHome: isHome,
      venueId: venueId,
      opponentVenueId: opponentVenueId,
      usesRinks: true,
      greenAreaId: _greenAreaId,
      orientation:
          (isHome &&
              _isOutdoorSelectedGreen &&
              _orientationEnabledForSelectedGreen)
          ? _orientation
          : null,
      fixtureLabel: fixtureLabel,
      captainMemberProfileId: null,
      viceCaptainMemberProfileId: null,
      createTeamSelection: false,
      homeRinkLabels: homeRinkLabels,
      rinkAssignments: const [],
      teamSelectionMembers: const [],
    );

    final assignedCount = availablePreferredLabels.length.clamp(
      0,
      _rinksRequired,
    );
    final missingCount = unavailablePreferredLabels.length;

    final message = preferredRinkLabels.isEmpty
        ? 'Created successfully'
        : missingCount == 0
        ? 'Created successfully. Preferred rinks assigned.'
        : 'Created successfully. $assignedCount preferred rink${assignedCount == 1 ? '' : 's'} assigned; '
              '$missingCount preferred rink${missingCount == 1 ? '' : 's'} unavailable, remaining rink booking left unassigned.';

    return RepeatFixtureCreateOutcome(fixtureId: fixtureId, message: message);
  }

  Future<void> _createRepeatFixtures(
    List<RepeatFixtureDate> dates, {
    required List<String> preferredRinkLabels,
  }) async {
    final results = <RepeatFixtureCreationResult>[];

    setState(() => _loading = true);

    try {
      for (final d in dates) {
        try {
          // Temporary first pass.
          // Next step: replace this with the real fixture insert.
          final outcome = await _createSingleRepeatFixture(
            d,
            preferredRinkLabels: preferredRinkLabels,
          );

          results.add(
            RepeatFixtureCreationResult(
              date: d.date,
              success: true,
              message: outcome.message,
              fixtureId: outcome.fixtureId,
            ),
          );
        } catch (e) {
          results.add(
            RepeatFixtureCreationResult(
              date: d.date,
              success: false,
              message: e.toString(),
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }

    await _showRepeatCreationResults(results);

    if (!mounted) return;

    _hasUnsavedChanges = false;
    Navigator.pop(context, true);
  }

  int _asInt(dynamic value, int fallback) {
    if (value is int) return value;
    return int.tryParse((value ?? '').toString()) ?? fallback;
  }

  int? _freeCapacityFromAvailabilityRows(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return null;

    final first = rows.first;
    final totalRinks = _asInt(first['total_rinks'], rows.length);

    return _asInt(first['free_capacity_rinks'], totalRinks);
  }

  Future<bool> _canAcceptRinksRequiredChange(int requestedRinks) async {
    // Reducing the number of rinks is always safe.
    if (requestedRinks <= _rinksRequired) return true;

    // Only home fixtures using rinks need this check.
    if (!_selectedFixtureUsesRinks || !_isHome) return true;

    if (_greenAreaId == null || _startAtLocal == null || _endAtLocal == null) {
      return true;
    }

    try {
      final rows = await _rpcWithSingleRetry(
        'get_green_rink_availability',
        params: {
          'p_green_area_id': _greenAreaId,
          'p_start_at': clubTimeToUtc(_startAtLocal!).toIso8601String(),
          'p_end_at': clubTimeToUtc(_endAtLocal!).toIso8601String(),
        },
      );

      final availability = List<Map<String, dynamic>>.from(rows);
      final freeRinks = _freeCapacityFromAvailabilityRows(availability);

      if (!mounted) return false;

      // Refresh the visible availability display while we are here.
      setState(() {
        _rinkAvailability = availability;
        _rinkAvailabilityError = null;
      });

      if (freeRinks == null) return true;

      return requestedRinks <= freeRinks;
    } catch (e) {
      if (!mounted) return false;

      setState(() {
        _rinkAvailabilityError = e.toString();
      });

      return false;
    }
  }

  Future<void> _showInsufficientRinksDialog() async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Not enough rinks'),
          content: const Text(
            'There are not enough free rinks for this fixture.\n\n'
            'Please change the green, time, date, or reduce the number of rinks required.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  int _compareVenueNames(Map<String, dynamic> a, Map<String, dynamic> b) {
    final nameA = (a['name'] ?? '').toString().trim().toLowerCase();
    final nameB = (b['name'] ?? '').toString().trim().toLowerCase();

    final byName = nameA.compareTo(nameB);
    if (byName != 0) return byName;

    final townA = (a['town_city'] ?? '').toString().trim().toLowerCase();
    final townB = (b['town_city'] ?? '').toString().trim().toLowerCase();
    return townA.compareTo(townB);
  }

  List<Map<String, dynamic>> _sortedVenues(
    Iterable<Map<String, dynamic>> venues,
  ) {
    final sorted = List<Map<String, dynamic>>.from(venues);
    sorted.sort(_compareVenueNames);
    return sorted;
  }

  Future<void> _loadVenues() async {
    final homeVenues = await _client
        .from('venues')
        .select(
          'id, name, town_city, postcode, is_home_venue, latitude, longitude, google_place_id',
        )
        .eq('club_id', widget.clubId)
        .eq('is_home_venue', true)
        .order('name');

    final opponentVenues = await _client
        .from('venues')
        .select(
          'id, name, town_city, postcode, is_home_venue, latitude, longitude, google_place_id',
        )
        .eq('club_id', widget.clubId)
        .eq('is_home_venue', false)
        .order('name');

    _homeVenues = _sortedVenues(List<Map<String, dynamic>>.from(homeVenues));
    _opponentVenues = _sortedVenues(
      List<Map<String, dynamic>>.from(opponentVenues),
    );

    // Defaults (first item), if not already selected
    _homeVenueId ??= _homeVenues.isNotEmpty
        ? _homeVenues.first['id'].toString()
        : null;

    // Leave opponent unset by default.
    // Home external fixtures may legitimately start as "To be confirmed".
    _opponentVenueId ??= null;

    _eventVenueId ??= _homeVenueId ?? _opponentVenueId;
  }

  Future<String?> _pickVenue({
    required List<Map<String, dynamic>> Function() getVenues,
    required String title,
    required VenueCreationType creationType,
  }) async {
    String search = '';
    List<Map<String, dynamic>> filtered = _sortedVenues(getVenues());

    final canCreateVenue = creationType == VenueCreationType.home
        ? _isSuperuser
        : (_isSuperuser || _isClubAdmin || _isSelector);

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setStateSheet) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  top: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.75,
                  child: Column(
                    children: [
                      // Heading + action buttons
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),

                          if (canCreateVenue &&
                              creationType == VenueCreationType.external)
                            TextButton.icon(
                              onPressed: () async {
                                final imported =
                                    await _discoverNearbyBowlsClubs();

                                if (!sheetContext.mounted || imported == 0) {
                                  return;
                                }

                                setStateSheet(() {
                                  filtered = _sortedVenues(getVenues());
                                });
                              },
                              icon: const Icon(Icons.radar),
                              label: const Text('Find local clubs'),
                            ),

                          if (canCreateVenue)
                            TextButton.icon(
                              onPressed: () async {
                                final newId = await _createVenueFromFixture(
                                  creationType: creationType,
                                );

                                if (newId == null || !sheetContext.mounted) {
                                  return;
                                }

                                Navigator.of(sheetContext).pop(newId);
                              },
                              icon: const Icon(Icons.add),
                              label: Text(
                                creationType == VenueCreationType.home
                                    ? 'Add home venue'
                                    : 'Add external venue',
                              ),
                            ),
                        ],
                      ),

                      // Special option for HOME external fixtures
                      if (creationType == VenueCreationType.external &&
                          _isHome) ...[
                        const SizedBox(height: 8),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.help_outline),
                          title: const Text('Opponent to be confirmed'),
                          subtitle: const Text(
                            'Create the fixture now and choose the opponent later.',
                          ),
                          onTap: () {
                            Navigator.of(sheetContext).pop('__TBC__');
                          },
                        ),
                        const Divider(),
                      ],

                      const SizedBox(height: 12),

                      // Venue search
                      TextField(
                        decoration: const InputDecoration(
                          hintText: 'Search venues...',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          search = value.toLowerCase();

                          setStateSheet(() {
                            filtered = _sortedVenues(
                              getVenues().where((v) {
                                final name = (v['name'] ?? '')
                                    .toString()
                                    .toLowerCase();

                                final town = (v['town_city'] ?? '')
                                    .toString()
                                    .toLowerCase();

                                final postcode = (v['postcode'] ?? '')
                                    .toString()
                                    .toLowerCase();

                                return name.contains(search) ||
                                    town.contains(search) ||
                                    postcode.contains(search);
                              }),
                            );
                          });
                        },
                      ),

                      const SizedBox(height: 12),

                      // Venue list
                      Expanded(
                        child: filtered.isEmpty
                            ? const Center(
                                child: Text('No venues match your search.'),
                              )
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (_, i) {
                                  final v = filtered[i];

                                  final name = (v['name'] ?? '').toString();

                                  final town = (v['town_city'] ?? '')
                                      .toString()
                                      .trim();

                                  final postcode = (v['postcode'] ?? '')
                                      .toString()
                                      .trim();

                                  return ListTile(
                                    title: Text(name),
                                    subtitle: Text(
                                      [
                                        if (town.isNotEmpty) town,
                                        if (postcode.isNotEmpty) postcode,
                                      ].join(' • '),
                                    ),
                                    onTap: () {
                                      Navigator.of(
                                        sheetContext,
                                      ).pop(v['id'].toString());
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _loadTeams() async {
    final rows = await _client
        .from('teams')
        .select('id, name, is_active')
        .eq('club_id', widget.clubId)
        .eq('is_active', true)
        .order('name');

    _teams = List<Map<String, dynamic>>.from(rows);
    _teamId ??= _teams.isNotEmpty ? _teams.first['id'].toString() : null;
  }

  Future<void> _loadGreenAreas() async {
    debugPrint('GREEN LOAD: _isHome=$_isHome, _homeVenueId=$_homeVenueId');

    // Green areas are only relevant for HOME fixtures
    if (!_isHome) {
      if (mounted) {
        setState(() {
          _greenAreas = [];
          _greenAreaId = null;
          _orientation = null;
        });
      }
      return;
    }

    if (_homeVenueId == null) {
      if (mounted) {
        setState(() {
          _greenAreas = [];
          _greenAreaId = null;
          _orientation = null;
        });
      }
      return;
    }

    final greens = await _client
        .from('green_areas')
        .select(
          'id, name, venue_id, discipline, orientation_mode, allowed_orientations',
        )
        .eq('venue_id', _homeVenueId!)
        .order('name');

    debugPrint(
      'GREEN LOAD: found ${greens.length} greens for venue $_homeVenueId',
    );
    debugPrint('GREEN LOAD: greens=$greens');

    final loadedGreens = List<Map<String, dynamic>>.from(greens);

    if (!mounted) return;

    setState(() {
      final existingGreenAreaId = _greenAreaId;

      _greenAreas = loadedGreens;

      final existingStillAvailable =
          existingGreenAreaId != null &&
          _greenAreas.any((g) => g['id']?.toString() == existingGreenAreaId);

      _greenAreaId = existingStillAvailable
          ? existingGreenAreaId
          : (_greenAreas.isNotEmpty
                ? _greenAreas.first['id'].toString()
                : null);

      _syncOrientationToSelectedGreen();
    });
  }

  Future<void> _moveBookedRinkToFreeRink(
    Map<String, dynamic> booked,
    String newRinkLabel,
  ) async {
    final oldLabel =
        (booked['rink_label'] ?? booked['label'] ?? booked['name'] ?? '')
            .toString();

    final fixtureRinkId = booked['fixture_rink_id']?.toString();

    if (fixtureRinkId == null || fixtureRinkId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cannot move this booking yet. Missing fixture rink id.',
          ),
        ),
      );
      return;
    }

    await Supabase.instance.client
        .from('fixture_rinks')
        .update({'home_rink_label': newRinkLabel})
        .eq('id', fixtureRinkId);

    setState(() {
      _selectedBookedRink = null;
    });

    await _loadRinkAvailability();

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Moved $oldLabel to $newRinkLabel')));
  }

  Future<void> _swapBookedRinks(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) async {
    final aId = a['fixture_rink_id']?.toString();
    final bId = b['fixture_rink_id']?.toString();

    final aLabel = (a['rink_label'] ?? a['label'] ?? a['name'] ?? '')
        .toString();
    final bLabel = (b['rink_label'] ?? b['label'] ?? b['name'] ?? '')
        .toString();

    if (aId == null || aId.isEmpty || bId == null || bId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot swap. Missing fixture rink id.')),
      );
      return;
    }

    try {
      await Supabase.instance.client.rpc(
        'swap_fixture_rink_labels',
        params: {'p_a_fixture_rink_id': aId, 'p_b_fixture_rink_id': bId},
      );

      setState(() {
        _selectedBookedRink = null;
      });

      await _loadRinkAvailability();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Swapped $aLabel with $bLabel')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Swap failed: $e')));
    }
  }

  Future<void> _handleRinkTap(Map<String, dynamic> rink) async {
    if (!_hasEnoughRinkCapacity) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'There are not enough free rinks for this fixture. Change the green, time, date, or reduce the rinks required.',
          ),
        ),
      );
      return;
    }

    final rinkLabel =
        (rink['rink_label'] ?? rink['label'] ?? rink['name'] ?? '').toString();

    final isBooked = rink['is_booked'] == true;

    debugPrint(
      'RINK TAP label=$rinkLabel isBooked=$isBooked '
      'canAdmin=$_canEditAdminFixtureDetails '
      'selectedBooked=${_selectedBookedRink != null}',
    );

    if (rinkLabel.isEmpty) return;

    if (isBooked) {
      if (!_canEditAdminFixtureDetails) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This rink is already booked.')),
        );
        return;
      }

      final currentSelectedLabel =
          (_selectedBookedRink?['rink_label'] ??
                  _selectedBookedRink?['label'] ??
                  _selectedBookedRink?['name'] ??
                  '')
              .toString();

      if (currentSelectedLabel == rinkLabel) {
        setState(() {
          _selectedBookedRink = null;
        });
        return;
      }

      if (_selectedBookedRink != null) {
        _swapBookedRinks(_selectedBookedRink!, rink);
        return;
      }

      setState(() {
        _selectedBookedRink = rink;
      });
      return;
    }

    if (_selectedBookedRink != null) {
      _moveBookedRinkToFreeRink(_selectedBookedRink!, rinkLabel);
      return;
    }

    _toggleHomeRinkSelection(rinkLabel);
  }

  void _syncOrientationToSelectedGreen() {
    final g = _selectedGreenArea;
    if (g == null) {
      _orientation = null;
      return;
    }

    final allowed = _allowedOrientationsFor(g);
    if (allowed.isEmpty) {
      _orientation = null;
      return;
    }

    if (_orientation == null || !allowed.contains(_orientation)) {
      _orientation = allowed.first;
    }
  }

  void _applyInitialRinkBookingContext() {
    final booking = widget.initialRinkBooking;

    if (booking == null || _initialRinkBookingApplied) return;

    _initialRinkBookingApplied = true;

    _isHome = true;
    _fixtureLocation = FixtureLocationType.home;

    _startAtLocal = booking.startAt;
    _endAtLocal = booking.suggestedEndAt ?? booking.latestEndAt;

    final greenExists = _greenAreas.any(
      (g) => g['id']?.toString() == booking.greenAreaId,
    );

    if (greenExists) {
      _greenAreaId = booking.greenAreaId;
    }

    _selectedHomeRinkByTeam.clear();

    if (booking.rinkLabel.trim().isNotEmpty) {
      _selectedHomeRinkByTeam[1] = booking.rinkLabel;
    }

    _syncOrientationToSelectedGreen();
    _shownInsufficientRinksWarning = false;
  }

  void _applyFixtureType(String? fixtureTypeId) {
    if (fixtureTypeId == null) return;

    final row = _fixtureTypes.cast<Map<String, dynamic>?>().firstWhere(
      (r) => r?['id']?.toString() == fixtureTypeId,
      orElse: () => null,
    );

    if (row == null) return;

    final selectionMode = (row['selection_mode'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final name = (row['name'] ?? '').toString().trim();
    final section = (row['section'] ?? '').toString().trim();
    final isInternal = row['is_internal'] == true;
    final defaultRinksRequired = row['default_rinks_required'] as int?;
    final defaultPlayersPerRink = row['default_players_per_rink'] as int?;

    final defaultFormat = (row['default_format'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final defaultDressCode = (row['dress_code'] ?? 'open')
        .toString()
        .trim()
        .toLowerCase();

    final linkedTeamId = row['team_id']?.toString();
    final usesRinks = row['uses_rinks'] == true;

    final selectionModeLower = selectionMode.toLowerCase();

    final usesSimpleBookingWorkflow =
        isInternal && selectionModeLower == 'preselect';

    setState(() {
      _fixtureTypeId = fixtureTypeId;
      _workflowLockedByFixtureType = true;
      _hasUnsavedChanges = true;

      if (!usesRinks) {
        _isHome = true;
        _fixtureLocation = FixtureLocationType.home;
        _workflowType = FixtureWorkflowType.rsvp;

        _isTeamFixture = false;
        _isPreselectFixture = false;
        _teamId = null;
        _opponentVenueId = null;
        _greenAreaId = null;
        _greenAreas = [];
        _orientation = null;
        _rinksRequired = 0;
        _playersPerRink = 1;

        _teamNameCtrl.text = name;
        _eventVenueId ??= _homeVenueId ?? _opponentVenueId;
        _eventOrganiserMemberProfileId ??= _currentMemberId;
      }

      if (isInternal) {
        _isHome = true;
        _fixtureLocation = FixtureLocationType.home;
        _opponentVenueId = null;
      }

      if (selectionMode == 'team') {
        _workflowType = FixtureWorkflowType.team;
        _isTeamFixture = true;
        _isPreselectFixture = false;
        _teamNameCtrl.text = name;

        if (linkedTeamId != null && linkedTeamId.isNotEmpty) {
          _teamId = linkedTeamId;
        } else {
          _teamId = null; // force user to choose team
        }
      } else if (selectionMode == 'preselect') {
        _isTeamFixture = false;
        _isPreselectFixture = true;
        _teamId = null;

        _teamNameCtrl.text = name;
      } else if (selectionMode == 'opensession') {
        //        _workflowType = FixtureWorkflowType.rsvp; // neutral existing workflow
        _isTeamFixture = false;
        _isPreselectFixture = false;
        _teamId = null;

        _teamNameCtrl.text = name;
      } else {
        // rsvp / practice
        _workflowType = FixtureWorkflowType.rsvp;
        _isTeamFixture = false;
        _isPreselectFixture = false;
        _teamId = null;

        _teamNameCtrl.text = name;
      }

      if (section.isNotEmpty) {
        _section = section;
      }
      _dressCode = defaultDressCode.isEmpty ? 'open' : defaultDressCode;

      if (usesRinks) {
        if (defaultFormat.isNotEmpty) {
          _format = defaultFormat == 'fours' ? 'rinks' : defaultFormat;

          switch (_format) {
            case 'singles':
              _playersPerRink = 1;
              break;
            case 'pairs':
            case 'aussie_pairs':
              _playersPerRink = 2;
              break;
            case 'triples':
              _playersPerRink = 3;
              break;
            case 'fours':
            case 'rinks':
              _playersPerRink = 4;
              break;
            default:
              if (defaultPlayersPerRink != null) {
                _playersPerRink = defaultPlayersPerRink;
              }
          }
        } else if (defaultPlayersPerRink != null) {
          _playersPerRink = defaultPlayersPerRink;

          switch (_playersPerRink) {
            case 1:
              _format = 'singles';
              break;
            case 2:
              _format = 'pairs';
              break;
            case 3:
              _format = 'triples';
              break;
            case 4:
            default:
              _format = 'rinks';
              break;
          }
        }

        if (defaultRinksRequired != null) {
          _rinksRequired = defaultRinksRequired;
        }
      }
      if (usesSimpleBookingWorkflow) {
        _fixtureLocation = FixtureLocationType.home;
        _isHome = true;

        _workflowType = FixtureWorkflowType.rsvp; // hidden anyway
        _isTeamFixture = false;
        _isPreselectFixture = true;

        _teamId = null;
        _opponentVenueId = null;

        _teamNameCtrl.text = name;
      }
    });

    _defaultBookerIntoFirstPlayerSlot();

    if (usesRinks) {
      _loadGreenAreas();
      _loadRinkAvailability();
    }
  }

  String _memberLabel(Map<String, dynamic> m) {
    final first = (m['first_name'] ?? '').toString().trim();
    final last = (m['last_name'] ?? '').toString().trim();
    final display = (m['display_name'] ?? '').toString().trim();

    if (last.isNotEmpty && first.isNotEmpty) return '$last, $first';
    if (display.isNotEmpty) return display;
    return 'Unnamed member';
  }

  String _selectedMemberLabel(String? memberProfileId) {
    if (memberProfileId == null) return 'Select player';

    final match = _clubMembers.where(
      (m) => m['id'].toString() == memberProfileId,
    );
    if (match.isEmpty) return 'Select player';

    return _memberLabel(match.first);
  }

  String _selectedMemberOrPrompt(String? memberProfileId, String prompt) {
    if (memberProfileId == null || memberProfileId.isEmpty) return prompt;

    final match = _clubMembers.where(
      (m) => m['id'].toString() == memberProfileId,
    );
    if (match.isEmpty) return prompt;

    return _memberLabel(match.first);
  }

  Future<void> _pickEventOrganiser({required bool vice}) async {
    final currentId = vice
        ? _eventViceOrganiserMemberProfileId
        : _eventOrganiserMemberProfileId;
    final otherId = vice
        ? _eventOrganiserMemberProfileId
        : _eventViceOrganiserMemberProfileId;

    final selected = await Navigator.of(context).push<List<String>?>(
      MaterialPageRoute(
        builder: (_) => ClubMemberPickerPage(
          clubId: widget.clubId,
          title: vice ? 'Select Deputy Organiser' : 'Select Organiser',
          fixtureId: null,
          useFixtureSection: false,
          initialSectionFilter: MemberPickerSectionFilter.open,
          allowMultiple: false,
          initialSelectedIds: {
            if (currentId != null && currentId.isNotEmpty) currentId,
          },
          excludeMemberProfileIds: {
            if (otherId != null && otherId.isNotEmpty) otherId,
          },
        ),
      ),
    );

    if (!mounted || selected == null) return;

    final memberId = selected.isEmpty ? null : selected.first;

    setState(() {
      if (vice) {
        _eventViceOrganiserMemberProfileId = memberId;
      } else {
        _eventOrganiserMemberProfileId = memberId;
      }
    });
    _markDirty();
  }

  Widget _buildEventOrganisersSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Event organisers',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'The organiser and deputy can manage the event and see member responses.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _pickEventOrganiser(vice: false),
              icon: const Icon(Icons.person_outline),
              label: Text(
                'Organiser: ${_selectedMemberOrPrompt(_eventOrganiserMemberProfileId, 'Select organiser')}',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _pickEventOrganiser(vice: true),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: Text(
                'Deputy: ${_selectedMemberOrPrompt(_eventViceOrganiserMemberProfileId, 'Optional')}',
              ),
            ),
            if (_eventViceOrganiserMemberProfileId != null &&
                _eventViceOrganiserMemberProfileId!.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _eventViceOrganiserMemberProfileId = null;
                    });
                    _markDirty();
                  },
                  icon: const Icon(Icons.clear),
                  label: const Text('Remove deputy'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _selectedOpponentLabel(String key) {
    final memberId = _opponentSelections[key];
    if (memberId != null && memberId.isNotEmpty) {
      return _selectedMemberLabel(memberId);
    }

    final externalName = _opponentExternalNames[key]?.trim() ?? '';
    if (externalName.isNotEmpty) return externalName;

    return 'Optional — select or enter name';
  }

  Future<String?> _promptForExternalOpponentName({
    required int playerNo,
    required String initialValue,
  }) async {
    var enteredName = initialValue;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Opponent $playerNo name'),
          content: TextFormField(
            initialValue: initialValue,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'External opponent name',
              hintText: 'Leave blank to cancel',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              enteredName = value;
            },
            onFieldSubmitted: (value) {
              final name = value.trim();

              if (name.isNotEmpty) {
                Navigator.of(dialogContext).pop(name);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = enteredName.trim();

                if (name.isEmpty) return;

                Navigator.of(dialogContext).pop(name);
              },
              child: const Text('Use name'),
            ),
          ],
        );
      },
    );

    return result;
  }

  Future<void> _chooseOpponentForSlot({
    required int teamNo,
    required int playerNo,
  }) async {
    final key = _slotKey(teamNo, playerNo);

    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        final hasValue =
            (_opponentSelections[key]?.isNotEmpty == true) ||
            (_opponentExternalNames[key]?.trim().isNotEmpty == true);

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.person_search),
                title: const Text('Select a club member'),
                onTap: () => Navigator.pop(sheetContext, 'member'),
              ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Enter an external opponent name'),
                onTap: () => Navigator.pop(sheetContext, 'external'),
              ),
              if (hasValue)
                ListTile(
                  leading: const Icon(Icons.clear),
                  title: const Text('Leave opponent blank'),
                  onTap: () => Navigator.pop(sheetContext, 'clear'),
                ),
            ],
          ),
        );
      },
    );

    if (!mounted || choice == null) return;

    if (choice == 'member') {
      final beforeMember = _opponentSelections[key];
      final beforeExternal = _opponentExternalNames[key];

      await pickFixtureSlotMember(
        context: context,
        clubId: widget.clubId,
        title: 'Select Opponent $playerNo',
        bucket: 'opponent',
        key: key,
        selections: _opponentSelections,
        fixtureId: null,
        useFixtureSection: true,
        initialSectionFilter: _memberPickerSectionFilterForCurrentFixture(),
        showError: _showSaveErrorDialog,
        memberAlreadySelectedElsewhere: _memberAlreadySelectedElsewhere,
      );

      if (!mounted) return;

      final selectedMember = _opponentSelections[key];
      if (selectedMember != null && selectedMember.isNotEmpty) {
        setState(() => _opponentExternalNames.remove(key));
      } else {
        setState(() {});
      }

      if (beforeMember != _opponentSelections[key] ||
          beforeExternal != _opponentExternalNames[key]) {
        _markDirty();
      }
      return;
    }

    if (choice == 'external') {
      final name = await _promptForExternalOpponentName(
        playerNo: playerNo,
        initialValue: _opponentExternalNames[key] ?? '',
      );

      if (!mounted || name == null) return;

      setState(() {
        _opponentSelections.remove(key);
        _opponentExternalNames[key] = name;
      });
      _markDirty();
      return;
    }

    if (choice == 'clear') {
      setState(() {
        _opponentSelections.remove(key);
        _opponentExternalNames.remove(key);
      });
      _markDirty();
    }
  }

  bool _markerRequiredForTeam(int teamNo) {
    final markerId = _markerSelections[_slotKey(teamNo, 1)];
    return _markerRequiredByTeam[teamNo] == true ||
        _markerRequestByTeam[teamNo] == true ||
        (markerId != null && markerId.isNotEmpty);
  }

  void _setMarkerRequiredForTeam(int teamNo, bool required) {
    setState(() {
      _markerRequiredByTeam[teamNo] = required;

      if (!required) {
        _markerSelections.remove(_slotKey(teamNo, 1));
        _markerRequestByTeam.remove(teamNo);
      }
    });
    _markDirty();
  }

  Future<void> _pickMarkerForTeam(int teamNo) async {
    final key = _slotKey(teamNo, 1);
    final beforeMarker = _markerSelections[key];

    await pickFixtureSlotMember(
      context: context,
      clubId: widget.clubId,
      title: 'Select Marker for Team $teamNo',
      bucket: 'marker',
      key: key,
      selections: _markerSelections,
      fixtureId: null,
      useFixtureSection: false,
      initialSectionFilter: MemberPickerSectionFilter.open,
      showError: _showSaveErrorDialog,
      memberAlreadySelectedElsewhere: _memberAlreadySelectedElsewhere,
    );

    if (!mounted) return;

    final markerId = _markerSelections[key];
    setState(() {
      if (markerId != null && markerId.isNotEmpty) {
        _markerRequiredByTeam[teamNo] = true;
        _markerRequestByTeam[teamNo] = false;
      }
    });

    if (beforeMarker != markerId) _markDirty();
  }

  void _toggleMarkerRequestForTeam(int teamNo) {
    final shouldRequest = _markerRequestByTeam[teamNo] != true;

    setState(() {
      _markerRequiredByTeam[teamNo] = true;
      _markerRequestByTeam[teamNo] = shouldRequest;

      if (shouldRequest) {
        _markerSelections.remove(_slotKey(teamNo, 1));
      }
    });
    _markDirty();
  }

  void _clearNamedMarkerForTeam(int teamNo) {
    setState(() {
      _markerSelections.remove(_slotKey(teamNo, 1));
      // The rink can still require a marker without immediately asking for one.
      _markerRequiredByTeam[teamNo] = true;
    });
    _markDirty();
  }

  String? get _selectedGreenName {
    if (_greenAreaId == null) return null;

    for (final g in _greenAreas) {
      if (g['id'].toString() == _greenAreaId) {
        return g['name']?.toString();
      }
    }

    return null;
  }

  Color get _selectedFixtureBgColor {
    final ft = _fixtureTypeById(_fixtureTypeId);
    final hex = ft?['colour_scheme']?['background_hex']?.toString();

    if (hex == null || hex.isEmpty) {
      return Colors.blue.shade50;
    }

    return _colourFromHex(hex);
  }

  Color get _selectedFixtureFgColor {
    final ft = _fixtureTypeById(_fixtureTypeId);
    final hex = ft?['colour_scheme']?['foreground_hex']?.toString();

    if (hex == null || hex.isEmpty) {
      return Colors.blue.shade900;
    }

    return _colourFromHex(hex);
  }

  Map<String, dynamic>? get _selectedGreenArea {
    if (_greenAreaId == null) return null;
    for (final g in _greenAreas) {
      if (g['id'].toString() == _greenAreaId) return g;
    }
    return null;
  }

  final Map<int, String> _selectedHomeRinkByTeam = {};

  int? _teamNoForSelectedRink(String rinkLabel) {
    for (final entry in _selectedHomeRinkByTeam.entries) {
      if (entry.value == rinkLabel) {
        return entry.key;
      }
    }
    return null;
  }

  static const Duration _recommendedFixtureDuration = Duration(hours: 2);

  Duration? get _currentRinkBookingDuration {
    final booking = widget.initialRinkBooking;
    if (booking == null) return null;

    if (_startAtLocal == null || _endAtLocal == null) return null;

    return _endAtLocal!.difference(_startAtLocal!);
  }

  bool get _currentRinkBookingIsShort {
    final duration = _currentRinkBookingDuration;
    if (duration == null) return false;

    return duration < _recommendedFixtureDuration;
  }

  String _friendlyDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0 && minutes > 0) {
      return '$hours hr ${minutes} mins';
    }

    if (hours > 0) {
      return hours == 1 ? '1 hr' : '$hours hrs';
    }

    return '$minutes mins';
  }

  void _toggleHomeRinkSelection(String rinkLabel) {
    final existingTeamNo = _teamNoForSelectedRink(rinkLabel);

    setState(() {
      // Click again = unbook/unselect
      if (existingTeamNo != null) {
        _selectedHomeRinkByTeam.remove(existingTeamNo);
        return;
      }

      // Otherwise assign to first team without a rink
      for (var teamNo = 1; teamNo <= _rinksRequired; teamNo++) {
        if (!_selectedHomeRinkByTeam.containsKey(teamNo)) {
          _selectedHomeRinkByTeam[teamNo] = rinkLabel;
          return;
        }
      }
    });
  }

  List<String> _selectedRepeatRinkLabels() {
    final labels = <String>[];

    for (final rink in _rinkAvailability) {
      final rinkLabel =
          (rink['rink_label'] ?? rink['label'] ?? rink['name'] ?? '')
              .toString();

      if (rinkLabel.isEmpty) continue;

      if (_teamNoForSelectedRink(rinkLabel) != null) {
        labels.add(rinkLabel);
      }
    }

    return labels;
  }

  List<String> _allowedOrientationsFor(Map<String, dynamic> greenAreaRow) {
    final raw = greenAreaRow['allowed_orientations'];
    if (raw is! List) return [];

    // Stored as lowercase: ["north_south","east_west"]
    final vals = raw
        .map((e) => e.toString().trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    // Stable ordering preference
    vals.sort((a, b) {
      const pref = {'north_south': 0, 'east_west': 1};
      return (pref[a] ?? 99).compareTo(pref[b] ?? 99);
    });

    return vals;
  }

  String _backgroundImageForWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (width >= 1000) {
      return 'assets/images/blank_bg_desktop_2.png';
    }
    if (width >= 600) {
      return 'assets/images/blank_bg_tablet_2.png';
    }
    return 'assets/images/blank_bg_phone_2.png';
  }

  bool get _canEditAdminFixtureDetails =>
      _isSuperuser || _isClubAdmin || _isSelector || _isFixtureCreator;

  bool get _canEditFixtureOperationalDetails =>
      _canEditAdminFixtureDetails || _isFixtureCaptain || _isFixtureViceCaptain;

  Map<String, dynamic>? get _selectedFixtureType =>
      _fixtureTypeById(_fixtureTypeId);

  String get _selectedFixtureSelectionMode =>
      (_selectedFixtureType?['selection_mode'] ?? '')
          .toString()
          .trim()
          .toLowerCase();

  bool get _selectedFixtureIsInternal =>
      _selectedFixtureType?['is_internal'] == true;

  bool get _selectedFixtureIsBookableByMembers =>
      _selectedFixtureType?['bookable_by_members'] == true;

  /// WORKFLOW:
  /// Controls which create-screen process/UI is used.
  bool get _simpleBookingMode =>
      _selectedFixtureIsInternal &&
      _selectedFixtureSelectionMode == 'preselect';

  bool get _shouldShowRinksSection {
    return _selectedFixtureUsesRinks &&
        _isHome &&
        _greenAreaId != null &&
        (_rinksRequired > 0);
  }

  bool get _isOpenSessionFixture =>
      _selectedFixtureSelectionMode == 'opensession' ||
      _selectedFixtureSelectionMode == 'open_session' ||
      _selectedFixtureSelectionMode == 'open-session';

  bool get _selectedFixtureUsesRinks {
    final raw = _selectedFixtureType?['uses_rinks'];
    if (raw == null) return true; // safer default for existing fixture types
    return raw == true;
  }

  bool get _isEventStyleFixture =>
      _selectedFixtureType != null && !_selectedFixtureUsesRinks;

  bool _looksLikeTransientNetworkError(Object e) {
    final s = e.toString().toLowerCase();

    return s.contains('socketexception') ||
        s.contains('semaphore timeout') ||
        s.contains('connection timed out') ||
        s.contains('connection closed') ||
        s.contains('failed host lookup') ||
        s.contains('network is unreachable');
  }

  List<Map<String, dynamic>> get _allVenues {
    final byId = <String, Map<String, dynamic>>{};

    for (final v in [..._homeVenues, ..._opponentVenues]) {
      final id = v['id']?.toString();
      if (id == null || id.isEmpty) continue;
      byId[id] = v;
    }

    return _sortedVenues(byId.values);
  }

  /// ACCESS:
  /// Controls whether the logged-in user may create/use this fixture type.
  bool get _canUseSelectedFixtureType {
    if (_selectedFixtureType == null) return false;
    if (_canEditAdminFixtureDetails) return true;

    return _selectedFixtureIsBookableByMembers;
  }

  bool get _canSeeAllFixtureTypes =>
      _isSuperuser || _isClubAdmin || _isSelector;

  bool get _isOutdoorSelectedGreen {
    final g = _selectedGreenArea;
    if (g == null) return false;
    final discipline = (g['discipline'] ?? '').toString().toLowerCase();
    return discipline.contains('outdoor');
  }

  bool get _orientationEnabledForSelectedGreen {
    final g = _selectedGreenArea;
    if (g == null) return false;
    final mode = (g['orientation_mode'] ?? '').toString().toLowerCase();
    return mode != 'off';
  }

  bool get _canUseRepeat {
    if (_isPreselectFixture) return false;

    return _isClubAdmin || _isSelector || _isSuperuser;
  }

  bool get _hasEnoughRinkCapacity {
    if (_rinkAvailability.isEmpty) return true;

    int asInt(dynamic v, int fallback) {
      if (v is int) return v;
      return int.tryParse((v ?? '').toString()) ?? fallback;
    }

    final first = _rinkAvailability.first;
    final totalRinks = asInt(first['total_rinks'], _rinkAvailability.length);
    final freeRinks = asInt(first['free_capacity_rinks'], totalRinks);

    return freeRinks >= _rinksRequired;
  }

  bool _memberAlreadySelectedElsewhere({
    required String memberProfileId,
    required String targetBucket,
    required String targetKey,
  }) {
    bool foundIn(Map<String, String?> map, String bucket) {
      for (final entry in map.entries) {
        if (bucket == targetBucket && entry.key == targetKey) {
          continue;
        }

        if (entry.value == memberProfileId) {
          return true;
        }
      }

      return false;
    }

    return foundIn(_playerSelections, 'player') ||
        foundIn(_opponentSelections, 'opponent') ||
        foundIn(_markerSelections, 'marker');
  }

  Color _colourFromHex(String hex) {
    final clean = hex.replaceAll('#', '').trim();
    if (clean.length != 6) return Colors.grey.shade100;
    return Color(int.parse('FF$clean', radix: 16));
  }

  String? _selectedTeamName() {
    if (_teamId == null || _teamId!.isEmpty) return null;

    final team = _teams.firstWhere(
      (t) => t['id'].toString() == _teamId,
      orElse: () => <String, dynamic>{},
    );

    final name = (team['name'] ?? '').toString().trim();
    return name.isEmpty ? null : name;
  }

  String _normaliseVenueName(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  String _normalisePostcode(String value) {
    return value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  }

  Map<String, dynamic>? _findPossibleDuplicateVenue({
    required String name,
    required String postcode,
  }) {
    final normalisedName = _normaliseVenueName(name);
    final normalisedPostcode = _normalisePostcode(postcode);

    for (final venue in _allVenues) {
      final existingName = _normaliseVenueName(
        (venue['name'] ?? '').toString(),
      );
      final existingPostcode = _normalisePostcode(
        (venue['postcode'] ?? '').toString(),
      );

      final sameName =
          normalisedName.isNotEmpty && existingName == normalisedName;
      final samePostcode =
          normalisedPostcode.isNotEmpty &&
          existingPostcode.isNotEmpty &&
          existingPostcode == normalisedPostcode;

      if (sameName || samePostcode) return venue;
    }

    return null;
  }

  Future<bool> _confirmCreatePossibleDuplicate(
    Map<String, dynamic> existing,
  ) async {
    final name = (existing['name'] ?? '').toString().trim();
    final town = (existing['town_city'] ?? '').toString().trim();
    final postcode = (existing['postcode'] ?? '').toString().trim();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Possible duplicate venue'),
        content: Text(
          'A similar venue already exists:\n\n'
          '$name'
          '${town.isEmpty ? '' : '\n$town'}'
          '${postcode.isEmpty ? '' : '\n$postcode'}\n\n'
          'Create another venue anyway?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Use existing list'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Create anyway'),
          ),
        ],
      ),
    );

    return result == true;
  }

  Map<String, dynamic> _asStringDynamicMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return <String, dynamic>{};
  }

  String _venuePlacesError(dynamic data, int status) {
    final map = _asStringDynamicMap(data);
    final message = map['error']?.toString().trim();
    if (message != null && message.isNotEmpty) return message;
    return 'Google venue search failed (HTTP $status).';
  }

  Future<Map<String, dynamic>> _invokeVenuePlaces(
    Map<String, dynamic> body,
  ) async {
    final response = await _client.functions.invoke('venue-places', body: body);

    if (response.status < 200 || response.status >= 300) {
      throw Exception(_venuePlacesError(response.data, response.status));
    }

    return _asStringDynamicMap(response.data);
  }

  Map<String, double>? _homeVenueCoordinates() {
    if (_homeVenueId == null) return null;

    final venue = _homeVenues.firstWhere(
      (v) => v['id']?.toString() == _homeVenueId,
      orElse: () => <String, dynamic>{},
    );

    final latitude = venue['latitude'];
    final longitude = venue['longitude'];

    if (latitude is num && longitude is num) {
      return {
        'latitude': latitude.toDouble(),
        'longitude': longitude.toDouble(),
      };
    }

    return null;
  }

  Future<Map<String, dynamic>?> _searchGoogleForVenue({
    required String initialQuery,
    required GoogleVenueSearchMode initialMode,
  }) async {
    final queryController = TextEditingController(text: initialQuery);
    var searching = false;
    var searchMode = initialMode;
    String? error;
    List<Map<String, dynamic>> places = [];

    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
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
                final body = <String, dynamic>{
                  'action': 'search',
                  'clubId': widget.clubId,
                  'query': query,
                  'mode': searchMode == GoogleVenueSearchMode.bowlsClub
                      ? 'bowls_club'
                      : 'general',
                };

                final coordinates = _homeVenueCoordinates();
                if (coordinates != null) {
                  body.addAll(coordinates);
                  body['radiusMetres'] = 50000;
                }

                final data = await _invokeVenuePlaces(body);
                final rawPlaces = data['places'];

                if (!dialogContext.mounted) return;
                setStateDialog(() {
                  places = rawPlaces is List
                      ? rawPlaces
                            .map(_asStringDynamicMap)
                            .where((p) => p.isNotEmpty)
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
                final details = _asStringDynamicMap(data['place']);

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

            final bowlsOnly = searchMode == GoogleVenueSearchMode.bowlsClub;

            return AlertDialog(
              title: Text(
                bowlsOnly ? 'Search for a bowls club' : 'Search Google Places',
              ),
              content: SizedBox(
                width: 620,
                height: 520,
                child: Column(
                  children: [
                    TextField(
                      controller: queryController,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        labelText: bowlsOnly
                            ? 'Bowls club or area'
                            : 'Venue or place',
                        hintText: bowlsOnly
                            ? 'e.g. Petts Wood'
                            : 'e.g. Civic Hall, Bromley',
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
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: searching
                            ? null
                            : () {
                                setStateDialog(() {
                                  searchMode = bowlsOnly
                                      ? GoogleVenueSearchMode.general
                                      : GoogleVenueSearchMode.bowlsClub;
                                  places = [];
                                  error = null;
                                });
                              },
                        icon: Icon(bowlsOnly ? Icons.public : Icons.sports),
                        label: Text(
                          bowlsOnly
                              ? 'Search all venues instead'
                              : 'Search bowls clubs only',
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (searching) const LinearProgressIndicator(),
                    if (error != null) ...[
                      const SizedBox(height: 10),
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
                                    : bowlsOnly
                                    ? 'Search by club name or area. Only likely lawn bowls clubs will be shown.'
                                    : 'Search for a venue, then select the correct result.',
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView.separated(
                              itemCount: places.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, index) {
                                final place = places[index];
                                final name =
                                    place['name']?.toString() ??
                                    'Unnamed place';
                                final address =
                                    place['formattedAddress']?.toString() ?? '';

                                return ListTile(
                                  leading: const Icon(
                                    Icons.location_on_outlined,
                                  ),
                                  title: Text(name),
                                  subtitle: address.isEmpty
                                      ? null
                                      : Text(address),
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
        );
      },
    );

    queryController.dispose();
    return selected;
  }

  bool _nearbyPlaceAlreadySaved(Map<String, dynamic> place) {
    final placeId = place['placeId']?.toString().trim();
    final name = place['name']?.toString().trim().toLowerCase() ?? '';
    final postcode = place['postcode']?.toString().trim().toUpperCase() ?? '';

    return _opponentVenues.any((venue) {
      final existingPlaceId = venue['google_place_id']?.toString().trim();
      if (placeId != null && placeId.isNotEmpty && existingPlaceId == placeId) {
        return true;
      }

      final existingName = venue['name']?.toString().trim().toLowerCase() ?? '';
      final existingPostcode =
          venue['postcode']?.toString().trim().toUpperCase() ?? '';
      return name.isNotEmpty &&
          existingName == name &&
          postcode.isNotEmpty &&
          existingPostcode == postcode;
    });
  }

  Future<String?> _createVenueFromGooglePlace(
    Map<String, dynamic> place,
  ) async {
    final name = place['name']?.toString().trim() ?? '';
    if (name.isEmpty) return null;

    final postcode = place['postcode']?.toString().trim().toUpperCase() ?? '';

    final result = await _client.rpc(
      'create_club_venue',
      params: {
        'p_club_id': widget.clubId,
        'p_name': name,
        'p_is_home_venue': false,
        'p_address_line1':
            place['addressLine1']?.toString().trim().isEmpty == false
            ? place['addressLine1'].toString().trim()
            : null,
        'p_town_city': place['townCity']?.toString().trim().isEmpty == false
            ? place['townCity'].toString().trim()
            : null,
        'p_postcode': postcode.isEmpty ? null : postcode,
        'p_contact_phone': place['phone']?.toString().trim().isEmpty == false
            ? place['phone'].toString().trim()
            : null,
        'p_latitude': place['latitude'] is num
            ? (place['latitude'] as num).toDouble()
            : null,
        'p_longitude': place['longitude'] is num
            ? (place['longitude'] as num).toDouble()
            : null,
        'p_directions_url': place['googleMapsUrl']?.toString(),
        'p_google_place_id': place['placeId']?.toString(),
        'p_website_url': place['websiteUrl']?.toString(),
        'p_google_maps_url': place['googleMapsUrl']?.toString(),
        'p_allow_possible_duplicate': false,
      },
    );

    return result?.toString();
  }

  Future<int> _discoverNearbyBowlsClubs() async {
    final coordinates = _homeVenueCoordinates();
    if (coordinates == null) {
      await _showSaveErrorDialog(
        'The selected home venue needs latitude and longitude before nearby bowls clubs can be found. Edit or recreate the home venue using Google Places first.',
      );
      return 0;
    }

    var radiusMiles = 10;
    var searching = false;
    var importing = false;
    String? error;
    List<Map<String, dynamic>> places = [];
    final selectedPlaceIds = <String>{};

    final selectedPlaces = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            Future<void> searchNearby() async {
              setStateDialog(() {
                searching = true;
                error = null;
                places = [];
                selectedPlaceIds.clear();
              });

              try {
                final result = await _invokeVenuePlaces({
                  'action': 'nearby_bowls',
                  'clubId': widget.clubId,
                  'latitude': coordinates['latitude'],
                  'longitude': coordinates['longitude'],
                  'radiusMetres': radiusMiles * 1609.344,
                });

                final rawPlaces = result['places'];
                final found = rawPlaces is List
                    ? rawPlaces
                          .map(_asStringDynamicMap)
                          .where(
                            (place) =>
                                place['placeId']?.toString().isNotEmpty == true,
                          )
                          .toList()
                    : <Map<String, dynamic>>[];

                setStateDialog(() {
                  places = found;
                  searching = false;
                });
              } catch (e) {
                setStateDialog(() {
                  searching = false;
                  error = e.toString().replaceFirst('Exception: ', '');
                });
              }
            }

            final availableCount = places
                .where((place) => !_nearbyPlaceAlreadySaved(place))
                .length;

            return AlertDialog(
              title: const Text('Find local bowls clubs'),
              content: SizedBox(
                width: 720,
                height: MediaQuery.of(context).size.height * 0.68,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Search around the selected home venue, then tick the clubs to add to this club’s external venue list.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('Radius:'),
                        const SizedBox(width: 10),
                        DropdownButton<int>(
                          value: radiusMiles,
                          items: const [5, 10, 15, 20, 25, 30]
                              .map(
                                (miles) => DropdownMenuItem<int>(
                                  value: miles,
                                  child: Text('$miles miles'),
                                ),
                              )
                              .toList(),
                          onChanged: searching || importing
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  setStateDialog(() {
                                    radiusMiles = value;
                                    places = [];
                                    selectedPlaceIds.clear();
                                    error = null;
                                  });
                                },
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: searching || importing
                              ? null
                              : searchNearby,
                          icon: const Icon(Icons.radar),
                          label: const Text('Search'),
                        ),
                      ],
                    ),
                    if (searching) ...[
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(),
                    ],
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
                                    ? 'Searching nearby clubs…'
                                    : 'Choose a radius and press Search.',
                              ),
                            )
                          : ListView.separated(
                              itemCount: places.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, index) {
                                final place = places[index];
                                final placeId =
                                    place['placeId']?.toString() ?? '';
                                final alreadySaved = _nearbyPlaceAlreadySaved(
                                  place,
                                );
                                final selected = selectedPlaceIds.contains(
                                  placeId,
                                );
                                final distance = place['distanceMiles'];
                                final distanceText = distance is num
                                    ? '${distance.toStringAsFixed(1)} miles away'
                                    : null;
                                final address =
                                    place['formattedAddress']?.toString() ?? '';

                                return CheckboxListTile(
                                  value: alreadySaved ? true : selected,
                                  onChanged: alreadySaved || importing
                                      ? null
                                      : (value) {
                                          setStateDialog(() {
                                            if (value == true) {
                                              selectedPlaceIds.add(placeId);
                                            } else {
                                              selectedPlaceIds.remove(placeId);
                                            }
                                          });
                                        },
                                  secondary: Icon(
                                    alreadySaved
                                        ? Icons.check_circle
                                        : Icons.sports,
                                  ),
                                  title: Text(
                                    place['name']?.toString() ??
                                        'Unnamed bowls club',
                                  ),
                                  subtitle: Text(
                                    [
                                      if (distanceText != null) distanceText,
                                      if (address.isNotEmpty) address,
                                      if (alreadySaved) 'Already in venue list',
                                    ].join('\n'),
                                  ),
                                  isThreeLine:
                                      alreadySaved || address.isNotEmpty,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                );
                              },
                            ),
                    ),
                    if (places.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '$availableCount new club${availableCount == 1 ? '' : 's'} found; '
                          '${selectedPlaceIds.length} selected.',
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: importing
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: importing || selectedPlaceIds.isEmpty
                      ? null
                      : () {
                          final selected = places
                              .where(
                                (place) => selectedPlaceIds.contains(
                                  place['placeId']?.toString(),
                                ),
                              )
                              .toList();
                          Navigator.of(dialogContext).pop(selected);
                        },
                  icon: const Icon(Icons.playlist_add),
                  label: Text('Add selected (${selectedPlaceIds.length})'),
                ),
              ],
            );
          },
        );
      },
    );

    if (selectedPlaces == null || selectedPlaces.isEmpty) return 0;

    var created = 0;
    final failures = <String>[];
    for (final place in selectedPlaces) {
      try {
        final newId = await _createVenueFromGooglePlace(place);
        if (newId != null) created++;
      } catch (e) {
        failures.add(
          '${place['name'] ?? 'Unknown club'}: '
          '${e.toString().replaceFirst('Exception: ', '')}',
        );
      }
    }

    await _loadVenues();

    if (mounted) {
      final message = failures.isEmpty
          ? '$created bowls club${created == 1 ? '' : 's'} added.'
          : '$created added; ${failures.length} could not be added.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }

    if (failures.isNotEmpty && mounted) {
      await _showSaveErrorDialog(
        'Some clubs could not be added:\n\n${failures.join('\n')}',
      );
    }

    return created;
  }

  Future<String?> _createVenueFromFixture({
    required VenueCreationType creationType,
  }) async {
    final isHomeVenue = creationType == VenueCreationType.home;

    if (isHomeVenue && !_isSuperuser) {
      await _showSaveErrorDialog(
        'Only a superuser can create a new home venue.',
      );
      return null;
    }

    if (!isHomeVenue && !(_isSuperuser || _isClubAdmin || _isSelector)) {
      await _showSaveErrorDialog(
        'You do not have permission to create a venue.',
      );
      return null;
    }

    final formKey = GlobalKey<FormState>();
    final venueNameController = TextEditingController();
    final addressLine1Controller = TextEditingController();
    final townCityController = TextEditingController();
    final postcodeController = TextEditingController();
    final phoneController = TextEditingController();
    final websiteController = TextEditingController();

    String? googlePlaceId;
    String? googleMapsUrl;
    double? latitude;
    double? longitude;
    String? formattedAddress;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            Future<void> findWithGoogle() async {
              final place = await _searchGoogleForVenue(
                initialQuery: venueNameController.text.trim(),
                initialMode: _isEventStyleFixture
                    ? GoogleVenueSearchMode.general
                    : GoogleVenueSearchMode.bowlsClub,
              );
              if (place == null || !dialogContext.mounted) return;

              setStateDialog(() {
                venueNameController.text = place['name']?.toString() ?? '';
                addressLine1Controller.text =
                    place['addressLine1']?.toString() ?? '';
                townCityController.text = place['townCity']?.toString() ?? '';
                postcodeController.text = place['postcode']?.toString() ?? '';
                phoneController.text = place['phone']?.toString() ?? '';
                websiteController.text = place['websiteUrl']?.toString() ?? '';

                googlePlaceId = place['placeId']?.toString();
                googleMapsUrl = place['googleMapsUrl']?.toString();
                formattedAddress = place['formattedAddress']?.toString();

                final rawLatitude = place['latitude'];
                final rawLongitude = place['longitude'];
                latitude = rawLatitude is num ? rawLatitude.toDouble() : null;
                longitude = rawLongitude is num
                    ? rawLongitude.toDouble()
                    : null;
              });
            }

            return AlertDialog(
              title: Text(
                isHomeVenue ? 'Add home venue' : 'Add external venue',
              ),
              content: SizedBox(
                width: 540,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!isHomeVenue) ...[
                          FilledButton.tonalIcon(
                            onPressed: findWithGoogle,
                            icon: const Icon(Icons.travel_explore),
                            label: Text(
                              _isEventStyleFixture
                                  ? 'Find venue with Google'
                                  : 'Find bowls club with Google',
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextFormField(
                          controller: venueNameController,
                          autofocus: isHomeVenue,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Venue or club name',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Please enter a venue name.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: addressLine1Controller,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Address',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: townCityController,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Town or city',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: postcodeController,
                          textCapitalization: TextCapitalization.characters,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Postcode',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Telephone (optional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: websiteController,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: 'Website (optional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        if (googlePlaceId != null &&
                            googlePlaceId!.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(
                                Icons.verified,
                                size: 18,
                                color: Colors.green.shade700,
                              ),
                              const SizedBox(width: 7),
                              const Expanded(
                                child: Text(
                                  'Details loaded from Google Places.',
                                ),
                              ),
                            ],
                          ),
                          if (formattedAddress?.isNotEmpty == true) ...[
                            const SizedBox(height: 4),
                            Text(
                              formattedAddress!,
                              style: Theme.of(
                                dialogContext,
                              ).textTheme.bodySmall,
                            ),
                          ],
                        ],
                        const SizedBox(height: 12),
                        Text(
                          isHomeVenue
                              ? 'Home venues are available only to this club and require superuser authority.'
                              : 'Review and edit the details before saving this opponent or external event venue.',
                          style: Theme.of(dialogContext).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    if (formKey.currentState?.validate() != true) return;
                    FocusManager.instance.primaryFocus?.unfocus();
                    Navigator.of(dialogContext).pop(true);
                  },
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('Create venue'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) {
      venueNameController.dispose();
      addressLine1Controller.dispose();
      townCityController.dispose();
      postcodeController.dispose();
      phoneController.dispose();
      websiteController.dispose();
      return null;
    }

    final venueName = venueNameController.text.trim();
    final addressLine1 = addressLine1Controller.text.trim();
    final townCity = townCityController.text.trim();
    final postcode = postcodeController.text.trim().toUpperCase();
    final phone = phoneController.text.trim();
    final websiteUrl = websiteController.text.trim();

    venueNameController.dispose();
    addressLine1Controller.dispose();
    townCityController.dispose();
    postcodeController.dispose();
    phoneController.dispose();
    websiteController.dispose();

    final possibleDuplicate = _findPossibleDuplicateVenue(
      name: venueName,
      postcode: postcode,
    );

    if (possibleDuplicate != null) {
      final createAnyway = await _confirmCreatePossibleDuplicate(
        possibleDuplicate,
      );
      if (!createAnyway) return null;
    }

    try {
      final result = await _client.rpc(
        'create_club_venue',
        params: {
          'p_club_id': widget.clubId,
          'p_name': venueName,
          'p_is_home_venue': isHomeVenue,
          'p_address_line1': addressLine1.isEmpty ? null : addressLine1,
          'p_town_city': townCity.isEmpty ? null : townCity,
          'p_postcode': postcode.isEmpty ? null : postcode,
          'p_contact_phone': phone.isEmpty ? null : phone,
          'p_latitude': latitude,
          'p_longitude': longitude,
          'p_directions_url': googleMapsUrl,
          'p_google_place_id': googlePlaceId,
          'p_website_url': websiteUrl.isEmpty ? null : websiteUrl,
          'p_google_maps_url': googleMapsUrl,
          'p_allow_possible_duplicate': possibleDuplicate != null,
        },
      );

      final newId = result?.toString();

      await _loadVenues();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isHomeVenue ? 'Home venue created.' : 'External venue created.',
            ),
          ),
        );
      }

      return newId;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Create venue error: $e')));
      }
      return null;
    }
  }

  Future<dynamic> _rpcWithSingleRetry(
    String functionName, {
    required Map<String, dynamic> params,
  }) async {
    try {
      return await _client.rpc(functionName, params: params);
    } catch (e) {
      if (!_looksLikeTransientNetworkError(e)) rethrow;

      await Future<void>.delayed(const Duration(milliseconds: 700));

      return _client.rpc(functionName, params: params);
    }
  }

  Future<void> _loadClubMembers() async {
    final rows = await _client
        .from('club_memberships')
        .select('''
          member_profile:member_profiles(*)
        ''')
        .eq('club_id', widget.clubId)
        .eq('is_active', true);

    final members = <Map<String, dynamic>>[];

    for (final row in rows) {
      final profile = row['member_profile'];
      if (profile is Map<String, dynamic>) {
        members.add(profile);
      }
    }

    members.sort((a, b) => _memberLabel(a).compareTo(_memberLabel(b)));

    _clubMembers = members;

    debugPrint('CLUB MEMBERS LOADED: ${_clubMembers.length}');
    for (final m in _clubMembers) {
      debugPrint('MEMBER: ${m['id']} ${_memberLabel(m)}');
    }
  }

  Map<String, dynamic>? _currentMemberProfileRow() {
    final currentId = _currentMemberId;
    if (currentId == null || currentId.isEmpty) return null;

    for (final member in _clubMembers) {
      if (member['id']?.toString() == currentId) {
        return member;
      }
    }

    return null;
  }

  String _normalisedMemberGender(Map<String, dynamic>? member) {
    if (member == null) return '';

    final raw =
        (member['gender'] ??
                member['sex'] ??
                member['member_gender'] ??
                member['playing_gender'] ??
                member['section'] ??
                '')
            .toString()
            .trim()
            .toLowerCase();

    if (raw.isEmpty) return '';

    if (raw == 'm' ||
        raw == 'male' ||
        raw == 'man' ||
        raw == 'men' ||
        raw == 'mens' ||
        raw == "men's") {
      return 'male';
    }

    if (raw == 'f' ||
        raw == 'female' ||
        raw == 'woman' ||
        raw == 'women' ||
        raw == 'ladies' ||
        raw == "ladies'" ||
        raw == 'lady') {
      return 'female';
    }

    return raw;
  }

  bool _bookerEligibleForCurrentSection() {
    final section = _section.trim().toLowerCase();

    // Open and mixed fixtures can default the creator into the first player slot.
    if (section.isEmpty || section == 'open' || section == 'mixed') {
      return true;
    }

    final gender = _normalisedMemberGender(_currentMemberProfileRow());

    // If the member record does not currently contain a gender/section field,
    // keep the existing helpful default rather than blocking the 90% case.
    if (gender.isEmpty) {
      return true;
    }

    if (section == 'mens' || section == "men's") {
      return gender == 'male';
    }

    if (section == 'ladies' || section == "ladies'") {
      return gender == 'female';
    }

    return true;
  }

  MemberPickerSectionFilter _memberPickerSectionFilterForCurrentFixture() {
    final section = _section.trim().toLowerCase();

    if (section == 'mens' || section == "men's") {
      return MemberPickerSectionFilter.mens;
    }

    if (section == 'ladies' || section == "ladies'") {
      return MemberPickerSectionFilter.ladies;
    }

    if (section == 'mixed') {
      return MemberPickerSectionFilter.mixed;
    }

    return MemberPickerSectionFilter.open;
  }

  void _defaultBookerIntoFirstPlayerSlot() {
    if (_currentMemberId == null) return;

    final key = _slotKey(1, 1);
    final currentValue = _playerSelections[key];
    final isEligible = _bookerEligibleForCurrentSection();

    if (!isEligible) {
      if (_bookerAutoPlacedInFirstPlayerSlot &&
          currentValue == _currentMemberId) {
        setState(() {
          _playerSelections.remove(key);
          _bookerAutoPlacedInFirstPlayerSlot = false;
        });
      }
      return;
    }

    if (currentValue == null || currentValue.isEmpty) {
      setState(() {
        _playerSelections[key] = _currentMemberId;
        _bookerAutoPlacedInFirstPlayerSlot = true;
      });
    }
  }

  Future<void> _pickEndDateTime() async {
    final now = DateTime.now();
    final initialDate =
        _endAtLocal ??
        _startAtLocal?.add(const Duration(hours: 2)) ??
        now.add(const Duration(hours: 2));

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );
    if (time == null) return;

    setState(() {
      _endAtLocal = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
    _loadRinkAvailability();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final initialDate = _startAtLocal ?? now;

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );
    if (time == null) return;

    setState(() {
      _startAtLocal = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );

      // Default end time to start + 2 hours if not set yet,
      // or if end is not after the new start.
      if (_endAtLocal == null || !_endAtLocal!.isAfter(_startAtLocal!)) {
        _endAtLocal = _startAtLocal!.add(const Duration(hours: 2));
      }
    });
    _loadRinkAvailability();
  }

  String _formatForDisplay(int ppr) {
    switch (ppr) {
      case 1:
        return 'Singles (1)';
      case 2:
        return 'Pairs (2)';
      case 3:
        return 'Triples (3)';
      case 4:
        return 'Fours (4)';
      default:
        return '$ppr per rink';
    }
  }

  String _formatCodeForRinks(int playersPerRink) {
    switch (playersPerRink) {
      case 1:
        return 'singles';
      case 2:
        return 'pairs';
      case 3:
        return 'triples';
      case 4:
        return 'rinks';
      default:
        throw ArgumentError('Invalid playersPerRink: $playersPerRink');
    }
  }

  String _prettyOrientation(String v) {
    // north_south -> north_South
    final t = v.replaceAll('_', ' ');
    return t[0].toUpperCase() + t.substring(1);
  }

  String _friendlySaveError(PostgrestException e) {
    if (e.message.contains('Not enough rinks available')) {
      return 'Not enough rinks are available at that time. Please choose another time, date, or green.';
    }

    return e.message;
  }

  String _slotKey(int teamNo, int slotNo) => '$teamNo:$slotNo';

  int _playersForFormat(String format) {
    switch (format) {
      case 'singles':
        return 1;
      case 'pairs':
      case 'aussie_pairs':
        return 2;
      case 'triples':
        return 3;
      case 'fours':
      case 'rinks':
        return 4;
      default:
        return _playersPerRink;
    }
  }

  bool _hasDraftAssignmentsOutside(int rinks, int playersPerRink) {
    for (var teamNo = 1; teamNo <= _rinksRequired; teamNo++) {
      final rinkWillBeRemoved = teamNo > rinks;
      if (rinkWillBeRemoved &&
          ((_selectedHomeRinkByTeam[teamNo]?.isNotEmpty ?? false) ||
              (_markerSelections[_slotKey(teamNo, 1)]?.isNotEmpty ?? false) ||
              _markerRequiredByTeam[teamNo] == true ||
              _markerRequestByTeam[teamNo] == true)) {
        return true;
      }

      for (var playerNo = 1; playerNo <= _playersPerRink; playerNo++) {
        if (!rinkWillBeRemoved && playerNo <= playersPerRink) continue;
        final key = _slotKey(teamNo, playerNo);
        if ((_playerSelections[key]?.isNotEmpty ?? false) ||
            (_opponentSelections[key]?.isNotEmpty ?? false) ||
            (_opponentExternalNames[key]?.trim().isNotEmpty ?? false)) {
          return true;
        }
      }
    }
    return false;
  }

  void _clearDraftAssignmentsOutside(int rinks, int playersPerRink) {
    for (var teamNo = 1; teamNo <= _rinksRequired; teamNo++) {
      final rinkWillBeRemoved = teamNo > rinks;
      if (rinkWillBeRemoved) {
        _selectedHomeRinkByTeam.remove(teamNo);
        _markerSelections.remove(_slotKey(teamNo, 1));
        _markerRequiredByTeam.remove(teamNo);
        _markerRequestByTeam.remove(teamNo);
      }

      for (var playerNo = 1; playerNo <= _playersPerRink; playerNo++) {
        if (!rinkWillBeRemoved && playerNo <= playersPerRink) continue;
        final key = _slotKey(teamNo, playerNo);
        _playerSelections.remove(key);
        _opponentSelections.remove(key);
        _opponentExternalNames.remove(key);
      }
    }
  }

  Future<bool> _confirmStructuralOverride(int rinks, int playersPerRink) async {
    if (!_hasDraftAssignmentsOutside(rinks, playersPerRink)) return true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change playing format?'),
        content: const Text(
          'This change will remove draft rink, player, opponent, or marker '
          'assignments that no longer fit. No saved fixture data is affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    return confirmed == true;
  }

  Future<void> _resetPlayingDefaults() async {
    final row = _fixtureTypeById(_fixtureTypeId);
    if (row == null || row['uses_rinks'] != true) return;

    final defaultRinks = row['default_rinks_required'] as int? ?? 1;
    final rawFormat = (row['default_format'] ?? '').toString().toLowerCase();
    final defaultPlayers = row['default_players_per_rink'] as int? ?? 4;
    final defaultFormat = rawFormat.isEmpty
        ? _formatCodeForRinks(defaultPlayers)
        : (rawFormat == 'fours' ? 'rinks' : rawFormat);
    final players = _playersForFormat(defaultFormat);

    if (!await _confirmStructuralOverride(defaultRinks, players) || !mounted) {
      return;
    }
    if (!await _canAcceptRinksRequiredChange(defaultRinks) || !mounted) {
      await _showInsufficientRinksDialog();
      return;
    }

    setState(() {
      _clearDraftAssignmentsOutside(defaultRinks, players);
      _section = (row['section'] ?? 'open').toString();
      _format = defaultFormat;
      _playersPerRink = players;
      _rinksRequired = defaultRinks;
      _dressCode = (row['dress_code'] ?? 'open').toString();
      _rinksRequiredFieldVersion++;
    });
    _defaultBookerIntoFirstPlayerSlot();
    _markDirty();
    await _loadRinkAvailability();
  }

  Future<void> _showSaveErrorDialog(String message) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Booking could not be saved'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _validateInitialRinkBookingLimits() {
    final initialBooking = widget.initialRinkBooking;

    if (initialBooking == null) return;
    if (_startAtLocal == null || _endAtLocal == null) return;

    final sameInitialDate =
        _startAtLocal!.year == initialBooking.startAt.year &&
        _startAtLocal!.month == initialBooking.startAt.month &&
        _startAtLocal!.day == initialBooking.startAt.day;

    if (!sameInitialDate) {
      return;
    }

    if (_endAtLocal!.isAfter(initialBooking.latestEndAt)) {
      throw Exception(
        'This booking must finish by ${formatClubDateTime(initialBooking.latestEndAt)}.',
      );
    }
  }

  Future<void> _save() async {
    if (_loading) {
      debugPrint('SAVE: ignored because already loading');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_fixtureTypeId == null || _fixtureTypeId!.trim().isEmpty) {
        throw Exception('Please choose a Fixture Type.');
      }
      if (_section.trim().isEmpty) {
        throw Exception('Section is missing for the selected Fixture Type.');
      }
      if (_startAtLocal == null) {
        throw Exception('Please select a start date/time.');
      }
      if (_endAtLocal == null) {
        throw Exception('Please select an end date/time.');
      }
      if (!_endAtLocal!.isAfter(_startAtLocal!)) {
        throw Exception('The end time must be after the start time.');
      }

      final selectedFixtureType = _fixtureTypeById(_fixtureTypeId);
      final isInternalFixtureType = selectedFixtureType?['is_internal'] == true;
      final usesRinks = selectedFixtureType?['uses_rinks'] == true;

      if (!usesRinks) {
        if (_teamNameCtrl.text.trim().isEmpty) {
          throw Exception('Please enter an event name.');
        }
        if (_eventVenueId == null || _eventVenueId!.trim().isEmpty) {
          throw Exception('Please select a venue.');
        }
        if (_eventOrganiserMemberProfileId == null ||
            _eventOrganiserMemberProfileId!.trim().isEmpty) {
          throw Exception('Please select an organiser.');
        }
        if (_eventOrganiserMemberProfileId ==
            _eventViceOrganiserMemberProfileId) {
          throw Exception(
            'The organiser and deputy organiser must be different members.',
          );
        }
      } else {
        if (_homeVenueId == null) {
          throw Exception('Please select a home venue.');
        }

        if (!isInternalFixtureType && !_isHome && _opponentVenueId == null) {
          throw Exception('Please select an opponent venue.');
        }

        if (_isHome && _greenAreaId == null) {
          throw Exception('Please select a green area.');
        }
      }

      // Decide what goes into fixtures.venue_id and fixtures.opponent_venue_id.
      //
      // IMPORTANT (to satisfy your DB check "Green area does not belong to venue"):
      // - For HOME fixtures, venue_id must be the HOME venue (so green_area.venue_id matches fixtures.venue_id).
      // - For AWAY fixtures, venue_id should be the OPPONENT venue (the venue you travel to).
      //
      final String venueId = !usesRinks
          ? _eventVenueId!
          : (_isHome ? _homeVenueId! : _opponentVenueId!);

      final String? opponentVenueId = !usesRinks
          ? null
          : (isInternalFixtureType
                ? null
                : (_isHome ? _opponentVenueId : _homeVenueId));

      final fixtureLabel = _isTeamFixture
          ? (_selectedTeamName() ?? '')
          : _teamNameCtrl.text.trim();

      debugPrint('CREATE FIXTURE isTeamFixture=$_isTeamFixture');

      if (_isTeamFixture && _teamId == null) {
        throw Exception('Please select a team.');
      }

      final captainMemberProfileId = _isEventStyleFixture
          ? _eventOrganiserMemberProfileId
          : (_simpleBookingMode ? _currentMemberId : null);

      final viceCaptainMemberProfileId = _isEventStyleFixture
          ? _eventViceOrganiserMemberProfileId
          : null;

      debugPrint(
        'CREATE FIXTURE captainMemberProfileId=$captainMemberProfileId',
      );
      debugPrint('CREATE FIXTURE currentMemberId=$_currentMemberId');
      debugPrint('CREATE FIXTURE canSeeAll=$_canSeeAllFixtureTypes');

      _validateInitialRinkBookingLimits();

      final homeRinkLabels = <Map<String, dynamic>>[];
      final rinkAssignments = <Map<String, dynamic>>[];
      final selectedMemberRoles = <String, String>{};

      if (usesRinks) {
        for (var teamNo = 1; teamNo <= _rinksRequired; teamNo++) {
          final homeRinkLabel = _selectedHomeRinkByTeam[teamNo];

          if (homeRinkLabel != null && homeRinkLabel.isNotEmpty) {
            homeRinkLabels.add({
              'team_no': teamNo,
              'home_rink_label': homeRinkLabel,
            });
          }

          if (_isPreselectFixture) {
            for (var playerNo = 1; playerNo <= _playersPerRink; playerNo++) {
              final key = _slotKey(teamNo, playerNo);

              final playerId = _playerSelections[key];
              if (playerId != null && playerId.isNotEmpty) {
                rinkAssignments.add({
                  'team_no': teamNo,
                  'member_profile_id': playerId,
                  'position': playerNo,
                });
                selectedMemberRoles[playerId] = 'player';
              }

              final opponentId = _opponentSelections[key];
              final externalOpponentName =
                  _opponentExternalNames[key]?.trim() ?? '';

              if (opponentId != null && opponentId.isNotEmpty) {
                rinkAssignments.add({
                  'team_no': teamNo,
                  'member_profile_id': opponentId,
                  'position': 100 + playerNo,
                });
                selectedMemberRoles[opponentId] = 'opponent';
              } else if (externalOpponentName.isNotEmpty) {
                rinkAssignments.add({
                  'team_no': teamNo,
                  'display_name': externalOpponentName,
                  'position': 100 + playerNo,
                });
              }
            }

            final markerKey = _slotKey(teamNo, 1);
            final markerId = _markerSelections[markerKey];
            final markerRequired = _markerRequiredForTeam(teamNo);
            final requestMarker = markerId == null || markerId.isEmpty
                ? _markerRequestByTeam[teamNo] == true
                : false;

            if (markerId != null && markerId.isNotEmpty) {
              rinkAssignments.add({
                'team_no': teamNo,
                'member_profile_id': markerId,
                'position': 201,
                'marker_required': true,
                'request_marker': false,
              });
              selectedMemberRoles[markerId] = 'marker';
            } else if (markerRequired || requestMarker) {
              rinkAssignments.add({
                'team_no': teamNo,
                'position': 201,
                'marker_required': markerRequired,
                'request_marker': requestMarker,
              });
            }
          }
        }
      }

      final teamSelectionMembers = selectedMemberRoles.entries.map((entry) {
        final memberId = entry.key;
        final role = entry.value;
        final isBooker = memberId == captainMemberProfileId;

        return {
          'member_profile_id': memberId,
          'role': role,
          'acceptance': isBooker ? 'accepted' : 'pending',
          'is_selected': true,
        };
      }).toList();

      final fixtureId = await _createFixtureWithSetupRpc(
        startAtLocal: _startAtLocal!,
        endAtLocal: _endAtLocal!,
        isHome: _isHome,
        venueId: venueId,
        opponentVenueId: opponentVenueId,
        usesRinks: usesRinks,
        greenAreaId: _greenAreaId,
        orientation:
            (usesRinks &&
                _isHome &&
                _isOutdoorSelectedGreen &&
                _orientationEnabledForSelectedGreen)
            ? _orientation
            : null,
        fixtureLabel: fixtureLabel,
        captainMemberProfileId: captainMemberProfileId,
        viceCaptainMemberProfileId: viceCaptainMemberProfileId,
        createTeamSelection: _isPreselectFixture,
        homeRinkLabels: homeRinkLabels,
        rinkAssignments: rinkAssignments,
        teamSelectionMembers: teamSelectionMembers,
      );

      // The fixture and all Pre-Select assignments have now been created.
      // Use the same reconciliation process as the Communications Control
      // Centre so that every expected communication record is prepared.
      final communicationsWarnings = <String>[];

      if (usesRinks && _isPreselectFixture) {
        try {
          debugPrint(
            'CREATE FIXTURE COMMUNICATIONS: '
            'reconciling fixture $fixtureId',
          );

          final rawCommunicationsResult = await _client.rpc(
            'repair_preselect_communications',
            params: {'p_fixture_id': fixtureId},
          );

          debugPrint(
            'CREATE FIXTURE COMMUNICATIONS reconciliation result='
            '$rawCommunicationsResult',
          );

          final attachmentResult = await FixtureCommunicationsService(
            _client,
          ).rebuildTeamSheetAttachmentForFixture(fixtureId: fixtureId);

          debugPrint(
            'CREATE FIXTURE COMMUNICATIONS: revision '
            '${attachmentResult.compositionVersion} attached to '
            '${attachmentResult.notificationRowsUpdated} queued row(s) and '
            '${attachmentResult.emailRowsUpdated} unsent email row(s)',
          );

          // Notification processing is handled centrally by the queue processor.
          // Do not drain the global notification queue from fixture creation.
          debugPrint(
            'CREATE FIXTURE COMMUNICATIONS: '
            'notifications queued for central processing',
          );
        } catch (e, stackTrace) {
          debugPrint(
            'CREATE FIXTURE: fixture $fixtureId was saved, '
            'but communications preparation failed: $e',
          );

          debugPrintStack(stackTrace: stackTrace);

          communicationsWarnings.add(
            'The fixture was created, but its communications could not be '
            'prepared completely. They can be checked and repaired in the '
            'Communications Control Centre.',
          );
        }
      }

      debugPrint('SAVE: pop');

      if (!mounted) return;

      if (communicationsWarnings.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Fixture created'),
            content: Text(communicationsWarnings.join('\n\n')),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Continue'),
              ),
            ],
          ),
        );

        if (!mounted) return;
      }

      debugPrint(
        'create_fixture_page: created fixtureId=$fixtureId, '
        'opening fixture details...',
      );

      if (!mounted) return;

      // The fixture is now safely created, so the Create page is no longer dirty.
      // Also leave the page in its normal, non-loading state while the Details
      // page is displayed above it.
      setState(() {
        _loading = false;
        _error = null;
        _hasUnsavedChanges = false;
      });

      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => FixtureDetailsPage(fixtureId: fixtureId),
        ),
      );

      // When FixtureDetailsPage is eventually closed, close CreateFixturePage
      // and tell the calling fixture-list screen that its data must be refreshed.
      if (!mounted) return;

      Navigator.of(context).pop(true);
      return;
    } on PostgrestException catch (e) {
      final message = e.message.contains('Not enough rinks available')
          ? 'Not enough rinks are available at that time. Please choose another time, date, or green.'
          : (e.message.isNotEmpty ? e.message : 'Database error');

      if (mounted) {
        setState(() {
          _loading = false;
          _error = null;
        });
      }

      await _showSaveErrorDialog(message);
    } catch (e) {
      final message = e.toString();

      if (mounted) {
        setState(() {
          _loading = false;
          _error = null;
        });
      }

      await _showSaveErrorDialog(message);
    }
  }

  Map<String, dynamic>? _fixtureTypeById(String? id) {
    if (id == null) return null;

    for (final ft in _fixtureTypes) {
      if (ft['id'].toString() == id) return ft;
    }
    return null;
  }

  Widget _buildMemberBookingInlineSection() {
    final playersPerSide = _playersPerRink;

    return Card(
      margin: const EdgeInsets.only(top: 8, bottom: 20),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Players, opponents and rinks',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            const SizedBox(height: 12),

            for (var teamNo = 1; teamNo <= _rinksRequired; teamNo++) ...[
              Text(
                'Team $teamNo',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),

              for (
                var playerNo = 1;
                playerNo <= playersPerSide;
                playerNo++
              ) ...[
                Row(
                  children: [
                    SizedBox(width: 80, child: Text('Player $playerNo')),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await pickFixtureSlotMember(
                            context: context,
                            clubId: widget.clubId,
                            title: 'Select Player $playerNo',
                            bucket: 'player',
                            key: _slotKey(teamNo, playerNo),
                            selections: _playerSelections,
                            fixtureId: null,
                            useFixtureSection: true,
                            initialSectionFilter:
                                _memberPickerSectionFilterForCurrentFixture(),
                            showError: _showSaveErrorDialog,
                            memberAlreadySelectedElsewhere:
                                _memberAlreadySelectedElsewhere,
                          );

                          if (mounted) setState(() {});
                        },
                        child: Text(
                          _selectedMemberLabel(
                            _playerSelections[_slotKey(teamNo, playerNo)],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(width: 90, child: Text('Opponent $playerNo')),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _chooseOpponentForSlot(
                          teamNo: teamNo,
                          playerNo: playerNo,
                        ),
                        child: Text(
                          _selectedOpponentLabel(_slotKey(teamNo, playerNo)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],

              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Marker required'),
                subtitle: const Text('Set independently for this rink/team.'),
                value: _markerRequiredForTeam(teamNo),
                onChanged: (value) => _setMarkerRequiredForTeam(teamNo, value),
              ),

              if (_markerRequiredForTeam(teamNo)) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _pickMarkerForTeam(teamNo),
                      icon: const Icon(Icons.person_search),
                      label: Text(
                        _markerSelections[_slotKey(teamNo, 1)]?.isNotEmpty ==
                                true
                            ? _selectedMemberLabel(
                                _markerSelections[_slotKey(teamNo, 1)],
                              )
                            : 'Select named marker',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _toggleMarkerRequestForTeam(teamNo),
                      icon: Icon(
                        _markerRequestByTeam[teamNo] == true
                            ? Icons.campaign
                            : Icons.campaign_outlined,
                      ),
                      label: Text(
                        _markerRequestByTeam[teamNo] == true
                            ? 'Marker request selected'
                            : 'Ask for a marker',
                      ),
                    ),
                    if (_markerSelections[_slotKey(teamNo, 1)]?.isNotEmpty ==
                        true)
                      TextButton.icon(
                        onPressed: () => _clearNamedMarkerForTeam(teamNo),
                        icon: const Icon(Icons.clear),
                        label: const Text('Clear marker'),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _markerRequestByTeam[teamNo] == true
                      ? 'An open marker request will be created for this rink.'
                      : (_markerSelections[_slotKey(teamNo, 1)]?.isNotEmpty ==
                                true
                            ? 'A named marker is assigned to this rink.'
                            : 'A marker is required, but no request will be sent yet.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const Divider(height: 28),
            ],

            _buildGreenAndRinkAvailabilityBlock(),
          ],
        ),
      ),
    );
  }

  Widget _buildGreenAndRinkAvailabilityBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _selectedGreenName?.isNotEmpty == true
              ? 'Rinks — $_selectedGreenName'
              : 'Rinks',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 8),
        _buildRinkAvailabilitySection(),
      ],
    );
  }

  Widget _buildRinkAvailabilitySection() {
    if (_greenAreaId == null || _startAtLocal == null || _endAtLocal == null) {
      return const Text(
        'Choose green, start time and end time to see rink availability.',
        textAlign: TextAlign.center,
      );
    }

    if (_loadingRinkAvailability) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_rinkAvailabilityError != null) {
      return Text(
        'Could not load rink availability: $_rinkAvailabilityError',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.red),
      );
    }

    if (_rinkAvailability.isEmpty) {
      return const Text(
        'No physical rinks found for this green.',
        textAlign: TextAlign.center,
      );
    }

    int asInt(dynamic v, int fallback) {
      if (v is int) return v;
      return int.tryParse((v ?? '').toString()) ?? fallback;
    }

    final first = _rinkAvailability.first;

    final totalRinks = asInt(first['total_rinks'], _rinkAvailability.length);
    final freeRinks = asInt(first['free_capacity_rinks'], totalRinks);
    final enoughRinks = freeRinks >= _rinksRequired;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: enoughRinks ? Colors.green.shade50 : Colors.red.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: enoughRinks ? Colors.green.shade300 : Colors.red.shade300,
            ),
          ),
          child: Text(
            '$freeRinks of $totalRinks rinks free',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: enoughRinks ? Colors.green.shade900 : Colors.red.shade900,
            ),
          ),
        ),

        Column(
          children: _rinkAvailability.map((r) {
            final rinkLabel = (r['rink_label'] ?? r['label'] ?? r['name'] ?? '')
                .toString();
            final isBooked = r['is_booked'] == true;
            final bookedText = (r['booked_text'] ?? '').toString();

            final selectedTeamNo = _teamNoForSelectedRink(rinkLabel);
            final isSelected = selectedTeamNo != null;

            final bgHex = (r['background_hex'] ?? '#FEE2E2').toString();
            final fgHex = (r['foreground_hex'] ?? '#991B1B').toString();

            final bookedBgColor = _colourFromHex(bgHex);
            final bookedFgColor = _colourFromHex(fgHex);

            final selectedBookedLabel =
                (_selectedBookedRink?['rink_label'] ??
                        _selectedBookedRink?['label'] ??
                        _selectedBookedRink?['name'] ??
                        '')
                    .toString();

            final isSelectedBooked =
                isBooked && selectedBookedLabel == rinkLabel;

            return InkWell(
              onTap: () => _handleRinkTap(r),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isSelectedBooked
                      ? Colors.amber.shade100
                      : isBooked
                      ? bookedBgColor
                      : isSelected
                      ? _selectedFixtureBgColor
                      : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    width: (isSelected || isSelectedBooked) ? 2 : 1,
                    color: isSelectedBooked
                        ? Colors.orange.shade700
                        : isBooked
                        ? bookedFgColor.withOpacity(0.35)
                        : isSelected
                        ? _selectedFixtureBgColor
                        : Colors.green.shade300,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            rinkLabel.isEmpty ? 'Rink' : rinkLabel,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: isSelectedBooked
                                  ? Colors.orange.shade900
                                  : isBooked
                                  ? bookedFgColor
                                  : isSelected
                                  ? _selectedFixtureFgColor
                                  : Colors.green.shade900,
                            ),
                          ),
                        ),
                        if (isSelectedBooked)
                          Icon(
                            Icons.swap_horiz,
                            size: 18,
                            color: Colors.orange.shade900,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isBooked
                          ? isSelectedBooked
                                ? 'Selected booking — tap a free rink to move it, or another booked rink to swap'
                                : bookedText
                          : isSelected
                          ? 'Selected for Team $selectedTeamNo'
                          : _selectedBookedRink != null
                          ? 'Free — tap to move selected booking here'
                          : 'Free',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isSelectedBooked
                            ? Colors.orange.shade900
                            : isBooked
                            ? bookedFgColor
                            : isSelected
                            ? _selectedFixtureFgColor
                            : Colors.green.shade900,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _fixtureTypeSwatch(Map<String, dynamic> ft) {
    final colourScheme = ft['colour_scheme'] as Map<String, dynamic>?;
    final hasColours = colourScheme != null;

    final bg = hasColours
        ? colorFromHex(
            colourScheme['background_hex']?.toString(),
            fallback: Colors.grey.shade200,
          )
        : Colors.grey.shade100;

    final fg = hasColours
        ? colorFromHex(
            colourScheme['foreground_hex']?.toString(),
            fallback: Colors.black87,
          )
        : Colors.black87;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fg.withOpacity(0.20)),
      ),
      child: Text(
        ft['name']?.toString() ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 16),
      ),
    );
  }

  Widget _selectedFixtureTypeField() {
    final selected = _fixtureTypeById(_fixtureTypeId);

    if (selected == null) {
      return InkWell(
        onTap: _pickFixtureType,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Fixture Type',
            border: OutlineInputBorder(),
          ),
          child: const Text('Select Fixture Type'),
        ),
      );
    }

    final colourScheme = selected['colour_scheme'] as Map<String, dynamic>?;
    final hasColours = colourScheme != null;

    final bg = hasColours
        ? colorFromHex(
            colourScheme['background_hex']?.toString(),
            fallback: Colors.grey.shade200,
          )
        : Colors.grey.shade100;

    final fg = hasColours
        ? colorFromHex(
            colourScheme['foreground_hex']?.toString(),
            fallback: Colors.black87,
          )
        : Colors.black87;

    return InkWell(
      onTap: _pickFixtureType,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Fixture Type',
          border: OutlineInputBorder(),
        ),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 56),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: fg.withOpacity(0.20)),
          ),
          child: Text(
            selected['name']?.toString() ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w600,
              fontSize: 18,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _fixtureTypeSelectedSwatch(Map<String, dynamic> ft) {
    final colourScheme = ft['colour_scheme'] as Map<String, dynamic>?;
    final hasColours = colourScheme != null;

    final bg = hasColours
        ? colorFromHex(
            colourScheme['background_hex']?.toString(),
            fallback: Colors.grey.shade200,
          )
        : Colors.transparent;

    final fg = hasColours
        ? colorFromHex(
            colourScheme['foreground_hex']?.toString(),
            fallback: Colors.black87,
          )
        : Colors.black87;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: double.infinity,
          height: constraints.maxHeight,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: hasColours ? bg : null,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasColours ? fg.withOpacity(0.25) : Colors.black12,
            ),
          ),
          child: Text(
            ft['name']?.toString() ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w600,
              fontSize: 18,
              height: 1.2,
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickFixtureType() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.70,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Select Fixture Type',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _fixtureTypes.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final ft = _fixtureTypes[i];
                        final id = ft['id'].toString();

                        return InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.pop(sheetContext, id),
                          child: _fixtureTypeSwatch(ft),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (selected == null) return;
    final selectedType = _fixtureTypeById(selected);
    if (selectedType != null) {
      final usesRinks = selectedType['uses_rinks'] == true;
      final targetRinks = usesRinks
          ? (selectedType['default_rinks_required'] as int? ?? 1)
          : 0;
      final rawFormat = (selectedType['default_format'] ?? '')
          .toString()
          .toLowerCase();
      final targetPlayers = usesRinks
          ? (rawFormat.isEmpty
                ? (selectedType['default_players_per_rink'] as int? ?? 4)
                : _playersForFormat(rawFormat))
          : 1;

      if (!await _confirmStructuralOverride(targetRinks, targetPlayers) ||
          !mounted) {
        return;
      }
      setState(() {
        _clearDraftAssignmentsOutside(targetRinks, targetPlayers);
      });
    }
    _applyFixtureType(selected);
  }

  Future<void> _showRepeatCreationResults(
    List<RepeatFixtureCreationResult> results,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Repeat fixture results'),
          content: SizedBox(
            width: 520,
            child: ListView(
              shrinkWrap: true,
              children: results.map((r) {
                final dateText = MaterialLocalizations.of(
                  context,
                ).formatFullDate(r.date);

                return ListTile(
                  leading: Icon(
                    r.success ? Icons.check_circle : Icons.error,
                    color: r.success ? Colors.green : Colors.red,
                  ),
                  title: Text(dateText),
                  subtitle: Text(r.message),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final startLabel = _startAtLocal == null
        ? 'Start Date & Time'
        : formatClubDateTime(_startAtLocal!);

    final endLabel = _endAtLocal == null
        ? 'End Date & Time'
        : formatClubDateTime(_endAtLocal!);

    final selectedGreen = _selectedGreenArea;
    final allowedOrients = selectedGreen == null
        ? <String>[]
        : _allowedOrientationsFor(selectedGreen);

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;

        if (!_hasUnsavedChanges) {
          Navigator.pop(context);
          return;
        }

        final discard = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Discard changes?'),
              content: const Text(
                'You have unsaved fixture changes. Discard them?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Discard'),
                ),
              ],
            );
          },
        );

        if (discard == true && mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isEventStyleFixture
                ? 'Create Event'
                : (_simpleBookingMode ? 'Book Fixture' : 'Create Fixture'),
          ),
        ),

        floatingActionButton: _hasUnsavedChanges
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_canUseRepeat) ...[
                    FloatingActionButton.extended(
                      heroTag: 'repeat_fixture',
                      onPressed: _loading ? null : _openRepeatPlanner,
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      icon: const Icon(Icons.repeat),
                      label: const Text('Repeat'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  FloatingActionButton.extended(
                    heroTag: 'save_fixture',
                    onPressed: _loading ? null : _save,
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: const Text('Save'),
                  ),
                ],
              )
            : null,

        body: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.16,
                child: Image.asset(
                  _backgroundImageForWidth(context),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            _loading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_error != null) ...[
                          Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                          const SizedBox(height: 12),
                        ],

                        const Text(
                          'Fixture Type',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        _selectedFixtureTypeField(),
                        const SizedBox(height: 12),

                        if (_isPreselectFixture && !_isEventStyleFixture) ...[
                          TextField(
                            controller: _teamNameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Fixture label',
                              hintText:
                                  'e.g. Club Championship Semi-final or Mixed Singles',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        if (!_simpleBookingMode && !_isEventStyleFixture) ...[
                          const Text(
                            'Location',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),

                          if (_fixtureTypeById(
                                _fixtureTypeId,
                              )?['is_internal'] ==
                              true) ...[
                            InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Location',
                                border: OutlineInputBorder(),
                              ),
                              child: const Text('Home'),
                            ),
                          ] else ...[
                            SegmentedButton<FixtureLocationType>(
                              segments: const [
                                ButtonSegment(
                                  value: FixtureLocationType.home,
                                  label: Text('Home'),
                                  icon: Icon(Icons.home),
                                ),
                                ButtonSegment(
                                  value: FixtureLocationType.away,
                                  label: Text('Away'),
                                  icon: Icon(Icons.directions_bus),
                                ),
                              ],
                              selected: {_fixtureLocation},
                              onSelectionChanged: (newSelection) async {
                                final v = newSelection.first;
                                setState(() {
                                  _fixtureLocation = v;
                                  _isHome = v == FixtureLocationType.home;
                                  _greenAreas = [];
                                  _greenAreaId = null;
                                  _orientation = null;
                                });
                                _markDirty();
                                await _loadGreenAreas();
                              },
                            ),
                          ],
                          const SizedBox(height: 12),
                        ],

                        if (_isTeamFixture &&
                            !_simpleBookingMode &&
                            !_isEventStyleFixture) ...[
                          DropdownButtonFormField<String>(
                            value: _teamId,
                            decoration: const InputDecoration(
                              labelText: 'Team',
                              border: OutlineInputBorder(),
                            ),
                            items: _teams.map((team) {
                              return DropdownMenuItem<String>(
                                value: team['id'].toString(),
                                child: Text((team['name'] ?? '').toString()),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                _teamId = value;

                                final selectedTeam = _teams.firstWhere(
                                  (t) => t['id'].toString() == value,
                                  orElse: () => <String, dynamic>{},
                                );

                                final selectedTeamName =
                                    (selectedTeam['name'] ?? '')
                                        .toString()
                                        .trim();

                                if (selectedTeamName.isNotEmpty) {
                                  _teamNameCtrl.text = selectedTeamName;
                                }
                              });
                              _markDirty();
                            },
                          ),
                          const SizedBox(height: 12),
                        ],

                        if (_isEventStyleFixture) ...[
                          TextField(
                            controller: _teamNameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Event name',
                              hintText: 'e.g. AGM, Summer Barbecue, Quiz Night',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],

                        if (_currentRinkBookingIsShort &&
                            _currentRinkBookingDuration != null &&
                            widget.initialRinkBooking != null)
                          _ShortRinkBookingWarning(
                            availableDuration: _currentRinkBookingDuration!,
                            latestEndAt: widget.initialRinkBooking!.latestEndAt,
                          ),

                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Start'),
                                  const SizedBox(height: 6),
                                  OutlinedButton(
                                    onPressed: _pickDateTime,
                                    child: Text(startLabel),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('End'),
                                  const SizedBox(height: 6),
                                  OutlinedButton(
                                    onPressed: _pickEndDateTime,
                                    child: Text(endLabel),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        if (_isEventStyleFixture) ...[
                          InkWell(
                            onTap: () async {
                              final selected = await _pickVenue(
                                getVenues: () => _allVenues,
                                title: 'Select Venue',
                                creationType: VenueCreationType.external,
                              );

                              if (selected != null) {
                                setState(() => _eventVenueId = selected);
                                _markDirty();
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Venue',
                                border: OutlineInputBorder(),
                              ),
                              child: Text(
                                _allVenues
                                        .firstWhere(
                                          (v) =>
                                              v['id'].toString() ==
                                              _eventVenueId,
                                          orElse: () => {
                                            'name': 'Select venue',
                                          },
                                        )['name']
                                        ?.toString() ??
                                    'Select venue',
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.how_to_reg_outlined),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Members will be able to respond Yes, No or Maybe. '
                                    'The organiser can use these responses to monitor attendance numbers.',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          _buildEventOrganisersSection(),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _notesCtrl,
                            minLines: 3,
                            maxLines: 8,
                            decoration: const InputDecoration(
                              labelText: 'Information',
                              alignLabelWithHint: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        if (!_simpleBookingMode && !_isEventStyleFixture) ...[
                          const SizedBox(height: 8),

                          if (_isPreselectFixture) ...[
                            InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Pre-Selection mode',
                                border: OutlineInputBorder(),
                              ),
                              child: const Text('Pre-Select'),
                            ),
                          ] else ...[
                            SegmentedButton<FixtureWorkflowType>(
                              segments: const [
                                ButtonSegment(
                                  value: FixtureWorkflowType.rsvp,
                                  label: Text('RSVP'),
                                  icon: Icon(Icons.how_to_reg),
                                ),
                                ButtonSegment(
                                  value: FixtureWorkflowType.team,
                                  label: Text('Team'),
                                  icon: Icon(Icons.groups),
                                ),
                              ],

                              selected: {_workflowType},
                              onSelectionChanged: _workflowLockedByFixtureType
                                  ? null
                                  : (newSelection) {
                                      final v = newSelection.first;
                                      setState(() {
                                        _workflowType = v;
                                        _isTeamFixture =
                                            v == FixtureWorkflowType.team;
                                        _isPreselectFixture = false;

                                        if (_isTeamFixture) {
                                          _teamId ??= _teams.isNotEmpty
                                              ? _teams.first['id'].toString()
                                              : null;
                                        } else {
                                          _teamId = null;
                                        }
                                      });
                                      _markDirty();
                                    },
                            ),
                          ],

                          const SizedBox(height: 8),
                        ],

                        if (!_isTeamFixture &&
                            !_isPreselectFixture &&
                            !_simpleBookingMode &&
                            !_isEventStyleFixture) ...[
                          TextField(
                            controller: _teamNameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Fixture label (optional)',
                              hintText: 'e.g. Mid-week National Team Selection',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        if (!_isEventStyleFixture &&
                            (!_simpleBookingMode ||
                                _homeVenues.length > 1)) ...[
                          InkWell(
                            onTap: () async {
                              final selected = await _pickVenue(
                                getVenues: () => _homeVenues,
                                title: 'Select home venue',
                                creationType: VenueCreationType.home,
                              );

                              if (selected != null) {
                                setState(() {
                                  _homeVenueId = selected;
                                  _greenAreas = [];
                                  _greenAreaId = null;
                                  _orientation = null;
                                });
                                _markDirty();
                                await _loadGreenAreas();
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Home venue',
                                border: OutlineInputBorder(),
                              ),
                              child: Text(
                                _homeVenues
                                        .firstWhere(
                                          (v) =>
                                              v['id'].toString() ==
                                              _homeVenueId,
                                          orElse: () => {
                                            'name': 'Select venue',
                                          },
                                        )['name']
                                        ?.toString() ??
                                    'Select venue',
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),
                        ],

                        if (!_simpleBookingMode &&
                            !_isEventStyleFixture &&
                            _fixtureTypeById(_fixtureTypeId)?['is_internal'] !=
                                true) ...[
                          InkWell(
                            onTap: () async {
                              final selected = await _pickVenue(
                                getVenues: () => _opponentVenues,
                                title: 'Select opponent',
                                creationType: VenueCreationType.external,
                              );

                              if (selected != null) {
                                setState(() {
                                  _opponentVenueId = selected == '__TBC__'
                                      ? null
                                      : selected;
                                });
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Opponent Club',
                                border: OutlineInputBorder(),
                              ),
                              child: Text(
                                _opponentVenues
                                        .firstWhere(
                                          (v) =>
                                              v['id'].toString() ==
                                              _opponentVenueId,
                                          orElse: () => {'name': 'Select Club'},
                                        )['name']
                                        ?.toString() ??
                                    'Select Club',
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        if (!_isEventStyleFixture &&
                            _isHome &&
                            (!_simpleBookingMode ||
                                _greenAreas.length > 1)) ...[
                          if (_greenAreas.isEmpty) ...[
                            const InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'Green area',
                                border: OutlineInputBorder(),
                              ),
                              child: Text('No greens available for this venue'),
                            ),
                            const SizedBox(height: 12),
                          ] else ...[
                            DropdownButtonFormField<String>(
                              value: _greenAreaId,
                              decoration: const InputDecoration(
                                labelText: 'Green area',
                                border: OutlineInputBorder(),
                              ),
                              items: _greenAreas.map((g) {
                                return DropdownMenuItem(
                                  value: g['id'].toString(),
                                  child: Text(g['name'].toString()),
                                );
                              }).toList(),
                              onChanged: (v) {
                                final previousGreenAreaId = _greenAreaId;

                                setState(() {
                                  _greenAreaId = v;

                                  if (previousGreenAreaId != v) {
                                    _selectedHomeRinkByTeam.clear();
                                    _selectedBookedRink = null;
                                    _shownInsufficientRinksWarning = false;
                                    _rinksRequiredFieldVersion++;
                                  }

                                  _syncOrientationToSelectedGreen();
                                });

                                _markDirty();
                                _loadRinkAvailability();
                              },
                            ),
                            const SizedBox(height: 12),
                          ],
                        ],

                        if (!_isEventStyleFixture &&
                            _isHome &&
                            _isOutdoorSelectedGreen &&
                            _orientationEnabledForSelectedGreen &&
                            allowedOrients.isNotEmpty) ...[
                          DropdownButtonFormField<String>(
                            value: _orientation,
                            decoration: const InputDecoration(
                              labelText: 'Orientation',
                            ),
                            items: allowedOrients.map((o) {
                              return DropdownMenuItem(
                                value: o,
                                child: Text(_prettyOrientation(o)),
                              );
                            }).toList(),
                            onChanged: (v) {
                              setState(() => _orientation = v);
                              _markDirty();
                            },
                          ),
                          const SizedBox(height: 12),
                        ],

                        if (!_isEventStyleFixture) ...[
                          DropdownButtonFormField<String>(
                            value: _section.isEmpty ? null : _section,
                            decoration: const InputDecoration(
                              labelText: 'Section',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'open',
                                child: Text('Open'),
                              ),
                              DropdownMenuItem(
                                value: 'mixed',
                                child: Text('Mixed'),
                              ),
                              DropdownMenuItem(
                                value: 'mens',
                                child: Text("Men's"),
                              ),
                              DropdownMenuItem(
                                value: 'ladies',
                                child: Text("Ladies"),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _section = value ?? '';
                              });
                              _defaultBookerIntoFirstPlayerSlot();
                              _markDirty();
                            },
                          ),

                          const SizedBox(height: 12),

                          if (!_isEventStyleFixture) ...[
                            DropdownButtonFormField<String>(
                              value: _format,
                              decoration: const InputDecoration(
                                labelText: 'Format',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'rinks',
                                  child: Text('Fours (4)'),
                                ),
                                DropdownMenuItem(
                                  value: 'triples',
                                  child: Text('Triples (3)'),
                                ),
                                DropdownMenuItem(
                                  value: 'pairs',
                                  child: Text('Pairs (2)'),
                                ),
                                DropdownMenuItem(
                                  value: 'aussie_pairs',
                                  child: Text('Aussie Pairs (2)'),
                                ),
                                DropdownMenuItem(
                                  value: 'singles',
                                  child: Text('Singles (1)'),
                                ),
                              ],
                              onChanged: (value) async {
                                if (value == null) return;
                                final players = _playersForFormat(value);
                                if (!await _confirmStructuralOverride(
                                      _rinksRequired,
                                      players,
                                    ) ||
                                    !mounted) {
                                  return;
                                }

                                setState(() {
                                  _clearDraftAssignmentsOutside(
                                    _rinksRequired,
                                    players,
                                  );
                                  _format = value;
                                  _playersPerRink = players;
                                });

                                _markDirty();
                              },
                            ),

                            const SizedBox(height: 12),

                            DropdownButtonFormField<int>(
                              value: _playersPerRink,
                              decoration: const InputDecoration(
                                labelText: 'Players per rink',
                              ),
                              items: List.generate(4, (i) => i + 1).map((n) {
                                return DropdownMenuItem(
                                  value: n,
                                  child: Text(n.toString()),
                                );
                              }).toList(),
                              onChanged: (value) async {
                                if (value == null) return;
                                if (!await _confirmStructuralOverride(
                                      _rinksRequired,
                                      value,
                                    ) ||
                                    !mounted) {
                                  return;
                                }
                                setState(() {
                                  _clearDraftAssignmentsOutside(
                                    _rinksRequired,
                                    value,
                                  );
                                  _playersPerRink = value;
                                  if (!(_format == 'aussie_pairs' &&
                                      value == 2)) {
                                    _format = _formatCodeForRinks(value);
                                  }
                                });
                                _markDirty();
                              },
                            ),

                            const SizedBox(height: 12),

                            DropdownButtonFormField<String>(
                              value: _dressCode,
                              decoration: const InputDecoration(
                                labelText: 'Dress code',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'open',
                                  child: Text('Open'),
                                ),
                                DropdownMenuItem(
                                  value: 'whites',
                                  child: Text('Whites'),
                                ),
                                DropdownMenuItem(
                                  value: 'greys',
                                  child: Text('Greys'),
                                ),
                                DropdownMenuItem(
                                  value: 'blacks',
                                  child: Text('Blacks'),
                                ),
                                DropdownMenuItem(
                                  value: 'jackets',
                                  child: Text('Jackets'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() => _dressCode = value);
                                _markDirty();
                              },
                            ),

                            if (_fixtureTypeId != null) ...[
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: _resetPlayingDefaults,
                                  icon: const Icon(Icons.restart_alt),
                                  label: const Text(
                                    'Reset to Fixture Type defaults',
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ],

                        if (!_isEventStyleFixture) ...[
                          DropdownButtonFormField<int>(
                            key: ValueKey('rinks_$_rinksRequiredFieldVersion'),
                            value: _rinksRequired,
                            decoration: const InputDecoration(
                              labelText: 'Rinks required',
                            ),
                            items: List.generate(12, (i) => i + 1).map((n) {
                              return DropdownMenuItem(
                                value: n,
                                child: Text(n.toString()),
                              );
                            }).toList(),
                            onChanged: (v) async {
                              final previousRinks = _rinksRequired;
                              final requestedRinks = v ?? previousRinks;

                              if (!await _confirmStructuralOverride(
                                    requestedRinks,
                                    _playersPerRink,
                                  ) ||
                                  !mounted) {
                                setState(() {
                                  _rinksRequiredFieldVersion++;
                                });
                                return;
                              }

                              final canAccept =
                                  await _canAcceptRinksRequiredChange(
                                    requestedRinks,
                                  );

                              if (!mounted) return;

                              if (!canAccept) {
                                setState(() {
                                  _rinksRequired = previousRinks;
                                  _rinksRequiredFieldVersion++;
                                });
                                await Future<void>.delayed(Duration.zero);
                                if (!mounted) return;
                                await _showInsufficientRinksDialog();
                                return;
                              }

                              setState(() {
                                _clearDraftAssignmentsOutside(
                                  requestedRinks,
                                  _playersPerRink,
                                );
                                _rinksRequired = requestedRinks;
                                _shownInsufficientRinksWarning = false;
                              });

                              _markDirty();

                              await _loadRinkAvailability();
                            },
                          ),
                          const SizedBox(height: 20),
                        ],

                        if (!_isEventStyleFixture && _simpleBookingMode) ...[
                          _buildMemberBookingInlineSection(),
                        ] else if (!_isEventStyleFixture &&
                            _shouldShowRinksSection) ...[
                          _buildGreenAndRinkAvailabilityBlock(),
                        ],
                      ],
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

class _ShortRinkBookingWarning extends StatelessWidget {
  const _ShortRinkBookingWarning({
    required this.availableDuration,
    required this.latestEndAt,
  });

  final Duration availableDuration;
  final DateTime latestEndAt;

  @override
  Widget build(BuildContext context) {
    String friendlyDuration(Duration duration) {
      final hours = duration.inHours;
      final minutes = duration.inMinutes.remainder(60);

      if (hours > 0 && minutes > 0) {
        return '$hours hr ${minutes} mins';
      }

      if (hours > 0) {
        return hours == 1 ? '1 hr' : '$hours hrs';
      }

      return '$minutes mins';
    }

    String timeLabel(DateTime value) {
      final hour = value.hour.toString().padLeft(2, '0');
      final minute = value.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber, color: Color(0xFFB45309)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This slot is shorter than the normal 2-hour fixture window. '
              'Only ${friendlyDuration(availableDuration)} is available before the sunset booking limit '
              'at ${timeLabel(latestEndAt)}.',
              style: const TextStyle(
                color: Color(0xFF92400E),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RepeatFixtureCreationResult {
  RepeatFixtureCreationResult({
    required this.date,
    required this.success,
    required this.message,
    this.fixtureId,
  });

  final DateTime date;
  final bool success;
  final String message;
  final String? fixtureId;
}

class RepeatFixtureCreateOutcome {
  RepeatFixtureCreateOutcome({required this.fixtureId, required this.message});

  final String fixtureId;
  final String message;
}
