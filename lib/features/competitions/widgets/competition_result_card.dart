import 'package:flutter/material.dart';
import '../competition_repository.dart';

class CompetitionResultCard extends StatelessWidget {
  final CompetitionData data;
  final CompetitionRow match;
  final Set<String> ownEntryIds;
  const CompetitionResultCard({
    super.key,
    required this.data,
    required this.match,
    this.ownEntryIds = const {},
  });
  @override
  Widget build(BuildContext context) {
    if (match['status'] != 'completed' || match['winner_entry_id'] == null) {
      return const SizedBox.shrink();
    }
    final involved =
        ownEntryIds.contains(match['side_a_entry_id']) ||
        ownEntryIds.contains(match['side_b_entry_id']);
    final won = ownEntryIds.contains(match['winner_entry_id']);
    final background = involved
        ? (won ? Colors.green.shade100 : Colors.red.shade100)
        : Colors.blue.shade50;
    final foreground = involved
        ? (won ? Colors.green.shade900 : Colors.red.shade900)
        : Colors.blue.shade900;
    final border = involved
        ? (won ? Colors.green.shade700 : Colors.red.shade700)
        : Colors.blue.shade700;
    return Card(
      color: background,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: foreground),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    involved
                        ? (won ? Icons.emoji_events : Icons.sports_score)
                        : Icons.verified,
                    color: foreground,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      involved
                          ? (won ? 'You won' : 'You lost')
                          : 'Confirmed result',
                      style: TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                match['result_kind'] == 'walkover'
                    ? 'Walkover (W/O)'
                    : 'Result confirmed.',
              ),
              if (match['result_kind'] != 'walkover')
                Text(
                  '${data.side(match, 'a')}: ${match['score_a'] ?? '—'}\n${data.side(match, 'b')}: ${match['score_b'] ?? '—'}',
                ),
              Text(
                'Winner: ${data.entrant(match['winner_entry_id']?.toString())}',
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
