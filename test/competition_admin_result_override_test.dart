import 'dart:io';
import 'package:bowls_saas/features/scorecards/scorecard.dart';
import 'package:bowls_saas/features/scorecards/scorecard_pdf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/scorecards/shared_scorecard_api.dart';
import 'competition_player_result_screen_test.dart' as fixture;

class DecisionRepository extends fixture.ResultRepository {
  int decisions = 0;
  String? savedReason, savedToken;
  @override
  Future<Map<String, dynamic>> adminResultReview(String id) async => {
    'token': 'latest-card-review',
    'hasShared': true,
    'match': Map<String, dynamic>.from(data.matches.first),
  };
  @override
  Future<void> confirmAdminResult(
    String id,
    int a,
    int b,
    String winner,
    String reason,
    String token,
  ) async {
    decisions++;
    savedReason = reason;
    savedToken = token;
    final m = data.matches.first;
    m['status'] = 'completed';
    m['score_a'] = a;
    m['score_b'] = b;
    m['winner_entry_id'] = winner;
    data.matches.last['side_a_entry_id'] = winner;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Admin decision PDF retains 21 ends and original signed record',
    () async {
      final card = Scorecard.create()
        ..title = 'Synthetic Admin decision verification'
        ..sideA = 'Original challenger'
        ..sideB = 'Original opponent';
      final start = DateTime.utc(2026, 11, 16, 10);
      card.startMatch(start);
      for (var i = 0; i < 21; i++) {
        card.startEnd(start.add(Duration(minutes: i)));
        card.recordEnd(i, 1, 0);
      }
      card.finish(start.add(const Duration(hours: 2)));
      card.fixtureLink = {
        'sharedConfirmed': true,
        'sharedWinnerName': 'Original opponent',
        'sharedAdminDecision': {
          'sideAName': 'Original challenger',
          'sideBName': 'Original opponent',
          'scoreA': 4,
          'scoreB': 21,
          'winnerName': 'Original opponent',
          'reason': 'Checked paper scorecard with both competitors',
        },
      };
      final bytes = await scorecardPdf(card);
      expect(bytes.length, greaterThan(1000));
      expect(scorecardPdfPageCount(card), 1);
      if (const bool.fromEnvironment('ADMIN_DECISION_PDF_QA')) {
        await Directory('tmp/pdfs').create(recursive: true);
        await File('tmp/pdfs/admin-decision-scorecard.pdf').writeAsBytes(bytes);
      }
      expect(card.totalA, 21);
      expect(card.totalB, 0);
    },
  );

  testWidgets(
    'Returned shared card hides manual save; explicit Admin decision requires reason and confirms correct winner',
    (t) async {
      final repo = DecisionRepository();
      repo.data.matches.first['fixture_id'] = 'shared-fixture';
      await fixture.open(t, repo, admin: true);
      expect(find.text('Submit result for confirmation'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      await t.tap(find.text('Record Admin decision'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('admin-score-a')), '4');
      await t.enterText(find.byKey(const ValueKey('admin-score-b')), '21');
      await t.tap(find.text('Winning entry'));
      await t.pumpAndSettle();
      await t.tap(find.text('Blair / Partner').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Confirm Admin result and advance winner'));
      await t.pumpAndSettle();
      expect(repo.decisions, 0);
      expect(find.textContaining('give a reason'), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('admin-decision-reason')),
        'Checked paper card with both players',
      );
      await t.tap(find.text('Confirm Admin result and advance winner'));
      await t.pumpAndSettle();
      expect(repo.decisions, 1);
      expect(repo.submissions, 0);
      expect(repo.confirmations, 0);
      expect(repo.savedToken, 'latest-card-review');
      expect(repo.savedReason, 'Checked paper card with both players');
      expect(repo.data.matches.last['side_a_entry_id'], 'b');
      expect(find.text('Result confirmed.'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('Players cannot see Admin decision control', (t) async {
    final repo = DecisionRepository();
    await fixture.open(t, repo);
    expect(find.text('Record Admin decision'), findsNothing);
  });
  test(
    'Admin decision winner supersedes the original scorecard winner in saved metadata',
    () {
      final meta = SharedScorecardApi.confirmationMetadata({
        'competitionStatus': 'completed',
        'totalA': 21,
        'totalB': 4,
        'document': {'sideA': 'Original A', 'sideB': 'Original B'},
        'adminDecision': {'winnerName': 'Actual B', 'scoreA': 4, 'scoreB': 21},
      });
      expect(meta['sharedConfirmed'], true);
      expect(meta['sharedWinnerName'], 'Actual B');
      expect(meta['sharedAdminDecision'], isNotNull);
    },
  );
}
