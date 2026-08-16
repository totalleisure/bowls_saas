import 'dart:convert';

import '../rinks/rinks_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/date_format.dart';

import '../../Core/widgets/app_badge.dart';

import 'package:bowls_saas/services/team_sheet_pdf.dart';
import 'package:bowls_saas/services/team_sheet_share.dart';
import 'package:bowls_saas/services/team_sheet_service.dart';

import 'package:bowls_saas/core/widgets/club_member_picker_page.dart';

class ManageTeamScreen extends StatefulWidget {
  final Map<String, dynamic> fixture;
  final bool readOnly;

  const ManageTeamScreen({
    super.key,
    required this.fixture,
    this.readOnly = false,
  });

  @override
  State<ManageTeamScreen> createState() => _ManageTeamScreenState();
}

class _ManageTeamScreenState extends State<ManageTeamScreen> {
  final _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  bool _isTeamFixture = false;
  bool _usesRsvpPool = false;
  bool _isPreselectFixture = false;
  bool _isInternalFixture = false;

  String? _selectionId;
  String _status = 'draft';

  List<Map<String, dynamic>> _pool = []; // RSVP yes/maybe
  List<Map<String, dynamic>> _selected = []; // team_selection_members

  List<Map<String, dynamic>> _rinks = [];
  Map<String, Map<int, Map<String, dynamic>>> _assignmentsByRink = {};
  bool _savingAssignments = false;

  bool _checkingPermissions = true;

  bool _isSuperuser = false;
  bool _isClubAdmin = false;
  bool _isSelector = false;
  bool _isFixtureCaptain = false;
  bool _isFixtureViceCaptain = false;

  bool _canEditSelection = false;
  bool _canAssignRinks = false;
  bool _canEditRinkSetup = false;
  bool _canPublish = false;
  bool _canForceAccept = false;
  bool _canAddPeople = false;

  bool get effectiveReadOnly => widget.readOnly || !_canEditSelection;

  bool get _canModifySelection => !widget.readOnly && _canEditSelection;
  bool get _canSendReminders => !widget.readOnly && _canEditSelection;
  bool get _canPublishTeam => !widget.readOnly && _canPublish;
  bool get _canForceAcceptSelection => !widget.readOnly && _canForceAccept;

  List<Map<String, dynamic>> _clubMembers = []; // for Add Member dialog

  String? _currentMemberProfileId;
  String _search = '';

  String _selectedFilter = 'all';

  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _pageScrollController = ScrollController();
  final GlobalKey _teamPoolHeaderKey = GlobalKey();

  final TextEditingController _clubMemberSearchController =
      TextEditingController();
  String _clubMemberSearch = '';

