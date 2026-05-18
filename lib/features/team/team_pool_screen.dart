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

  final _teamNameController = TextEditingController();
  final _descriptionController = TextEditingController();

  bool _loading = true;
  bool _savingTeam = false;
  String? _error;
  bool _showInactive = false;

  bool _canEdit = false;
  bool _checkingPerms = true;

  List<Map<String, dynamic>> _rows = [];

  String _section = 'open';
  String? _managerMemberProfileId;
  String? _captainMemberProfileId;
  String? _viceCaptainMemberProfileId;

  String _managerName = '';
  String _captainName = '';
  String _viceCaptainName = '';

  @override
  void initState() {
    super.initState();
    _teamNameController.text = widget.teamName;
    _init();
  }

  @override
  void dispose() {
    _teamNameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await Future.wait([
      _loadTeamDetails(),
      _loadPool(),
      _loadCanEdit(),
    ]);
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _loadTeamDetails(),
      _loadPool(),
    ]);
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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _canEdit = false;
        _checkingPerms = false;
      });
    }
  }

  String _clean(String? value) => (value ?? '').trim();

  String _memberDisplayName(Map<String, dynamic>? mp) {
    if (mp == null) return '';

    final fn = _clean(mp['first_name']?.toString());
    final ln = _clean(mp['last_name']?.toString());
    final preferred = _clean(mp['preferred_position']?.toString());

    final name = [
      if (ln.isNotEmpty) ln,
      if (fn.isNotEmpty) fn,
    ].join(', ');

    final safeName = name.isEmpty ? '(No name)' : name;
    return preferred.isEmpty ? safeName : '$safeName ($preferred)';
  }

  String _sectionLabel(String value) {
    switch (value) {
      case 'mens':
        return 'Mens';
      case 'ladies':
        return 'Ladies';
      case 'mixed':
        return 'Mixed';
      case 'open':
      default:
        return 'Open';
    }
  }

  MemberPickerSectionFilter _sectionFilterFromString(String value) {
    switch (value) {
      case 'mens':
        return MemberPickerSectionFilter.mens;
      case 'ladies':
        return MemberPickerSectionFilter.ladies;
      case 'mixed':
        return MemberPickerSectionFilter.mixed;
      case 'open':
      default:
        return MemberPickerSectionFilter.open;
    }
  }

  Future<String> _loadSingleMemberName(String? memberProfileId) async {
    if (memberProfileId == null || memberProfileId.isEmpty) return '';

    final row = await _client
        .from('member_profiles')
        .select('first_name,last_name,preferred_position')
        .eq('id', memberProfileId)
        .maybeSingle();

    return _memberDisplayName(row);
  }

  Future<void> _loadTeamDetails() async {
    try {
      final team = await _client
          .from('teams')
          .select(
            'id,name,section,manager_member_profile_id,captain_member_profile_id,vice_captain_member_profile_id,description',
          )
          .eq('id', widget.teamId)
          .single();

      final managerId = team['manager_member_profile_id']?.toString();
      final captainId = team['captain_member_profile_id']?.toString();
      final viceId = team['vice_captain_member_profile_id']?.toString();

      final names = await Future.wait([
        _loadSingleMemberName(managerId),
        _loadSingleMemberName(captainId),
        _loadSingleMemberName(viceId),
      ]);

      if (!mounted) return;
      setState(() {
        _teamNameController.text = _clean(team['name']?.toString()).isEmpty
            ? widget.teamName
            : _clean(team['name']?.toString());
        _section = _clean(team['section']?.toString()).isEmpty
            ? 'open'
            : _clean(team['section']?.toString());
        _managerMemberProfileId = managerId;
        _captainMemberProfileId = captainId;
        _viceCaptainMemberProfileId = viceId;
        _descriptionController.text = team['description']?.toString() ?? '';
        _managerName = names[0];
        _captainName = names[1];
        _viceCaptainName = names[2];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
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
            'id, member_profile_id, is_active, member_profiles(first_name,last_name,preferred_position,phone,email_address)',
          )
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

      if (!mounted) return;
      setState(() {
        _rows = list;
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

  Future<void> _saveTeamDetails() async {
    if (!_canEdit || _savingTeam) return;

    setState(() => _savingTeam = true);

    try {
      await _client.from('teams').update({
        'name': _teamNameController.text.trim(),
        'section': _section,
        'manager_member_profile_id': _managerMemberProfileId,
        'captain_member_profile_id': _captainMemberProfileId,
        'vice_captain_member_profile_id': _viceCaptainMemberProfileId,
        'description': _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      }).eq('id', widget.teamId);

      if (!mounted) return;
      setState(() => _savingTeam = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Team details saved')),
      );
      await _loadTeamDetails();
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingTeam = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save team details: $e')),
      );
    }
  }

  Future<void> _setActive(String teamMemberId, bool isActive) async {
    try {
      await _client
          .from('team_members')
          .update({'is_active': isActive}).eq('id', teamMemberId);
      await _loadPool();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e')),
      );
    }
  }

  Future<void> _pickTeamRole({required String title, required String role}) async {
    final selectedIds = await Navigator.of(context).push<List<String>?>(
      MaterialPageRoute(
        builder: (_) => ClubMemberPickerPage(
          clubId: widget.clubId,
          title: title,
          teamId: null,
          fixtureId: null,
          useFixtureSection: false,
          initialSectionFilter: _sectionFilterFromString(_section),
          allowMultiple: false,
        ),
      ),
    );

    if (!mounted || selectedIds == null) return;

    final selectedId = selectedIds.isEmpty ? null : selectedIds.first;
    final selectedName = await _loadSingleMemberName(selectedId);

    if (!mounted) return;
    setState(() {
      switch (role) {
        case 'manager':
          _managerMemberProfileId = selectedId;
          _managerName = selectedName;
          break;
        case 'captain':
          _captainMemberProfileId = selectedId;
          _captainName = selectedName;
          break;
        case 'vice':
          _viceCaptainMemberProfileId = selectedId;
          _viceCaptainName = selectedName;
          break;
      }
    });
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
          title: 'Add players to ${_teamNameController.text.trim().isEmpty ? widget.teamName : _teamNameController.text.trim()}',
          teamId: null,
          fixtureId: null,
          useFixtureSection: false,
          initialSectionFilter: _sectionFilterFromString(_section),
          allowMultiple: true,
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

  Widget _buildRolePicker({
    required String label,
    required String value,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(value.isEmpty ? 'Not set' : value),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_canEdit && value.isNotEmpty)
            IconButton(
              tooltip: 'Clear $label',
              onPressed: onClear,
              icon: const Icon(Icons.clear),
            ),
          if (_canEdit)
            IconButton(
              tooltip: 'Select $label',
              onPressed: onPick,
              icon: const Icon(Icons.person_search),
            ),
        ],
      ),
    );
  }

  Widget _buildTeamDetailsCard() {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Team details',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _teamNameController,
              enabled: _canEdit,
              decoration: const InputDecoration(
                labelText: 'Team name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: ['mens', 'ladies', 'mixed', 'open'].contains(_section)
                  ? _section
                  : 'open',
              decoration: const InputDecoration(
                labelText: 'Section',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'mens', child: Text('Mens')),
                DropdownMenuItem(value: 'ladies', child: Text('Ladies')),
                DropdownMenuItem(value: 'mixed', child: Text('Mixed')),
                DropdownMenuItem(value: 'open', child: Text('Open')),
              ],
              onChanged: _canEdit
                  ? (value) {
                      if (value == null) return;
                      setState(() => _section = value);
                    }
                  : null,
            ),
            const SizedBox(height: 8),
            _buildRolePicker(
              label: 'Manager',
              value: _managerName,
              onPick: () => _pickTeamRole(title: 'Select Manager', role: 'manager'),
              onClear: () => setState(() {
                _managerMemberProfileId = null;
                _managerName = '';
              }),
            ),
            const Divider(height: 1),
            _buildRolePicker(
              label: 'Captain',
              value: _captainName,
              onPick: () => _pickTeamRole(title: 'Select Captain', role: 'captain'),
              onClear: () => setState(() {
                _captainMemberProfileId = null;
                _captainName = '';
              }),
            ),
            const Divider(height: 1),
            _buildRolePicker(
              label: 'Vice Captain',
              value: _viceCaptainName,
              onPick: () => _pickTeamRole(title: 'Select Vice Captain', role: 'vice'),
              onClear: () => setState(() {
                _viceCaptainMemberProfileId = null;
                _viceCaptainName = '';
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              enabled: _canEdit,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),
            if (_canEdit) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _savingTeam ? null : _saveTeamDetails,
                  icon: _savingTeam
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(_savingTeam ? 'Saving...' : 'Save team details'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPoolHeader(int visibleCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Team members / pool ($visibleCount)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Text(_sectionLabel(_section)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleRows = _showInactive
        ? _rows
        : _rows.where((r) => r['is_active'] == true).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Team — ${_teamNameController.text.trim().isEmpty ? widget.teamName : _teamNameController.text.trim()}'),
        actions: [
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
                      onPressed: _refreshAll,
                      child: const Text('Retry'),
                    ),
                  ],
                )
              : RefreshIndicator(
                  onRefresh: _refreshAll,
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: visibleRows.isEmpty ? 3 : visibleRows.length + 2,
                    separatorBuilder: (_, i) {
                      if (i < 2) return const SizedBox.shrink();
                      return const Divider(height: 1);
                    },
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return Column(
                          children: [
                            if (!_checkingPerms && !_canEdit)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                                child: Material(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                      'Read-only: only club Admin/Selector or this team’s Captain/Vice/Manager can edit this team.',
                                      style: Theme.of(context).textTheme.bodyMedium,
                                    ),
                                  ),
                                ),
                              ),
                            _buildTeamDetailsCard(),
                          ],
                        );
                      }

                      if (i == 1) return _buildPoolHeader(visibleRows.length);

                      if (i == 2 && visibleRows.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No team members in this pool yet.'),
                        );
                      }

                      final rowIndex = i - 2;
                      if (rowIndex < 0 || rowIndex >= visibleRows.length) {
                        return const SizedBox.shrink();
                      }

                      final row = visibleRows[rowIndex];
                      final mp = row['member_profiles'] as Map<String, dynamic>?;
                      final name = _memberDisplayName(mp);

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
