import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'team_permissions.dart';
import 'package:bowls_saas/core/widgets/club_member_picker_page.dart';

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

    final name = [
      if (ln.isNotEmpty) ln,
      if (fn.isNotEmpty) fn,
    ].join(', ');

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

      list.sort((a, b) {
        final amp = a['member_profiles'] as Map<String, dynamic>?;
        final bmp = b['member_profiles'] as Map<String, dynamic>?;

        final aLast = (amp?['last_name'] ?? '').toString().toLowerCase();
        final bLast = (bmp?['last_name'] ?? '').toString().toLowerCase();

        final lastCompare = aLast.compareTo(bLast);
        if (lastCompare != 0) return lastCompare;

        final aFirst = (amp?['first_name'] ?? '').toString().toLowerCase();
        final bFirst = (bmp?['first_name'] ?? '').toString().toLowerCase();

        return aFirst.compareTo(bFirst);
      });

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
    final alreadyInPool = _rows
        .map((r) => r['member_profile_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();

    final selectedIds = await Navigator.of(context).push<List<String>?>(
      MaterialPageRoute(
        builder: (_) => ClubMemberPickerPage(
          clubId: widget.clubId,
          title: 'Add players to ${widget.teamName}',

          // We are choosing from the whole club, not only existing team members.
          teamId: null,

          // Team Pool is not fixture-section-led unless you pass a fixture id.
          fixtureId: null,
          useFixtureSection: false,
          initialSectionFilter: MemberPickerSectionFilter.open,

          allowMultiple: true,

          // This stops existing pool members appearing.
          excludeMemberProfileIds: alreadyInPool,
        ),
      ),
    );

    if (!mounted || selectedIds == null || selectedIds.isEmpty) return;

    setState(() => _loading = true);

    try {
      final payload = selectedIds.map((memberProfileId) {
        return {
          'team_id': widget.teamId,
          'member_profile_id': memberProfileId,
          'is_active': true,
        };
      }).toList();

      await _client.from('team_members').insert(payload);

      await _loadPool();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add players: $e')),
      );
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