  List<Map<String, dynamic>> get _filteredClubMembers {
    final q = _clubMemberSearch.trim().toLowerCase();

    final selectedIds = _selected
        .map((e) => e['member_profile_id']?.toString())
        .whereType<String>()
        .toSet();

    return _clubMembers.where((m) {
      final id = m['member_profile_id']?.toString() ?? m['id']?.toString();
      if (id == null || id.isEmpty || selectedIds.contains(id)) return false;

      if (q.isEmpty) return true;

      final displayName = (m['display_name'] ?? '').toString().toLowerCase();
      final firstName = (m['first_name'] ?? '').toString().toLowerCase();
      final lastName = (m['last_name'] ?? '').toString().toLowerCase();
      final email = (m['email_address'] ?? '').toString().toLowerCase();
      final preferred = (m['preferred_position'] ?? '')
          .toString()
          .toLowerCase();

      return displayName.contains(q) ||
          firstName.contains(q) ||
          lastName.contains(q) ||
          email.contains(q) ||
          preferred.contains(q);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _clubMemberSearchController.addListener(() {
      setState(() {
        _clubMemberSearch = _clubMemberSearchController.text
            .trim()
            .toLowerCase();
      });
    });
    _init();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _pageScrollController.dispose();
    _clubMemberSearchController.dispose();
    super.dispose();
  }

  void _keepTeamPoolOnScreen() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final context = _teamPoolHeaderKey.currentContext;
      if (context == null) return;

      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: 0,
      );
    });
  }

  Future<void> _init() async {
    await _loadUserPermissions();
    await _load();
  }

  Future<String?> _myMemberProfileId() async {
    try {
      final id = await _client.rpc('my_member_profile_id');
      return id?.toString();
    } catch (_) {
      return null;
    }
  }

  String _preferredPosition(Map<String, dynamic>? memberProfile) {
    return (memberProfile?['preferred_position'] ?? '').toString().trim();
  }

  String _fallbackDisplayName(Map<String, dynamic>? memberProfile) {
    final displayName = (memberProfile?['display_name'] ?? '')
        .toString()
        .trim();
    if (displayName.isNotEmpty) return displayName;

    final firstName = (memberProfile?['first_name'] ?? '').toString().trim();
    final lastName = (memberProfile?['last_name'] ?? '').toString().trim();
    final combined = ('$firstName $lastName').trim();

    return combined.isEmpty ? '(no name)' : combined;
  }

  String _displayNameWithPreferredPosition(
    Map<String, dynamic>? memberProfile,
  ) {
    final name = _fallbackDisplayName(memberProfile);
    final preferred = _preferredPosition(memberProfile);

    if (preferred.isEmpty) return name;

    return '$name ($preferred)';
  }

  int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  String _positionLabel(int position, int playersPerRink) {
    if (playersPerRink == 4) {
      switch (position) {
        case 1:
          return 'Lead';
        case 2:
          return 'Two';
        case 3:
          return 'Three';
        case 4:
          return 'Skip';
      }
    }

    if (playersPerRink == 3) {
      switch (position) {
        case 1:
          return 'Lead';
        case 2:
          return 'Two';
        case 3:
          return 'Skip';
      }
    }

    if (playersPerRink == 2) {
      switch (position) {
        case 1:
          return 'Lead';
        case 2:
          return 'Skip';
      }
    }

    if (playersPerRink == 1) {
      return 'Player';
    }

    return 'Player $position';
  }

  Map<String, dynamic>? _assignmentFor({
    required String fixtureRinkId,
    required int position,
  }) {
    return _assignmentsByRink[fixtureRinkId]?[position];
  }

  String _assignmentLabel(Map<String, dynamic>? assignment) {
    if (assignment == null) return 'Select player';

    final memberProfileId = assignment['member_profile_id']?.toString();
    if (memberProfileId == null || memberProfileId.isEmpty) {
      return 'Select player';
    }

    final selectedRow = _selected.firstWhere(
      (r) => r['member_profile_id']?.toString() == memberProfileId,
      orElse: () => <String, dynamic>{},
    );

    final profile = selectedRow['member_profiles'] as Map<String, dynamic>?;
    if (profile != null) {
      return _displayNameWithPreferredPosition(profile);
    }

    final assignmentProfile =
        assignment['member_profiles'] as Map<String, dynamic>?;
    if (assignmentProfile != null) {
      return _displayNameWithPreferredPosition(assignmentProfile);
    }

    return memberProfileId;
  }

  Map<String, dynamic>? _selectedRowForAssignment(
    Map<String, dynamic>? assignment,
  ) {
    final memberProfileId = assignment?['member_profile_id']?.toString();
    if (memberProfileId == null || memberProfileId.isEmpty) return null;

    for (final row in _selected) {
      if (row['member_profile_id']?.toString() == memberProfileId) {
        return row;
      }
    }

    return null;
  }

  String _assignmentAcceptance(Map<String, dynamic>? assignment) {
    final selectedRow = _selectedRowForAssignment(assignment);
    return (selectedRow?['acceptance'] ?? 'pending')
        .toString()
        .toLowerCase()
        .trim();
  }

  Color? _assignmentBackgroundColor(Map<String, dynamic>? assignment) {
    if (assignment == null ||
        assignment['member_profile_id']?.toString().trim().isNotEmpty != true) {
      return null;
    }

    switch (_assignmentAcceptance(assignment)) {
      case 'accepted':
        return Colors.green.shade100;
      case 'declined':
        return Colors.red.shade100;
      case 'pending':
      default:
        return Colors.orange.shade100;
    }
  }

  Color _assignmentForegroundColor(Map<String, dynamic>? assignment) {
    if (assignment == null ||
        assignment['member_profile_id']?.toString().trim().isNotEmpty != true) {
      return Theme.of(context).colorScheme.onSurface;
    }

    switch (_assignmentAcceptance(assignment)) {
      case 'accepted':
        return Colors.green.shade900;
      case 'declined':
        return Colors.red.shade900;
      case 'pending':
      default:
        return Colors.orange.shade900;
    }
  }

  Color? _assignmentBorderColor(Map<String, dynamic>? assignment) {
    if (assignment == null ||
        assignment['member_profile_id']?.toString().trim().isNotEmpty != true) {
      return null;
    }

    switch (_assignmentAcceptance(assignment)) {
      case 'accepted':
        return Colors.green.shade400;
      case 'declined':
        return Colors.red.shade400;
      case 'pending':
      default:
        return Colors.orange.shade400;
    }
  }

  List<Map<String, dynamic>> _assignableSelectedRows() {
    final rows = _selected
        .where((s) {
          final role = (s['role'] ?? 'player').toString().toLowerCase().trim();
          final isSelected = s['is_selected'] == true;
          return isSelected && (role == 'player' || role == 'reserve');
        })
        .map((s) => Map<String, dynamic>.from(s))
        .toList();

    rows.sort((a, b) {
      final amp = a['member_profiles'] as Map<String, dynamic>?;
      final bmp = b['member_profiles'] as Map<String, dynamic>?;
      return _compareMemberProfiles(amp, bmp);
    });

    return rows;
  }

  Map<String, dynamic>? _poolRowForMember(String memberProfileId) {
    for (final row in _pool) {
      if (row['member_profile_id']?.toString() == memberProfileId) {
        return row;
      }
    }
    return null;
  }

  String _rsvpStatusForMember(String memberProfileId) {
    final row = _poolRowForMember(memberProfileId);
    return (row?['rsvp_status'] ?? row?['status'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
  }

  Future<bool> _confirmUnavailablePlayerSelection(
    String memberProfileId,
  ) async {
    final status = _rsvpStatusForMember(memberProfileId);
    if (status != 'no') return true;

    final poolRow = _poolRowForMember(memberProfileId);
    final profile = poolRow?['member_profiles'] as Map<String, dynamic>?;
    final name = _displayNameWithPreferredPosition(profile);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Player marked not available'),
        content: Text(
          name.isNotEmpty
              ? '$name has already indicated that they are not available for this match.\n\nAre you sure you wish to select them?'
              : 'This player has already indicated that they are not available for this match.\n\nAre you sure you wish to select them?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Select anyway'),
          ),
        ],
      ),
    );

    return confirmed == true;
  }

  MapEntry<String, MapEntry<int, Map<String, dynamic>>>?
  _assignmentEntryForMember(String memberProfileId) {
    for (final rinkEntry in _assignmentsByRink.entries) {
      for (final positionEntry in rinkEntry.value.entries) {
        if (positionEntry.value['member_profile_id']?.toString() ==
            memberProfileId) {
          return MapEntry(rinkEntry.key, positionEntry);
        }
      }
    }
    return null;
  }

  String? _assignmentLocationLabelForMember(String memberProfileId) {
    final assignmentEntry = _assignmentEntryForMember(memberProfileId);
    if (assignmentEntry == null) return null;

    final rinkId = assignmentEntry.key;
    final position = assignmentEntry.value.key;

    Map<String, dynamic>? rink;
    for (final r in _rinks) {
      if (r['id']?.toString() == rinkId) {
        rink = r;
        break;
      }
    }

    final teamNo = rink?['fixture_rink_no']?.toString() ?? '';
    final playersPerRink = _asInt(rink?['players_per_rink']);
    final positionLabel = _positionLabel(position, playersPerRink);

    if (teamNo.isEmpty) return positionLabel;
    return 'Team $teamNo • $positionLabel';
  }

  List<Map<String, dynamic>> _currentAssignmentPayload() {
    final rows = <Map<String, dynamic>>[];

    for (final rinkEntry in _assignmentsByRink.entries) {
      final rinkId = rinkEntry.key;
      for (final positionEntry in rinkEntry.value.entries) {
        final memberProfileId = positionEntry.value['member_profile_id']
            ?.toString()
            .trim();

        if (memberProfileId == null || memberProfileId.isEmpty) {
          continue;
        }

        rows.add({
          'fixture_rink_id': rinkId,
          'position': positionEntry.key,
          'member_profile_id': memberProfileId,
        });
      }
    }

    return rows;
  }

  Future<void> _saveCurrentAssignments() async {
    if (_selectionId == null) return;

    await _client.rpc(
      'save_fixture_rink_assignments',
      params: {
        'p_fixture_id': widget.fixture['id']?.toString(),
        'p_team_selection_id': _selectionId!,
        'p_assignments': _currentAssignmentPayload(),
      },
    );
  }

  Future<void> _clearAssignmentSlot(String rinkId, int position) async {
    if (effectiveReadOnly || !_canAssignRinks || _savingAssignments) return;

    final previous = <String, Map<int, Map<String, dynamic>>>{};
    for (final entry in _assignmentsByRink.entries) {
      previous[entry.key] = Map<int, Map<String, dynamic>>.from(entry.value);
    }

    try {
      setState(() {
        _savingAssignments = true;
        _assignmentsByRink[rinkId]?.remove(position);
        if (_assignmentsByRink[rinkId]?.isEmpty == true) {
          _assignmentsByRink.remove(rinkId);
        }
      });

      await _saveCurrentAssignments();
    } catch (e) {
      if (mounted) {
        setState(() => _assignmentsByRink = previous);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Clear failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingAssignments = false);
    }
  }

  Future<bool> _confirmReservePromotion(String memberProfileId) async {
    final selectedRow = _selected.firstWhere(
      (r) => r['member_profile_id']?.toString() == memberProfileId,
      orElse: () => <String, dynamic>{},
    );

    final role = (selectedRow['role'] ?? '').toString().toLowerCase().trim();
    if (role != 'reserve') return true;

    final profile = selectedRow['member_profiles'] as Map<String, dynamic>?;
    final playerName = profile == null
        ? ''
        : _displayNameWithPreferredPosition(profile);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Promote reserve to player?'),
        content: Text(
          playerName.isNotEmpty
              ? '$playerName is currently marked as a reserve. Assigning them to a team will promote them to player. Continue?'
              : 'This member is currently marked as a reserve. Assigning them to a team will promote them to player. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Promote and assign'),
          ),
        ],
      ),
    );

    return confirmed == true;
  }

  Future<void> _assignMemberToSlot({
    required String rinkId,
    required int position,
    required String memberProfileId,
  }) async {
    if (effectiveReadOnly || !_canAssignRinks || _savingAssignments) return;

    final confirmed = await _confirmReservePromotion(memberProfileId);
    if (!confirmed) return;

    final previous = <String, Map<int, Map<String, dynamic>>>{};
    for (final entry in _assignmentsByRink.entries) {
      previous[entry.key] = Map<int, Map<String, dynamic>>.from(entry.value);
    }

    try {
      setState(() {
        _savingAssignments = true;

        // Move semantics: one player can occupy only one position.
        for (final byPosition in _assignmentsByRink.values) {
          byPosition.removeWhere(
            (_, row) => row['member_profile_id']?.toString() == memberProfileId,
          );
        }

        _assignmentsByRink.removeWhere((_, byPosition) => byPosition.isEmpty);

        _assignmentsByRink.putIfAbsent(rinkId, () => {});
        _assignmentsByRink[rinkId]![position] = {
          'fixture_rink_id': rinkId,
          'position': position,
          'member_profile_id': memberProfileId,
        };
      });

      await _saveCurrentAssignments();
    } catch (e) {
      if (mounted) {
        setState(() => _assignmentsByRink = previous);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Assign failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingAssignments = false);
    }
  }

  Future<void> _selectAssignmentSlot({
    required BuildContext context,
    required String rinkId,
    required int position,
    required String title,
  }) async {
    if (effectiveReadOnly || !_canAssignRinks || _savingAssignments) return;

    final rows = _assignableSelectedRows();

    final selectedMemberId = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.clear),
                title: const Text('Clear this position'),
                onTap: () => Navigator.of(context).pop('__clear__'),
              ),
              const Divider(),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('No selected players or reserves are available.'),
                )
              else
                for (final row in rows)
                  Builder(
                    builder: (context) {
                      final memberId = row['member_profile_id']?.toString();
                      final profile =
                          row['member_profiles'] as Map<String, dynamic>?;
                      final role = (row['role'] ?? 'player')
                          .toString()
                          .toLowerCase();
                      final name = _displayNameWithPreferredPosition(profile);

                      final assignedLabel = memberId == null
                          ? null
                          : _assignmentLocationLabelForMember(memberId);
                      final isAssigned = assignedLabel != null;
                      final isReserve = role == 'reserve';

                      final Color? tileColor = isReserve
                          ? Colors.orange.shade100
                          : isAssigned
                          ? Colors.green.shade100
                          : null;

                      final Color? iconColor = isReserve
                          ? Colors.orange.shade800
                          : isAssigned
                          ? Colors.green.shade800
                          : null;

                      return Card(
                        color: tileColor,
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        child: ListTile(
                          title: Text(name),
                          subtitle: Text(
                            isReserve
                                ? 'Reserve'
                                : isAssigned
                                ? assignedLabel
                                : 'Not yet positioned',
                          ),
                          trailing: isReserve
                              ? Icon(Icons.swap_vert, color: iconColor)
                              : isAssigned
                              ? Icon(Icons.check_circle, color: iconColor)
                              : null,
                          onTap: memberId == null || memberId.isEmpty
                              ? null
                              : () => Navigator.of(context).pop(memberId),
                        ),
                      );
                    },
                  ),
            ],
          ),
        );
      },
    );

    if (!mounted || selectedMemberId == null) return;

    if (selectedMemberId == '__clear__') {
      await _clearAssignmentSlot(rinkId, position);
      return;
    }

    await _assignMemberToSlot(
      rinkId: rinkId,
      position: position,
      memberProfileId: selectedMemberId,
    );
  }

  String _memberSortKey(Map<String, dynamic>? memberProfile) {
    final firstName = (memberProfile?['first_name'] ?? '').toString().trim();
    final lastName = (memberProfile?['last_name'] ?? '').toString().trim();
    final displayName = _fallbackDisplayName(memberProfile);

    if (lastName.isNotEmpty || firstName.isNotEmpty) {
      return '${lastName.toLowerCase()}|${firstName.toLowerCase()}|${displayName.toLowerCase()}';
    }

    final parts = displayName
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      final inferredLast = parts.last;
      final inferredFirst = parts.take(parts.length - 1).join(' ');
      return '${inferredLast.toLowerCase()}|${inferredFirst.toLowerCase()}|${displayName.toLowerCase()}';
    }

    return 'zzzz|zzzz|${displayName.toLowerCase()}';
  }

  int _compareMemberProfiles(Map<String, dynamic>? a, Map<String, dynamic>? b) {
    return _memberSortKey(a).compareTo(_memberSortKey(b));
  }

  String _buildPublishedTeamMessage() {
    final fixture = widget.fixture;

    final when = parseClubTime(fixture['start_at'].toString());
    final isHome = fixture['is_home'] as bool;

    final venue = (fixture['venue']?['name'] as String?) ?? '';
    final opponent =
        (fixture['opponent_name'] as String?) ??
        ''; // if you have it; else blank
    final homeAway = isHome ? 'Home' : 'Away';

    String fmtName(Map<String, dynamic> r) {
      final mp = r['member_profiles'] as Map<String, dynamic>?;
      return (mp?['display_name'] as String?) ?? '(no name)';
    }

    final players = _selected.where((s) => s['role'] == 'player').toList();
    final reserves = _selected.where((s) => s['role'] == 'reserve').toList();

    String line(Map<String, dynamic> r, int i) {
      final name = fmtName(r);
      final acc = (r['acceptance']?.toString() ?? 'pending').toUpperCase();
      return '${i + 1}. $name ($acc)';
    }

    final sb = StringBuffer();
    sb.writeln('Team published');
    sb.writeln('${when.toString()} • $homeAway');
    if (venue.isNotEmpty) sb.writeln('Venue: $venue');
    if (!isHome && opponent.isNotEmpty) sb.writeln('Opponent: $opponent');
    sb.writeln('');

    sb.writeln('Players:');
    for (var i = 0; i < players.length; i++) {
      sb.writeln(line(players[i], i));
    }

    sb.writeln('');
    sb.writeln('Reserves:');
    if (reserves.isEmpty) {
      sb.writeln('None');
    } else {
      for (var i = 0; i < reserves.length; i++) {
        sb.writeln(
          'R${i + 1}. ${fmtName(reserves[i])} (${(reserves[i]['acceptance']?.toString() ?? 'pending').toUpperCase()})',
        );
      }
    }

    sb.writeln('');
    sb.writeln('Please confirm acceptance in the app.');

    return sb.toString();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      final fixtureId = widget.fixture['id'] as String;
      final teamId = widget.fixture['team_id']
          ?.toString(); // null for non-team fixtures

      debugPrint(
        'ManageTeam: fixtureId=${widget.fixture['id']} teamId=$teamId requiresRsvp=${widget.fixture['requires_rsvp']}',
      );

      final requiresRsvp = widget.fixture['requires_rsvp'] == true;
      final clubId = widget.fixture['club_id']?.toString();

      final competitionType =
          widget.fixture['competition_type'] as Map<String, dynamic>?;
      final selectionMode = (competitionType?['selection_mode'] ?? '')
          .toString()
          .toLowerCase()
          .trim();
      final isInternalFixtureType = competitionType?['is_internal'] == true;

      _isTeamFixture = teamId != null && selectionMode != 'preselect';
      _isPreselectFixture = selectionMode == 'preselect';
      _isInternalFixture = isInternalFixtureType;
      _usesRsvpPool = !_isTeamFixture && !_isPreselectFixture && requiresRsvp;

      // get or create selection
      final existing = await client
          .from('team_selections')
          .select('id, status')
          .eq('fixture_id', fixtureId)
          .maybeSingle();

      if (existing == null) {
        final created = await client
            .from('team_selections')
            .insert({'fixture_id': fixtureId})
            .select('id, status')
            .single();

        _selectionId = created['id'] as String;
        _status = created['status'].toString();
      } else {
        _selectionId = existing['id'] as String;
        _status = existing['status'].toString();
      }

      if (fixtureId == null || clubId == null) {
        throw Exception('Fixture missing id/club_id');
      }

      debugPrint(
        'MANAGE_TEAM fixtureId=$fixtureId clubId=$clubId teamId=$teamId requiresRsvp=$requiresRsvp',
      );

      // 1) Load candidates (pool)
      List<Map<String, dynamic>> candidates = [];

      if (_isTeamFixture) {
        final rows = await client
            .from('team_members')
            .select(
              'member_profile_id, member_profiles(id, display_name, first_name, last_name, phone, preferred_position)',
            )
            .eq('team_id', teamId!) // 👈 THIS
            .eq('is_active', true);

        candidates = List<Map<String, dynamic>>.from(rows);
        debugPrint('MANAGE_TEAM branch: team_members');
      } else if (_usesRsvpPool) {
        // 2) RSVP fixture -> only members who said yes/maybe
        final rows = await client
            .from('fixture_rsvps')
            .select(
              'member_profile_id, status, member_profiles(id, display_name, first_name, last_name, phone, preferred_position)',
            )
            .eq('fixture_id', fixtureId)
            .inFilter('status', ['yes', 'maybe']);

        final roleByMemberId = <String, String>{};

        if (_selectionId != null) {
          final roleRows = await client
              .from('team_selection_members')
              .select('member_profile_id, role')
              .eq('team_selection_id', _selectionId!);

          for (final r in (roleRows as List)) {
            final memberId = r['member_profile_id']?.toString() ?? '';
            final role = (r['role'] ?? 'player')
                .toString()
                .toLowerCase()
                .trim();
            if (memberId.isNotEmpty) {
              roleByMemberId[memberId] = role;
            }
          }
        }

        candidates = List<Map<String, dynamic>>.from(rows).map((r) {
          final memberId = r['member_profile_id']?.toString() ?? '';
          return {
            ...r,
            'role': roleByMemberId[memberId] ?? 'player',
            'rsvp_status': r['status'],
          };
        }).toList();

        debugPrint('MANAGE_TEAM branch: fixture_rsvps yes/maybe');
        debugPrint('MANAGE_TEAM roleByMemberId=$roleByMemberId');
      } else if (_isPreselectFixture) {
        // Pre-select fixtures should not show the whole club as the main visible pool.
        // Players are selected explicitly, and any extras should be added via Add Player(s).
        candidates = [];
        debugPrint(
          'MANAGE_TEAM branch: preselect -> no default candidate pool',
        );
      } else {
        // 3) Non-team, no-RSVP fixture -> all active club members
        final rows = await client
            .from('club_memberships')
            .select(
              'member_profile_id, member_profiles(id, display_name, first_name, last_name, phone, preferred_position)',
            )
            .eq('club_id', clubId)
            .eq('is_active', true);

        candidates = List<Map<String, dynamic>>.from(rows);
        debugPrint('MANAGE_TEAM branch: club_memberships');
      }

      // 2) Load RSVP overlay (optional)
      final Map<String, String> rsvpByProfileId = {};

      if (teamId != null && teamId.isNotEmpty) {
        final rsvpRows = await client
            .from('fixture_rsvps')
            .select('member_profile_id, status')
            .eq('fixture_id', fixtureId);

        for (final r in rsvpRows) {
          final id = r['member_profile_id']?.toString();
          final st = r['status']?.toString();
          if (id != null && st != null) {
            rsvpByProfileId[id] = st;
          }
        }
      }

      // 3) Attach RSVP status to candidates for UI badges/filters
      for (final c in candidates) {
        final mpId = c['member_profile_id']?.toString();

        // If the candidate row already came from fixture_rsvps, keep that status.
        // Otherwise fall back to the overlay map.
        c['rsvp_status'] =
            c['status']?.toString() ??
            (mpId == null ? null : rsvpByProfileId[mpId]);
      }

      _pool = candidates;

      // current selected
      final selRows = await client
          .from('team_selection_members')
          .select(
            'member_profile_id, role, acceptance, responded_at, acceptance_by, is_selected, '
            'member_profiles!team_selection_members_member_profile_id_fkey(display_name, first_name, last_name, phone, preferred_position), '
            'accepted_by_profile:member_profiles!team_selection_members_acceptance_by_fkey(display_name)',
          )
          .eq('team_selection_id', _selectionId!)
          .eq('is_selected', true)
          .order('created_at');

      _selected = List<Map<String, dynamic>>.from(selRows);

      debugPrint('MANAGE_TEAM _selected=$_selected');

      for (final s in _selected) {
        debugPrint(
          'MANAGE_TEAM selected member=${s['member_profile_id']} role=${s['role']} is_selected=${s['is_selected']}',
        );
      }

      final rinkRows = await client
          .from('fixture_rinks')
          .select(
            'id, fixture_rink_no, format, players_per_rink, home_rink_label',
          )
          .eq('fixture_id', fixtureId);

      final rinkList = List<Map<String, dynamic>>.from(rinkRows);

      rinkList.sort((a, b) {
        final ao = _asInt(a['fixture_rink_no']);
        final bo = _asInt(b['fixture_rink_no']);
        return ao.compareTo(bo);
      });

      final assignmentRows = await client
          .from('fixture_rink_assignments')
          .select(
            'fixture_rink_id, position, member_profile_id, member_profiles!fixture_rink_assignments_member_profile_id_fkey(display_name, first_name, last_name, preferred_position)',
          )
          .eq('fixture_id', fixtureId);

      final byRink = <String, Map<int, Map<String, dynamic>>>{};

      for (final a in List<Map<String, dynamic>>.from(assignmentRows)) {
        final rinkId = a['fixture_rink_id']?.toString();
        final position = _asInt(a['position']);

        if (rinkId == null || rinkId.isEmpty || position <= 0) continue;

        byRink.putIfAbsent(rinkId, () => {});
        byRink[rinkId]![position] = a;
      }

      _rinks = rinkList;
      _assignmentsByRink = byRink;

      // sort pool by name
      int availabilityRank(Map<String, dynamic> r) {
        final s =
            r['rsvp_status']?.toString().toLowerCase() ??
            r['status']?.toString().toLowerCase() ??
            '';

        switch (s) {
          case 'yes':
            return 0; // Available
          case 'maybe':
            return 1; // Maybe
          case '':
            return 2; // No response yet
          case 'no':
            return 3; // Not available
          default:
            return 2;
        }
      }

      _pool.sort((a, b) {
        final ar = availabilityRank(a);
        final br = availabilityRank(b);

        if (ar != br) {
          return ar.compareTo(br);
        }

        final amp = a['member_profiles'] as Map<String, dynamic>?;
        final bmp = b['member_profiles'] as Map<String, dynamic>?;

        return _compareMemberProfiles(amp, bmp);
      });

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _acceptOnBehalf(String memberId) async {
    if (!_canForceAcceptSelection) return;
    if (_selectionId == null) return;

    try {
      final actingMemberId = await _myMemberProfileId();
      if (actingMemberId == null || actingMemberId.isEmpty) {
        throw Exception('Could not determine logged-in member profile.');
      }

      final updated = await _client
          .from('team_selection_members')
          .update({
            'acceptance': 'accepted',
            'responded_at': DateTime.now().toUtc().toIso8601String(),
            'acceptance_by': actingMemberId,
          })
          .eq('team_selection_id', _selectionId!)
          .eq('member_profile_id', memberId)
          .select('member_profile_id, acceptance, acceptance_by');

      if ((updated as List).isEmpty) {
        throw Exception('No team selection row was updated.');
      }

      await _load();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Player marked as accepted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Accept error: $e')));
    }
  }

  Future<void> _loadUserPermissions() async {
    if (mounted) {
      setState(() => _checkingPermissions = true);
    }

    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _isSuperuser = false;
          _isClubAdmin = false;
          _isSelector = false;
          _isFixtureCaptain = false;
          _isFixtureViceCaptain = false;
          _canEditSelection = false;
          _canAssignRinks = false;
          _canEditRinkSetup = false;
          _canPublish = false;
          _canForceAccept = false;
          _canAddPeople = false;
        });
        return;
      }

      final clubId =
          (widget.fixture['club_id'] ?? widget.fixture['clubId'] ?? '')
              .toString();

      final fixtureCaptainId =
          (widget.fixture['captain_member_profile_id'] ?? '').toString();
      final fixtureViceCaptainId =
          (widget.fixture['vice_captain_member_profile_id'] ?? '').toString();

      bool isSuperuser = false;
      bool isClubAdmin = false;
      bool isSelector = false;
      bool isFixtureCaptain = false;
      bool isFixtureViceCaptain = false;

      String? myMemberProfileId;

      final su = await _client
          .from('app_superusers')
          .select('user_id')
          .eq('user_id', user.id)
          .maybeSingle();

      isSuperuser = su != null;

      final mp = await _client
          .from('member_profiles')
          .select('id')
          .eq('user_id', user.id)
          .maybeSingle();

      myMemberProfileId = mp?['id']?.toString();
      _currentMemberProfileId = myMemberProfileId;

      if (clubId.isNotEmpty && myMemberProfileId != null) {
        final cm = await _client
            .from('club_memberships')
            .select('role, is_active')
            .eq('club_id', clubId)
            .eq('member_profile_id', myMemberProfileId)
            .maybeSingle();

        final isActive = cm?['is_active'] == true;
        final role = (cm?['role'] ?? '').toString().toLowerCase();

        isClubAdmin = isActive && role == 'admin';
        isSelector = isActive && role == 'selector';
      }

      if (myMemberProfileId != null && myMemberProfileId.isNotEmpty) {
        isFixtureCaptain =
            fixtureCaptainId.isNotEmpty &&
            fixtureCaptainId == myMemberProfileId;
        isFixtureViceCaptain =
            fixtureViceCaptainId.isNotEmpty &&
            fixtureViceCaptainId == myMemberProfileId;
      }

      final canEditSelection =
          isSuperuser ||
          isClubAdmin ||
          isSelector ||
          isFixtureCaptain ||
          isFixtureViceCaptain;

      final canAssignRinks = canEditSelection;

      final canEditRinkSetup = isSuperuser || isClubAdmin || isSelector;

      final canPublish = canEditSelection;
      final canForceAccept = canEditSelection;

      // Anyone who can manage the team selection can use Add Players.
      final canAddPeople = canEditSelection;

      debugPrint('--- MANAGE_TEAM permissions ---');
      debugPrint('_isSuperuser=$isSuperuser');
      debugPrint('_isClubAdmin=$isClubAdmin');
      debugPrint('_isSelector=$isSelector');
      debugPrint('_isFixtureCaptain=$isFixtureCaptain');
      debugPrint('_isFixtureViceCaptain=$isFixtureViceCaptain');
      debugPrint('_canEditSelection=$canEditSelection');
      debugPrint('_canAssignRinks=$canAssignRinks');
      debugPrint('_canEditRinkSetup=$canEditRinkSetup');
      debugPrint('_canPublish=$canPublish');
      debugPrint('_canForceAccept=$canForceAccept');
      debugPrint('_canAddPeople=$canAddPeople');

      if (!mounted) return;
      setState(() {
        _isSuperuser = isSuperuser;
        _isClubAdmin = isClubAdmin;
        _isSelector = isSelector;
        _isFixtureCaptain = isFixtureCaptain;
        _isFixtureViceCaptain = isFixtureViceCaptain;

        _canEditSelection = canEditSelection;
        _canAssignRinks = canAssignRinks;
        _canEditRinkSetup = canEditRinkSetup;
        _canPublish = canPublish;
        _canForceAccept = canForceAccept;
        _canAddPeople = canAddPeople;
      });
    } catch (e) {
      debugPrint('MANAGE_TEAM _loadUserPermissions error: $e');

      if (!mounted) return;
      setState(() {
        _isSuperuser = false;
        _isClubAdmin = false;
        _isSelector = false;
        _isFixtureCaptain = false;
        _isFixtureViceCaptain = false;
        _canEditSelection = false;
        _canAssignRinks = false;
        _canEditRinkSetup = false;
        _canPublish = false;
        _canForceAccept = false;
        _canAddPeople = false;
      });
    } finally {
      if (mounted) {
        setState(() => _checkingPermissions = false);
      }
    }
  }

  Future<void> _loadClubMembers() async {
    final clubId = (widget.fixture['club_id'] ?? widget.fixture['clubId'] ?? '')
        .toString();
    if (clubId.isEmpty) return;

    final rows = await _client
        .from('club_memberships')
        .select(
          'member_profile_id, member_profiles(first_name, last_name, display_name, email_address, preferred_position)',
        )
        .eq('club_id', clubId);

    final members = <Map<String, dynamic>>[];
    for (final r in (rows as List)) {
      final mp = r['member_profiles'] as Map<String, dynamic>?;
      final first = (mp?['first_name'] ?? '').toString().trim();
      final last = (mp?['last_name'] ?? '').toString().trim();
      final name = ('$first $last').trim();

      final display = (mp?['display_name'] ?? '').toString().trim();
      final preferred = (mp?['preferred_position'] ?? '').toString().trim();
      final email = (mp?['email_address'] ?? '').toString().trim();

      members.add({
        'member_profile_id': r['member_profile_id']?.toString(),
        'first_name': first,
        'last_name': last,
        'display_name': display.isNotEmpty
            ? display
            : (name.isEmpty
                  ? (r['member_profile_id']?.toString() ?? '')
                  : name),
        'preferred_position': preferred,
        'email_address': email,
      });
    }

    members.sort((a, b) => _compareMemberProfiles(a, b));

    if (mounted) {
      setState(() => _clubMembers = members);
    }
  }

  Future<void> _openAddPlayersPicker() async {
    if (!_canAddPeople || effectiveReadOnly) return;

    if (_selectionId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Team selection not loaded yet. Try again in a moment.',
          ),
        ),
      );
      return;
    }

    final excludeIds = _memberIdsAlreadyInAddPeopleList();

    final selectedIds = await Navigator.of(context).push<List<String>?>(
      MaterialPageRoute(
        builder: (_) => ClubMemberPickerPage(
          clubId: widget.fixture['club_id'].toString(),
          title: 'Add Players',
          fixtureId: widget.fixture['id'].toString(),
          useFixtureSection: true,
          allowMultiple: true,
          excludeMemberProfileIds: excludeIds,
        ),
      ),
    );

    if (!mounted || selectedIds == null || selectedIds.isEmpty) return;

    setState(() => _loading = true);

    try {
      await _addMembersFromPicker(selectedIds.toSet());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add players: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addMembersFromPicker(Set<String> selectedIds) async {
    if (selectedIds.isEmpty) return;

    final fixtureId = widget.fixture['id']?.toString();
    final teamId = widget.fixture['team_id']?.toString();

    if (fixtureId == null || fixtureId.isEmpty) {
      throw Exception('Fixture not loaded correctly.');
    }

    List<Map<String, dynamic>> inserted = [];

    if (_isTeamFixture) {
      if (teamId == null || teamId.isEmpty) {
        throw Exception('Team fixture has no team assigned.');
      }

      final payload = selectedIds
          .map(
            (id) => {
              'team_id': teamId,
              'member_profile_id': id,
              'is_active': true,
            },
          )
          .toList();

      inserted = List<Map<String, dynamic>>.from(
        await _client.from('team_members').insert(payload).select(),
      );
    } else if (_isPreselectFixture) {
      if (_selectionId == null || _selectionId!.isEmpty) {
        throw Exception('Team selection not loaded yet.');
      }

      final payload = selectedIds
          .map(
            (id) => {
              'team_selection_id': _selectionId,
              'member_profile_id': id,
              'role': 'player',
              'acceptance': 'pending',
              'is_selected': true,
            },
          )
          .toList();

      inserted = List<Map<String, dynamic>>.from(
        await _client
            .from('team_selection_members')
            .insert(payload)
            .select('member_profile_id, role, acceptance, is_selected'),
      );
    } else {
      final payload = selectedIds
          .map(
            (id) => {
              'fixture_id': fixtureId,
              'member_profile_id': id,
              'status': 'maybe',
            },
          )
          .toList();

      inserted = List<Map<String, dynamic>>.from(
        await _client
            .from('fixture_rsvps')
            .insert(payload)
            .select('id, fixture_id, member_profile_id, status'),
      );
    }

    await _load();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Inserted rows: ${inserted.length}')),
      );
    }
  }

  Future<void> _shareTeamSheet() async {
    try {
      if (_selectionId == null) throw Exception('Team selection not ready');

      final client = Supabase.instance.client;
      final svc = TeamSheetService(client);

      final fixtureId = widget.fixture['id'] as String;

      // Pull these from widget.fixture if they exist there, or wherever you store them
      final clubName = (widget.fixture['club_name'] ?? 'Club').toString();
      final opponentName = (widget.fixture['opponent_name'] ?? 'Opponent')
          .toString();
      final startAt = DateTime.parse(widget.fixture['start_at'].toString());
      final isHome = widget.fixture['is_home'] == true;
      final section = (widget.fixture['section'] ?? '').toString();

      final data = await svc.loadTeamSheetData(
        fixtureId: fixtureId,
        teamSelectionId: _selectionId!,
        clubName: clubName,
        opponentName: opponentName,
        startAt: startAt,
        isHome: isHome,
        section: section,
        primaryColor: 0xFF0B3D91,
        secondaryColor: 0xFFFFD200,
        dress: 'Greys/Whites or Blacks',
        notes: null,
      );

      final pdfBytes = await buildTeamSheetPdf(data);

      await shareTeamSheetPdf(
        pdfBytes,
        message: '${data.clubName} v ${data.opponentName} — ${data.startAt}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Share failed: $e')));
    }
  }

  Map<String, dynamic>? _selectedRowFor(String memberId) {
    final rows = _selected
        .where((r) => r['member_profile_id'] == memberId)
        .toList();
    return rows.isEmpty ? null : rows.first;
  }

  List<Map<String, dynamic>> _filterPool(List<Map<String, dynamic>> pool) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return pool;

    return pool.where((r) {
      final mp = r['member_profiles'] as Map<String, dynamic>?;
      final displayName = _displayNameWithPreferredPosition(mp).toLowerCase();
      final firstName = (mp?['first_name'] ?? '').toString().toLowerCase();
      final lastName = (mp?['last_name'] ?? '').toString().toLowerCase();
      final phone = (mp?['phone'] ?? '').toString().toLowerCase();
      final preferred = (mp?['preferred_position'] ?? '')
          .toString()
          .toLowerCase();
      final status = (r['rsvp_status'] ?? r['status'] ?? '')
          .toString()
          .toLowerCase();

      return displayName.contains(q) ||
          firstName.contains(q) ||
          lastName.contains(q) ||
          phone.contains(q) ||
          preferred.contains(q) ||
          status.contains(q);
    }).toList();
  }

  Future<void> _togglePlayer(String memberId) async {
    if (!_canModifySelection) return;
    if (_selectionId == null) return;

    final client = Supabase.instance.client;

    try {
      final existingAny = await client
          .from('team_selection_members')
          .select('member_profile_id, role, acceptance, is_selected')
          .eq('team_selection_id', _selectionId!)
          .eq('member_profile_id', memberId)
          .maybeSingle();

      final currentlySelected = existingAny?['is_selected'] == true;

      if (!currentlySelected) {
        final confirmedAvailable = await _confirmUnavailablePlayerSelection(
          memberId,
        );
        if (!confirmedAvailable) return;
      }

      if (existingAny == null) {
        await client.from('team_selection_members').insert({
          'team_selection_id': _selectionId,
          'member_profile_id': memberId,
          'role': 'player',
          'acceptance': 'pending',
          'is_selected': true,
        });
      } else {
        await client
            .from('team_selection_members')
            .update({'is_selected': !currentlySelected})
            .eq('team_selection_id', _selectionId!)
            .eq('member_profile_id', memberId);
      }

      if (!mounted) return;

      setState(() {
        if (currentlySelected) {
          // This path is not normally used from the visible Team Pool because
          // selected players are filtered out, but keep the local state correct
          // if this method is reused elsewhere.
          _selected.removeWhere(
            (r) => r['member_profile_id']?.toString() == memberId,
          );

          // If the player has been removed from the selection, also remove any
          // local assignment so the screen does not show an invalid slot.
          for (final byPosition in _assignmentsByRink.values) {
            byPosition.removeWhere(
              (_, row) => row['member_profile_id']?.toString() == memberId,
            );
          }
          _assignmentsByRink.removeWhere((_, byPosition) => byPosition.isEmpty);
        } else {
          final alreadyInSelected = _selected.any(
            (r) => r['member_profile_id']?.toString() == memberId,
          );

          if (!alreadyInSelected) {
            final poolRow = _pool.cast<Map<String, dynamic>?>().firstWhere(
              (r) => r?['member_profile_id']?.toString() == memberId,
              orElse: () => null,
            );

            _selected.add({
              'member_profile_id': memberId,
              'role': (existingAny?['role'] ?? 'player').toString(),
              'acceptance': (existingAny?['acceptance'] ?? 'pending')
                  .toString(),
              'is_selected': true,
              'member_profiles': poolRow?['member_profiles'],
              'accepted_by_profile': null,
            });
          }
        }
      });

      _keepTeamPoolOnScreen();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Update team error: $e')));
    }
  }

  Future<void> _setRole(String memberId, String role) async {
    if (!_canModifySelection) return;
    if (_selectionId == null) return;

    try {
      final existing = await Supabase.instance.client
          .from('team_selection_members')
          .select('role')
          .eq('team_selection_id', _selectionId!)
          .eq('member_profile_id', memberId)
          .maybeSingle();

      final oldRole = (existing?['role'] ?? '').toString().toLowerCase().trim();
      final newRole = role.toLowerCase().trim();

      final assignmentLocation = _assignmentLocationLabelForMember(memberId);
      final hasTeamPosition = assignmentLocation != null;

      if (newRole == 'reserve' && hasTeamPosition) {
        final selectedRow = _selected.firstWhere(
          (r) => r['member_profile_id']?.toString() == memberId,
          orElse: () => <String, dynamic>{},
        );

        final profile = selectedRow['member_profiles'] as Map<String, dynamic>?;
        final name = _displayNameWithPreferredPosition(profile);

        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove player from team?'),
            content: Text(
              name.isNotEmpty
                  ? '$name is currently assigned to $assignmentLocation.\n\nMaking this member a reserve will remove them from that team position. Do you want to continue?'
                  : 'This member is currently assigned to $assignmentLocation.\n\nMaking them a reserve will remove them from that team position. Do you want to continue?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Make reserve'),
              ),
            ],
          ),
        );

        if (confirmed != true) return;
      }

      debugPrint('SETROLE memberId=$memberId');
      debugPrint('SETROLE existing=$existing');
      debugPrint('SETROLE oldRole=$oldRole newRole=$newRole');
      debugPrint('SETROLE selectionId=$_selectionId');

      await Supabase.instance.client
          .from('team_selection_members')
          .update({'role': role})
          .eq('team_selection_id', _selectionId!)
          .eq('member_profile_id', memberId);

      if (newRole == 'reserve' && hasTeamPosition) {
        for (final byPosition in _assignmentsByRink.values) {
          byPosition.removeWhere(
            (_, row) => row['member_profile_id']?.toString() == memberId,
          );
        }
        _assignmentsByRink.removeWhere((_, byPosition) => byPosition.isEmpty);
        await _saveCurrentAssignments();
      }

      if (oldRole == 'reserve' && newRole == 'player') {
        debugPrint('SETROLE reserve->player trigger fired for $memberId');

        final fixture = widget.fixture;
        final profileRow = await Supabase.instance.client
            .from('member_profiles')
            .select('display_name, first_name, last_name, preferred_position')
            .eq('id', memberId)
            .maybeSingle();

        final playerProfile = profileRow == null
            ? null
            : Map<String, dynamic>.from(profileRow);

        final playerName =
            playerProfile?['display_name']?.toString().trim().isNotEmpty == true
            ? playerProfile!['display_name'].toString().trim()
            : [
                playerProfile?['first_name']?.toString().trim() ?? '',
                playerProfile?['last_name']?.toString().trim() ?? '',
              ].where((s) => s.isNotEmpty).join(' ');

        final isHome = fixture['is_home'] == true;
        final startAtText = fixture['start_at']?.toString();

        final fixtureLabel =
            (fixture['team_name']?.toString().trim().isNotEmpty ?? false)
            ? fixture['team_name'].toString().trim()
            : 'Fixture';

        final venueName =
            (fixture['venue_name']?.toString().trim().isNotEmpty ?? false)
            ? fixture['venue_name'].toString().trim()
            : ((fixture['opponent_name']?.toString().trim().isNotEmpty ?? false)
                  ? fixture['opponent_name'].toString().trim()
                  : '');

        await Supabase.instance.client.from('notification_queue').insert({
          'event_type': 'reserve_promoted',
          'member_profile_id': _currentMemberProfileId,
          'target_member_profile_id': memberId,
          'fixture_id': fixture['id'],
          'team_selection_id': _selectionId,
          'payload': {
            'player_name': playerName,
            'fixture_label': fixtureLabel,
            'fixture_date': startAtText,
            'home_away': isHome ? 'Home' : 'Away',
            'venue_name': venueName,
            'old_role': 'reserve',
            'new_role': 'player',
          },
          'status': 'pending',
        });
      }

      if (!mounted) return;
      setState(() {
        for (final row in _selected) {
          if (row['member_profile_id']?.toString() == memberId) {
            row['role'] = role;
            break;
          }
        }
      });
    } catch (e, st) {
      debugPrint('SETROLE error: $e');
      debugPrint('SETROLE stack: $st');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Set role error: $e')));
    }
  }

  Map<String, dynamic>? _assignmentForSelectedMember(String memberProfileId) {
    for (final rinkEntry in _assignmentsByRink.entries) {
      for (final positionEntry in rinkEntry.value.entries) {
        if (positionEntry.value['member_profile_id']?.toString() ==
            memberProfileId) {
          return {
            'fixture_rink_id': rinkEntry.key,
            'position': positionEntry.key,
            ...positionEntry.value,
          };
        }
      }
    }
    return null;
  }

  Map<String, dynamic>? _rinkForAssignment(Map<String, dynamic>? assignment) {
    final rinkId = assignment?['fixture_rink_id']?.toString();
    if (rinkId == null || rinkId.isEmpty) return null;

    for (final rink in _rinks) {
      if (rink['id']?.toString() == rinkId) {
        return rink;
      }
    }
    return null;
  }

  bool _isSelectedMemberAllocated(Map<String, dynamic> selectedRow) {
    final role = (selectedRow['role'] ?? 'player')
        .toString()
        .toLowerCase()
        .trim();

    if (role == 'reserve') return true;

    final memberId = selectedRow['member_profile_id']?.toString();
    if (memberId == null || memberId.isEmpty) return false;

    return _assignmentForSelectedMember(memberId) != null;
  }

  String _selectedMemberPlacementLabel(Map<String, dynamic> selectedRow) {
    final role = (selectedRow['role'] ?? 'player')
        .toString()
        .toLowerCase()
        .trim();

    if (role == 'reserve') return 'Reserve';

    final memberId = selectedRow['member_profile_id']?.toString();
    if (memberId == null || memberId.isEmpty) return 'Not allocated';

    final assignment = _assignmentForSelectedMember(memberId);
    if (assignment == null) return 'Not allocated';

    final rink = _rinkForAssignment(assignment);
    final teamNo = rink?['fixture_rink_no']?.toString() ?? '';
    final position = _asInt(assignment['position']);
    final playersPerRink = _asInt(rink?['players_per_rink']);

    String location;
    if (role == 'opponent') {
      final opponentNo = position >= 100 ? position - 100 : position;
      location = 'Opponent $opponentNo';
    } else if (role == 'marker') {
      location = 'Marker';
    } else {
      location = _positionLabel(position, playersPerRink);
    }

    return teamNo.isEmpty ? location : 'Team $teamNo • $location';
  }

  Future<void> _returnUnallocatedMemberToPool(
    Map<String, dynamic> selectedRow,
  ) async {
    final memberId = selectedRow['member_profile_id']?.toString();
    if (memberId == null || memberId.isEmpty) return;

    final profile = selectedRow['member_profiles'] as Map<String, dynamic>?;
    final name = _fallbackDisplayName(profile);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Return member to pool?'),
        content: Text(
          '$name is selected but has not been allocated to a team position.\n\n'
          'Return this member to the available pool?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Return to pool'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _removeSelected(memberId);
  }

  List<String> _unallocatedSelectedPlayerNames() {
    final assignedIds = <String>{};

    for (final byPosition in _assignmentsByRink.values) {
      for (final assignment in byPosition.values) {
        final memberId = assignment['member_profile_id']?.toString().trim();
        if (memberId != null && memberId.isNotEmpty) {
          assignedIds.add(memberId);
        }
      }
    }

    final names = <String>[];

    for (final row in _selected) {
      final memberId = row['member_profile_id']?.toString().trim();
      if (memberId == null || memberId.isEmpty) continue;

      final role = (row['role'] ?? '').toString().toLowerCase().trim();
      if (role == 'reserve') continue;
      if (assignedIds.contains(memberId)) continue;

      final profile = row['member_profiles'] is Map<String, dynamic>
          ? row['member_profiles'] as Map<String, dynamic>
          : row['member_profiles'] is Map
          ? Map<String, dynamic>.from(row['member_profiles'] as Map)
          : null;

      names.add(_fallbackDisplayName(profile));
    }

    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  Future<void> _showUnallocatedSelectedPlayersDialog(
    List<String> playerNames,
  ) async {
    final shownNames = playerNames.take(8).join('\n');
    final extraCount = playerNames.length - playerNames.take(8).length;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Team selection not complete'),
        content: Text(
          playerNames.length == 1
              ? '${playerNames.first} has been selected but has not been assigned to a team position or marked as a reserve.\n\nPlease assign them to a position, make them a reserve, or remove them before publishing.'
              : 'These selected players have not been assigned to a team position or marked as reserves:\n\n$shownNames${extraCount > 0 ? '\n...and $extraCount more' : ''}\n\nPlease assign them to positions, make them reserves, or remove them before publishing.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  bool _isUnallocatedSelectedPlayersError(Object error) {
    return error.toString().contains('UNALLOCATED_SELECTED_PLAYERS');
  }

  List<int>? _parseIncompleteTeamError(Object error) {
    final match = RegExp(
      r'INCOMPLETE_TEAM:(\d+):(\d+)',
    ).firstMatch(error.toString());
    if (match == null) return null;

    return [int.parse(match.group(1)!), int.parse(match.group(2)!)];
  }

  Future<bool> _confirmPublishIncomplete({
    required int requiredPositions,
    required int assignedPositions,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Publish incomplete team?'),
        content: Text(
          'This team is incomplete. '
          '$requiredPositions player positions are required, but only '
          '$assignedPositions have been assigned.\n\n'
          'Do you want to publish it anyway?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Publish anyway'),
          ),
        ],
      ),
    );

    return result == true;
  }

  Future<void> _publishTeamSelection({required bool allowIncomplete}) async {
    await Supabase.instance.client.rpc(
      'publish_team_selection_safe',
      params: {
        'p_fixture_id': widget.fixture['id']?.toString(),
        'p_team_selection_id': _selectionId!,
        'p_allow_incomplete': allowIncomplete,
      },
    );
  }

  Future<Map<String, dynamic>> _buildPublicationTeamSheetAttachment() async {
    if (_selectionId == null) throw Exception('Team selection not ready');

    final fixtureId = widget.fixture['id']?.toString();
    if (fixtureId == null || fixtureId.isEmpty) {
      throw Exception('Fixture id not found');
    }

    final svc = TeamSheetService(_client);

    final clubName = (widget.fixture['club_name'] ?? 'Club').toString();
    final opponentName = (widget.fixture['opponent_name'] ?? 'Opponent')
        .toString();
    final startAt = DateTime.parse(widget.fixture['start_at'].toString());
    final isHome = widget.fixture['is_home'] == true;
    final section = (widget.fixture['section'] ?? '').toString();

    final data = await svc.loadTeamSheetData(
      fixtureId: fixtureId,
      teamSelectionId: _selectionId!,
      clubName: clubName,
      opponentName: opponentName,
      startAt: startAt,
      isHome: isHome,
      section: section,
      primaryColor: 0xFF0B3D91,
      secondaryColor: 0xFFFFD200,
      dress: 'Greys/Whites or Blacks',
      notes: null,
    );

    final pdfBytes = await buildTeamSheetPdf(data);

    final d = toClubTime(data.startAt);
    final when =
        '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
    final safeClub = data.clubName.replaceAll(RegExp(r'[<>:"/\|?*]'), '-');
    final safeOpp = data.opponentName.replaceAll(RegExp(r'[<>:"/\|?*]'), '-');

    return {
      'name': '$safeClub v $safeOpp - $when.pdf',
      'contentType': 'application/pdf',
      'contentBytes': base64Encode(pdfBytes),
    };
  }

  Future<int> _attachPublicationTeamSheetToQueuedEmails() async {
    if (_selectionId == null) throw Exception('Team selection not ready');

    final fixtureId = widget.fixture['id']?.toString();
    if (fixtureId == null || fixtureId.isEmpty) {
      throw Exception('Fixture id not found');
    }

    final attachment = await _buildPublicationTeamSheetAttachment();

    final result = await _client.rpc(
      'attach_publication_team_sheet',
      params: {
        'p_fixture_id': fixtureId,
        'p_team_selection_id': _selectionId!,
        'p_attachment': attachment,
      },
    );

    if (result is int) return result;
    return int.tryParse(result?.toString() ?? '') ?? 0;
  }

  Future<int> _processPublicationNotifications() async {
    final result = await _client.rpc(
      'process_notification_queue',
      params: {'p_limit': 50},
    );

    if (result is int) return result;
    return int.tryParse(result?.toString() ?? '') ?? 0;
  }

  Future<void> _publish() async {
    if (!_canPublishTeam) return;
    if (_selectionId == null) return;

    final unallocatedPlayers = _unallocatedSelectedPlayerNames();
    if (unallocatedPlayers.isNotEmpty) {
      await _showUnallocatedSelectedPlayersDialog(unallocatedPlayers);
      return;
    }

    try {
      try {
        await _publishTeamSelection(allowIncomplete: false);
      } catch (e) {
        if (_isUnallocatedSelectedPlayersError(e)) {
          if (!mounted) return;
          await _showUnallocatedSelectedPlayersDialog(const [
            'One or more selected players',
          ]);
          return;
        }

        final incomplete = _parseIncompleteTeamError(e);
        if (incomplete == null) rethrow;

        if (!mounted) return;
        final publishAnyway = await _confirmPublishIncomplete(
          requiredPositions: incomplete[0],
          assignedPositions: incomplete[1],
        );

        if (!publishAnyway) return;

        await _publishTeamSelection(allowIncomplete: true);
      }

      var processedCount = 0;
      var attachedCount = 0;
      Object? preparationError;

      try {
        processedCount = await _processPublicationNotifications();
        attachedCount = await _attachPublicationTeamSheetToQueuedEmails();
      } catch (e) {
        preparationError = e;
        debugPrint('Publish preparation warning: $e');
      }

      if (!mounted) return;
      setState(() => _status = 'published');

      final message = preparationError == null
          ? 'Team published. $processedCount notification(s) processed; team sheet attached to $attachedCount email(s).'
          : 'Team published, but preparing notifications/team sheet needs checking: $preparationError';

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Publish error: $e')));
    }
  }

  Future<void> _removeSelected(String memberProfileId) async {
    if (!_canModifySelection) return;
    if (_selectionId == null) return;

    final selectedRow = _selected.firstWhere(
      (r) => r['member_profile_id']?.toString() == memberProfileId,
      orElse: () => <String, dynamic>{},
    );

    final acceptance = (selectedRow['acceptance'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    if (acceptance == 'accepted') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Remove accepted player?'),
          content: const Text(
            'This player has already accepted selection. Remove them from the selected team?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    try {
      final fixtureId = widget.fixture['id']?.toString();
      if (fixtureId == null || fixtureId.isEmpty) {
        throw Exception('Fixture id missing.');
      }

      final client = Supabase.instance.client;

      final updated = await client
          .from('team_selection_members')
          .update({'is_selected': false})
          .eq('team_selection_id', _selectionId!)
          .eq('member_profile_id', memberProfileId)
          .select('member_profile_id, is_selected');

      if ((updated as List).isEmpty) {
        throw Exception('No team selection row was updated.');
      }

      await client
          .from('fixture_rink_assignments')
          .delete()
          .eq('fixture_id', fixtureId)
          .eq('member_profile_id', memberProfileId);

      if (!mounted) return;

      setState(() {
        _selected.removeWhere(
          (r) => r['member_profile_id']?.toString() == memberProfileId,
        );

        // If the player was already assigned to a team/position, remove that
        // local assignment as well. The database delete above has already made
        // the persisted state match this.
        for (final byPosition in _assignmentsByRink.values) {
          byPosition.removeWhere(
            (_, row) => row['member_profile_id']?.toString() == memberProfileId,
          );
        }
        _assignmentsByRink.removeWhere((_, byPosition) => byPosition.isEmpty);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    }
  }

  Widget _poolRow(Map<String, dynamic> r) {
    final memberId = r['member_profile_id'] as String;
    final mp = r['member_profiles'] as Map<String, dynamic>?;
    final name = _displayNameWithPreferredPosition(mp);
    final rsvp =
        r['rsvp_status']?.toString().toLowerCase() ??
        r['status']?.toString().toLowerCase() ??
        '';

    final sel = _selectedRowFor(memberId);
    final isSelected = sel != null;

    final availabilityText = rsvp == 'yes'
        ? 'Available'
        : rsvp == 'no'
        ? 'Not available'
        : rsvp == 'maybe'
        ? 'Maybe'
        : 'No response yet';

    Color? tileColor;
    if (rsvp == 'yes') {
      tileColor = const Color(0xFFE8F5E9); // soft green
    } else if (rsvp == 'no') {
      tileColor = const Color(0xFFFFEBEE); // soft red
    } else if (rsvp == 'maybe') {
      tileColor = const Color(0xFFFFF8E1); // soft amber
    }

    return Card(
      color: tileColor,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: isSelected
            ? const Icon(Icons.check, size: 18)
            : const SizedBox(width: 18),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Row(
          children: [
            Text(availabilityText),
            const SizedBox(width: 8),

            if (rsvp == 'yes')
              const Icon(Icons.check_circle, size: 14, color: Colors.green),

            if (rsvp == 'no')
              const Icon(Icons.cancel, size: 14, color: Colors.red),

            if (rsvp == 'maybe')
              const Icon(Icons.help, size: 14, color: Colors.orange),
          ],
        ),
        onTap: _canModifySelection
            ? () async {
                await _togglePlayer(memberId);
                _keepTeamPoolOnScreen();
              }
            : null,
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredSelected {
    return _selected.where((s) {
      final role = (s['role'] ?? 'player').toString().toLowerCase();
      final acceptance = (s['acceptance'] ?? 'pending')
          .toString()
          .toLowerCase();

      switch (_selectedFilter) {
        case 'players':
          return role == 'player';
        case 'reserves':
          return role == 'reserve';
        case 'opponents':
          return role == 'opponent';
        case 'markers':
          return role == 'marker';
        case 'pending':
          return acceptance == 'pending';
        case 'accepted':
          return acceptance == 'accepted';
        case 'declined':
          return acceptance == 'declined';
        case 'not_allocated':
          return !_isSelectedMemberAllocated(s);
        default:
          return true;
      }
    }).toList();
  }

  Future<void> _sendAcceptanceReminders(List<Map<String, dynamic>> rows) async {
    if (!_canSendReminders) return;
    if (_selectionId == null) return;

    final fixtureId = widget.fixture['id']?.toString();
    if (fixtureId == null || fixtureId.isEmpty) return;

    final targetIds = rows
        .where((r) {
          final acceptance = (r['acceptance'] ?? 'pending')
              .toString()
              .toLowerCase();
          return acceptance == 'pending';
        })
        .map((r) => r['member_profile_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (targetIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pending players to remind.')),
      );
      return;
    }

    final fixtureLabel =
        (widget.fixture['team_name']?.toString().trim().isNotEmpty ?? false)
        ? widget.fixture['team_name'].toString().trim()
        : 'Fixture';

    final payload = targetIds.map((targetId) {
      return {
        'event_type': 'acceptance_reminder',
        'member_profile_id': _currentMemberProfileId,
        'target_member_profile_id': targetId,
        'fixture_id': fixtureId,
        'team_selection_id': _selectionId,
        'payload': {
          'fixture_label': fixtureLabel,
          'fixture_date': widget.fixture['start_at']?.toString(),
          'home_away': widget.fixture['is_home'] == true ? 'Home' : 'Away',
          'venue_name':
              widget.fixture['venue_name']?.toString() ??
              widget.fixture['opponent_name']?.toString() ??
              '',
        },
        'status': 'pending',
      };
    }).toList();

    await _client.from('notification_queue').insert(payload);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Reminder queued for ${targetIds.length} player(s).'),
      ),
    );
  }

  Set<String> _memberIdsAlreadyInAddPeopleList() {
    final ids = <String>{};

    // 1) Anyone already selected into the actual team
    for (final r in _selected) {
      final id = r['member_profile_id']?.toString();
      if (id != null && id.isNotEmpty) {
        ids.add(id);
      }
    }

    // 2) Anyone already visible in the candidate/pool list
    // This matters because the Add Players picker is adding people
    // to the source list, not directly to the final selected team.
    for (final r in _pool) {
      final id = r['member_profile_id']?.toString();
      if (id != null && id.isNotEmpty) {
        ids.add(id);
      }
    }

    return ids;
  }

  Widget _buildIntegratedTeamAssignmentsSection() {
    if (_selectionId == null) return const SizedBox.shrink();

    if (_rinks.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Team positions',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'No teams have been created for this fixture yet.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final required = _rinks.fold<int>(
      0,
      (total, rink) => total + _asInt(rink['players_per_rink']),
    );

    final assigned = _currentAssignmentPayload().length;
    final remaining = required - assigned;

    return Card(
      margin: const EdgeInsets.only(top: 8, bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Team positions',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              remaining <= 0
                  ? '$assigned of $required positions filled'
                  : '$assigned of $required positions filled • $remaining remaining',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (_savingAssignments) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final useTwoColumns = constraints.maxWidth >= 720;
                final cardWidth = useTwoColumns
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth;

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final rink in _rinks)
                      SizedBox(
                        width: cardWidth,
                        child: _buildTeamAssignmentCard(rink),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamAssignmentCard(Map<String, dynamic> rink) {
    final rinkId = rink['id']?.toString() ?? '';
    final teamNo = rink['fixture_rink_no']?.toString() ?? '';
    final playersPerRink = _asInt(rink['players_per_rink']);

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Team $teamNo',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            for (var position = 1; position <= playersPerRink; position++) ...[
              _buildTeamPositionRow(
                rinkId: rinkId,
                position: position,
                playersPerRink: playersPerRink,
              ),
              if (position < playersPerRink) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTeamPositionRow({
    required String rinkId,
    required int position,
    required int playersPerRink,
  }) {
    final assignment = _assignmentFor(
      fixtureRinkId: rinkId,
      position: position,
    );

    final hasAssignment =
        assignment?['member_profile_id']?.toString().trim().isNotEmpty == true;

    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(_positionLabel(position, playersPerRink)),
        ),
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              backgroundColor: _assignmentBackgroundColor(assignment),
              foregroundColor: _assignmentForegroundColor(assignment),
              side: _assignmentBorderColor(assignment) == null
                  ? null
                  : BorderSide(color: _assignmentBorderColor(assignment)!),
            ),
            onPressed: _canAssignRinks && !_savingAssignments
                ? () => _selectAssignmentSlot(
                    context: context,
                    rinkId: rinkId,
                    position: position,
                    title: 'Select ${_positionLabel(position, playersPerRink)}',
                  )
                : null,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _assignmentLabel(assignment),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        if (hasAssignment && _canAssignRinks && !_savingAssignments) ...[
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.clear),
            onPressed: () => _clearAssignmentSlot(rinkId, position),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPublished = _status == 'published';

    final isHome = widget.fixture['is_home'] == true;

    final competitionType =
        widget.fixture['competition_type'] as Map<String, dynamic>?;
    final selectionMode = (competitionType?['selection_mode'] ?? '')
        .toString()
        .toLowerCase()
        .trim();

    final modeLabel = selectionMode == 'preselect'
        ? 'Pre-Select'
        : (widget.fixture['team_id'] != null ? 'Team' : 'RSVP');

    final pageTitle = '${isHome ? 'Home' : 'Away'} $modeLabel Management';

    final selectedIds = _selected
        .map((r) => r['member_profile_id']?.toString())
        .whereType<String>()
        .toSet();

    final visiblePool = _filterPool(
      _pool.where((r) {
        final id = r['member_profile_id']?.toString();
        return id != null && !selectedIds.contains(id);
      }).toList(),
    );

    final rinksRequired =
        int.tryParse(widget.fixture['rinks_required']?.toString() ?? '') ?? 0;
    final playersPerRink =
        int.tryParse(widget.fixture['players_per_rink']?.toString() ?? '') ?? 0;
    final requiredPlayers = rinksRequired * playersPerRink;

    final playersCount = _selected
        .where((s) => (s['role'] ?? 'player') == 'player')
        .length;
    final opponentsCount = _selected
        .where((s) => (s['role'] ?? '') == 'opponent')
        .length;
    final markersCount = _selected
        .where((s) => (s['role'] ?? '') == 'marker')
        .length;
    final reservesCount = _selected
        .where((s) => (s['role'] ?? '') == 'reserve')
        .length;

    final requiredPerSide = rinksRequired * playersPerRink;
    final requiredMarkers = _isInternalFixture && _isPreselectFixture
        ? rinksRequired
        : 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(pageTitle),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: (_canAddPeople && !effectiveReadOnly)
          ? FloatingActionButton.extended(
              onPressed: _openAddPlayersPicker,
              icon: const Icon(Icons.person_add),
              label: const Text('Add players'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : ListView(
              controller: _pageScrollController,
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ElevatedButton.icon(
                          onPressed:
                              (_selectionId == null || !_canEditRinkSetup)
                              ? null
                              : () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => RinksSetupScreen(
                                        fixtureId: widget.fixture['id']
                                            .toString(),
                                        isHome:
                                            widget.fixture['is_home'] == true,
                                      ),
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.grid_view),
                          label: const Text('Teams Setup'),
                        ),

                        const SizedBox(height: 8),

                        // Team position assignment is now integrated below.
                        if (!isPublished)
                          ElevatedButton(
                            onPressed: _canPublish ? _publish : null,
                            child: const Text('Publish Team'),
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    final msg = _buildPublishedTeamMessage();
                                    await Clipboard.setData(
                                      ClipboardData(text: msg),
                                    );
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('Team message copied'),
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.copy),
                                  label: const Text('Copy'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    final msg = _buildPublishedTeamMessage();
                                    Share.share(msg);
                                  },
                                  icon: const Icon(Icons.share),
                                  label: const Text('Share'),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isInternalFixture && _isPreselectFixture
                              ? 'Players: $playersCount / $requiredPerSide'
                              : (requiredPlayers > 0
                                    ? 'Players: $playersCount / $requiredPlayers'
                                    : 'Players: $playersCount'),
                        ),
                        if (_isInternalFixture && _isPreselectFixture) ...[
                          const SizedBox(height: 4),
                          Text('Opponents: $opponentsCount / $requiredPerSide'),
                          const SizedBox(height: 4),
                          Text('Markers: $markersCount / $requiredMarkers'),
                        ] else ...[
                          const SizedBox(height: 4),
                          Text('Reserves: $reservesCount'),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                _buildIntegratedTeamAssignmentsSection(),

                const SizedBox(height: 8),

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: _selectedFilter == 'all',
                      onSelected: (_) =>
                          setState(() => _selectedFilter = 'all'),
                    ),
                    ChoiceChip(
                      label: const Text('Players'),
                      selected: _selectedFilter == 'players',
                      onSelected: (_) =>
                          setState(() => _selectedFilter = 'players'),
                    ),
                    if (_isInternalFixture && _isPreselectFixture)
                      ChoiceChip(
                        label: const Text('Opponents'),
                        selected: _selectedFilter == 'opponents',
                        onSelected: (_) =>
                            setState(() => _selectedFilter = 'opponents'),
                      ),
                    if (_isInternalFixture && _isPreselectFixture)
                      ChoiceChip(
                        label: const Text('Markers'),
                        selected: _selectedFilter == 'markers',
                        onSelected: (_) =>
                            setState(() => _selectedFilter = 'markers'),
                      ),
                    if (!(_isInternalFixture && _isPreselectFixture))
                      ChoiceChip(
                        label: const Text('Reserves'),
                        selected: _selectedFilter == 'reserves',
                        onSelected: (_) =>
                            setState(() => _selectedFilter = 'reserves'),
                      ),
                    ChoiceChip(
                      label: const Text('Not Allocated'),
                      selected: _selectedFilter == 'not_allocated',
                      onSelected: (_) =>
                          setState(() => _selectedFilter = 'not_allocated'),
                    ),
                    ChoiceChip(
                      label: const Text('Pending'),
                      selected: _selectedFilter == 'pending',
                      onSelected: (_) =>
                          setState(() => _selectedFilter = 'pending'),
                    ),
                    ChoiceChip(
                      label: const Text('Accepted'),
                      selected: _selectedFilter == 'accepted',
                      onSelected: (_) =>
                          setState(() => _selectedFilter = 'accepted'),
                    ),
                    ChoiceChip(
                      label: const Text('Declined'),
                      selected: _selectedFilter == 'declined',
                      onSelected: (_) =>
                          setState(() => _selectedFilter = 'declined'),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                if (_canEditSelection)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.notifications_active_outlined),
                        label: const Text('Remind pending'),
                        onPressed: () => _sendAcceptanceReminders(_selected),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.filter_alt_outlined),
                        label: const Text('Remind filtered'),
                        onPressed: () =>
                            _sendAcceptanceReminders(_filteredSelected),
                      ),
                    ],
                  ),

                const SizedBox(height: 8),

                if (_selected.isEmpty)
                  const Text('No one selected yet.')
                else
                  ..._filteredSelected.map((s) {
                    final memberId = s['member_profile_id'] as String;
                    final mp = s['member_profiles'] as Map<String, dynamic>?;
                    final name = _displayNameWithPreferredPosition(mp);
                    final role = s['role']?.toString() ?? 'player';
                    final acceptance = s['acceptance']?.toString() ?? 'pending';
                    final phone = (mp?['phone'] as String?) ?? '';
                    final isAllocated = _isSelectedMemberAllocated(s);
                    final placementLabel = _selectedMemberPlacementLabel(s);

                    final acceptedByProfile =
                        s['accepted_by_profile'] as Map<String, dynamic>?;
                    final acceptedByName =
                        (acceptedByProfile?['display_name'] as String?)
                            ?.trim() ??
                        '';
                    final playerOwnId = s['member_profile_id']?.toString();
                    final acceptanceById = s['acceptance_by']?.toString();

                    final acceptedOnBehalf =
                        acceptance == 'accepted' &&
                        acceptedByName.isNotEmpty &&
                        (acceptanceById?.isNotEmpty ?? false) &&
                        acceptanceById != playerOwnId;

                    Color bgColor;
                    if (acceptance == 'accepted') {
                      bgColor = const Color(0xFFE8F5E9); // soft green
                    } else if (acceptance == 'declined') {
                      bgColor = const Color(0xFFFFEBEE); // soft red
                    } else {
                      bgColor = const Color(0xFFFFF8E1); // soft amber
                    }

                    return Card(
                      color: bgColor,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        onTap: _canModifySelection
                            ? () async => _removeSelected(memberId)
                            : null,
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (role == 'reserve') AppBadge(text: 'RESERVE'),
                            if (role == 'opponent') AppBadge(text: 'OPPONENT'),
                            if (role == 'marker') AppBadge(text: 'MARKER'),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              placementLabel,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: isAllocated
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Colors.red.shade700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              acceptance == 'accepted'
                                  ? 'Accepted'
                                  : acceptance == 'declined'
                                  ? 'Declined'
                                  : 'Awaiting response',
                            ),
                            if (acceptedOnBehalf)
                              Text(
                                'Accepted by $acceptedByName',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            if (phone.isNotEmpty)
                              Text(
                                phone,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                        trailing:
                            !_canModifySelection && !_canForceAcceptSelection
                            ? null
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!isAllocated && _canModifySelection)
                                    TextButton.icon(
                                      onPressed: () =>
                                          _returnUnallocatedMemberToPool(s),
                                      icon: const Icon(Icons.undo, size: 18),
                                      label: const Text('Return to pool'),
                                    ),
                                  PopupMenuButton<String>(
                                    onSelected: (v) async {
                                      if (v == 'player' ||
                                          v == 'reserve' ||
                                          v == 'opponent' ||
                                          v == 'marker') {
                                        if (_canModifySelection) {
                                          await _setRole(memberId, v);
                                        }
                                      } else if (v == 'accept') {
                                        if (_canForceAcceptSelection) {
                                          await _acceptOnBehalf(memberId);
                                        }
                                      } else if (v == 'remind') {
                                        await _sendAcceptanceReminders([s]);
                                      } else if (v == 'return_to_pool') {
                                        await _returnUnallocatedMemberToPool(s);
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      if (_canEditSelection)
                                        const PopupMenuItem(
                                          value: 'player',
                                          child: Text('Make player'),
                                        ),
                                      if (_canEditSelection &&
                                          _isInternalFixture &&
                                          _isPreselectFixture)
                                        const PopupMenuItem(
                                          value: 'opponent',
                                          child: Text('Make opponent'),
                                        ),
                                      if (_canEditSelection &&
                                          _isInternalFixture &&
                                          _isPreselectFixture)
                                        const PopupMenuItem(
                                          value: 'marker',
                                          child: Text('Make marker'),
                                        ),
                                      if (_canEditSelection &&
                                          !(_isInternalFixture &&
                                              _isPreselectFixture))
                                        const PopupMenuItem(
                                          value: 'reserve',
                                          child: Text('Make reserve'),
                                        ),
                                      if (!isAllocated && _canModifySelection)
                                        const PopupMenuItem(
                                          value: 'return_to_pool',
                                          child: Text('Return to pool'),
                                        ),
                                      if (_canForceAccept)
                                        const PopupMenuItem(
                                          value: 'accept',
                                          child: Text('Accept'),
                                        ),
                                      if (_canEditSelection)
                                        const PopupMenuItem(
                                          value: 'remind',
                                          child: Text('Send reminder'),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                      ),
                    );
                  }),
                const SizedBox(height: 16),

                if (_isPreselectFixture) ...[
                  Text(
                    'Additional players',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Use the Add players button to search the club list and add more players.',
                  ),
                ] else ...[
                  Card(
                    key: _teamPoolHeaderKey,
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _isTeamFixture
                                ? 'Team pool'
                                : (_usesRsvpPool
                                      ? 'RSVP pool (Yes/Maybe)'
                                      : 'Club members'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _searchCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Search members',
                              prefixIcon: Icon(Icons.search),
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (v) => setState(() => _search = v),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 420,
                            child: visiblePool.isEmpty
                                ? Align(
                                    alignment: Alignment.topLeft,
                                    child: Text(
                                      _search.trim().isEmpty
                                          ? 'No eligible members found.'
                                          : 'No members match your search.',
                                    ),
                                  )
                                : ListView.builder(
                                    primary: false,
                                    itemCount: visiblePool.length,
                                    itemBuilder: (context, index) =>
                                        _poolRow(visiblePool[index]),
                                  ),
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
}
