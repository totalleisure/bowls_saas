import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TeamPoolAddMembersScreen extends StatefulWidget {
  final String teamId;
  final String clubId;

  const TeamPoolAddMembersScreen({
    super.key,
    required this.teamId,
    required this.clubId,
  });

  @override
  State<TeamPoolAddMembersScreen> createState() => _TeamPoolAddMembersScreenState();
}

class _TeamPoolAddMembersScreenState extends State<TeamPoolAddMembersScreen> {
  final _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  String _search = '';

  // club candidates: list of rows from club_memberships with embedded member_profiles
  List<Map<String, dynamic>> _candidates = [];

  // active pool member_profile_ids (so we can exclude/disable)
  Set<String> _activePool = {};

  // selected member_profile_ids to add
  Set<String> _selected = {};

  String _fullName(Map<String, dynamic>? mp) {
    if (mp == null) return '';
    final fn = (mp['first_name'] ?? '').toString().trim();
    final ln = (mp['last_name'] ?? '').toString().trim();
    final name = ('$fn $ln').trim();
    return name.isEmpty ? '(No name)' : name;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _selected = {};
    });

    try {
      // 1) Load active pool member_profile_ids
      final poolRes = await _client
          .from('team_members')
          .select('member_profile_id, is_active')
          .eq('team_id', widget.teamId);

      final poolList = (poolRes as List).cast<Map<String, dynamic>>();
      final activeIds = <String>{};
      for (final r in poolList) {
        if (r['is_active'] == true) {
          activeIds.add(r['member_profile_id'].toString());
        }
      }

      // 2) Load club candidates
      final clubRes = await _client
          .from('club_memberships')
          .select('member_profile_id, is_active, role, member_profiles(first_name,last_name,phone,email_address)')
          .eq('club_id', widget.clubId)
          .eq('is_active', true)
          .order('last_name', referencedTable: 'member_profiles')
          .order('first_name', referencedTable: 'member_profiles');

      final candidates = (clubRes as List).cast<Map<String, dynamic>>();

      setState(() {
        _activePool = activeIds;
        _candidates = candidates;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredCandidates {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _candidates;

    return _candidates.where((row) {
      final mp = row['member_profiles'] as Map<String, dynamic>?;
      final name = _fullName(mp).toLowerCase();
      final phone = (mp?['phone'] ?? '').toString().toLowerCase();
      final email = (mp?['email_address'] ?? '').toString().toLowerCase();
      return name.contains(q) || phone.contains(q) || email.contains(q);
    }).toList();
  }

  Future<void> _addSelected() async {
    if (_selected.isEmpty) return;

    setState(() => _loading = true);

    try {
      await _client.from('team_members').upsert(
        _selected.map((mpId) => {
          'team_id': widget.teamId,
          'member_profile_id': mpId,
          'is_active': true,
        }).toList(),
        onConflict: 'team_id,member_profile_id',
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _loading = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Add failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredCandidates;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add players to pool'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _addSelected,
            child: Text('Add (${_selected.length})'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('Error:\n$_error'),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _load,
                      child: const Text('Retry'),
                    ),
                  ],
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search by name, phone, or email',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() => _search = v),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final row = rows[i];
                          final mpId = row['member_profile_id'].toString();
                          final mp = row['member_profiles'] as Map<String, dynamic>?;
                          final name = _fullName(mp);
                          final phone = (mp?['phone'] ?? '').toString();
                          final email = (mp?['email_address'] ?? '').toString();

                          final alreadyActive = _activePool.contains(mpId);
                          final selected = _selected.contains(mpId);

                          return ListTile(
                            enabled: !alreadyActive,
                            title: Text(name),
                            subtitle: Text([
                              if (phone.isNotEmpty) phone,
                              if (email.isNotEmpty) email,
                              if (alreadyActive) 'Already in pool',
                            ].join(' • ')),
                            trailing: alreadyActive
                                ? const Icon(Icons.check_circle, color: Colors.grey)
                                : Checkbox(
                                    value: selected,
                                    onChanged: (v) {
                                      setState(() {
                                        if (v == true) {
                                          _selected.add(mpId);
                                        } else {
                                          _selected.remove(mpId);
                                        }
                                      });
                                    },
                                  ),
                            onTap: alreadyActive
                                ? null
                                : () {
                                    setState(() {
                                      if (selected) {
                                        _selected.remove(mpId);
                                      } else {
                                        _selected.add(mpId);
                                      }
                                    });
                                  },
                          );
                        },
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton.icon(
            onPressed: (_loading || _selected.isEmpty) ? null : _addSelected,
            icon: const Icon(Icons.person_add_alt_1),
            label: Text('Add selected (${_selected.length})'),
          ),
        ),
      ),
    );
  }
}