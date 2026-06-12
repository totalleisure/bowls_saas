import '../../core/widgets/app_badge.dart';
import '../clubs/club_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'captain_view_section.dart';
import 'set_captain_section.dart';
import 'fixture_display.dart';
import 'fixture_message_screen.dart';
import '../team/team_section.dart';
import '../team/manage_team_screen.dart';
import '../rinks/rinks_setup_screen.dart';
import '../rinks/rink_assignments_screen.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/hex_color.dart';
import '../../core/widgets/club_member_picker_page.dart';
import '../../features/fixtures/fixture_rsvp_section.dart';
import '../../features/clubs/club_access.dart';

String _formatLocalDateTime(DateTime dt) {
  final d = dt.day.toString().padLeft(2, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final y = dt.year.toString();
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$d/$m/$y $hh:$mm';
}

String _formatLocalDisplay(DateTime dt) {
  return formatClubDateTime(dt);
}

class FixtureDetailsPage extends StatefulWidget {
  final String fixtureId;
  const FixtureDetailsPage({super.key, required this.fixtureId});

  @override
  State<FixtureDetailsPage> createState() => _FixtureDetailsPageState();
}

class _FixtureDetailsPageState extends State<FixtureDetailsPage> {
  int _loadCount = 0;

  String? _currentMemberId;

  bool _isSuperuser = false;
  bool _isClubAdmin = false;
  bool _isSelector = false;
  bool _isFixtureCreator = false;

  bool _hasClubMembership = false;
  bool _isGuest = false;
  String? _mySexAtBirth;

  bool _loadingPermissions = true;

  bool _isAdmin = false;
  bool _isSuper = false;

  bool _canEditFixture = false;
  bool _canDeleteFixture = false;
  bool _canAssignCaptaincy = false;
  bool _canManageTeam = false;
  bool _canViewTeam = false;

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _fixture;
  bool _didChangeFixture = false;

  String? _myMemberProfileId;
  Map<String, dynamic>? _myTeamSelection;
  String? _myTeamSelectionStatus;
  bool _loadingMyTeamSelection = false;

  // Team name editing
  final TextEditingController _teamNameCtrl = TextEditingController();
  bool _savingTeamName = false;
  bool _teamNameLocked = true;

  // Team fixtures: allow choosing a team (else free-text fixture label)
  List<Map<String, dynamic>> _teams = [];
  String? _selectedTeamId;
  bool _savingTeam = false;
  bool _isTeamFixtureUi = false;

  List<Map<String, dynamic>> _clubMembers = [];

  List<Map<String, dynamic>> _memberPreselectRinks = [];
  List<Map<String, dynamic>> _memberPreselectAssignments = [];

  final ScrollController _scrollController = ScrollController();

  final _client = Supabase.instance.client;

  List<Map<String, dynamic>> _greenAreas = [];
  String? _greenAreaId;
  String? _orientation;

  Map<String, dynamic>? _selectedBookedRink;

  List<Map<String, dynamic>> _rinkAvailability = [];
  bool _loadingRinkAvailability = false;
  String? _rinkAvailabilityError;

  String? _currentTeamSelectionId() {
    final ts = _fixture?['ts'];

    if (ts is Map<String, dynamic>) {
      return ts['id']?.toString();
    }

    if (ts is List && ts.isNotEmpty) {
      final first = ts.first;
      if (first is Map<String, dynamic>) {
        return first['id']?.toString();
      }
    }

    return null;
  }

  final Map<String, String> _selectedHomeRinkByFixtureRinkId = {};

  Map<String, dynamic>? get _selectedCompetitionType {
    final ct = _fixture?['competition_type'];
    return ct is Map<String, dynamic> ? ct : null;
  }

  String get _fixtureMessageSenderName {
    if (_isFixtureCaptain) return 'Captain';
    if (_isFixtureViceCaptain) return 'Vice-Captain';
    if (_isSelector) return 'Selector';
    if (_isClubAdmin) return 'Club Admin';
    if (_isSuperuser) return 'Superuser';
    return 'Club official';
  }

  String get _selectedCompetitionSelectionMode =>
      (_selectedCompetitionType?['selection_mode'] ?? '')
          .toString()
          .trim()
          .toLowerCase();

  bool get _selectedCompetitionIsInternal =>
      _selectedCompetitionType?['is_internal'] == true;

  /// WORKFLOW (this replaces the old logic)
  bool get _usesSimpleBookingWorkflow =>
      _selectedCompetitionIsInternal &&
      _selectedCompetitionSelectionMode == 'preselect';

  bool get _isHome {
    return _fixture?['is_home'] == true;
  }

  String? get _homeVenueId {
    return _fixture?['venue_id']?.toString();
  }

  DateTime? get _startAtLocal {
    final raw = _fixture?['start_at']?.toString();
    if (raw == null || raw.isEmpty) return null;
    return parseClubTime(raw);
  }

  DateTime? get _endAtLocal {
    final raw = _fixture?['end_at']?.toString();
    if (raw == null || raw.isEmpty) {
      final start = _startAtLocal;
      return start == null ? null : start.add(const Duration(hours: 2));
    }
    return parseClubTime(raw);
  }

  bool get _canEditAdminFixtureDetails =>
      _isSuperuser || _isClubAdmin || _isSelector || _isFixtureCreator;

  bool get _canEditFixtureOperationalDetails =>
      _canEditAdminFixtureDetails || _isFixtureCaptain || _isFixtureViceCaptain;

  bool get _canMaintainMemberPreselectFixture {
    return _usesSimpleBookingWorkflow &&
        (_canUseFullAdminTools || _canManageTeam || _isFixtureCaptain);
  }

  bool get _canMaintainFixtureRinks {
    return _canEditAdminFixtureDetails ||
        _canEditFixtureOperationalDetails ||
        _canMaintainMemberPreselectFixture;
  }

  bool get _isFixtureCaptain {
    final captainId = _fixture?['captain_member_profile_id']?.toString();

    return _currentMemberId != null &&
        captainId != null &&
        captainId == _currentMemberId;
  }

  bool get _isFixtureViceCaptain {
    final viceCaptainId = _fixture?['vice_captain_member_profile_id']
        ?.toString();

    return _currentMemberId != null &&
        viceCaptainId != null &&
        viceCaptainId == _currentMemberId;
  }

  bool get _canUseFullAdminTools {
    return _isSuper || _isAdmin;
  }

  bool _canSelectBookedRink(Map<String, dynamic> rink) {
    final bookedFixtureId = rink['booked_fixture_id']?.toString();

    debugPrint(
      'CAN SELECT BOOKED RINK: '
      'bookedFixtureId=$bookedFixtureId '
      'thisFixture=${widget.fixtureId} '
      'canAdmin=$_canEditAdminFixtureDetails '
      'canOps=$_canEditFixtureOperationalDetails',
    );

    if (bookedFixtureId == null || bookedFixtureId.isEmpty) {
      return false;
    }

    // Admin-level users can select/move any booked rink.
    if (_canEditAdminFixtureDetails) {
      return true;
    }

    // Captains / vice / operational editors can only select their own fixture's rinks.
    if (_canEditFixtureOperationalDetails) {
      return bookedFixtureId == widget.fixtureId;
    }

    return false;
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

  bool _canSwapBookedRinks(
    Map<String, dynamic> selected,
    Map<String, dynamic> clicked,
  ) {
    final selectedFixtureId = selected['booked_fixture_id']?.toString();
    final clickedFixtureId = clicked['booked_fixture_id']?.toString();

    if (selectedFixtureId == null ||
        selectedFixtureId.isEmpty ||
        clickedFixtureId == null ||
        clickedFixtureId.isEmpty) {
      return false;
    }

    // Admin-level users can swap across fixtures.
    if (_canEditAdminFixtureDetails) {
      return true;
    }

    // Operational users can only swap within this fixture.
    if (_canEditFixtureOperationalDetails) {
      return selectedFixtureId == widget.fixtureId &&
          clickedFixtureId == widget.fixtureId;
    }

    return false;
  }

  bool _canUnassignBookedRink(Map<String, dynamic> rink) {
    if (!_canMaintainFixtureRinks) return false;

    final bookedFixtureId = rink['booked_fixture_id']?.toString();
    final isBookedByThisFixture =
        bookedFixtureId != null && bookedFixtureId == widget.fixtureId;

    // Admin / superuser: can unassign any booked rink
    if (_isAdmin || _isSuper) return true;

    // Captain / vice: only this fixture's rinks
    if ((_isFixtureCaptain || _isFixtureViceCaptain) && isBookedByThisFixture) {
      return true;
    }

    // Member pre-select maintainer: only this fixture's rinks
    if (_canMaintainMemberPreselectFixture && isBookedByThisFixture) {
      return true;
    }

    return false;
  }

  bool get _canRsvpToFixture {
    return _hasClubMembership && !_isGuest;
  }

  bool get _canEditFixtureLabel {
    return _isSuperuser ||
        _isClubAdmin ||
        _isSelector ||
        _isFixtureCaptain ||
        _isFixtureViceCaptain;
  }

  void _handleRinkTap(Map<String, dynamic> rink) {
    final rinkLabel =
        (rink['rink_label'] ?? rink['label'] ?? rink['name'] ?? '').toString();

    final isBooked = rink['is_booked'] == true;

    debugPrint(
      'DETAIL RINK TAP label=$rinkLabel isBooked=$isBooked '
      'admin=$_canEditAdminFixtureDetails ops=$_canEditFixtureOperationalDetails '
      'selectedBooked=${_selectedBookedRink != null}',
    );

    if (rinkLabel.isEmpty) return;

    if (isBooked) {
      if (!_canSelectBookedRink(rink)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You cannot move this rink booking.')),
        );
        return;
      }

      final selectedLabel =
          (_selectedBookedRink?['rink_label'] ??
                  _selectedBookedRink?['label'] ??
                  _selectedBookedRink?['name'] ??
                  '')
              .toString();

      if (selectedLabel == rinkLabel) {
        setState(() {
          _selectedBookedRink = null;
        });
        return;
      }

      if (_selectedBookedRink != null) {
        if (!_canSwapBookedRinks(_selectedBookedRink!, rink)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You can only swap rinks within your own fixture.'),
            ),
          );
          return;
        }

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

  Future<void> _moveBookedRinkToFreeRink(
    Map<String, dynamic> booked,
    String newRinkLabel,
  ) async {
    final currentOffset = _scrollController.offset;

    final oldLabel =
        (booked['rink_label'] ?? booked['label'] ?? booked['name'] ?? '')
            .toString();

    final fixtureRinkId = booked['fixture_rink_id']?.toString();

    if (fixtureRinkId == null || fixtureRinkId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot move this booking. Missing fixture rink id.'),
        ),
      );
      return;
    }

    try {
      await Supabase.instance.client
          .from('fixture_rinks')
          .update({'home_rink_label': newRinkLabel})
          .eq('id', fixtureRinkId);

      setState(() {
        _selectedBookedRink = null;
      });

      await _loadMemberPreselectData();
      await _loadRinkAvailability();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(
            currentOffset.clamp(
              0.0,
              _scrollController.position.maxScrollExtent,
            ),
          );
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Moved $oldLabel to $newRinkLabel')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Move failed: $e')));
    }
  }

  Future<void> _swapBookedRinks(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) async {
    final currentOffset = _scrollController.offset;

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

      await _loadMemberPreselectData();
      await _loadRinkAvailability();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(
            currentOffset.clamp(
              0.0,
              _scrollController.position.maxScrollExtent,
            ),
          );
        }
      });

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

  Future<void> _loadGreenAreas() async {
    debugPrint(
      'GREEN LOAD DETAILS: '
      'isHome=$_isHome '
      'homeVenueId=$_homeVenueId '
      'venue=${_fixture?['venue_id']} '
      'opponentVenue=${_fixture?['opponent_venue_id']} '
      'fixture=${_fixture?['id']}',
    );

    if (!_isHome || _homeVenueId == null) {
      if (!mounted) return;
      setState(() {
        _greenAreas = [];
        _greenAreaId = null;
        _orientation = null;
      });
      return;
    }

    final greens = await _client
        .from('green_areas')
        .select(
          'id, name, venue_id, discipline, orientation_mode, allowed_orientations',
        )
        .eq('venue_id', _homeVenueId!)
        .order('name');

    final loadedGreens = List<Map<String, dynamic>>.from(greens);

    if (!mounted) return;

    setState(() {
      _greenAreas = loadedGreens;

      // Prefer fixture green_area_id if it exists, otherwise default first green.
      final fixtureGreenId = _fixture?['green_area_id']?.toString();

      if (fixtureGreenId != null &&
          loadedGreens.any((g) => g['id'].toString() == fixtureGreenId)) {
        _greenAreaId = fixtureGreenId;
      } else {
        _greenAreaId = loadedGreens.isNotEmpty
            ? loadedGreens.first['id'].toString()
            : null;
      }

      _syncOrientationToSelectedGreen();
    });

    await _loadRinkAvailability();
  }

  void _syncOrientationToSelectedGreen() {
    if (_greenAreaId == null) {
      _orientation = null;
      return;
    }

    final matches = _greenAreas
        .where((g) => g['id'].toString() == _greenAreaId)
        .toList();

    if (matches.isEmpty) {
      _orientation = null;
      return;
    }

    final green = matches.first;
    final allowed = green['allowed_orientations'];

    if (allowed is List && allowed.isNotEmpty) {
      _orientation = allowed.first.toString();
    } else {
      _orientation = null;
    }
  }

  Future<void> _saveFixtureRinkAssignment({
    required String fixtureRinkId,
    required int position,
    required String? memberProfileId,
  }) async {
    if (memberProfileId == null) {
      await _client
          .from('fixture_rink_assignments')
          .delete()
          .eq('fixture_rink_id', fixtureRinkId)
          .eq('position', position);
    } else {
      final existing = _existingAssignmentForMember(
        memberProfileId: memberProfileId,
        fixtureRinkId: fixtureRinkId,
        position: position,
      );

      if (existing != null) {
        await _showSaveErrorDialog(
          'This member has already been selected elsewhere in this fixture. Please choose a different member.',
        );
        return;
      }

      await _client.from('fixture_rink_assignments').upsert({
        'fixture_id': widget.fixtureId,
        'fixture_rink_id': fixtureRinkId,
        'position': position,
        'member_profile_id': memberProfileId,
      }, onConflict: 'fixture_rink_id,position');
    }

    await _loadMemberPreselectData();
  }

  Future<void> _enqueueFixtureSelectedNotification({
    required String memberProfileId,
    required String fixtureRinkId,
    required int position,
  }) async {
    final rink = _memberPreselectRinks.firstWhere(
      (r) => r['id'].toString() == fixtureRinkId,
      orElse: () => <String, dynamic>{},
    );

    final teamNo = rink['fixture_rink_no']?.toString();
    final homeRinkLabel = (rink['home_rink_label'] ?? '').toString();
    final playersPerRink = rink['players_per_rink']?.toString();
    final roleLabel = position == 201
        ? 'marker'
        : position >= 100
        ? 'opponent'
        : 'player';

    await _client.from('notification_queue').insert({
      'event_type': 'fixture_selected',
      'member_profile_id': _currentMemberId ?? memberProfileId,
      'target_member_profile_id': memberProfileId,
      'fixture_id': widget.fixtureId,
      'team_selection_id': await _teamSelectionIdForFixture(),
      'payload': {
        'fixture_label': fixtureTitleUnified(
          _fixture!,
          myClubName: (_fixture?['opponent_venue']?['name'] ?? '').toString(),
        ),
        'start_at': _fixture?['start_at']?.toString(),
        'fixture_rink_id': fixtureRinkId,
        'team_no': teamNo,
        'home_rink_label': homeRinkLabel,
        'players_per_rink': playersPerRink,
        'position': position,
        'role': roleLabel,
      },
      'status': 'pending',
    });
  }

  Future<void> _showSaveErrorDialog(String message) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Selection not allowed'),
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

  Map<String, dynamic>? _existingAssignmentForMember({
    required String memberProfileId,
    required String fixtureRinkId,
    required int position,
  }) {
    for (final a in _memberPreselectAssignments) {
      final existingMemberId = a['member_profile_id']?.toString();
      final existingRinkId = a['fixture_rink_id']?.toString();
      final existingPosition = a['position'];

      if (existingMemberId == memberProfileId &&
          !(existingRinkId == fixtureRinkId && existingPosition == position)) {
        return a;
      }
    }

    return null;
  }

  Future<void> _loadClubMembers() async {
    final clubId = _fixture?['club_id']?.toString();
    if (clubId == null || clubId.isEmpty) return;

    final rows = await _client
        .from('club_memberships')
        .select('''
          member_profile:member_profiles(
            id,
            first_name,
            last_name,
            display_name,
            email_address
          )
        ''')
        .eq('club_id', clubId)
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
  }

  Future<void> _loadMyMemberProfileId() async {
    try {
      final id = await Supabase.instance.client.rpc('my_member_profile_id');
      if (!mounted) return;
      setState(() {
        _myMemberProfileId = id?.toString();
      });
    } catch (_) {
      // ignore for now
    }
  }

  Future<void> _loadMyTeamSelection() async {
    try {
      setState(() => _loadingMyTeamSelection = true);

      final client = Supabase.instance.client;
      final myId = (await client.rpc('my_member_profile_id')).toString();
      final teamSelectionId = _currentTeamSelectionId();

      if (teamSelectionId == null) {
        if (!mounted) return;
        setState(() {
          _myTeamSelection = null;
          _myTeamSelectionStatus = null;
          _loadingMyTeamSelection = false;
        });
        return;
      }

      final row = await client
          .from('team_selection_members')
          .select(
            'id, team_selection_id, member_profile_id, role, acceptance, responded_at, created_at',
          )
          .eq('team_selection_id', teamSelectionId)
          .eq('member_profile_id', myId)
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        _myTeamSelection = row == null ? null : Map<String, dynamic>.from(row);
        _myTeamSelectionStatus = row?['acceptance']?.toString();
        _loadingMyTeamSelection = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _myTeamSelection = null;
        _myTeamSelectionStatus = null;
        _loadingMyTeamSelection = false;
      });
    }
  }

  Future<void> _loadMemberPreselectData() async {
    final rinks = await _client
        .from('fixture_rinks')
        .select('id, fixture_rink_no, players_per_rink, home_rink_label')
        .eq('fixture_id', widget.fixtureId)
        .order('fixture_rink_no');

    final rinkRows = List<Map<String, dynamic>>.from(rinks);

    final rinkIds = rinkRows.map((r) => r['id'].toString()).toList();

    if (rinkIds.isEmpty) {
      if (!mounted) return;

      setState(() {
        _memberPreselectRinks = [];
        _memberPreselectAssignments = [];
      });

      return;
    }

    final assignments = await _client
        .from('fixture_rink_assignments')
        .select('''
      fixture_rink_id,
      member_profile_id,
      position,
      member:member_profiles(
        id,
        first_name,
        last_name,
        display_name
      )
    ''')
        .inFilter('fixture_rink_id', rinkIds);

    final assignmentRows = List<Map<String, dynamic>>.from(assignments);

    final selection = await _client
        .from('team_selections')
        .select('id')
        .eq('fixture_id', widget.fixtureId)
        .maybeSingle();

    final acceptanceByMemberId = <String, String>{};

    if (selection != null) {
      final teamSelectionId = selection['id'].toString();

      final selectionRows = await _client
          .from('team_selection_members')
          .select('member_profile_id, role, acceptance, is_selected')
          .eq('team_selection_id', teamSelectionId)
          .eq('is_selected', true);

      for (final row in List<Map<String, dynamic>>.from(selectionRows)) {
        final memberId = row['member_profile_id']?.toString();
        final acceptance = row['acceptance']?.toString();

        if (memberId != null && memberId.isNotEmpty && acceptance != null) {
          acceptanceByMemberId[memberId] = acceptance;
        }
      }
    }

    for (final row in assignmentRows) {
      final memberId = row['member_profile_id']?.toString();

      row['acceptance'] = memberId == null
          ? null
          : acceptanceByMemberId[memberId];
    }

    if (!mounted) return;

    setState(() {
      _memberPreselectRinks = rinkRows;
      _memberPreselectAssignments = assignmentRows;
    });
  }

  Future<void> _loadTeamNameLocked() async {
    final client = Supabase.instance.client;

    // 1) Any RSVPs for this fixture?
    final rsvps = await client
        .from('fixture_rsvps')
        .select('id')
        .eq('fixture_id', widget.fixtureId);

    // 2) Any rink assignments for this fixture?
    final rinkAssignments = await client
        .from('fixture_rink_assignments')
        .select('id')
        .eq('fixture_id', widget.fixtureId);

    final locked =
        (rsvps as List).isNotEmpty || (rinkAssignments as List).isNotEmpty;

    if (!mounted) return;
    setState(() => _teamNameLocked = locked);
  }

  Future<void> _loadUserPermissions() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      throw Exception('No logged-in user');
    }

    final myProfileId = (await supabase.rpc('my_member_profile_id')).toString();

    debugPrint('PROFILE RAW myProfileId = $myProfileId');
    debugPrint('FIXTURE club_id = ${_fixture?['club_id']}');
    debugPrint('FIXTURE captain = ${_fixture?['captain_member_profile_id']}');
    debugPrint(
      'FIXTURE vice    = ${_fixture?['vice_captain_member_profile_id']}',
    );

    final profile = await supabase
        .from('member_profiles')
        .select('sex_at_birth')
        .eq('id', myProfileId)
        .maybeSingle();

    _mySexAtBirth = profile?['sex_at_birth']?.toString().trim().toLowerCase();

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
        .eq('club_id', _fixture!['club_id'])
        .maybeSingle();

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

      final captainId = _fixture?['captain_member_profile_id']?.toString();

      final viceCaptainId = _fixture?['vice_captain_member_profile_id']
          ?.toString();
    } else {
      _hasClubMembership = false;
      _isGuest = false;
      _currentMemberId = myProfileId;
      _isClubAdmin = false;
      _isSelector = false;
      _isFixtureCreator = _isSuperuser;
    }

    final captainId = _fixture?['captain_member_profile_id']?.toString();
    final viceCaptainId = _fixture?['vice_captain_member_profile_id']
        ?.toString();

    debugPrint(
      'Dashboard perms: super=$_isSuperuser '
      'admin=$_isClubAdmin '
      'selector=$_isSelector '
      'fixtureCreator=$_isFixtureCreator '
      'captain=$_isFixtureCaptain '
      'vice=$_isFixtureViceCaptain '
      'memberId=$_currentMemberId',
    );

    if (mounted) {
      setState(() {
        _loadingPermissions = false;
      });
    }
  }

  Future<void> _load() async {
    _loadCount++;
    print('FixtureDetails _load() count=$_loadCount id=${widget.fixtureId}');
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final f = await Supabase.instance.client
          .from('fixtures')
          .select(
            'id, club_id, venue_id, opponent_venue_id, green_area_id, '
            'start_at, end_at, is_home, section, rinks_required, players_per_rink, orientation, '
            'team_id, team_name, notes, '
            'captain_member_profile_id, vice_captain_member_profile_id, requires_rsvp, '
            'competition_type:competition_types!fixtures_competition_type_id_fkey('
            'id, name, is_internal, selection_mode, uses_rinks, bookable_by_members, '
            'colour_scheme:fixture_colour_schemes('
            'id, name, background_hex, foreground_hex'
            ')'
            '), '
            'team:teams!fixtures_team_id_fkey(name), '
            'venue:venues!fixtures_venue_id_fkey(name), '
            'opponent_venue:venues!fixtures_opponent_venue_id_fkey(name), '
            'green_areas(name, discipline, orientation_mode), '
            'captain:member_profiles!fixtures_captain_member_profile_id_fkey(display_name), '
            'vice:member_profiles!fixtures_vice_captain_member_profile_id_fkey(display_name), '
            'ts:team_selections(id, status)',
          )
          .eq('id', widget.fixtureId)
          .single();

      if (!mounted) return;
      setState(() {
        _fixture = Map<String, dynamic>.from(f);
        _teamNameCtrl.text = (_fixture?['team_name'] ?? '').toString();
        _selectedTeamId = _fixture?['team_id']?.toString();

        final loadedCompetitionType =
            _fixture?['competition_type'] as Map<String, dynamic>?;
        final loadedSelectionMode =
            (loadedCompetitionType?['selection_mode'] ?? '').toString().trim();

        _isTeamFixtureUi =
            loadedSelectionMode == 'team' || _selectedTeamId != null;
        _loading = false;
      });

      // run post-load checks
      await _loadPermissions();
      await _loadMyMemberProfileId();
      await _loadMyTeamSelection();
      await _loadTeamNameLocked();
      await _loadTeams();
      await _loadMyRsvp();
      if (_usesSimpleBookingWorkflow) {
        await _loadClubMembers();
      }

      final fixtureRinksRequired =
          int.tryParse((_fixture?['rinks_required'] ?? '0').toString()) ?? 0;

      if (fixtureRinksRequired > 0) {
        await _loadMemberPreselectData();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadTeams() async {
    final clubId = _fixture?['club_id']?.toString();
    if (clubId == null) return;

    try {
      final rows = await Supabase.instance.client
          .from('teams')
          .select('id, name, is_active')
          .eq('club_id', clubId)
          .eq('is_active', true)
          .order('name');

      if (!mounted) return;
      setState(() {
        _teams = List<Map<String, dynamic>>.from(rows);
        _selectedTeamId ??= _fixture?['team_id']?.toString();
        if (_selectedTeamId == null &&
            _teams.isNotEmpty &&
            (_fixture?['team_id'] != null)) {
          _selectedTeamId = _teams.first['id'].toString();
        }
      });
    } catch (_) {}
  }

  String? _myRsvp; // 'yes' | 'maybe' | 'no' | null

  String _formatLabel(int p) {
    if (p == 2) return 'Pairs';
    if (p == 3) return 'Triples';
    return 'Rinks';
  }

  String _friendlyFixtureUpdateError(Object e) {
    final raw = e.toString();

    if (raw.contains('Not enough rinks available')) {
      return 'There are not enough rinks available for the new date/time.\n\n'
          'Please choose another date/time or reduce the number of rinks required.';
    }

    if (raw.contains('fixtures_no_overlap') ||
        raw.contains('overlap') ||
        raw.contains('conflict')) {
      return 'The new date/time conflicts with an existing fixture or rink booking.\n\n'
          'Please choose another date/time.';
    }

    return 'The fixture could not be updated.\n\n$raw';
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

  @override
  void initState() {
    super.initState();
    _initPage();
  }

  Future<void> _initPage() async {
    await _load();
    await _loadGreenAreas();
    await _loadUserPermissions();

    _loadMyRsvp();
  }

  @override
  void dispose() {
    _teamNameCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _editDateTime() async {
    final currentStartAtStr = _fixture?['start_at']?.toString();
    if (currentStartAtStr == null || currentStartAtStr.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fixture has no valid date/time.')),
      );
      return;
    }

    final currentLocal = parseClubTime(currentStartAtStr);

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: currentLocal,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );

    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(currentLocal),
    );

    if (pickedTime == null || !mounted) return;

    final newLocal = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm new fixture date/time'),
        content: Text('Change fixture to:\n${_formatLocalDateTime(newLocal)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await Supabase.instance.client
          .from('fixtures')
          .update({'start_at': clubTimeToUtc(newLocal).toIso8601String()})
          .eq('id', widget.fixtureId);

      _didChangeFixture = true;

      await _reloadPreservingScroll();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fixture date/time updated.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update fixture: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadPermissions() async {
    void resetPermissions() {
      _isAdmin = false;
      _isSuper = false;
      _canEditFixture = false;
      _canDeleteFixture = false;
      _canAssignCaptaincy = false;
      _canManageTeam = false;
      _canViewTeam = false;
    }

    try {
      final clubId = _fixture?['club_id']?.toString();

      if (clubId == null || clubId.isEmpty) {
        if (!mounted) return;
        setState(resetPermissions);
        return;
      }

      final access = await loadClubAccess(clubId: clubId, client: _client);

      final fixtureCaptainId = _fixture?['captain_member_profile_id']
          ?.toString();

      final fixtureViceCaptainId = _fixture?['vice_captain_member_profile_id']
          ?.toString();

      final isFixtureCaptain =
          fixtureCaptainId != null &&
          fixtureCaptainId == access.currentMemberId;

      final isFixtureVice =
          fixtureViceCaptainId != null &&
          fixtureViceCaptainId == access.currentMemberId;

      final canAdminManage = access.canAdminManageFixtures;

      final canEditFixture = canAdminManage;
      final canDeleteFixture = canAdminManage;
      final canAssignCaptaincy = canAdminManage;

      final canManageTeam = canAdminManage || isFixtureCaptain || isFixtureVice;

      final myTeamSelection = _myTeamSelection != null;
      final canViewTeam = canManageTeam || myTeamSelection;

      if (!mounted) return;

      setState(() {
        _myMemberProfileId = access.currentMemberId;

        _isAdmin = access.isClubAdmin;
        _isSuper = access.isSuperuser;

        // If you have this field in fixture_details_page.dart, keep this line.
        // If it errors, remove this one line.
        _isSelector = access.isSelector;

        _canEditFixture = canEditFixture;
        _canDeleteFixture = canDeleteFixture;
        _canAssignCaptaincy = canAssignCaptaincy;
        _canManageTeam = canManageTeam;
        _canViewTeam = canViewTeam;
      });
    } catch (e) {
      debugPrint('Fixture permissions load failed: $e');

      if (!mounted) return;

      setState(resetPermissions);
    }

    debugPrint(
      'Fixture permissions: '
      'admin=$_isAdmin '
      'super=$_isSuper '
      'edit=$_canEditFixture '
      'delete=$_canDeleteFixture '
      'assignCaptain=$_canAssignCaptaincy '
      'manageTeam=$_canManageTeam '
      'viewTeam=$_canViewTeam',
    );
  }

  Future<void> _confirmAndDelete() async {
    if (!_canDeleteFixture) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete fixture?'),
        content: const Text(
          'This will delete the fixture and all associated data '
          '(RSVPs, rinks, assignments, selections).\n\n'
          'You cannot delete a fixture if any player has accepted selection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);

    try {
      await _client.rpc(
        'delete_fixture',
        params: {'p_fixture_id': widget.fixtureId},
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() => _loading = false);

      if (!_isSuperuser) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
        return;
      }

      final forceConfirmed = await _confirmForceDeleteFixture(
        originalError: e.toString(),
      );

      if (forceConfirmed != true) return;

      await _forceDeleteFixture();
    }
  }

  Future<bool?> _confirmForceDeleteFixture({
    required String originalError,
  }) async {
    final controller = TextEditingController();

    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        var canForceDelete = false;

        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Force delete fixture?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'The normal delete failed. As a superuser, you can force '
                    'delete this fixture and all linked records.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This will permanently delete linked RSVPs, rinks, rink '
                    'assignments, team selections, diary links, notifications '
                    'and email logs where linked.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This cannot be undone.',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Original error:\n$originalError',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  const Text('Type DELETE FIXTURE to confirm:'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'DELETE FIXTURE',
                    ),
                    onChanged: (value) {
                      setDialogState(() {
                        canForceDelete = value.trim() == 'DELETE FIXTURE';
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: canForceDelete
                      ? () => Navigator.pop(ctx, true)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Force delete'),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(controller.dispose);
  }

  Future<void> _forceDeleteFixture() async {
    setState(() => _loading = true);

    try {
      final result = await _client.rpc(
        'admin_force_delete_fixture',
        params: {
          'p_fixture_id': widget.fixtureId,
          'p_confirm': 'DELETE FIXTURE',
        },
      );

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Fixture force deleted')));

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() => _loading = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Force delete failed: $e')));
    }
  }

  Future<void> _setRsvp(String status, String label) async {
    final previous = _myRsvp;

    // Update UI immediately
    setState(() => _myRsvp = status);

    try {
      final client = Supabase.instance.client;
      final fixtureId = widget.fixtureId;

      final myId = (await client.rpc('my_member_profile_id')).toString();

      await client.from('fixture_rsvps').upsert({
        'fixture_id': fixtureId,
        'member_profile_id': myId,
        'status': status,
        'responded_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'fixture_id,member_profile_id');

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('RSVP set to $label')));
    } catch (e) {
      // Revert highlight if DB write fails
      if (mounted) {
        setState(() => _myRsvp = previous);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('RSVP error: $e')));
      }
    }
    await _loadMyRsvp();
  }

  Future<void> _loadMyRsvp() async {
    try {
      final client = Supabase.instance.client;
      final fixtureId = widget.fixtureId;
      final myId = (await client.rpc('my_member_profile_id')).toString();

      final row = await client
          .from('fixture_rsvps')
          .select('status')
          .eq('fixture_id', fixtureId)
          .eq('member_profile_id', myId)
          .maybeSingle();

      if (!mounted) return;
      setState(() => _myRsvp = row?['status'] as String?);
    } catch (_) {
      // ignore load errors for now (no highlight is fine)
    }
  }

  Future<void> _editStartTime() async {
    final startLocal = parseClubTime(_fixture!['start_at'].toString());
    final endLocal = parseClubTime(_fixture!['end_at'].toString());

    final currentDuration = endLocal.difference(startLocal);

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: startLocal,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(startLocal),
    );
    if (pickedTime == null || !mounted) return;

    final newStart = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    final newEnd = newStart.add(currentDuration);

    if (newStart.isAtSameMomentAs(startLocal)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change fixture date/time?'),
        content: Text(
          'Change fixture to:\n'
          '${_formatLocalDateTime(newStart)} – ${DateFormat('HH:mm').format(newEnd)}\n\n'
          'Any physical rink assignments will be cleared. '
          'Teams and player assignments will remain unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Change'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await Supabase.instance.client
          .from('fixtures')
          .update({
            'start_at': clubTimeToUtc(newStart).toIso8601String(),
            'end_at': clubTimeToUtc(newEnd).toIso8601String(),
          })
          .eq('id', widget.fixtureId);

      await Supabase.instance.client.rpc(
        'queue_fixture_moved_notifications',
        params: {
          'p_fixture_id': widget.fixtureId,
          'p_old_start_at': clubTimeToUtc(startLocal).toIso8601String(),
          'p_old_end_at': clubTimeToUtc(endLocal).toIso8601String(),
        },
      );

      await _clearPhysicalRinkAssignments();

      _didChangeFixture = true;

      await _reloadRinksPreservingScroll();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fixture date/time updated. Rinks were unassigned.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cannot change fixture time'),
          content: Text(_friendlyFixtureUpdateError(e)),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _loadRinkAvailability() async {
    debugPrint(
      'RINK AVAILABILITY CHECK: '
      'green=$_greenAreaId '
      'start=$_startAtLocal '
      'end=$_endAtLocal',
    );

    if (_greenAreaId == null || _startAtLocal == null || _endAtLocal == null) {
      setState(() {
        _rinkAvailability = [];
        _rinkAvailabilityError = null;
      });
      return;
    }

    setState(() {
      _loadingRinkAvailability = true;
      _rinkAvailabilityError = null;
    });

    try {
      final rows = await _client.rpc(
        'get_green_rink_availability',
        params: {
          'p_green_area_id': _greenAreaId,
          'p_start_at': _startAtLocal!.toUtc().toIso8601String(),
          'p_end_at': _endAtLocal!.toUtc().toIso8601String(),
        },
      );

      debugPrint('RINK AVAILABILITY RPC rows=$rows');
      debugPrint('RINK AVAILABILITY RPC type=${rows.runtimeType}');

      if (!mounted) return;

      setState(() {
        _rinkAvailability = List<Map<String, dynamic>>.from(rows);
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _rinkAvailabilityError = e.toString();
        _rinkAvailability = [];
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingRinkAvailability = false;
        });
      }
    }
  }

  Future<void> _respondToTeamSelection(String acceptance) async {
    final previous = _myTeamSelectionStatus;

    setState(() => _myTeamSelectionStatus = acceptance);

    try {
      final client = Supabase.instance.client;
      final myId = (await client.rpc('my_member_profile_id')).toString();
      final teamSelectionId = _currentTeamSelectionId();

      if (teamSelectionId == null) {
        throw Exception('No team selection exists for this fixture.');
      }

      await client
          .from('team_selection_members')
          .update({
            'acceptance': acceptance,
            'responded_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('team_selection_id', teamSelectionId)
          .eq('member_profile_id', myId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            acceptance == 'accepted'
                ? 'Team selection accepted'
                : 'Team selection declined',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _myTeamSelectionStatus = previous);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to respond: $e')));
    }

    await _load();
  }

  Future<void> _editEndTime() async {
    final startLocal = parseClubTime(_fixture!['start_at'].toString());

    final endStr = _fixture!['end_at']?.toString();
    final endLocal = (endStr == null || endStr.isEmpty)
        ? startLocal.add(const Duration(hours: 2))
        : parseClubTime(endStr);

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(endLocal),
    );

    if (pickedTime == null || !mounted) return;

    final newEnd = DateTime(
      startLocal.year,
      startLocal.month,
      startLocal.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    if (newEnd.isAtSameMomentAs(endLocal)) return;

    if (!newEnd.isAfter(startLocal)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change fixture end time?'),
        content: Text(
          'Change fixture end time to:\n'
          '${DateFormat('HH:mm').format(newEnd)}\n\n'
          'Any physical rink assignments will be cleared. '
          'Teams and player assignments will remain unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Change'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await Supabase.instance.client
          .from('fixtures')
          .update({'end_at': clubTimeToUtc(newEnd).toIso8601String()})
          .eq('id', widget.fixtureId);

      await _clearPhysicalRinkAssignments();

      _didChangeFixture = true;

      await _reloadRinksPreservingScroll();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fixture end time updated. Rinks were unassigned.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cannot change fixture end time'),
          content: Text(_friendlyFixtureUpdateError(e)),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _clearPhysicalRinkAssignments() async {
    await Supabase.instance.client
        .from('fixture_rinks')
        .update({'home_rink_label': null})
        .eq('fixture_id', widget.fixtureId);
  }

  Widget _rsvpChoiceButton(String status, String label) {
    final isSelected = _myRsvp == status;

    return ElevatedButton(
      style: isSelected
          ? ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            )
          : null,
      onPressed: () => _setRsvp(status, label),
      child: Text(label),
    );
  }

  String _teamSelectionStatusLabel(String? status) {
    switch ((status ?? '').trim().toLowerCase()) {
      case 'accepted':
        return 'Accepted';
      case 'declined':
        return 'Declined';
      case 'pending':
        return 'Pending';
      default:
        return 'No response yet';
    }
  }

  Widget _teamSelectionChoiceButton(String status, String label) {
    final isSelected =
        (_myTeamSelectionStatus ?? '').trim().toLowerCase() == status;

    return ElevatedButton(
      style: isSelected
          ? ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            )
          : null,
      onPressed: () => _respondToTeamSelection(status),
      child: Text(label),
    );
  }

  String _memberLabelFromAssignment(Map<String, dynamic>? assignment) {
    if (assignment == null) return 'Not selected';

    final member = assignment['member'];
    if (member is! Map<String, dynamic>) return 'Not selected';

    final first = (member['first_name'] ?? '').toString().trim();
    final last = (member['last_name'] ?? '').toString().trim();
    final display = (member['display_name'] ?? '').toString().trim();

    if (last.isNotEmpty && first.isNotEmpty) return '$last, $first';
    if (display.isNotEmpty) return display;
    return 'Unnamed member';
  }

  Map<String, dynamic>? _assignmentFor({
    required String fixtureRinkId,
    required int position,
  }) {
    for (final a in _memberPreselectAssignments) {
      if (a['fixture_rink_id'].toString() == fixtureRinkId &&
          a['position'] == position) {
        return a;
      }
    }
    return null;
  }

  Color _colourFromHex(String hex) {
    var value = hex.replaceAll('#', '').trim();
    if (value.length == 6) value = 'FF$value';
    return Color(int.parse(value, radix: 16));
  }

  Color get _selectedFixtureBgColor {
    final cs = _fixture?['competition_type']?['colour_scheme'];
    return _colourFromHex((cs?['background_hex'] ?? '#6D4BB3').toString());
  }

  Color get _selectedFixtureFgColor {
    final cs = _fixture?['competition_type']?['colour_scheme'];
    return _colourFromHex((cs?['foreground_hex'] ?? '#FFFFFF').toString());
  }

  Color _acceptanceBackgroundColor(String? acceptance) {
    switch ((acceptance ?? 'pending').toLowerCase()) {
      case 'accepted':
        return const Color(0xFFE8F5E9); // light green

      case 'declined':
        return const Color(0xFFFFEBEE); // light red

      default:
        return const Color(0xFFFFE0B2); // light amber
    }
  }

  Color _acceptanceForegroundColor(String? acceptance) {
    switch ((acceptance ?? 'pending').toLowerCase()) {
      case 'accepted':
        return Colors.green.shade900;

      case 'declined':
        return Colors.red.shade900;

      default:
        return Colors.orange.shade900;
    }
  }

  int? _teamNoForSelectedRink(String rinkLabel) {
    final label = rinkLabel.trim();

    for (final rink in _memberPreselectRinks) {
      final selectedLabel = (rink['home_rink_label'] ?? '').toString().trim();

      if (selectedLabel == label) {
        final teamNo = rink['fixture_rink_no'];
        return teamNo is int ? teamNo : int.tryParse(teamNo.toString());
      }
    }

    return null;
  }

  Future<void> _reloadRinksPreservingScroll() async {
    final offset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;

    await _load();
    await _loadRinkAvailability();

    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      final max = _scrollController.position.maxScrollExtent;
      final target = offset.clamp(0.0, max);

      _scrollController.jumpTo(target);
    });
  }

  Future<void> _toggleHomeRinkSelection(String rinkLabel) async {
    final label = rinkLabel.trim();

    final selected = _memberPreselectRinks.where((r) {
      return (r['home_rink_label'] ?? '').toString().trim() == label;
    }).toList();

    // Toggle OFF if this rink is already selected
    if (selected.isNotEmpty) {
      final rink = selected.first;

      await Supabase.instance.client
          .from('fixture_rinks')
          .update({'home_rink_label': null})
          .eq('id', rink['id']);

      await _reloadRinksPreservingScroll();

      return;
    }

    // Toggle ON: assign to first team/rink without a physical rink
    final unassigned = _memberPreselectRinks.where((r) {
      return (r['home_rink_label'] ?? '').toString().trim().isEmpty;
    }).toList();

    if (unassigned.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All teams already have a rink.')),
      );
      return;
    }

    final rink = unassigned.first;

    await Supabase.instance.client
        .from('fixture_rinks')
        .update({'home_rink_label': label})
        .eq('id', rink['id']);

    await _reloadRinksPreservingScroll();
  }

  Future<void> _clearMemberPreselectSlot({
    required String fixtureRinkId,
    required int position,
  }) async {
    final oldMemberProfileId = _assignmentFor(
      fixtureRinkId: fixtureRinkId,
      position: position,
    )?['member_profile_id']?.toString();

    if (oldMemberProfileId == null || oldMemberProfileId.isEmpty) return;

    await Supabase.instance.client
        .from('fixture_rink_assignments')
        .delete()
        .eq('fixture_id', widget.fixtureId)
        .eq('fixture_rink_id', fixtureRinkId)
        .eq('position', position);

    await _markTeamSelectionMemberUnselected(oldMemberProfileId);

    await _load();
  }

  Future<String?> _teamSelectionIdForFixture() async {
    final row = await Supabase.instance.client
        .from('team_selections')
        .select('id')
        .eq('fixture_id', widget.fixtureId)
        .maybeSingle();

    return row?['id']?.toString();
  }

  Future<void> _markTeamSelectionMemberSelected(String memberProfileId) async {
    final client = Supabase.instance.client;
    final teamSelectionId = await _teamSelectionIdForFixture();

    if (teamSelectionId == null || teamSelectionId.isEmpty) {
      debugPrint('No team_selection row found for fixture ${widget.fixtureId}');
      return;
    }

    final existing = await client
        .from('team_selection_members')
        .select('id, acceptance')
        .eq('team_selection_id', teamSelectionId)
        .eq('member_profile_id', memberProfileId)
        .maybeSingle();

    if (existing == null) {
      await client.from('team_selection_members').insert({
        'team_selection_id': teamSelectionId,
        'member_profile_id': memberProfileId,
        'role': 'player',
        'acceptance': 'pending',
        'is_selected': true,
      });
    } else {
      await client
          .from('team_selection_members')
          .update({'is_selected': true})
          .eq('id', existing['id']);
    }
  }

  Future<void> _markTeamSelectionMemberUnselected(
    String memberProfileId,
  ) async {
    final client = Supabase.instance.client;
    final teamSelectionId = await _teamSelectionIdForFixture();

    if (teamSelectionId == null || teamSelectionId.isEmpty) {
      debugPrint('No team_selection row found for fixture ${widget.fixtureId}');
      return;
    }

    await client
        .from('team_selection_members')
        .update({'is_selected': false})
        .eq('team_selection_id', teamSelectionId)
        .eq('member_profile_id', memberProfileId);
  }

  Future<void> _selectMemberPreselectSlot({
    required BuildContext context,
    required String fixtureRinkId,
    required int position,
    required String pickerTitle,
    required bool useFixtureSection,
    MemberPickerSectionFilter? initialSectionFilter,
  }) async {
    final oldMemberProfileId = _assignmentFor(
      fixtureRinkId: fixtureRinkId,
      position: position,
    )?['member_profile_id']?.toString();

    final selected = await Navigator.of(context).push<List<String>?>(
      MaterialPageRoute(
        builder: (_) => ClubMemberPickerPage(
          clubId: _fixture!['club_id'].toString(),
          title: pickerTitle,
          fixtureId: widget.fixtureId,
          useFixtureSection: useFixtureSection,
          initialSectionFilter:
              initialSectionFilter ?? MemberPickerSectionFilter.mixed,
          allowMultiple: false,
          initialSelectedIds: {
            if (oldMemberProfileId != null && oldMemberProfileId.isNotEmpty)
              oldMemberProfileId,
          },
        ),
      ),
    );

    if (!mounted) return;

    if (selected == null) return; // Cancel

    final newMemberProfileId = selected.isEmpty ? null : selected.first;

    // If old member removed or replaced, mark old one unselected
    if (oldMemberProfileId != null &&
        oldMemberProfileId.isNotEmpty &&
        oldMemberProfileId != newMemberProfileId) {
      await _markTeamSelectionMemberUnselected(oldMemberProfileId);
    }

    // Save selected member OR clear assignment
    await _saveFixtureRinkAssignment(
      fixtureRinkId: fixtureRinkId,
      position: position,
      memberProfileId: newMemberProfileId,
    );

    // If new member selected, mark selected and notify if this is a new/replaced selection
    if (newMemberProfileId != null && newMemberProfileId.isNotEmpty) {
      await _markTeamSelectionMemberSelected(newMemberProfileId);

      if (newMemberProfileId != oldMemberProfileId) {
        await _enqueueFixtureSelectedNotification(
          memberProfileId: newMemberProfileId,
          fixtureRinkId: fixtureRinkId,
          position: position,
        );
      }
    }
  }

  Widget _buildMemberPreselectEditorPlaceholder() {
    debugPrint(
      'MEMBER PRESELECT EDITOR: '
      'isMemberBookable=$_usesSimpleBookingWorkflow '
      'canManageTeam=$_canManageTeam '
      'canMaintain=$_canMaintainMemberPreselectFixture '
      'myMember=$_myMemberProfileId '
      'captain=${_fixture?['captain_member_profile_id']}',
    );

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

            if (_memberPreselectRinks.isEmpty)
              const Text(
                'No teams/rinks have been created for this fixture yet.',
                textAlign: TextAlign.center,
              )
            else
              for (final rink in _memberPreselectRinks) ...[
                Builder(
                  builder: (context) {
                    final rinkId = rink['id'].toString();
                    final teamNo = rink['fixture_rink_no'] ?? '';
                    final playersPerSide =
                        (rink['players_per_rink'] as int?) ?? 2;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                              SizedBox(
                                width: 80,
                                child: Text('Player $playerNo'),
                              ),
                              Expanded(
                                child: Builder(
                                  builder: (context) {
                                    final assignment = _assignmentFor(
                                      fixtureRinkId: rinkId,
                                      position: playerNo,
                                    );

                                    final acceptance = assignment?['acceptance']
                                        ?.toString();

                                    return OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        backgroundColor:
                                            _acceptanceBackgroundColor(
                                              acceptance,
                                            ),
                                        foregroundColor:
                                            _acceptanceForegroundColor(
                                              acceptance,
                                            ),
                                      ),
                                      onPressed:
                                          _canMaintainMemberPreselectFixture
                                          ? () => _selectMemberPreselectSlot(
                                              context: context,
                                              fixtureRinkId: rinkId,
                                              position: playerNo,
                                              pickerTitle:
                                                  'Select Player $playerNo',
                                              useFixtureSection: true,
                                            )
                                          : null,
                                      child: Text(
                                        _memberLabelFromAssignment(assignment),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 16),
                              SizedBox(
                                width: 90,
                                child: Text('Opponent $playerNo'),
                              ),
                              Expanded(
                                child: Builder(
                                  builder: (context) {
                                    final assignment = _assignmentFor(
                                      fixtureRinkId: rinkId,
                                      position: 100 + playerNo,
                                    );

                                    final acceptance = assignment?['acceptance']
                                        ?.toString();

                                    return OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        backgroundColor:
                                            _acceptanceBackgroundColor(
                                              acceptance,
                                            ),
                                        foregroundColor:
                                            _acceptanceForegroundColor(
                                              acceptance,
                                            ),
                                      ),
                                      onPressed:
                                          _canMaintainMemberPreselectFixture
                                          ? () => _selectMemberPreselectSlot(
                                              context: context,
                                              fixtureRinkId: rinkId,
                                              position: 100 + playerNo,
                                              pickerTitle:
                                                  'Select Opponent $playerNo',
                                              useFixtureSection: true,
                                            )
                                          : null,
                                      child: Text(
                                        _memberLabelFromAssignment(assignment),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],

                        Row(
                          children: [
                            const SizedBox(width: 80, child: Text('Marker')),
                            Expanded(
                              child: Builder(
                                builder: (context) {
                                  final assignment = _assignmentFor(
                                    fixtureRinkId: rinkId,
                                    position: 201,
                                  );

                                  final acceptance = assignment?['acceptance']
                                      ?.toString();

                                  return OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor:
                                          _acceptanceBackgroundColor(
                                            acceptance,
                                          ),
                                      foregroundColor:
                                          _acceptanceForegroundColor(
                                            acceptance,
                                          ),
                                    ),
                                    onPressed:
                                        _canMaintainMemberPreselectFixture
                                        ? () => _selectMemberPreselectSlot(
                                            context: context,
                                            fixtureRinkId: rinkId,
                                            position: 201,
                                            pickerTitle: 'Select Marker',
                                            useFixtureSection: false,
                                            initialSectionFilter:
                                                MemberPickerSectionFilter.open,
                                          )
                                        : null,
                                    child: Text(
                                      _memberLabelFromAssignment(assignment),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],

            if (_isHome) ...[
              const SizedBox(height: 8),
              _buildRinkAvailabilityCard(embedded: true),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showRinkBookingActions(Map<String, dynamic> rink) async {
    final rinkLabel =
        (rink['rink_label'] ?? rink['label'] ?? rink['name'] ?? 'Rink')
            .toString();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),

                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.amber.shade700),
                      ),
                      child: Text(
                        rinkLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Rink booking actions',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Choose what you want to do with this rink booking.',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 22),

                InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => Navigator.pop(context, true),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.link_off,
                          color: Colors.orange.shade900,
                          size: 28,
                        ),

                        const SizedBox(width: 16),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Unassign rink',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Leave this team without a physical rink assignment.',
                                style: TextStyle(color: Colors.orange.shade800),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed == true) {
      await _unassignRink(rink);
    }
  }

  Future<void> _unassignRink(Map<String, dynamic> rink) async {
    final fixtureRinkId = rink['fixture_rink_id']?.toString();

    if (fixtureRinkId == null || fixtureRinkId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not identify the rink assignment.'),
        ),
      );
      return;
    }

    try {
      setState(() {
        _loadingRinkAvailability = true;
        _selectedBookedRink = null;
      });

      await Supabase.instance.client
          .from('fixture_rinks')
          .update({'home_rink_label': null})
          .eq('id', fixtureRinkId);

      _didChangeFixture = true;

      await _load();
      await _loadRinkAvailability();

      if (!mounted) return;

      setState(() {
        _selectedBookedRink = null;
        _loadingRinkAvailability = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Rink unassigned.')));
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingRinkAvailability = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not unassign rink: $e')));
    }
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
    final rinksRequired =
        int.tryParse((_fixture?['rinks_required'] ?? '').toString()) ?? 1;

    final enoughRinks = freeRinks >= rinksRequired;

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

            final bookedFixtureId = r['booked_fixture_id']?.toString();

            final isBookedByThisFixture =
                bookedFixtureId != null && bookedFixtureId == widget.fixtureId;

            // Important:
            // If the rink is booked, trust the booking owner.
            // Only use _teamNoForSelectedRink for free/unbooked rink selection.
            final isSelected = isBooked
                ? isBookedByThisFixture
                : selectedTeamNo != null;

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
              onTap: !_canMaintainFixtureRinks ? null : () => _handleRinkTap(r),
              onLongPress: !_canUnassignBookedRink(r)
                  ? null
                  : () => _showRinkBookingActions(r),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isSelectedBooked
                      ? Colors.amber.shade100
                      : isSelected
                      ? _selectedFixtureBgColor
                      : isBooked
                      ? bookedBgColor
                      : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    width: (isSelected || isSelectedBooked) ? 2 : 1,
                    color: isSelectedBooked
                        ? Colors.orange.shade700
                        : isSelected
                        ? _selectedFixtureFgColor
                        : isBooked
                        ? bookedFgColor.withOpacity(0.35)
                        : Colors.green.shade300,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        isBooked
                            ? isSelectedBooked
                                  ? 'Selected booking — tap a free rink to move it, another booked rink to swap, or long-press to unassign'
                                  : bookedText
                            : isSelected
                            ? 'Selected for Team $selectedTeamNo'
                            : _selectedBookedRink != null
                            ? 'Free — tap to move selected booking here'
                            : 'Free',
                        maxLines: 4,
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
                    ),

                    const SizedBox(width: 8),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: isSelectedBooked
                            ? Colors.orange.shade100
                            : isBooked
                            ? Colors.white.withOpacity(0.28)
                            : Colors.green.shade100,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: isSelectedBooked
                              ? Colors.orange.shade700
                              : isBooked
                              ? bookedFgColor.withOpacity(0.55)
                              : Colors.green.shade400,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSelectedBooked) ...[
                            Icon(
                              Icons.swap_horiz,
                              size: 14,
                              color: Colors.orange.shade900,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            rinkLabel.isEmpty ? 'Rink' : rinkLabel,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              color: isSelectedBooked
                                  ? Colors.orange.shade900
                                  : isBooked
                                  ? bookedFgColor
                                  : Colors.green.shade900,
                            ),
                          ),
                        ],
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

  Widget _buildGreenAndRinkAvailabilityBlock(String greenName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          greenName.isNotEmpty ? 'Rinks — $greenName' : 'Rinks',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 8),
        _buildRinkAvailabilitySection(),
      ],
    );
  }

  Widget _buildRinkAvailabilityCard({bool embedded = false}) {
    if (!_isHome || _greenAreaId == null) {
      return const SizedBox.shrink();
    }

    final rinksRequired =
        int.tryParse((_fixture?['rinks_required'] ?? '').toString()) ?? 0;

    if (rinksRequired <= 0) {
      return const SizedBox.shrink();
    }

    final content = _buildGreenAndRinkAvailabilityBlock(
      (_fixture?['green_areas']?['name'] ?? '').toString(),
    );

    if (embedded) {
      return content;
    }

    return Card(
      margin: const EdgeInsets.only(top: 8, bottom: 20),
      child: Padding(padding: const EdgeInsets.all(14), child: content),
    );
  }

  Future<void> _reloadPreservingScroll() async {
    final offset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;

    await _load();

    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      final max = _scrollController.position.maxScrollExtent;
      final target = offset.clamp(0.0, max);

      _scrollController.jumpTo(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Fixture details'),
          actions: [
            if (_canDeleteFixture)
              IconButton(
                tooltip: 'Delete fixture',
                icon: const Icon(Icons.delete_outline),
                onPressed: _confirmAndDelete,
              ),
          ],
        ),
        body: Center(child: Text('Error: $_error')),
      );
    }

    final fixture = _fixture!;

    final competitionType =
        fixture['competition_type'] as Map<String, dynamic>?;
    final competitionColourScheme =
        competitionType?['colour_scheme'] as Map<String, dynamic>?;
    final fixtureTypeBg = competitionColourScheme != null
        ? colorFromHex(
            competitionColourScheme['background_hex']?.toString(),
            fallback: Colors.grey.shade200,
          )
        : null;
    final fixtureTypeFg = competitionColourScheme != null
        ? colorFromHex(
            competitionColourScheme['foreground_hex']?.toString(),
            fallback: Colors.black87,
          )
        : null;

    final competitionTypeName = (competitionType?['name'] ?? '')
        .toString()
        .trim();
    final competitionSelectionMode = (competitionType?['selection_mode'] ?? '')
        .toString()
        .trim();
    final isInternalFixtureType = competitionType?['is_internal'] == true;

    final selectionMode = competitionSelectionMode
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');

    final usesRinks = competitionType?['uses_rinks'] == true;
    final isEventStyleFixture = !usesRinks;

    final isPreselectFixture = selectionMode == 'preselect';
    final isTeamFixture = selectionMode == 'team';
    final isOpenSessionFixture = selectionMode == 'open';

    final isRsvpFixture =
        selectionMode == 'rsvp' ||
        (fixture['requires_rsvp'] == true &&
            !isPreselectFixture &&
            !isTeamFixture &&
            !isOpenSessionFixture);

    final isHome = (fixture['is_home'] as bool?) ?? true;

    final modeLabel = isPreselectFixture
        ? 'Pre-Select'
        : isTeamFixture
        ? 'Team'
        : isOpenSessionFixture
        ? 'Open Session'
        : 'RSVP';

    final pageTitle = isEventStyleFixture
        ? 'Event Details'
        : '${isHome ? 'Home' : 'Away'} $modeLabel Fixture Details';

    final fixtureLabel = (fixture['team_name'] ?? '').toString().trim();

    final displayFixtureLabel = isEventStyleFixture
        ? (fixtureLabel.isNotEmpty ? fixtureLabel : competitionTypeName)
        : (competitionTypeName.isNotEmpty ? competitionTypeName : fixtureLabel);

    final teamRow = fixture['team'] as Map<String, dynamic>?;
    final teamName = (teamRow?['name'] ?? fixture['team_name'] ?? '')
        .toString()
        .trim();

    final startAt = fixture['start_at'] as String?;
    final when = startAt != null
        ? parseClubTime(startAt)
        : toClubTime(DateTime.now());

    final endAt = fixture['end_at'] as String?;
    final endWhen = endAt != null
        ? parseClubTime(endAt)
        : when.add(const Duration(hours: 2));

    final venue = (fixture['venue']?['name'] as String?) ?? '';
    final opponent = (fixture['opponent_venue']?['name'] ?? '')
        .toString()
        .trim();
    final green = (fixture['green_areas']?['name'] as String?) ?? '';
    final section = (fixture['section'] as String?) ?? '';

    final myClubName = opponent.trim();

    final matchHeader = isEventStyleFixture
        ? (displayFixtureLabel.isNotEmpty ? displayFixtureLabel : 'Event')
        : isPreselectFixture
        ? (displayFixtureLabel.isNotEmpty
              ? 'Internal $displayFixtureLabel'
              : 'Internal Fixture')
        : fixtureTitleUnified(fixture, myClubName: myClubName);

    final fixtureTeamName =
        (fixture['team']?['name'] ?? fixture['team_name'] ?? '')
            .toString()
            .trim();

    final lockedFixtureLabel = isEventStyleFixture
        ? (competitionTypeName.isNotEmpty ? competitionTypeName : 'Event')
        : isPreselectFixture
        ? 'Pre-Select Fixture'
        : isTeamFixture
        ? 'Team Fixture'
        : isOpenSessionFixture
        ? 'Open Session'
        : 'RSVP Fixture';

    final isWorkflowLocked = _teamNameLocked || isPreselectFixture;

    final fixtureTypeLabel = isPreselectFixture
        ? 'Pre-Select Fixture'
        : isTeamFixture
        ? 'Team Fixture'
        : isOpenSessionFixture
        ? 'Open Session'
        : 'RSVP Fixture';

    final fixtureTypeHelpText = isPreselectFixture
        ? 'Players are pre-selected for this fixture.'
        : isOpenSessionFixture
        ? 'This fixture is an open session. Members do not need to RSVP or accept team selection.'
        : isWorkflowLocked
        ? 'This fixture workflow can no longer be changed.'
        : isTeamFixture
        ? 'This fixture uses a team-based workflow.'
        : 'This fixture uses RSVP availability.';

    final rinks = (fixture['rinks_required'] as int?) ?? 0;
    final ppr = (fixture['players_per_rink'] as int?) ?? 4;

    final orientation = fixture['orientation'] as String?;
    final ga = fixture['green_areas'] as Map<String, dynamic>?;
    final greenDiscipline = ga?['discipline'] as String?;
    final greenOrientationMode = ga?['orientation_mode'] as String?;

    final showOrientation =
        isHome &&
        greenDiscipline == 'outdoor' &&
        greenOrientationMode != 'not_applicable';

    final captainName = (fixture['captain']?['display_name'] as String?) ?? '';
    final viceName = (fixture['vice']?['display_name'] as String?) ?? '';

    final myTeamSelection = _myTeamSelection;
    final canRespondToTeamSelection = myTeamSelection != null;
    final canManageTeam = _canManageTeam;
    final canViewTeam = _canViewTeam;

    final ts = fixture['ts'];
    String? teamSelectionStatus;
    if (ts is Map<String, dynamic>) {
      teamSelectionStatus = ts['status']?.toString();
    } else if (ts is List && ts.isNotEmpty) {
      teamSelectionStatus = (ts.first as Map<String, dynamic>?)?['status']
          ?.toString();
    }

    final isPublished = teamSelectionStatus == 'published';
    final showRsvpControls = isRsvpFixture && !isPublished;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => Navigator.pop(context, _didChangeFixture),
        ),
        title: Text(pageTitle),
        actions: [
          if (_canDeleteFixture)
            IconButton(
              tooltip: 'Delete fixture',
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmAndDelete, // make sure this method exists
            ),
          IconButton(
            tooltip: 'Send Fixture Message',
            icon: const Icon(Icons.message),
            onPressed: !_canEditFixtureOperationalDetails
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FixtureMessageScreen(
                          fixtureId: widget.fixtureId,
                          currentMemberProfileId: _currentMemberId,
                          senderName:
                              _fixtureMessageSenderName ?? 'A club member',
                        ),
                      ),
                    );
                  },
          ),
        ],
      ),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: fixtureTypeBg ?? Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: fixtureTypeFg?.withOpacity(0.25) ?? Colors.black12,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lockedFixtureLabel,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: fixtureTypeFg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${DateFormat('EEEE d MMMM yyyy').format(when)} · ${DateFormat('HH:mm').format(when)}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: fixtureTypeFg),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Text(
            matchHeader,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),

          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!isEventStyleFixture)
                AppBadge(text: isHome ? 'HOME' : 'AWAY'),

              if (displayFixtureLabel.isNotEmpty)
                AppBadge(text: displayFixtureLabel.toUpperCase()),

              if (!isEventStyleFixture && section.isNotEmpty)
                AppBadge(text: section.toUpperCase()),

              if (!isEventStyleFixture) ...[
                AppBadge(text: _formatLabel(ppr).toUpperCase()),
                AppBadge(text: '$rinks TEAMS'),
              ],

              if (!isEventStyleFixture && isHome && green.isNotEmpty)
                AppBadge(text: 'GREEN: $green'),

              if (!isEventStyleFixture && showOrientation)
                AppBadge(
                  text:
                      'ORIENTATION: ${(orientation ?? 'NOT SET').replaceAll('_', ' ').toUpperCase()}',
                ),
            ],
          ),

          if (isEventStyleFixture) ...[
            const SizedBox(height: 20),

            if (isEventStyleFixture) ...[
              const SizedBox(height: 20),
              Card(
                child: ListTile(
                  title: const Text('Venue'),
                  subtitle: Text(venue.isEmpty ? 'No venue set' : venue),
                ),
              ),
            ],

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Event information',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      (fixture['notes'] ?? '').toString().trim().isEmpty
                          ? 'No information has been added.'
                          : (fixture['notes'] ?? '').toString(),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),

          if (!isEventStyleFixture) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fixture workflow',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      fixtureTypeHelpText,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),

                    if (!isWorkflowLocked) ...[
                      const SizedBox(height: 16),

                      if (isTeamFixture) ...[
                        const Text(
                          'Team',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _selectedTeamId,
                          decoration: const InputDecoration(
                            hintText: 'Select a team',
                            border: OutlineInputBorder(),
                          ),
                          items: _teams.map((t) {
                            return DropdownMenuItem(
                              value: t['id'].toString(),
                              child: Text(t['name'].toString()),
                            );
                          }).toList(),
                          onChanged: (v) => setState(() => _selectedTeamId = v),
                        ),
                      ] else ...[
                        const Text(
                          'Fixture label',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _teamNameCtrl,
                          enabled: _canEditFixtureLabel,
                          decoration: const InputDecoration(
                            hintText: 'Enter fixture details (optional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],

                      const SizedBox(height: 12),
                      if (_canEditFixtureLabel)
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton(
                            onPressed: _savingTeam
                                ? null
                                : () async {
                                    setState(() => _savingTeam = true);
                                    try {
                                      if (isTeamFixture) {
                                        if (_selectedTeamId == null) {
                                          throw Exception(
                                            'Please select a team.',
                                          );
                                        }

                                        final selectedTeam = _teams.firstWhere(
                                          (t) =>
                                              t['id'].toString() ==
                                              _selectedTeamId,
                                          orElse: () => <String, dynamic>{},
                                        );

                                        final selectedTeamName =
                                            (selectedTeam['name'] ?? '')
                                                .toString()
                                                .trim();

                                        await Supabase.instance.client
                                            .from('fixtures')
                                            .update({
                                              'team_id': _selectedTeamId,
                                              'team_name':
                                                  selectedTeamName.isEmpty
                                                  ? null
                                                  : selectedTeamName,
                                            })
                                            .eq('id', widget.fixtureId);
                                      } else {
                                        final lbl = _teamNameCtrl.text.trim();
                                        await Supabase.instance.client
                                            .from('fixtures')
                                            .update({
                                              'team_id': null,
                                              'team_name': lbl.isEmpty
                                                  ? null
                                                  : lbl,
                                            })
                                            .eq('id', widget.fixtureId);
                                      }

                                      _didChangeFixture = true;
                                      await _reloadPreservingScroll();
                                    } catch (e) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text('Failed to save: $e'),
                                        ),
                                      );
                                    } finally {
                                      if (mounted)
                                        setState(() => _savingTeam = false);
                                    }
                                  },
                            child: _savingTeam
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Save'),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fixture timing',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Start',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: _canEditFixtureOperationalDetails
                                    ? _editStartTime
                                    : null,
                                child: Text(_formatLocalDisplay(when)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'End',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: _canEditFixtureOperationalDetails
                                    ? _editEndTime
                                    : null,
                                child: Text(_formatLocalDisplay(endWhen)),
                              ),
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
          const SizedBox(height: 20),

          if (!isEventStyleFixture) ...[
            Text(
              'Captain & vice-captain',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SetCaptainSection(fixture: fixture, readOnly: !_canAssignCaptaincy),

            if (!isOpenSessionFixture && canRespondToTeamSelection) ...[
              const SizedBox(height: 20),
              Text(
                'Team selection',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('You have been selected for this fixture.'),
                      const SizedBox(height: 10),

                      Row(
                        children: [
                          Text(
                            'Current response: ',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            _teamSelectionStatusLabel(_myTeamSelectionStatus),
                          ),
                        ],
                      ),

                      if (_myTeamSelection?['responded_at'] != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Responded: ${_formatLocalDisplay(DateTime.parse(_myTeamSelection!['responded_at'].toString()).toLocal())}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],

                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _teamSelectionChoiceButton('accepted', 'Accept'),
                          _teamSelectionChoiceButton('declined', 'Decline'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 16),
            if (showRsvpControls &&
                _canRsvpToFixture &&
                _isEligibleForFixtureSection(fixture)) ...[
              const SizedBox(height: 16),
              Text(
                'Your availability for this Fixture',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                children: [
                  _rsvpChoiceButton('yes', 'Yes'),
                  _rsvpChoiceButton('maybe', 'Maybe'),
                  _rsvpChoiceButton('no', 'No'),
                ],
              ),
            ],

            if (isRsvpFixture && isPublished) ...[
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'RSVP closed — fixture has been published.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            ],

            if (isRsvpFixture && !isPublished) ...[
              CaptainViewSection(fixture: fixture),
            ],

            if (!_usesSimpleBookingWorkflow) ...[
              const SizedBox(height: 12),
              _buildRinkAvailabilityCard(),
            ],

            if (_canMaintainMemberPreselectFixture) ...[
              _buildMemberPreselectEditorPlaceholder(),
            ],

            if (!_usesSimpleBookingWorkflow &&
                !isOpenSessionFixture &&
                canViewTeam) ...[
              const SizedBox(height: 12),
              TeamSection(
                key: ValueKey(
                  '${widget.fixtureId}-${_myTeamSelectionStatus ?? ''}-${fixture['ts']?['status'] ?? ''}',
                ),
                fixture: fixture,
                readOnly: !canManageTeam,
              ),
            ],
          ],
        ],
      ),
    );
  }
}
