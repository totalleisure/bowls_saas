/// Remove repeated imported lines, without rewriting or discarding distinct rules
/// or personal notes. Standalone handwritten notes are left exactly as entered.
String compactScorecardNotes(String notes, Map<String, dynamic>? fixture) {
  if (fixture == null) return notes;
  String key(String value) => value
      .replaceFirst(
        RegExp(r'^(scoring|winning condition|rules):\s*', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();
  final rules = fixture['rules'] as Map? ?? {};
  final scoring = '${rules['scoring'] ?? ''}'.trim();
  final rawRules = '${rules['rules'] ?? ''}'.trim();
  final name = '${fixture['competitionName'] ?? ''}';
  final round = '${fixture['roundName'] ?? ''}';
  final playBy = '${fixture['playBy'] ?? 'not set'}';
  final combined = '$name · $round · Play by $playBy';
  final fixtureLines = '${fixture['notes'] ?? ''}'.split('\n');
  final matchLabel = fixtureLines
      .where(
        (line) =>
            name.isNotEmpty &&
            round.isNotEmpty &&
            line.startsWith('$name - $round '),
      )
      .firstOrNull;
  final lines = notes
      .split('\n')
      .expand(
        (line) => line.trim() == combined && matchLabel != null
            ? [matchLabel, 'Play by: $playBy']
            : [line],
      );
  final seen = <String>{};
  return lines
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && seen.add(key(line)))
      .map((line) {
        if (rawRules.isNotEmpty && key(line) == key(rawRules)) {
          return 'Rules: ${line.replaceFirst(RegExp(r'^(scoring|rules):\s*', caseSensitive: false), '')}';
        }
        if (scoring.isNotEmpty && key(line) == key(scoring)) {
          return 'Winning condition: ${line.replaceFirst(RegExp(r'^(scoring|winning condition):\s*', caseSensitive: false), '')}';
        }
        return line;
      })
      .join('\n');
}
