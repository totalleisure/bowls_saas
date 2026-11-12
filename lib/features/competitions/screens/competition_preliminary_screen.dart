import 'package:flutter/material.dart';
import '../../../core/widgets/club_member_picker_page.dart';
import '../competition_repository.dart';

/// Only an unplayed opening bye can be converted without moving the bracket.
CompetitionRow? preliminaryBye(
  CompetitionData data,
  CompetitionRow match,
  String entryId,
) {
  if (data.competition['status'] != 'published' ||
      match['status'] != 'to_be_arranged' ||
      match['fixture_id'] != null ||
      match['score_a'] != null ||
      match['score_b'] != null) {
    return null;
  }
  final side = match['side_a_entry_id'] == entryId ? 'a' : 'b';
  if (match['side_${side}_entry_id'] != entryId) return null;
  final source = data.matches
      .where((m) => m['id'] == match['side_${side}_source_id'])
      .firstOrNull;
  if (source == null ||
      source['status'] != 'bye' ||
      source['winner_entry_id'] != entryId) {
    return null;
  }
  final round = data.rounds
      .where((r) => r['id'] == source['round_id'])
      .firstOrNull;
  final target = data.rounds
      .where((r) => r['id'] == match['round_id'])
      .firstOrNull;
  return round?['round_number'] == 1 && target?['round_number'] == 2
      ? source
      : null;
}

class CompetitionPreliminaryScreen extends StatefulWidget {
  final CompetitionData data;
  final CompetitionRow match;
  final CompetitionRepository repository;
  const CompetitionPreliminaryScreen({
    super.key,
    required this.data,
    required this.match,
    required this.repository,
  });
  @override
  State<CompetitionPreliminaryScreen> createState() =>
      _CompetitionPreliminaryScreenState();
}

class _CompetitionPreliminaryScreenState
    extends State<CompetitionPreliminaryScreen> {
  String? entryId, error;
  List<ClubMemberPickerMember> members = [];
  final reason = TextEditingController(
    text: 'An entry was omitted from the published draw.',
  );
  bool busy = false;
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    List<ClubMemberPickerMember> picked = [];
    final ids = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => ClubMemberPickerPage(
          clubId: widget.data.competition['club_id'].toString(),
          title: 'Select the omitted entry',
          useFixtureSection: false,
          allowMultiple: true,
          reviewSelectionOrder: true,
          selectionGroupSize:
              widget.data.competition['settings']['players_per_entry'] as int,
          excludeMemberProfileIds: widget.data.enteredMemberIds,
          onMembersSelected: (value) => picked = value,
        ),
      ),
    );
    if (ids == null || !mounted) return;
    setState(() {
      if (picked.length !=
          widget.data.competition['settings']['players_per_entry']) {
        error = 'Select exactly one complete entry.';
      } else {
        members = picked;
        error = null;
      }
    });
  }

  Future<void> save() async {
    if (entryId == null || members.isEmpty || reason.text.trim().isEmpty) {
      setState(
        () => error = 'Select the challengers, the omitted entry and a reason.',
      );
      return;
    }
    final source = preliminaryBye(widget.data, widget.match, entryId!)!;
    final round = widget.data.rounds.firstWhere(
      (r) => r['id'] == source['round_id'],
    );
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm published draw amendment?'),
        content: Text(
          '${widget.data.entrant(entryId)} (challengers)\nversus\n${members.map((m) => m.displayName).join(' / ')}\n\n'
          '${widget.data.reference(source)} · Play by: ${round['play_by'] ?? 'not set'}\n\n'
          'The winner takes the existing place in ${widget.data.reference(widget.match)}. '
          'Its other entry stays in place. Affected players will receive amendment emails through the normal queue. Staging sends only to approved test addresses.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Amend draw and queue emails'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.repository.addPreliminary(
        matchId: widget.match['id'].toString(),
        entryId: entryId!,
        sourceId: source['id'].toString(),
        members: members.map((m) => m.memberProfileId).toList(),
        playBy: round['play_by'] as String?,
        reason: reason.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Draw amended. ${result['emails_queued']} emails queued for automatic sending.',
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidates =
        [
              for (final side in ['a', 'b'])
                if (widget.match['side_${side}_entry_id'] != null)
                  widget.match['side_${side}_entry_id'].toString(),
            ]
            .where(
              (id) => preliminaryBye(widget.data, widget.match, id) != null,
            )
            .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Add preliminary match')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                '${widget.data.competition['name']} · ${widget.data.reference(widget.match)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              const Text(
                'Move an entry back into its preliminary slot and add the omitted entry. The rest of the published draw stays in place.',
              ),
              DropdownButtonFormField<String>(
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Existing entry — challengers',
                ),
                items: [
                  for (final id in candidates)
                    DropdownMenuItem(
                      value: id,
                      child: Text(widget.data.entrant(id)),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (value) => setState(() => entryId = value),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: busy ? null : pick,
                icon: const Icon(Icons.group_add),
                label: const Text('Select omitted entry'),
              ),
              if (members.isNotEmpty)
                Text(members.map((m) => m.displayName).join(' / ')),
              if (entryId != null) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '${widget.data.reference(preliminaryBye(widget.data, widget.match, entryId!)!)}\n'
                      '${widget.data.entrant(entryId)} (challengers)\nversus ${members.isEmpty ? 'omitted entry' : members.map((m) => m.displayName).join(' / ')}\n\n'
                      'Winner advances to ${widget.data.reference(widget.match)}. Existing preliminary date and rules apply.',
                    ),
                  ),
                ),
              ],
              TextField(
                controller: reason,
                enabled: !busy,
                maxLength: 2000,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Reason for amendment',
                ),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              FilledButton(
                onPressed: busy ? null : save,
                child: const Text('Review amendment'),
              ),
              if (busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
