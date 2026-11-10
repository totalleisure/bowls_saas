import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'scorecard.dart';

class ScorecardMatchSummary extends StatelessWidget {
  const ScorecardMatchSummary({super.key, required this.card});
  final Scorecard card;

  String date(String value) {
    final d = DateTime.tryParse(value);
    if (d == null) return value;
    final suffix = d.day % 100 >= 11 && d.day % 100 <= 13
        ? 'th'
        : switch (d.day % 10) {
            1 => 'st',
            2 => 'nd',
            3 => 'rd',
            _ => 'th',
          };
    return '${d.day}$suffix ${DateFormat('MMM yyyy').format(d)}';
  }

  String duration(int minutes) => minutes < 60
      ? '$minutes mins'
      : '${minutes ~/ 60}hr${minutes % 60 == 0 ? '' : ' ${minutes % 60}mins'}';
  Widget line(String label, String value) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: '$label : ',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        TextSpan(text: value),
      ],
    ),
  );
  Widget team(String name, String roster, Color color) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .06),
      border: Border.all(color: color.withValues(alpha: .25)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
        for (final role in roster.split('\n').where((s) => s.trim().isNotEmpty))
          if (role.contains(':'))
            line(
              role.substring(0, role.indexOf(':')),
              role.substring(role.indexOf(':') + 1).trim(),
            )
          else
            Text(role),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final fixture = card.fixtureLink ?? {};
    final venueParts = card.venue.split(' · ');
    final club = '${fixture['venue'] ?? venueParts.first}';
    final green =
        '${fixture['green'] ?? (venueParts.length > 1 ? venueParts.skip(1).join(' · ') : '')}';
    final competition = '${fixture['competitionName'] ?? card.title}';
    final round = '${fixture['roundName'] ?? ''}';
    final prefix = '$competition - $round ';
    final matchLine = '${fixture['notes'] ?? ''}'
        .split('\n')
        .where((s) => s.startsWith(prefix))
        .firstOrNull;
    final number = matchLine?.substring(prefix.length).trim();
    final roundLabel = number == null || number.isEmpty
        ? round
        : '$round-$number';
    final extraNotes = card.playerNotes
        .split('\n')
        .where(
          (s) =>
              !s.startsWith('Play by') &&
              !s.startsWith('$competition · $round · Play by') &&
              !s.startsWith(prefix),
        )
        .join('\n')
        .trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (club.isNotEmpty)
            Text(club, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('${green.isEmpty ? '' : '$green · '}Rink : ${card.rink}'),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: competition,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (roundLabel.isNotEmpty)
                  TextSpan(text: ' — Round : $roundLabel'),
              ],
            ),
          ),
          if (fixture['playBy'] != null)
            Text('Play by : ${date('${fixture['playBy']}')}'),
          Text('Match date : ${date(card.date)}'),
          const SizedBox(height: 8),
          Text(
            [
              '${card.format} · ${card.woods} woods',
              if (card.scoring == '100up') '100 Up',
              if (card.target != null) 'First to ${card.target}',
              if (card.maxEnds != null) 'Maximum ${card.maxEnds} ends',
            ].join(' · '),
          ),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'Time Limit : ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(
                  text: card.durationMinutes == null
                      ? 'None'
                      : duration(card.durationMinutes!),
                ),
                if (card.lastJackMinutes != null) ...[
                  const TextSpan(
                    text: ' · Last jack : ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(
                    text: '${duration(card.lastJackMinutes!)} from start',
                  ),
                ],
              ],
            ),
          ),
          team(card.sideA, card.playersA, Colors.red),
          team(card.sideB, card.playersB, Colors.blue),
          if (card.marker.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: line('Marker', card.marker),
            ),
          if (extraNotes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(extraNotes),
            ),
        ],
      ),
    );
  }
}
