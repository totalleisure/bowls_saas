import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/competitions/competition_repository.dart';
import 'package:bowls_saas/features/competitions/personal_competition_matches.dart';
import 'internal_competitions_test.dart' show FakeCompetitions, sample;

void main() {
  test('Opponent competition remains visible through every response state', () {
    final fixture = <String, dynamic>{
      'id': 'booked',
      'captain_member_profile_id': 'opponent',
      'start_at': '2026-12-01T10:00:00Z',
    };
    final matches = <PersonalCompetitionMatch>[
      (data: sample(), match: {'fixture_id': 'booked'}),
    ];
    for (final state in ['pending', 'accepted', 'declined']) {
      final displayed = upcomingPersonalCompetitionFixtures(
        matches,
        [fixture],
        DateTime.utc(2026, 11, 1),
        {'booked': state},
      );
      expect(displayed.single['_competitionAcceptance'], state);
      expect(
        acceptedFixturesWithoutCompetitionDuplicates([fixture], displayed),
        isEmpty,
      );
      expect(fixture.containsKey('_competitionAcceptance'), isFalse);
    }
    expect(
      upcomingPersonalCompetitionFixtures(
        matches,
        [fixture],
        DateTime.utc(2026, 11, 1),
        {},
      ).single['_competitionAcceptance'],
      'pending',
    );
  });
  test(
    'An off-App match leaves arrangement lists when its result is recorded',
    () {
      final match = <String, dynamic>{
        'status': 'to_be_arranged',
        'fixture_id': null,
      };
      expect(competitionNeedsArrangement(match), isTrue);
      match['status'] = 'result_pending';
      expect(competitionNeedsArrangement(match), isFalse);
      match.addAll({'status': 'completed', 'winner_entry_id': 'a'});
      expect(competitionNeedsArrangement(match), isFalse);
      // Its next match is independently actionable once both entries are known.
      expect(
        competitionNeedsArrangement({
          'status': 'to_be_arranged',
          'fixture_id': null,
        }),
        isTrue,
      );
    },
  );
  test(
    'Competition section takes precedence without changing reminder data',
    () {
      final accepted = <CompetitionRow>[
        {'id': 'competition'},
        {'id': 'ordinary'},
      ];
      final displayed = acceptedFixturesWithoutCompetitionDuplicates(accepted, [
        {'id': 'competition'},
      ]);
      expect(displayed.map((f) => f['id']), ['ordinary']);
      expect(accepted.map((f) => f['id']), ['competition', 'ordinary']);
    },
  );
  test('Only personal known-opponent published matches are loaded', () async {
    final repo = FakeCompetitions()
      ..personalEntries = [
        {'competition_id': 'competition', 'entry_id': 'a'},
      ];
    repo.additionalCompetitions = [
      {'id': 'other', 'status': 'published'},
      {'id': 'draft', 'status': 'draft'},
    ];
    final matches = await loadPersonalCompetitionMatches(repo, 'club', 'me');
    expect(matches.map((m) => m.match['id']), ['s1']);
    expect(repo.calls.where((c) => c.startsWith('load:')), [
      'load:club:competition',
    ]);
    expect(competitionNeedsArrangement(matches.single.match), isTrue);
    matches.single.match['fixture_id'] = 'booked';
    expect(competitionNeedsArrangement(matches.single.match), isFalse);
  });
  test(
    'Personal competition fixtures include opponents and exclude ordinary, past and cancelled',
    () {
      final data = sample();
      final matches = <PersonalCompetitionMatch>[
        for (final id in ['mine', 'other', 'past', 'cancelled'])
          (data: data, match: {'fixture_id': id}),
      ];
      CompetitionRow fixture(
        String id, {
        String captain = 'me',
        String start = '2026-12-01T10:00:00Z',
        bool cancelled = false,
      }) => {
        'id': id,
        'captain_member_profile_id': captain,
        'start_at': start,
        'cancelled_at': cancelled ? '2026-11-01' : null,
      };
      final selected = upcomingPersonalCompetitionFixtures(
        matches,
        [
          fixture('mine'),
          fixture('other', captain: 'someone'),
          fixture('ordinary'),
          fixture('past', start: '2026-10-01T10:00:00Z'),
          fixture('cancelled', cancelled: true),
        ],
        DateTime.utc(2026, 11, 1),
        {'mine': 'accepted', 'other': 'declined'},
      );
      expect(selected.map((f) => f['id']), ['mine', 'other']);
      expect(selected.map((f) => f['_competitionAcceptance']), [
        'accepted',
        'declined',
      ]);
    },
  );
}
