import 'competition_repository.dart';

typedef PersonalCompetitionMatch = ({
  CompetitionData data,
  CompetitionRow match,
});

Future<List<PersonalCompetitionMatch>> loadPersonalCompetitionMatches(
  CompetitionRepository repository,
  String clubId,
  String memberId,
) async {
  final competitions = (await repository.list(
    clubId,
  )).where((c) => c['status'] == 'published').toList();
  final entries = await repository.myEntries(
    memberId,
    competitions.map((c) => c['id'].toString()).toList(),
  );
  final ownIds = entries.map((e) => e['entry_id']).toSet();
  final result = <PersonalCompetitionMatch>[];
  for (final competition in competitions.where(
    (c) => entries.any((e) => e['competition_id'] == c['id']),
  )) {
    final data = await repository.load(clubId, competition['id'].toString());
    for (final match in data.matches.where(
      (m) =>
          m['side_a_entry_id'] != null &&
          m['side_b_entry_id'] != null &&
          (ownIds.contains(m['side_a_entry_id']) ||
              ownIds.contains(m['side_b_entry_id'])),
    )) {
      result.add((data: data, match: match));
    }
  }
  return result;
}

bool competitionNeedsArrangement(CompetitionRow match) =>
    match['status'] == 'to_be_arranged' && match['fixture_id'] == null;

/// Display-only filtering; the original list still feeds next-match reminders.
List<CompetitionRow> acceptedFixturesWithoutCompetitionDuplicates(
  List<CompetitionRow> accepted,
  List<CompetitionRow> arranged,
) {
  final ids = arranged.map((fixture) => fixture['id']).toSet();
  return accepted.where((fixture) => !ids.contains(fixture['id'])).toList();
}

List<CompetitionRow> upcomingPersonalCompetitionFixtures(
  List<PersonalCompetitionMatch> matches,
  List<CompetitionRow> fixtures,
  DateTime now,
  Map<String, String> acceptanceByFixture,
) {
  final linkedIds = matches
      .map((m) => m.match['fixture_id'])
      .whereType<String>()
      .toSet();
  return fixtures
      .where(
        (f) =>
            linkedIds.contains(f['id']) &&
            f['cancelled_at'] == null &&
            (DateTime.tryParse('${f['start_at']}')?.isAfter(now) ?? false),
      )
      .map(
        (f) => <String, dynamic>{
          ...f,
          '_competitionAcceptance': acceptanceByFixture[f['id']] ?? 'pending',
        },
      )
      .toList()
    ..sort((a, b) => '${a['start_at']}'.compareTo('${b['start_at']}'));
}
