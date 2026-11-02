import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../clubs/club_access.dart';
import '../competition_repository.dart';
import 'competition_setup_screen.dart';
import 'competition_season_screen.dart';

class CompetitionsScreen extends StatefulWidget {
  final String clubId, clubName;
  final CompetitionRepository? repository;
  final Future<ClubAccess> Function()? accessLoader;
  const CompetitionsScreen({
    super.key,
    required this.clubId,
    required this.clubName,
    this.repository,
    this.accessLoader,
  });
  @override
  State<CompetitionsScreen> createState() => _CompetitionsScreenState();
}

class _CompetitionsScreenState extends State<CompetitionsScreen> {
  late final repo =
      widget.repository ?? CompetitionRepository(Supabase.instance.client);
  List<CompetitionRow> rows = [];
  List<CompetitionRow> myEntries = [];
  bool mineOnly = false;
  String memberId = '';
  bool loading = true, manage = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final access =
          await (widget.accessLoader?.call() ??
              loadClubAccess(clubId: widget.clubId));
      final result = await repo.list(widget.clubId);
      final mine = await repo.myEntries(
        access.currentMemberId,
        result.map((c) => c['id'].toString()).toList(),
      );
      if (!mounted) return;
      setState(() {
        myEntries = mine;
        rows = result;
        manage = access.isSuperuser || access.isClubAdmin;
        memberId = access.currentMemberId;
        if (!manage) mineOnly = true;
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  Future<void> open(String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CompetitionSeasonScreen(
          clubId: widget.clubId,
          competitionId: id,
          canManage: manage,
          memberId: memberId,
          repository: repo,
        ),
      ),
    );
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Competitions'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: loading ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    floatingActionButton: manage && !loading
        ? FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: const Text('New competition'),
            onPressed: () async {
              final id = await Navigator.of(context).push<String>(
                MaterialPageRoute(
                  builder: (_) => CompetitionSetupScreen(
                    clubId: widget.clubId,
                    repository: repo,
                  ),
                ),
              );
              if (id != null && mounted) await open(id);
            },
          )
        : null,
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Unable to load competitions.\n$error'),
                  TextButton(onPressed: load, child: const Text('Try again')),
                ],
              ),
            ),
          )
        : ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              Text(
                widget.clubName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Follow your Club competitions, draws, deadlines and results.',
                ),
              ),
              if (manage)
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('All competitions'),
                      selected: !mineOnly,
                      onSelected: (_) => setState(() => mineOnly = false),
                    ),
                    ChoiceChip(
                      label: Text('My entries (${myEntries.length})'),
                      selected: mineOnly,
                      onSelected: (_) => setState(() => mineOnly = true),
                    ),
                  ],
                ),
              if (mineOnly && myEntries.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'You have no entries in the available competitions.',
                  ),
                ),
              if (rows.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No competitions are available yet.'),
                  ),
                ),
              for (final c in rows.where(
                (c) =>
                    !mineOnly ||
                    myEntries.any((e) => e['competition_id'] == c['id']),
              ))
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.emoji_events_outlined),
                    title: Text('${c['name']}'),
                    subtitle: Text(
                      '${c['season']} · ${c['status'] == 'draft' ? 'Draft — organisers only' : 'Published'}${mineOnly ? '\n${myEntries.where((e) => e['competition_id'] == c['id']).map((e) => ((e['competition_entries'] as Map?)?['name'] ?? '').toString()).join('\n')}' : ''}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => open(c['id'].toString()),
                  ),
                ),
            ],
          ),
  );
}
