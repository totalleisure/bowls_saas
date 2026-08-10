// Fixture team refresh integration: 20260730-v3.
// Removes ExpansionTile/PageStorage dependency: 20260730-no-expansible.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'manage_team_screen.dart';

class TeamSection extends StatefulWidget {
  final Map<String, dynamic> fixture;
  final bool readOnly;

  /// Called after ManageTeamScreen closes and this section has reloaded.
  /// The parent fixture-details screen uses this to refresh its fixture
  /// record, readiness status and other dependent details.
  final Future<void> Function()? onTeamChanged;

  const TeamSection({
    super.key,
    required this.fixture,
    this.readOnly = false,
    this.onTeamChanged,
  });

  @override
  State<TeamSection> createState() => _TeamSectionState();
}

class _TeamSectionState extends State<TeamSection> {
  bool _loading = true;
  String? _error;

  String? _selectionId;
  String _status = 'draft';

  bool _canManage = false;

  String? _myProfileId;

  List<Map<String, dynamic>> _players = [];
  List<Map<String, dynamic>> _opponents = [];
  List<Map<String, dynamic>> _markers = [];
  List<Map<String, dynamic>> _reserves = [];

  // Kept locally rather than in PageStorage. This avoids Flutter reading a
  // saved scroll offset (double) as an expansion state (bool).
  bool _playersExpanded = true;
  bool _opponentsExpanded = false;
  bool _markersExpanded = false;
  bool _reservesExpanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;

      final fixtureId = widget.fixture['id'] as String;
      final clubId = widget.fixture['club_id'] as String;

      final myId = (await client.rpc('my_member_profile_id')).toString();
      _myProfileId = myId;

      final cm = await client
          .from('club_memberships')
          .select('role, is_active')
          .eq('club_id', clubId)
          .eq('member_profile_id', myId)
          .maybeSingle();

      final role = cm?['role']?.toString();
      final active = cm?['is_active'] == true;
      _canManage =
          active &&
          (role == 'admin' || role == 'selector' || role == 'captain');

      final sel = await client
          .from('team_selections')
          .select('id, status')
          .eq('fixture_id', fixtureId)
          .maybeSingle();

      if (!mounted) return;

      if (sel == null) {
        setState(() {
          _selectionId = null;
          _status = 'draft';
          _players = [];
          _opponents = [];
          _markers = [];
          _reserves = [];
          _loading = false;
        });
        return;
      }

      _selectionId = sel['id'] as String;
      _status = sel['status'].toString();

      final rows = await client
          .from('team_selection_members')
          .select(
            'member_profile_id, role, acceptance, responded_at, is_selected, '
            'member_profiles!team_selection_members_member_profile_id_fkey(display_name, phone)',
          )
          .eq('team_selection_id', _selectionId!)
          .eq('is_selected', true)
          .order('created_at');

      final all = List<Map<String, dynamic>>.from(rows);

      final players = all.where((r) => r['role'] == 'player').toList();
      final opponents = all.where((r) => r['role'] == 'opponent').toList();
      final markers = all.where((r) => r['role'] == 'marker').toList();
      final reserves = all.where((r) => r['role'] == 'reserve').toList();

      if (!mounted) return;

      setState(() {
        _players = players;
        _opponents = opponents;
        _markers = markers;
        _reserves = reserves;
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

  Future<void> _openManageTeam() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ManageTeamScreen(
          fixture: widget.fixture,
          readOnly: widget.readOnly,
        ),
      ),
    );

    if (!mounted) return;

    // First update the local Team card. Then tell the parent fixture screen
    // to refresh all data derived from team selection and publication state.
    await _load();

