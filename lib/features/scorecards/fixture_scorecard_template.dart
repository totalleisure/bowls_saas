import '../../core/utils/date_format.dart';
import 'scorecard.dart';

Scorecard scorecardFromFixture(
  Map<String, dynamic> snapshot, {
  Map<String, dynamic>? conditions,
  Map<String, dynamic>? link,
  bool applyEntryHandicap = true,
}) {
  final players = (snapshot['players'] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  final ppr = (snapshot['playersPerSide'] as num?)?.toInt() ?? 1;
  List<Map<String, dynamic>> side(bool home) =>
      players.where((p) {
        final pos = p['position'] as int;
        return home ? pos >= 1 && pos <= ppr : pos >= 101 && pos <= 100 + ppr;
      }).toList()..sort(
        (a, b) => (a['position'] as int).compareTo(b['position'] as int),
      );
  final a = side(true), b = side(false);
  String names(List<Map<String, dynamic>> values, String fallback) =>
      values.isEmpty ? fallback : values.map((p) => p['name']).join(' / ');
  String signer(List<Map<String, dynamic>> values, int position) {
    for (final p in values) {
      if (p['position'] == position) return '${p['name']}';
    }
    return '';
  }

  String roster(List<Map<String, dynamic>> values) => values
      .map((p) {
        final pos = (p['position'] as int) % 100;
        final role = ppr == 1
            ? 'Player'
            : pos == ppr
            ? 'Skip'
            : pos == 1
            ? 'Lead'
            : pos == 2
            ? 'Second'
            : 'Third';
        return '$role: ${p['name']}';
      })
      .join('\n');
  final rules = Map<String, dynamic>.from(snapshot['rules'] as Map? ?? {});
  final scoring = '${rules['scoring'] ?? ''}';
  int? number(dynamic value) {
    if (value == null || '$value'.isEmpty) return null;
    final n = num.tryParse('$value');
    if (n == null || n != n.truncateToDouble()) return null;
    return n.toInt();
  }

  int handicap(dynamic value) {
    if (value == null) return 0;
    final n = number(value);
    if (n == null) {
      throw const FormatException(
        'This competition uses a fractional handicap. Please check the scoring conditions before creating a card.',
      );
    }
    return n;
  }

  final c = Scorecard.create()
    ..title = '${snapshot['title'] ?? 'Member fixture'}'
    ..date = parseClubTime(
      '${snapshot['startAt']}',
    ).toIso8601String().substring(0, 10)
    ..venue = [
      snapshot['venue'],
      snapshot['green'],
    ].where((s) => s != null && '$s'.isNotEmpty).join(' · ')
    ..rink = '${snapshot['rink'] ?? ''}'
    ..format = switch (ppr) {
      1 => 'Singles',
      2 => 'Pairs',
      3 => 'Triples',
      _ => 'Fours',
    }
    ..sideA = names(a, 'Side A')
    ..sideB = names(b, 'Side B')
    ..playersA = roster(a)
    ..playersB = roster(b)
    ..suggestedSignerA = signer(a, ppr)
    ..suggestedSignerB = signer(b, 100 + ppr)
    ..woods = number(rules['woods_per_player']) ?? 4
    ..scoring = RegExp(r'100\s*up', caseSensitive: false).hasMatch(scoring)
        ? '100up'
        : 'shots'
    ..target =
        number(rules['target_score']) ??
        int.tryParse(
          RegExp(
                r'first\s+to\s+(\d+)',
                caseSensitive: false,
              ).firstMatch(scoring)?.group(1) ??
              '',
        )
    ..maxEnds =
        number(rules['max_ends']) ??
        int.tryParse(
          RegExp(
                r'\b(\d+)\s+ends\b',
                caseSensitive: false,
              ).firstMatch(scoring)?.group(1) ??
              '',
        )
    ..durationMinutes = rules['time_limit_mode'] == 'minutes'
        ? number(rules['time_limit_minutes'])
        : null
    ..lastJackMinutes = null
    ..handicapA = applyEntryHandicap ? handicap(snapshot['handicapA']) : 0
    ..handicapB = applyEntryHandicap ? handicap(snapshot['handicapB']) : 0
    ..fixtureLink = {...snapshot, ...?link};
  if (c.scoring == '100up') c.target ??= 100;
  final rawRules = '${rules['rules'] ?? ''}';
  final allowance = number(rules['last_jack_before_end_minutes']);
  if (rules['time_limit_mode'] == 'minutes' && allowance != null) {
    if (c.durationMinutes == null ||
        allowance <= 0 ||
        allowance >= c.durationMinutes!) {
      throw const FormatException(
        'Check the competition last-jack allowance: it must be less than the match time limit.',
      );
    }
    c.lastJackMinutes = c.durationMinutes! - allowance;
  }
  c.notes = [
    if (snapshot['competitionName'] != null)
      '${snapshot['competitionName']} · ${snapshot['roundName']} · Play by ${snapshot['playBy'] ?? 'not set'}',
    if (scoring.isNotEmpty) 'Scoring: $scoring',
    if (rawRules.isNotEmpty) rawRules,
    if (snapshot['notes'] != null && '${snapshot['notes']}'.isNotEmpty)
      '${snapshot['notes']}',
    if (!applyEntryHandicap)
      'Multi-rink match: review any handicap allocation for this rink.',
  ].join('\n');
  for (final p in players) {
    if (p['position'] == 201) c.marker = '${p['name']}';
  }
  if (conditions != null) {
    c.woods = number(conditions['woods']) ?? c.woods;
    c.target = number(conditions['target']);
    c.maxEnds = number(conditions['maxEnds']);
    c.durationMinutes = number(conditions['durationMinutes']);
    c.lastJackMinutes = number(conditions['lastJackMinutes']);
    c.handicapA = number(conditions['handicapA']) ?? 0;
    c.handicapB = number(conditions['handicapB']) ?? 0;
    c.scoring = '${conditions['scoring'] ?? 'shots'}';
    c.notes = '${conditions['notes'] ?? c.notes}';
  }
  c.notes = c.displayNotes;
  return c;
}

Map<String, dynamic> fixtureScorecardConditions(Scorecard c) => {
  'woods': c.woods,
  'target': c.target,
  'maxEnds': c.maxEnds,
  'durationMinutes': c.durationMinutes,
  'lastJackMinutes': c.lastJackMinutes,
  'handicapA': c.handicapA,
  'handicapB': c.handicapB,
  'scoring': c.scoring,
  'notes': c.notes,
};
