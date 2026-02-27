import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/date_format.dart';

class RinkAssignmentsScreen extends StatefulWidget {
  final String fixtureId;
  final String teamSelectionId;

  const RinkAssignmentsScreen({
    super.key,
    required this.fixtureId,
    required this.teamSelectionId,
  });

  @override
  State<RinkAssignmentsScreen> createState() => _RinkAssignmentsScreenState();
}


class _RinkAssignmentsScreenState extends State<RinkAssignmentsScreen> {
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _rinks = [];
  List<Map<String, dynamic>> _pool = [];

  // For colouring dropdown options: member_profile_id values already assigned
  Set<String> _assignedMemberIds = {};

  // rinkId -> pos -> assignment row
  Map<String, Map<int, Map<String, dynamic>>> _byRink = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;

      // 1) Load rinks for this fixture
      final rinks = await client
          .from('fixture_rinks')
          .select('id, fixture_rink_no, format, players_per_rink, home_rink_label')
          .eq('fixture_id', widget.fixtureId);

      final rinkList = List<Map<String, dynamic>>.from(rinks);

      int _asInt(dynamic v) {
        if (v == null) return 0;
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse(v.toString()) ?? 0;
      }

      rinkList.sort((a, b) {
        final al = (a['home_rink_label'] as String?)?.trim();
        final bl = (b['home_rink_label'] as String?)?.trim();

        // if both labels exist, sort by label
        if (al != null && al.isNotEmpty && bl != null && bl.isNotEmpty) {
          return al.compareTo(bl);
        }

        // otherwise sort by fixture_rink_no
        final ao = _asInt(a['fixture_rink_no']);
        final bo = _asInt(b['fixture_rink_no']);
        return ao.compareTo(bo);
      });

      // 2) Load pool (players + reserves) from published team selection
      final poolRows = await client
          .from('team_selection_members')
          .select(
            'member_profile_id, role, acceptance, '
            'member_profiles(display_name)',
          )
          .eq('team_selection_id', widget.teamSelectionId)
          .inFilter('role', ['player', 'reserve']);

      // 3) Load assignments
      final asnRows = await client
          .from('fixture_rink_assignments')
          .select('fixture_rink_id, position, member_profile_id, member_profiles(display_name)')
          .eq('fixture_id', widget.fixtureId);

      // Build lookup: rinkId -> position -> assignment row
      final byRink = <String, Map<int, Map<String, dynamic>>>{};
      final assigned = <String>{};

      for (final a in List<Map<String, dynamic>>.from(asnRows)) {
        final rinkId = a['fixture_rink_id'].toString();
        final pos = _asInt(a['position']);
        final mid = a['member_profile_id']?.toString();

        byRink.putIfAbsent(rinkId, () => {});
        byRink[rinkId]![pos] = a;

        if (mid != null && mid.isNotEmpty) assigned.add(mid);
      }

