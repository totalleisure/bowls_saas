import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/competitions/competition_repository.dart';
import 'package:bowls_saas/features/competitions/competition_bracket_pdf.dart';
import 'package:bowls_saas/features/competitions/screens/competition_season_screen.dart';
import 'package:bowls_saas/features/scorecards/fixture_scorecard_template.dart';
import 'package:bowls_saas/features/scorecards/scorecard_setup.dart';
import 'competition_player_result_screen_test.dart' show ResultRepository;
import 'fixture_scorecard_test.dart' show snapshot;

class HandicapRepository extends ResultRepository {
  Map<String, int>? saved;
  HandicapRepository() {
    data.competition['status'] = 'draft';
    data.competition['settings']['handicap_mode'] = 'team_difference';
    data.entries.first['handicap'] = 24;
  }
  @override
  Future<List<CompetitionRow>> entryHandicaps(String entryId) async => [
    {
      'member_profile_id': 'one',
      'individual_handicap': 12,
      'member': {'first_name': 'Carol', 'last_name': 'Sullivan'},
    },
    {
      'member_profile_id': 'two',
      'individual_handicap': 12,
      'member': {'first_name': 'Dan', 'last_name': 'Bumford'},
    },
  ];
  @override
  Future<void> setMemberHandicaps(
    String entryId,
    Map<String, int> values,
  ) async {
    saved = values;
    data.entries.first['handicap'] = values.values.fold(0, (a, b) => a + b);
  }
}

void main() {
  test(
    'Individual labels preserve playing order, signed values and unknowns',
    () {
      final repo = HandicapRepository();
      final entry = repo.data.entries.first;
      entry['handicap_members'] = <Map<String, dynamic>>[
        {'name': 'Partner', 'individual_handicap': 8},
        {'name': 'Alex', 'individual_handicap': -2},
      ];
      expect(
        repo.data.entrant(entry['id']),
        'Alex (Hcp -2) / Partner (Hcp 8) [Hcp 24]',
      );
      expect(
        competitionPrintedSide(repo.data, repo.data.matches.first, 'a'),
        'Alex (Hcp -2) / Partner (Hcp 8) [Hcp 24]',
      );
      (entry['handicap_members'] as List).first['individual_handicap'] = null;
      expect(repo.data.entrant(entry['id']), contains('Partner (Hcp not set)'));
      repo.data.competition['settings']['handicap_mode'] = 'entry_start';
      expect(repo.data.entrant(entry['id']), 'Alex / Partner');
    },
  );
  testWidgets(
    'Admin edits individual values in a draft draw and sees the computed pair total',
    (t) async {
      final repo = HandicapRepository();
      await t.pumpWidget(
        MaterialApp(
          home: CompetitionSeasonScreen(
            clubId: 'club',
            competitionId: 'c',
            canManage: true,
            repository: repo,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Entries'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Team total 24'));
      await t.tap(find.text('Team total 24'));
      await t.pumpAndSettle();
      expect(find.text('Carol Sullivan'), findsOneWidget);
      expect(find.text('Dan Bumford'), findsOneWidget);
      await t.enterText(find.byType(TextFormField).last, '8');
      await t.tap(find.text('Save player handicaps'));
      await t.pumpAndSettle();
      expect(repo.saved, {'one': 12, 'two': 8});
      expect(find.text('Team total 20'), findsOneWidget);
    },
  );
  testWidgets(
    'Rule-derived starts are preserved and hidden from manual fixture editing',
    (t) async {
      final source = snapshot(2);
      source['rules'] = {
        ...(source['rules'] as Map),
        'handicap_mode': 'team_difference',
      };
      source['handicapA'] = 0;
      source['handicapB'] = 14;
      final card = scorecardFromFixture(source);
      expect(card.totalA, 0);
      expect(card.totalB, 14);
      await t.pumpWidget(MaterialApp(home: ScorecardSetup(card: card)));
      await t.pumpAndSettle();
      expect(find.text('Starting handicap A'), findsNothing);
      expect(find.text('Starting handicap B'), findsNothing);
    },
  );
  test('Handicap draw labels show totals without changing stored names', () {
    final repo = HandicapRepository();
    expect(
      competitionPrintedSide(repo.data, repo.data.matches.first, 'a'),
      contains('[Hcp 24]'),
    );
    expect(repo.data.entries.first['name'], 'Alex / Partner');
    repo.data.competition['settings']['handicap_mode'] = 'entry_start';
    expect(
      competitionPrintedSide(repo.data, repo.data.matches.first, 'a'),
      'Alex / Partner',
    );
  });
}
