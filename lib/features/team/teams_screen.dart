import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'team_pool_screen.dart';

class TeamsScreen extends StatefulWidget {
  final String clubId;
  final String clubName;

  const TeamsScreen({
    super.key,
    required this.clubId,
    required this.clubName,
  });

  @override
  State<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends State<TeamsScreen> {
  final _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _teams = [];

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _client
          .from('teams')
          .select('id, name, description, is_active')
          .eq('club_id', widget.clubId)
          .order('name');

      setState(() {
        _teams = (res as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _createTeamDialog() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    bool saving = false;

    Future<void> doSave(StateSetter setDialogState) async {
      final name = nameController.text.trim();
      final desc = descController.text.trim();

      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Team name is required')),
        );
        return;
      }

      setDialogState(() => saving = true);

      try {
        await _client.from('teams').insert({
          'club_id': widget.clubId,
          'name': name,
          'description': desc.isEmpty ? null : desc,
          'is_active': true,
        });

        if (!mounted) return;
        Navigator.of(context).pop();
        await _loadTeams();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Created team: $name')),
        );
      } catch (e) {
        if (!mounted) return;
        setDialogState(() => saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Create failed: $e')),
        );
      }
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Create team'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Team name *',
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                      border: OutlineInputBorder(),
                    ),
                    minLines: 2,
                    maxLines: 4,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: saving ? null : () => doSave(setDialogState),
                  icon: saving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasTeams = _teams.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text('Teams — ${widget.clubName}'),
        actions: [
          IconButton(
            onPressed: _createTeamDialog,
            icon: const Icon(Icons.add),
            tooltip: 'Create team',
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
                      onPressed: _loadTeams,
                      child: const Text('Retry'),
                    ),
                  ],
                )
              : !hasTeams
                  ? ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const Text('No teams yet.', style: TextStyle(fontSize: 16)),
                        const SizedBox(height: 8),
                        const Text('Create a team to start building the team pool.'),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _createTeamDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('Create your first team'),
                        ),
                      ],
                    )
                  : RefreshIndicator(
                      onRefresh: _loadTeams,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _teams.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final t = _teams[i];
                          final teamId = t['id'].toString();
                          final teamName = (t['name'] ?? '').toString();
                          final desc = (t['description'] ?? '').toString();
                          final active = t['is_active'] == true;

                          return ListTile(
                            title: Text(teamName.isEmpty ? '(Unnamed team)' : teamName),
                            subtitle: Text([
                              if (!active) 'INACTIVE',
                              if (desc.isNotEmpty) desc,
                            ].join(' • ')),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TeamPoolScreen(
                                    teamId: teamId,
                                    clubId: widget.clubId,
                                    teamName: teamName,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createTeamDialog,
        icon: const Icon(Icons.add),
        label: const Text('Create team'),
      ),
    );
  }
}