      if (!mounted) return;
      setState(() {
        _rinks = rinkList;
        _pool = List<Map<String, dynamic>>.from(poolRows);
        _assignmentsByRink = byRink;
        _assignedMemberIds = assigned;
        _loading = false;
      });
    } catch (e) {
      debugPrint('RinkAssignments load error: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _formatLabel(String f) {
    if (f == 'pairs') return 'Pairs';
    if (f == 'triples') return 'Triples';
    return 'Rinks';
  }

  Future<void> _clearSlot(String rinkId, int position) async {
    try {
      await Supabase.instance.client
          .from('fixture_rink_assignments')
          .delete()
          .eq('fixture_rink_id', rinkId)
          .eq('position', position);

      await _loadAll();
    } catch (e) {
      debugPrint('RinkAssignments load error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Clear failed: $e')));
      }
    }
  }

  Future<void> _assign({
    required String rinkId,
    required int position,
    required String memberProfileId,
  }) async {
    try {
      final client = Supabase.instance.client;

      // Remove any existing occupant of this slot
      await client
          .from('fixture_rink_assignments')
          .delete()
          .eq('fixture_rink_id', rinkId)
          .eq('position', position);

      // Remove this player from any other slot in this fixture
      await client
          .from('fixture_rink_assignments')
          .delete()
          .eq('fixture_id', widget.fixtureId)
          .eq('member_profile_id', memberProfileId);

      // Insert new assignment
      await client.from('fixture_rink_assignments').insert({
        'fixture_id': widget.fixtureId,
        'fixture_rink_id': rinkId,
        'member_profile_id': memberProfileId,
        'position': position,
      });

      await _loadAll();
    } catch (e) {
      debugPrint('RinkAssignments load error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Assign failed: $e')));
      }
    }
  }

  List<DropdownMenuItem<String?>> _poolItems() {
    final items = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('—'),
      ),
    ];

    // Sort pool by name
    final sorted = [..._pool];
    sorted.sort((a, b) {
      final an = ((a['member_profiles']?['display_name']) as String?) ?? '';
      final bn = ((b['member_profiles']?['display_name']) as String?) ?? '';
      return an.compareTo(bn);
    });

    for (final p in sorted) {
      final id = p['member_profile_id'].toString();
      final mp = p['member_profiles'] as Map<String, dynamic>?;
      final name = (mp?['display_name'] as String?) ?? '(no name)';
      final role = p['role']?.toString() ?? '';
      final acc = p['acceptance']?.toString() ?? 'pending';

      final suffix = acc == 'accepted'
          ? ' ✅'
          : acc == 'declined'
              ? ' ❌'
              : ' ⏳';

      final roleTag = role == 'reserve' ? ' (R)' : '';

      items.add(
        DropdownMenuItem<String?>(
          value: id,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            color: _assignedMemberIds.contains(id)
                ? Colors.green.withOpacity(0.18)
                : Colors.red.withOpacity(0.14),
            child: Text('$name$roleTag$suffix'),
          ),
        ),
      );
    }

    return items;
  }

  String _positionLabel(int position, int playersPerRink) {
    if (position == 1) return 'Lead';
    if (position == playersPerRink) return 'Skip';

    // middle positions
    if (playersPerRink == 4) {
      return position == 2 ? '2' : '3';
    }
    if (playersPerRink == 3) {
      return '2';
    }
    return position.toString();
  }

  Widget _slotRow({
    required String rinkId,
    required int position,
    required int playersPerRink,
  }) {
    final asn = _byRink[rinkId]?[position];
    final selectedId = asn?['member_profile_id']?.toString();

    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(_positionLabel(position, playersPerRink)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<String?>(
            value: selectedId,
            isDense: true,
            decoration: const InputDecoration(labelText: 'Player'),
            items: _poolItems(),
            onChanged: (v) async {
              if (v == null) {
                await _clearSlot(rinkId, position);
              } else {
                await _assign(
                  rinkId: rinkId,
                  position: position,
                  memberProfileId: v,
                );
              }
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assign rinks & positions'),
        actions: [
          IconButton(onPressed: _loadAll, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_rinks.isEmpty)
                      const Text('No rinks created yet. Go back and set up rinks first.')
                    else
                      ..._rinks.map((r) {
                        final rinkId = r['id'].toString();
                        final order = r['fixture_rink_no'] as int;
                        final fmt = r['format'].toString();
                        final ppr = (r['players_per_rink'] is num)
                            ? (r['players_per_rink'] as num).toInt()
                            : int.tryParse(r['players_per_rink']?.toString() ?? '') ?? 0;
                        final label = (r['home_rink_label'] as String?) ?? '';

                        final heading = 'Rink $order • ${_formatLabel(fmt)}'
                            '${label.isNotEmpty ? ' • $label' : ''}';

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  heading,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 8),

                                for (int pos = 1; pos <= ppr; pos++) ...[
                                  _slotRow(
                                    rinkId: rinkId,
                                    position: pos,
                                    playersPerRink: ppr,
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                ),
    );
  }
}
