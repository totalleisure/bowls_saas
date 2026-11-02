import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowls_saas/features/competitions/competition_repository.dart';
import 'package:bowls_saas/features/competitions/screens/competition_season_screen.dart';

class ResultRepository extends CompetitionRepository {
  @override
  Future<bool> publicationEnabled(String clubId) async => true;
  ResultRepository()
    : super(
        SupabaseClient(
          'https://example.invalid',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  int submissions = 0, confirmations = 0;
  final data = CompetitionData(
    {
      'id': 'c',
      'club_id': 'club',
      'name': 'Pairs',
      'status': 'published',
      'settings': {
        'section': 'mixed',
        'playing_format': 'pairs',
        'players_per_entry': 2,
        'booking_minutes': 150,
      },
    },
    [
      {'id': 'a', 'name': 'Alex / Partner'},
      {'id': 'b', 'name': 'Blair / Partner'},
    ],
    [
      {
        'id': 'r',
        'name': 'Semi-final',
        'round_number': 1,
        'rule_overrides': <String, dynamic>{},
      },
      {
        'id': 'f',
        'name': 'Final',
        'round_number': 2,
        'rule_overrides': <String, dynamic>{},
      },
    ],
    [
      {
        'id': 'm',
        'round_id': 'r',
        'match_number': 1,
        'side_a_entry_id': 'a',
        'side_b_entry_id': 'b',
        'status': 'to_be_arranged',
      },
      {
        'id': 'next',
        'round_id': 'f',
        'match_number': 1,
        'side_a_source_id': 'm',
        'status': 'to_be_arranged',
      },
    ],
  );
  @override
  Future<CompetitionData> load(String club, String id) async => data;
  @override
  Future<void> result(
    String id,
    int a,
    int b,
    String winner, {
    bool confirm = false,
  }) async {
    final m = data.matches.first;
    if (confirm) {
      confirmations++;
      m['status'] = 'completed';
      m['winner_entry_id'] = winner;
      data.matches.last['side_a_entry_id'] = winner;
    } else {
      submissions++;
      m['status'] = 'result_pending';
      m['score_a'] = a;
      m['score_b'] = b;
      m['proposed_winner_entry_id'] = winner;
    }
  }
}

Future<void> open(
  WidgetTester t,
  ResultRepository repo, {
  bool admin = false,
  bool entrant = true,
}) async {
  t.view.physicalSize = const Size(1000, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      home: CompetitionMatchScreen(
        data: repo.data,
        match: repo.data.matches.first,
        canManage: admin,
        canSubmit: entrant,
        repository: repo,
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'Player scoring card is above conditions; submission stays pending without advancing',
    (t) async {
      final repo = ResultRepository();
      await open(t, repo);
      expect(
        t.getTopLeft(find.byKey(const ValueKey('competition-result-card'))).dy,
        lessThan(t.getTopLeft(find.text('Playing conditions')).dy),
      );
      await t.enterText(find.byType(TextField).at(0), '21');
      await t.enterText(find.byType(TextField).at(1), '12');
      await t.tap(find.text('Winner'));
      await t.pumpAndSettle();
      await t.tap(find.text('Alex / Partner').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Submit result for confirmation'));
      await t.pumpAndSettle();
      expect(repo.submissions, 1);
      expect(repo.confirmations, 0);
      expect(repo.data.matches.last['side_a_entry_id'], isNull);
      expect(find.text('Awaiting Club Admin confirmation.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('Confirm 21'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Admin sees pending scores and must submit amendments before confirming',
    (t) async {
      final repo = ResultRepository();
      await repo.result('m', 21, 12, 'a');
      await open(t, repo, admin: true);
      expect(
        t.widget<TextField>(find.byType(TextField).first).controller?.text,
        '21',
      );
      final confirm = find.widgetWithText(
        OutlinedButton,
        'Confirm 21–12 · Alex / Partner wins',
      );
      expect(t.widget<OutlinedButton>(confirm).onPressed, isNotNull);
      await t.enterText(find.byType(TextField).first, '22');
      await t.pumpAndSettle();
      expect(t.widget<OutlinedButton>(confirm).onPressed, isNull);
      await t.tap(find.text('Submit result for confirmation'));
      await t.pumpAndSettle();
      await t.tap(find.text('Confirm 22–12 · Alex / Partner wins'));
      await t.pumpAndSettle();
      expect(repo.confirmations, 1);
      expect(repo.data.matches.last['side_a_entry_id'], 'a');
      expect(find.text('Result confirmed.'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Unrelated viewer cannot enter a result; pending player result is read only',
    (t) async {
      final repo = ResultRepository();
      await open(t, repo, entrant: false);
      expect(find.text('Submit result for confirmation'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    },
  );
  testWidgets('Scoring fits small phone with long pair names', (t) async {
    final repo = ResultRepository();
    repo.data.entries.first['name'] =
        'Anthony Robertson-Jonas / Stewart Harris';
    repo.data.entries.last['name'] = 'Andrew Warren / Matthew Walker';
    await open(t, repo);
    t.view.physicalSize = const Size(320, 650);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('Submit result for confirmation'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
