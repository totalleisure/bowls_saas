import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../../../core/widgets/club_member_picker_page.dart';
import '../competition_repository.dart';

bool competitionEntryCanReplace(CompetitionData data, String entryId) =>
    ['draft', 'published'].contains(data.competition['status']) &&
    !data.matches.any(
      (m) =>
          [m['side_a_entry_id'], m['side_b_entry_id']].contains(entryId) &&
          (!['to_be_arranged', 'bye'].contains(m['status']) ||
              m['score_a'] != null ||
              m['score_b'] != null ||
              m['proposed_winner_entry_id'] != null ||
              (m['status'] != 'bye' && m['winner_entry_id'] != null)),
    );

class CompetitionReplacePlayerScreen extends StatefulWidget {
  const CompetitionReplacePlayerScreen({
    super.key,
    required this.data,
    required this.entry,
    required this.repository,
    this.playerPicker,
  });
  final CompetitionData data;
  final CompetitionRow entry;
  final CompetitionRepository repository;
  final Future<ClubMemberPickerMember?> Function(BuildContext, Set<String>)?
  playerPicker;
  @override
  State<CompetitionReplacePlayerScreen> createState() =>
      _CompetitionReplacePlayerScreenState();
}

class _CompetitionReplacePlayerScreenState
    extends State<CompetitionReplacePlayerScreen> {
  List<CompetitionRow> players = [];
  String? outgoing, incoming, incomingName, error;
  final handicap = TextEditingController(), reason = TextEditingController();
  bool loading = true, saving = false;
  bool get usesHandicaps => widget.data.usesIndividualHandicaps;
  String name(CompetitionRow row) {
    final member = row['member'] as Map;
    return '${member['first_name'] ?? ''} ${member['last_name'] ?? ''}'.trim();
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final rows = await widget.repository.entryHandicaps(widget.entry['id']);
      final order = widget.entry['name'].toString().toLowerCase();
      int index(CompetitionRow p) {
        final i = order.indexOf(name(p).toLowerCase());
        return i < 0 ? 99999 : i;
      }

      rows.sort((a, b) => index(a).compareTo(index(b)));
      if (mounted)
        setState(() {
          players = rows;
          outgoing = rows.length == 1 ? rows.first['member_profile_id'] : null;
          loading = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          loading = false;
          error = 'Unable to load the entry. Go back and try again.';
        });
    }
  }

  @override
  void dispose() {
    handicap.dispose();
    reason.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    if (widget.playerPicker != null) {
      final selected = await widget.playerPicker!(
        context,
        widget.data.enteredMemberIds,
      );
      if (selected != null && mounted)
        setState(() {
          incoming = selected.memberProfileId;
          incomingName = selected.displayName;
          handicap.clear();
        });
      return;
    }
    List<ClubMemberPickerMember> picked = [];
    final ids = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => ClubMemberPickerPage(
          clubId: widget.data.competition['club_id'],
          title: 'Select replacement player',
          useFixtureSection: false,
          allowMultiple: false,
          excludeMemberProfileIds: widget.data.enteredMemberIds,
          onMembersSelected: (members) => picked = members,
        ),
      ),
    );
    if (ids == null || ids.length != 1 || picked.length != 1 || !mounted)
      return;
    setState(() {
      incoming = ids.single;
      incomingName = picked.single.displayName;
      handicap.clear();
    });
  }

  Future<void> save() async {
    final h = int.tryParse(handicap.text.trim());
    if (outgoing == null ||
        incoming == null ||
        reason.text.trim().isEmpty ||
        (usesHandicaps && (h == null || h < -1000 || h > 1000))) {
      setState(
        () => error =
            'Choose both players, give a reason${usesHandicaps ? ' and enter a whole-number handicap' : ''}.',
      );
      return;
    }
    final before = name(
      players.firstWhere((p) => p['member_profile_id'] == outgoing),
    );
    final names = players
        .map(
          (p) => p['member_profile_id'] == outgoing ? incomingName! : name(p),
        )
        .join(' / ');
    final published = widget.data.competition['status'] == 'published';
    final values = players
        .map(
          (p) =>
              p['member_profile_id'] == outgoing ? h : p['individual_handicap'],
        )
        .toList();
    final combined = values.every((v) => v is int)
        ? values.cast<int>().fold<int>(0, (sum, v) => sum + v).toString()
        : 'awaiting complete handicaps';
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm player replacement?'),
        content: SingleChildScrollView(
          child: Text(
            '$before → $incomingName\n\nEntry: $names\n'
            '${usesHandicaps ? 'Replacement handicap: $h\nNew combined handicap: $combined\nStarting scores will be recalculated.\n' : ''}\n'
            'The draw position and payment status stay the same. Any eligible unstarted linked booking will be updated.\n\n'
            '${published ? 'Revised details will be queued for affected players. Staging sends only to approved test addresses.' : 'This is a draft competition; no emails will be queued.'}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Replace player'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final result = await widget.repository.replacePlayer(
        entry: widget.entry,
        expectedMembers: players
            .map((p) => p['member_profile_id'].toString())
            .toList(),
        outgoingId: outgoing!,
        incomingId: incoming!,
        handicap: usesHandicaps ? h : null,
        reason: reason.text.trim(),
      );
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted)
        setState(() {
          saving = false;
          error = e is PostgrestException
              ? e.message
              : 'Unable to replace the player. Refresh the entry and try again.';
        });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Replace competition player')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '${widget.data.competition['name']}\n${widget.entry['name']}\n\nCorrect an unplayed entry without rebuilding its draw. Played results and existing scorecard setups must be resolved separately.',
                  ),
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: outgoing,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Player to replace',
                ),
                items: players
                    .map(
                      (p) => DropdownMenuItem<String>(
                        value: p['member_profile_id'],
                        child: Text(name(p)),
                      ),
                    )
                    .toList(),
                onChanged: saving ? null : (v) => setState(() => outgoing = v),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: saving ? null : pick,
                icon: const Icon(Icons.person_search),
                label: Text(incomingName ?? 'Choose replacement player'),
              ),
              if (usesHandicaps)
                TextField(
                  controller: handicap,
                  enabled: !saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Replacement individual handicap',
                  ),
                ),
              TextField(
                controller: reason,
                enabled: !saving,
                maxLength: 2000,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Reason for correction',
                ),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: saving || players.isEmpty ? null : save,
                child: Text(
                  saving ? 'Replacing player…' : 'Review replacement',
                ),
              ),
            ],
          ),
  );
}
