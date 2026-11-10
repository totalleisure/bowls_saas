import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/utils/date_format.dart';

/// Identify a fixture before anyone claims or opens its scorecard. Keep this
/// independent of scoring-rule parsing so a rule problem cannot hide the match.
class FixtureScorecardIdentity extends StatelessWidget {
  const FixtureScorecardIdentity({super.key, required this.snapshot});
  final Map<String, dynamic> snapshot;

  @override
  Widget build(BuildContext context) {
    final count = (snapshot['playersPerSide'] as num?)?.toInt() ?? 1;
    final players =
        (snapshot['players'] as List? ?? []).whereType<Map>().toList()..sort(
          (a, b) => ((a['position'] as num?)?.toInt() ?? 0).compareTo(
            (b['position'] as num?)?.toInt() ?? 0,
          ),
        );
    String names(int from, int to) => players
        .where((p) {
          final position = (p['position'] as num?)?.toInt() ?? 0;
          return position >= from && position <= to;
        })
        .map((p) => '${p['name'] ?? ''}'.trim())
        .where((name) => name.isNotEmpty)
        .join(' / ');
    final a = names(1, count), b = names(101, 100 + count);
    final marker = names(201, 201);
    final start = DateTime.tryParse('${snapshot['startAt'] ?? ''}');
    final end = DateTime.tryParse('${snapshot['endAt'] ?? ''}');
    final round = '${snapshot['roundName'] ?? ''}'.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (round.isNotEmpty)
          Text(round, style: const TextStyle(fontWeight: FontWeight.w600)),
        if (start != null)
          Text(
            '${DateFormat('EEE d MMM yyyy · HH:mm').format(toClubTime(start))}${end == null ? '' : '–${DateFormat('HH:mm').format(toClubTime(end))}'}',
          ),
        if (a.isNotEmpty || b.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              '${a.isEmpty ? 'Players to be confirmed' : a}\nv ${b.isEmpty ? 'Opponents to be confirmed' : b}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        if (marker.isNotEmpty) Text('Marker: $marker'),
      ],
    );
  }
}
