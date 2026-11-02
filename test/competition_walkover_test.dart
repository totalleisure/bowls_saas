import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/competitions/competition_repository.dart';
import 'package:bowls_saas/features/competitions/competition_bracket_pdf.dart';
import 'package:bowls_saas/features/competitions/screens/competition_season_screen.dart';
import 'competition_player_result_screen_test.dart' show ResultRepository;

class WalkoverRepository extends ResultRepository {
  int awards = 0;
  String? reason, note;
  @override
  Future<CompetitionRow?> walkoverAudit(String matchId) async => {
    'reason': reason,
    'note': note,
    'recorded_at': '2026-11-01',
  };
  @override
  Future<void> awardWalkover(
    CompetitionRow match,
    String winner,
    String reason,
    String note,
  ) async {
    awards++;
    this.reason = reason;
    this.note = note;
    data.matches.first.addAll({
      'status': 'completed',
      'result_kind': 'walkover',
      'winner_entry_id': winner,
      'score_a': null,
      'score_b': null,
    });
    data.matches.last['side_a_entry_id'] = winner;
  }
}

Future<void> openMatch(
  WidgetTester t,
  WalkoverRepository repo, {
  bool admin = true,
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
        canSubmit: true,
        ownEntryIds: const {'a'},
        repository: repo,
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('Only Admin sees walkover action; cancel never changes result', (
    t,
  ) async {
    final repo = WalkoverRepository();
    await openMatch(t, repo, admin: false);
    expect(find.text('Award walkover'), findsNothing);
  });
  testWidgets(
    'Walkover validates winner/reason, cancels safely, records Other and displays W/O without scores',
    (t) async {
      final repo = WalkoverRepository();
      await openMatch(t, repo);
      await t.tap(find.text('Award walkover'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(repo.awards, 0);
      await t.tap(find.text('Award walkover'));
      await t.pumpAndSettle();
      await t.tap(find.text('Confirm walkover'));
      await t.pumpAndSettle();
      expect(repo.awards, 0);
      expect(
        find.textContaining('Choose the winning entry and reason'),
        findsOneWidget,
      );
      await t.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await t.pumpAndSettle();
      await t.tap(find.text('Alex / Partner').last);
      await t.pumpAndSettle();
      await t.tap(find.byType(DropdownButtonFormField<String>).last);
      await t.pumpAndSettle();
      await t.tap(find.text('Other').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Confirm walkover'));
      await t.pumpAndSettle();
      expect(repo.awards, 0);
      await t.enterText(
        find.widgetWithText(
          TextFormField,
          'Admin explanation (required for Other)',
        ),
        'Private synthetic explanation',
      );
      await t.tap(find.text('Confirm walkover'));
      await t.pumpAndSettle();
      expect(repo.awards, 1);
      expect(repo.reason, 'other');
      expect(find.text('Walkover (W/O)'), findsOneWidget);
      expect(
        find.textContaining('Private synthetic explanation'),
        findsNothing,
      );
      expect(find.text('Award walkover'), findsNothing);
      expect(repo.data.matches.last['side_a_entry_id'], 'a');
      await t.tap(find.text('View walkover audit'));
      await t.pumpAndSettle();
      expect(
        find.textContaining('Private synthetic explanation'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );
  test(
    'PDF side includes W/O only for winning entry, with no invented score',
    () {
      final repo = WalkoverRepository();
      final m = repo.data.matches.first
        ..addAll({
          'status': 'completed',
          'result_kind': 'walkover',
          'winner_entry_id': 'a',
        });
      expect(
        competitionPrintedSide(repo.data, m, 'a', includeScore: true),
        'Alex / Partner  (W/O)',
      );
      expect(
        competitionPrintedSide(repo.data, m, 'b', includeScore: true),
        'Blair / Partner',
      );
    },
  );
}
