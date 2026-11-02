import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/hex_color.dart';
import '../competition_repository.dart';

/// A personal match awaiting arrangement. Opponents are shown after opening it.
class CompetitionArrangementCard extends StatelessWidget {
  final CompetitionData data;
  final CompetitionRow match;
  final VoidCallback onTap;
  const CompetitionArrangementCard({
    super.key,
    required this.data,
    required this.match,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = data.competition['fixture_type'] as Map?;
    final scheme = type?['colour_scheme'] as Map?;
    final background = colorFromHex(
      scheme?['background_hex']?.toString(),
      fallback: theme.colorScheme.surface,
    );
    final foreground = colorFromHex(
      scheme?['foreground_hex']?.toString(),
      fallback: theme.colorScheme.onSurface,
    );
    final settings = {...?(data.competition['settings'] as Map?)};
    final round = data.rounds
        .where((r) => r['id'] == match['round_id'])
        .firstOrNull;
    settings.addAll((round?['rule_overrides'] as Map?) ?? {});
    final deadline = DateTime.tryParse('${round?['play_by']}');
    return Card(
      color: background,
      surfaceTintColor: Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        textColor: foreground,
        iconColor: foreground,
        leading: const Icon(Icons.emoji_events_outlined),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Chip(
              label: Text('Competition Round : ${data.reference(match)}'),
              backgroundColor: foreground,
              labelStyle: TextStyle(
                color: background,
                fontWeight: FontWeight.bold,
              ),
              side: BorderSide(color: foreground),
            ),
            Text(
              '${data.competition['name']}',
              style: TextStyle(color: foreground, fontWeight: FontWeight.bold),
            ),
            if (type?['name'] != null)
              Text('${type!['name']}', style: TextStyle(color: foreground)),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                for (final key in ['section', 'playing_format', 'dress'])
                  if (settings[key]?.toString().trim().isNotEmpty ?? false)
                    '${settings[key]}',
                'Play by: ${deadline == null ? 'Not yet set' : DateFormat('d MMM yyyy').format(deadline)}',
              ].join(' • '),
              style: TextStyle(color: foreground),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
