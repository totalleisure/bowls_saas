import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:bowls_saas/features/competitions/competition_repository.dart';
import 'package:bowls_saas/features/competitions/screens/competition_preliminary_screen.dart';
import 'package:bowls_saas/features/competitions/screens/competition_season_screen.dart';
import 'competition_player_result_screen_test.dart' show ResultRepository;

void main() {
  testWidgets(
    'Admin can open the amendment review; players cannot see the action',
    (t) async {
      final repo = ResultRepository();
      repo.data.rounds.first['round_number'] = 2;
      repo.data.rounds.add({
        'id': 'p',
        'name': 'Preliminary',
        'round_number': 1,
        'rule_overrides': <String, dynamic>{},
      });
      repo.data.matches.first['side_a_source_id'] = 'p7';
      repo.data.matches.add({
        'id': 'p7',
        'round_id': 'p',
        'match_number': 7,
        'status': 'bye',
        'winner_entry_id': 'a',
      });
      Future<void> open(bool admin) async {
        await t.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            home: CompetitionMatchScreen(
              data: repo.data,
              match: repo.data.matches.first,
              canManage: admin,
              repository: repo,
            ),
          ),
        );
        await t.pumpAndSettle();
      }

      await open(false);
      expect(find.text('Add preliminary match'), findsNothing);
      await open(true);
      await t.ensureVisible(find.text('Add preliminary match'));
      await t.tap(find.text('Add preliminary match'));
      await t.pumpAndSettle();
      expect(find.text('Select omitted entry'), findsOneWidget);
      expect(find.text('Review amendment'), findsOneWidget);
      await t.ensureVisible(find.text('Review amendment'));
      await t.tap(find.text('Review amendment'));
      await t.pumpAndSettle();
      expect(
        find.text('Select the challengers, the omitted entry and a reason.'),
        findsOneWidget,
      );
    },
  );
  test(
    'Only a published unbooked opening bye can be amended; ordering is unchanged',
    () {
      final source = <String, dynamic>{
        'id': 'p7',
        'round_id': 'p',
        'status': 'bye',
        'winner_entry_id': 'steph',
      };
      final match = <String, dynamic>{
        'id': 'q4',
        'round_id': 'q',
        'status': 'to_be_arranged',
        'side_a_entry_id': 'steph',
        'side_a_source_id': 'p7',
        'side_b_entry_id': 'carol',
      };
      final competition = <String, dynamic>{'status': 'published'};
      final data = CompetitionData(
        competition,
        [],
        [
          {'id': 'p', 'round_number': 1},
          {'id': 'q', 'round_number': 2},
        ],
        [source, match],
      );
      expect(preliminaryBye(data, match, 'steph'), same(source));
      expect(preliminaryBye(data, match, 'carol'), isNull);
      for (final status in ['result_pending', 'completed']) {
        match['status'] = status;
        expect(preliminaryBye(data, match, 'steph'), isNull);
      }
      match['status'] = 'to_be_arranged';
      match['fixture_id'] = 'booking';
      expect(preliminaryBye(data, match, 'steph'), isNull);
      match['fixture_id'] = null;
      competition['status'] = 'draft';
      expect(preliminaryBye(data, match, 'steph'), isNull);
      expect(data.matches.map((m) => m['id']), ['p7', 'q4']);
    },
  );
}
