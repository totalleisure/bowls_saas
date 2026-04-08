import '../../core/widgets/app_badge.dart';
import '../clubs/club_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'captain_view_section.dart';
import 'set_captain_section.dart';
import '../team/team_section.dart';
import '../team/manage_team_screen.dart';
import '../rinks/rinks_setup_screen.dart';
import '../rinks/rink_assignments_screen.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/hex_color.dart';
import '../../features/fixtures/fixture_rsvp_section.dart';

String _formatLocalDateTime(DateTime dt) {
  final d = dt.day.toString().padLeft(2, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final y = dt.year.toString();
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$d/$m/$y $hh:$mm';
}

String _formatLocalDisplay(DateTime dt) {
  return formatWhenLocal(dt.toUtc().toIso8601String());
}

class FixtureDetailsPage extends StatefulWidget {
  final String fixtureId;
  const FixtureDetailsPage({super.key, required this.fixtureId});

  @override
  State<FixtureDetailsPage> createState() => _FixtureDetailsPageState();
}

class _FixtureDetailsPageState extends State<FixtureDetailsPage> {

  int _loadCount = 0;

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

  final _client = Supabase.instance.client;
  
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
          .select('id, team_selection_id, member_profile_id, role, acceptance, responded_at, created_at')
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
            'id, club_id, start_at, end_at, is_home, section, rinks_required, players_per_rink, orientation, '
            'team_id, team_name, competition_type_id, '
            'captain_member_profile_id, vice_captain_member_profile_id, requires_rsvp, '
            'competition_type:competition_types!fixtures_competition_type_id_fkey('
              'id, name, is_internal, selection_mode, '
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
            'ts:team_selections(id, status)'
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
        await _loadMyMemberProfileId();
        await _loadMyTeamSelection();
        await _loadTeamNameLocked();
        await _loadTeams();
        await _loadMyRsvp();
        await _loadPermissions();
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
        if (_selectedTeamId == null && _teams.isNotEmpty && (_fixture?['team_id'] != null)) {
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

  @override
  void initState() {
    super.initState();
    _load();
    _loadMyRsvp();
  }

  @override
  void dispose() {
    _teamNameCtrl.dispose();
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

    final currentUtc = DateTime.parse(currentStartAtStr).toUtc();
    final currentLocal = currentUtc.toLocal();

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
        content: Text(
          'Change fixture to:\n${_formatLocalDateTime(newLocal)}',
        ),
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
          .update({
            'start_at': newLocal.toUtc().toIso8601String(),
          })
          .eq('id', widget.fixtureId);

      _didChangeFixture = true;

      await _load();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fixture date/time updated.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update fixture: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadPermissions() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        if (!mounted) return;
        setState(() {
          _isAdmin = false;
          _isSuper = false;
          _canEditFixture = false;
          _canDeleteFixture = false;
          _canAssignCaptaincy = false;
          _canManageTeam = false;
          _canViewTeam = false;
        });
        return;
      }

      String? myProfileId = _myMemberProfileId;

      if (myProfileId == null) {
        final mp = await _client
            .from('member_profiles')
            .select('id')
            .eq('user_id', userId)
            .maybeSingle();

        myProfileId = mp?['id']?.toString();
      }

      final clubId = _fixture?['club_id']?.toString();
      if (clubId == null || myProfileId == null) {
        if (!mounted) return;
        setState(() {
          _isAdmin = false;
          _isSuper = false;
          _canEditFixture = false;
          _canDeleteFixture = false;
          _canAssignCaptaincy = false;
          _canManageTeam = false;
          _canViewTeam = false;
        });
        return;
      }

      final adminRow = await _client
          .from('club_memberships')
          .select('id')
          .eq('club_id', clubId)
          .eq('member_profile_id', myProfileId)
          .eq('role', 'admin')
          .maybeSingle();

      final selectorRow = await _client
          .from('club_memberships')
          .select('id')
          .eq('club_id', clubId)
          .eq('member_profile_id', myProfileId)
          .eq('role', 'selector')
          .maybeSingle();

      bool superFlag = false;
      try {
        final suRow = await _client
            .from('app_superusers')
            .select('user_id')
            .eq('user_id', userId)
            .maybeSingle();
        superFlag = suRow != null;
      } catch (_) {
        superFlag = false;
      }

      final fixtureCaptainId = _fixture?['captain_member_profile_id']?.toString();
      final fixtureViceCaptainId =
          _fixture?['vice_captain_member_profile_id']?.toString();

      final isAdmin = adminRow != null;
      final isSelector = selectorRow != null;
      final isSuper = superFlag;
      final isFixtureCaptain =
          fixtureCaptainId != null && fixtureCaptainId == myProfileId;
      final isFixtureVice =
          fixtureViceCaptainId != null && fixtureViceCaptainId == myProfileId;

      final canEditFixture = isSuper || isAdmin;
      final canDeleteFixture = isSuper || isAdmin;
      final canAssignCaptaincy = isSuper || isAdmin;
      final canManageTeam =
          isSuper || isAdmin || isSelector || isFixtureCaptain || isFixtureVice;

      final myTeamSelection = _myTeamSelection != null;
      final canViewTeam = canManageTeam || myTeamSelection;

      if (!mounted) return;
      setState(() {
        _isAdmin = isAdmin;
        _isSuper = isSuper;
        _canEditFixture = canEditFixture;
        _canDeleteFixture = canDeleteFixture;
        _canAssignCaptaincy = canAssignCaptaincy;
        _canManageTeam = canManageTeam;
        _canViewTeam = canViewTeam;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isAdmin = false;
        _isSuper = false;
        _canEditFixture = false;
        _canDeleteFixture = false;
        _canAssignCaptaincy = false;
        _canManageTeam = false;
        _canViewTeam = false;
      });
    }
    debugPrint('Fixture permissions: '
        'admin=$_isAdmin '
        'super=$_isSuper '
        'edit=$_canEditFixture '
        'delete=$_canDeleteFixture '
        'assignCaptain=$_canAssignCaptaincy '
        'manageTeam=$_canManageTeam '
        'viewTeam=$_canViewTeam');    
  }
  
  Future<void> _confirmAndDelete() async {
    if (!_canDeleteFixture) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete fixture?'),
        content: const Text(
          'This will delete the fixture and all associated data (RSVPs, rinks, assignments, selections).\n\n'
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
      await _client.rpc('delete_fixture', params: {
        'p_fixture_id': widget.fixtureId,
      });

      if (!mounted) return;
      Navigator.pop(context, true); // tell previous screen to refresh
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('RSVP set to $label')),
      );
    } catch (e) {
      // Revert highlight if DB write fails
      if (mounted) {
        setState(() => _myRsvp = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('RSVP error: $e')),
        );
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
    final startLocal = DateTime.parse(_fixture!['start_at']).toLocal();

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

    await Supabase.instance.client
        .from('fixtures')
        .update({
          'start_at': newStart.toUtc().toIso8601String(),
        })
        .eq('id', widget.fixtureId);

    _didChangeFixture = true;
    await _load();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to respond: $e')),
      );
    }

    await _load();
  }

  Future<void> _editEndTime() async {
    final startLocal = DateTime.parse(_fixture!['start_at']).toLocal();

    final endStr = _fixture!['end_at']?.toString();
    final endLocal = (endStr == null || endStr.isEmpty)
        ? startLocal.add(const Duration(hours: 2))
        : DateTime.parse(endStr).toLocal();

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: endLocal,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(endLocal),
    );
    if (pickedTime == null || !mounted) return;

    final newEnd = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    if (!newEnd.isAfter(startLocal)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End date/time must be after start date/time.')),
      );
      return;
    }

    await Supabase.instance.client
        .from('fixtures')
        .update({
          'end_at': newEnd.toUtc().toIso8601String(),
        })
        .eq('id', widget.fixtureId);

    _didChangeFixture = true;
    await _load();
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
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
        body: Center(
          child: Text('Error: $_error'),
        ),
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

    final competitionTypeName =
        (competitionType?['name'] ?? '').toString().trim();
    final competitionSelectionMode =
        (competitionType?['selection_mode'] ?? '').toString().trim();
    final isInternalFixtureType =
        competitionType?['is_internal'] == true;

    final isPreselectFixture = competitionSelectionMode == 'preselect';
    final isTeamFixture =
        (_isTeamFixtureUi || competitionSelectionMode == 'team') &&
        !isPreselectFixture;
    final isRsvpFixture =
        (fixture['requires_rsvp'] == true) && !isPreselectFixture;    

    final isHome = (fixture['is_home'] as bool?) ?? true;

    final modeLabel = isPreselectFixture
        ? 'Pre-Select'
        : (isTeamFixture ? 'Team' : 'RSVP');

    final pageTitle =
        '${isHome ? 'Home' : 'Away'} $modeLabel Fixture Details';

    final fixtureLabel = (fixture['team_name'] ?? '').toString().trim();
    final displayFixtureLabel =
        competitionTypeName.isNotEmpty ? competitionTypeName : fixtureLabel;

    final teamRow = fixture['team'] as Map<String, dynamic>?;
    final teamName = (teamRow?['name'] ?? fixture['team_name'] ?? '').toString().trim();

    final startAt = fixture['start_at'] as String?;
    final when = startAt != null
        ? DateTime.parse(startAt).toLocal()
        : DateTime.now();

    final endAt = fixture['end_at'] as String?;
    final endWhen = endAt != null
        ? DateTime.parse(endAt).toLocal()
        : when.add(const Duration(hours: 2));

    final venue = (fixture['venue']?['name'] as String?) ?? '';
    final opponent = (fixture['opponent_venue']?['name'] ?? '').toString().trim();
    final green = (fixture['green_areas']?['name'] as String?) ?? '';
    final section = (fixture['section'] as String?) ?? '';

    String buildFixtureHeader({
      required bool isHome,
      required bool isInternal,
      required bool isPreselectFixture,
      required bool isTeamFixture,
      required String opponent,
      required String teamName,
      required String fixtureLabel,
    }) {
      final cleanOpponent = opponent.trim();
      final cleanTeamName = teamName.trim();
      final cleanFixtureLabel = fixtureLabel.trim();

      if (isInternal || isPreselectFixture) {
        if (cleanFixtureLabel.isNotEmpty) {
          return 'Internal $cleanFixtureLabel';
        }
        return 'Internal Fixture';
      }

      if (isHome) {
        if (isTeamFixture) {
          if (cleanTeamName.isNotEmpty && cleanOpponent.isNotEmpty) {
            return 'Home $cleanTeamName v $cleanOpponent';
          }
          if (cleanTeamName.isNotEmpty) {
            return 'Home $cleanTeamName';
          }
          if (cleanOpponent.isNotEmpty) {
            return 'Home against $cleanOpponent';
          }
          return 'Home Fixture';
        }

        if (cleanOpponent.isNotEmpty) {
          return 'Home against $cleanOpponent';
        }
        return 'Home Fixture';
      }

      // Away
      if (isTeamFixture) {
        if (cleanOpponent.isNotEmpty && cleanTeamName.isNotEmpty) {
          return 'Away at $cleanOpponent v $cleanTeamName';
        }
        if (cleanOpponent.isNotEmpty) {
          return 'Away at $cleanOpponent';
        }
        if (cleanTeamName.isNotEmpty) {
          return 'Away v $cleanTeamName';
        }
        return 'Away Fixture';
      }

      if (cleanOpponent.isNotEmpty) {
        return 'Away at $cleanOpponent';
      }
      return 'Away Fixture';
    }

    final matchHeader = buildFixtureHeader(
      isHome: isHome,
      isInternal: isInternalFixtureType,
      isPreselectFixture: isPreselectFixture,
      isTeamFixture: isTeamFixture,
      opponent: opponent,
      teamName: teamName,
      fixtureLabel: displayFixtureLabel,
    );

    final fixtureTeamName =
        (fixture['team']?['name'] ?? fixture['team_name'] ?? '')
            .toString()
            .trim();

    final lockedFixtureLabel = isPreselectFixture
        ? 'Pre-Select Fixture'
        : isTeamFixture
            ? 'Team Fixture'
            : 'RSVP Fixture';

    final isWorkflowLocked = _teamNameLocked || isPreselectFixture;

    final fixtureTypeLabel = isPreselectFixture
        ? 'Pre-Select Fixture'
        : isTeamFixture
            ? 'Team Fixture'
            : 'RSVP Fixture';

    final fixtureTypeHelpText = isPreselectFixture
        ? 'Players are pre-selected for this fixture. This workflow cannot be changed here.'
        : isWorkflowLocked
            ? 'This fixture workflow is locked because responses, selections, or assignments already exist.'
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
      teamSelectionStatus =
          (ts.first as Map<String, dynamic>?)?['status']?.toString();
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
        ],
      ),
      body: ListView(
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
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: fixtureTypeFg,
                      ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Text(
            matchHeader,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),

          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppBadge(text: isHome ? 'HOME' : 'AWAY'),

              if (displayFixtureLabel.isNotEmpty)
                AppBadge(text: displayFixtureLabel.toUpperCase()),

              if (isHome && green.isNotEmpty)
                AppBadge(text: 'GREEN: $green'),

              if (showOrientation)
                AppBadge(text: 'ORIENTATION: ${(orientation ?? 'NOT SET').toUpperCase()}'),

              AppBadge(text: section.toUpperCase()),
              AppBadge(text: _formatLabel(ppr).toUpperCase()),
              AppBadge(text: '$rinks TEAMS'),

              if (captainName.isNotEmpty) AppBadge(text: 'CAPT: $captainName'),
              if (viceName.isNotEmpty) AppBadge(text: 'VICE: $viceName'),
            ],
          ),
          
          const SizedBox(height: 16),
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
                        decoration: const InputDecoration(
                          hintText: 'Enter fixture details (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),
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
                                      throw Exception('Please select a team.');
                                    }

                                    final selectedTeam = _teams.firstWhere(
                                      (t) => t['id'].toString() == _selectedTeamId,
                                      orElse: () => <String, dynamic>{},
                                    );

                                    final selectedTeamName =
                                        (selectedTeam['name'] ?? '').toString().trim();

                                    await Supabase.instance.client
                                        .from('fixtures')
                                        .update({
                                          'team_id': _selectedTeamId,
                                          'team_name': selectedTeamName.isEmpty
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
                                          'team_name': lbl.isEmpty ? null : lbl,
                                        })
                                        .eq('id', widget.fixtureId);
                                  }

                                  _didChangeFixture = true;
                                  await _load();
                                } catch (e) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Failed to save: $e')),
                                  );
                                } finally {
                                  if (mounted) setState(() => _savingTeam = false);
                                }
                              },
                        child: _savingTeam
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Start'),
                            const SizedBox(height: 6),
                            OutlinedButton(
                              onPressed: _canEditFixture ? _editStartTime : null,
                              child: Text(_formatLocalDisplay(when)),   
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
                              onPressed: _canEditFixture ? _editStartTime : null,
                              child: Text(_formatLocalDisplay(endWhen)),
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

          SetCaptainSection(
            fixture: fixture,
            readOnly: !_canAssignCaptaincy,
          ),

          if (canRespondToTeamSelection) ...[
            const SizedBox(height: 16),
            Text(
              'Team selection',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('You have been selected for this fixture.'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      children: [
                        ElevatedButton(
                          onPressed: () => _respondToTeamSelection('accepted'),
                          child: const Text('Accept'),
                        ),
                        OutlinedButton(
                          onPressed: () => _respondToTeamSelection('declined'),
                          child: const Text('Decline'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),
          if (showRsvpControls) ...[
            const SizedBox(height: 16),
            Text('Your availability', style: Theme.of(context).textTheme.titleMedium),
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

          const SizedBox(height: 12),
          if (isRsvpFixture && !isPublished) ...[
            CaptainViewSection(fixture: fixture),
          ],
          
          if (canViewTeam) ...[
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
      ),
    );
  }
}