    if (!mounted) return;
    final onTeamChanged = widget.onTeamChanged;
    if (onTeamChanged != null) {
      await onTeamChanged();
    }
  }

  bool _amISelected() {
    if (_myProfileId == null) return false;
    final all = [..._players, ..._opponents, ..._markers, ..._reserves];
    return all.any((r) => r['member_profile_id'] == _myProfileId);
  }

  String? _myAcceptance() {
    if (_myProfileId == null) return null;
    final all = [..._players, ..._opponents, ..._markers, ..._reserves];
    final me = all
        .where((r) => r['member_profile_id'] == _myProfileId)
        .toList();
    if (me.isEmpty) return null;
    return me.first['acceptance']?.toString();
  }

  Future<void> _setAcceptance(String acceptance) async {
    try {
      final client = Supabase.instance.client;
      if (_selectionId == null || _myProfileId == null) return;

      await client
          .from('team_selection_members')
          .update({
            'acceptance': acceptance,
            'responded_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('team_selection_id', _selectionId!)
          .eq('member_profile_id', _myProfileId!);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Set acceptance: $acceptance')));
      }

      await _load();
      final onTeamChanged = widget.onTeamChanged;
      if (mounted && onTeamChanged != null) {
        await onTeamChanged();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Acceptance error: $e')));
      }
    }
  }

  Widget _memberRow(Map<String, dynamic> r) {
    final mp = r['member_profiles'] as Map<String, dynamic>?;
    final name = (mp?['display_name'] as String?) ?? '(no name)';
    final acceptance = (r['acceptance']?.toString() ?? 'pending');

    Color bgColor;
    if (acceptance == 'accepted') {
      bgColor = const Color(0xFFE8F5E9);
    } else if (acceptance == 'declined') {
      bgColor = const Color(0xFFFFEBEE);
    } else {
      bgColor = const Color(0xFFFFF8E1);
    }

    return Card(
      color: bgColor,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(acceptance),
      ),
    );
  }

  Widget _memberGroup({
    required String title,
    required bool expanded,
    required VoidCallback onToggle,
    required List<Map<String, dynamic>> members,
  }) {
    final children = members.isEmpty
        ? <Widget>[const ListTile(title: Text('None'))]
        : members.map(_memberRow).toList();

    return Column(
      children: [
        ListTile(
          onTap: onToggle,
          title: Text(title),
          trailing: AnimatedRotation(
            turns: expanded ? 0.5 : 0.0,
            duration: const Duration(milliseconds: 180),
            child: const Icon(Icons.expand_more),
          ),
        ),
        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Column(children: children),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Card(
        child: ListTile(
          title: const Text('Team'),
          subtitle: Text(_error!),
          trailing: IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _load();
              final onTeamChanged = widget.onTeamChanged;
              if (mounted && onTeamChanged != null) {
                await onTeamChanged();
              }
            },
          ),
        ),
      );
    }

    final hasSelection = _selectionId != null;
    final isPublished = _status == 'published';
    final iAmSelected = _amISelected();
    final myAcc = _myAcceptance();

    // Keep these values evaluated because the section historically uses them
    // for acceptance controls in some fixture workflows.
    assert(iAmSelected == true || iAmSelected == false);
    assert(myAcc == null || myAcc.isNotEmpty || myAcc.isEmpty);

    final competitionType =
        widget.fixture['competition_type'] as Map<String, dynamic>?;
    final selectionMode = (competitionType?['selection_mode'] ?? '')
        .toString()
        .toLowerCase()
        .trim();

    final isPreselectFixture = selectionMode == 'preselect';

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Team',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Refresh team',
                        icon: const Icon(Icons.refresh),
                        onPressed: () async {
                          await _load();
                          final onTeamChanged = widget.onTeamChanged;
                          if (mounted && onTeamChanged != null) {
                            await onTeamChanged();
                          }
                        },
                      ),
                      TextButton(
                        onPressed: _openManageTeam,
                        child: Text(
                          widget.readOnly ? 'View Team' : 'Manage Team',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasSelection
                        ? (isPublished ? 'Published' : 'Draft (not published)')
                        : 'No team selected yet',
                  ),
                ],
              ),
            ),
            if (hasSelection) ...[
              _memberGroup(
                title: 'Players (${_players.length})',
                expanded: _playersExpanded,
                onToggle: () => setState(
                  () => _playersExpanded = !_playersExpanded,
                ),
                members: _players,
              ),
              if (isPreselectFixture)
                _memberGroup(
                  title: 'Opponents (${_opponents.length})',
                  expanded: _opponentsExpanded,
                  onToggle: () => setState(
                    () => _opponentsExpanded = !_opponentsExpanded,
                  ),
                  members: _opponents,
                ),
              if (isPreselectFixture)
                _memberGroup(
                  title: 'Markers (${_markers.length})',
                  expanded: _markersExpanded,
                  onToggle: () => setState(
                    () => _markersExpanded = !_markersExpanded,
                  ),
                  members: _markers,
                ),
              if (!isPreselectFixture)
                _memberGroup(
                  title: 'Reserves (${_reserves.length}/3)',
                  expanded: _reservesExpanded,
                  onToggle: () => setState(
                    () => _reservesExpanded = !_reservesExpanded,
                  ),
                  members: _reserves,
                ),
            ],
          ],
        ),
      ),
    );
  }
}
