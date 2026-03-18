import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'team_permissions.dart';
import 'team_pool_add_members_screen.dart';

class TeamPoolScreen extends StatefulWidget {
  final String teamId;
  final String clubId;
  final String teamName;

  const TeamPoolScreen({
    super.key,
    required this.teamId,
    required this.clubId,
    required this.teamName,
  });

  @override
  State<TeamPoolScreen> createState() => _TeamPoolScreenState();
}

class _TeamPoolScreenState extends State<TeamPoolScreen> {
  final _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  bool _showInactive = false;

  bool _canEdit = false;
  bool _checkingPerms = true;

  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadPool(); // keep your existing load
    await _loadCanEdit();
  }

  Future<void> _loadCanEdit() async {
    setState(() => _checkingPerms = true);
    try {
      final can = await TeamPermissions.canEditTeamPool(
        clubId: widget.clubId,
        teamId: widget.teamId,
      );
      if (!mounted) return;
      setState(() {
        _canEdit = can;
        _checkingPerms = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _canEdit = false;
        _checkingPerms = false;
      });
    }
  }

  String _fullName(Map<String, dynamic>? mp) {
    if (mp == null) return '';
    final fn = (mp['first_name'] ?? '').toString().trim();
    final ln = (mp['last_name'] ?? '').toString().trim();
    final name = ('$fn $ln').trim();
    return name.isEmpty ? '(No name)' : name;
  }

  Future<void> _loadPool() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _client
          .from('team_members')
          .select(
              'id, member_profile_id, is_active, member_profiles(first_name,last_name,phone,email_address)')
          .eq('team_id', widget.teamId)
          .order('last_name', referencedTable: 'member_profiles')
          .order('first_name', referencedTable: 'member_profiles');

      final list = (res as List).cast<Map<String, dynamic>>();

      setState(() {
        _rows = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _setActive(String teamMemberId, bool isActive) async {
    try {
      await _client.from('team_members').update({'is_active': isActive}).eq('id', teamMemberId);
      await _loadPool();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e')),
      );
    }
  }

  Future<void> _openAddPlayers() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TeamPoolAddMembersScreen(
          teamId: widget.teamId,
          clubId: widget.clubId,
        ),
      ),
    );

    if (added == true) {
      await _loadPool();
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleRows = _showInactive ? _rows : _rows.where((r) => r['is_active'] == true).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Team Pool — ${widget.teamName}'),
        actions: [
          IconButton(
            onPressed: (_canEdit && !_checkingPerms) ? _openAddPlayers : null,
            icon: const Icon(Icons.person_add_alt_1),
            tooltip: (_canEdit && !_checkingPerms) ? 'Add players' : 'Read-only',
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'toggle_inactive') {
                setState(() => _showInactive = !_showInactive);
              }
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'toggle_inactive',
                checked: _showInactive,
                child: const Text('Show inactive'),
              ),
            ],
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
                      onPressed: _loadPool,
                      child: const Text('Retry'),
                    ),
                  ],
                )
              : Column(
                  children: [
                    if (!_checkingPerms && !_canEdit)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        child: Material(
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              'Read-only: only club Admin/Selector or this team’s Captain/Vice/Manager can edit the pool.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ),
                      ),

                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadPool,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: visibleRows.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final row = visibleRows[i];
                            final mp = row['member_profiles'] as Map<String, dynamic>?;
                            final name = _fullName(mp);

                            final phone = (mp?['phone'] ?? '').toString();
                            final email = (mp?['email_address'] ?? '').toString();
                            final isActive = row['is_active'] == true;

                            return ListTile(
                              title: Text(name),
                              subtitle: Text([
                                if (phone.isNotEmpty) phone,
                                if (email.isNotEmpty) email,
                                if (!isActive) 'INACTIVE',
                              ].join(' • ')),
                              trailing: !_canEdit
                                  ? null
                                  : isActive
                                      ? TextButton.icon(
                                          onPressed: () => _setActive(row['id'].toString(), false),
                                          icon: const Icon(Icons.remove_circle_outline),
                                          label: const Text('Remove'),
                                        )
                                      : TextButton.icon(
                                          onPressed: () => _setActive(row['id'].toString(), true),
                                          icon: const Icon(Icons.restore),
                                          label: const Text('Reactivate'),
                                        ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
  floatingActionButton: (_canEdit && !_checkingPerms)
    ? FloatingActionButton.extended(
        onPressed: _openAddPlayers,
        icon: const Icon(Icons.add),
        label: const Text('Add players'),
      )
    : null,
    );
  }
}