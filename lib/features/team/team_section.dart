import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/date_format.dart';
import 'manage_team_screen.dart';

class TeamSection extends StatefulWidget {
  final Map<String, dynamic> fixture;
  final bool readOnly;

  const TeamSection({super.key, required this.fixture, this.readOnly = false});

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;

      final fixtureId = widget.fixture['id'] as String;
      final clubId = widget.fixture['club_id'] as String;

      // who am I?
      final myId = (await client.rpc('my_member_profile_id')).toString();
      _myProfileId = myId;

      // can I manage? (admin/selector/captain in this club)
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

      // load selection header (may not exist yet)
      final sel = await client
          .from('team_selections')
          .select('id, status')
          .eq('fixture_id', fixtureId)
          .maybeSingle();

      if (sel == null) {
        // No selection yet
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

      // load members of selection
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

      setState(() {
        _players = players;
        _opponents = opponents;
        _markers = markers;
        _reserves = reserves;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
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
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(acceptance),
      ),
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
            onPressed: _load,
          ),
        ),
      );
    }

    final hasSelection = _selectionId != null;
    final isPublished = _status == 'published';
    final iAmSelected = _amISelected();
    final myAcc = _myAcceptance();

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
                        onPressed: _load,
                      ),
                      TextButton(
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ManageTeamScreen(
                                fixture: widget.fixture,
                                readOnly: widget.readOnly,
                              ),
                            ),
                          );
                          await _load();
                        },
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
              ExpansionTile(
                title: Text('Players (${_players.length})'),
                initiallyExpanded: true,
                children: _players.isEmpty
                    ? [const ListTile(title: Text('None'))]
                    : _players.map(_memberRow).toList(),
              ),

              if (isPreselectFixture)
                ExpansionTile(
                  title: Text('Opponents (${_opponents.length})'),
                  children: _opponents.isEmpty
                      ? [const ListTile(title: Text('None'))]
                      : _opponents.map(_memberRow).toList(),
                ),

              if (isPreselectFixture)
                ExpansionTile(
                  title: Text('Markers (${_markers.length})'),
                  children: _markers.isEmpty
                      ? [const ListTile(title: Text('None'))]
                      : _markers.map(_memberRow).toList(),
                ),

              if (!isPreselectFixture)
                ExpansionTile(
                  title: Text('Reserves (${_reserves.length}/3)'),
                  children: _reserves.isEmpty
                      ? [const ListTile(title: Text('None'))]
                      : _reserves.map(_memberRow).toList(),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
