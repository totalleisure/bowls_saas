import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/scorecards/local_scorecard_store_io.dart';
import 'package:bowls_saas/features/scorecards/scorecard.dart';
import 'package:bowls_saas/features/scorecards/scorecard_repository.dart';
import 'package:bowls_saas/features/scorecards/scorecard_recovery_host.dart';

class RecoveryMemoryStore extends LocalScorecardStore {
  List<dynamic> cards = [];
  @override
  Future<List<dynamic>> read() async => jsonDecode(jsonEncode(cards)) as List;
  @override
  Future<void> write(List<dynamic> value) async {
    cards = jsonDecode(jsonEncode(value)) as List;
  }
}

void main() {
  Scorecard active() {
    final c = Scorecard.create()
      ..title = 'Interrupted match'
      ..lastJackMinutes = 140;
    final start = DateTime.now().toUtc().subtract(const Duration(minutes: 141));
    c.startMatch(start);
    c.startEnd(start);
    c.recordEnd(0, 3, 0);
    c.startEnd(start.add(const Duration(minutes: 139)));
    return c;
  }

  testWidgets(
    'Cold restart detects unfinished scorecard, resumes scores and enforces elapsed deadline offline',
    (t) async {
      final store = RecoveryMemoryStore();
      final first = ScorecardRepository(store: store);
      final c = active();
      await first.save(c);
      final restored = ScorecardRepository(store: store);
      final access = ValueNotifier('Club App');
      addTearDown(access.dispose);
      await t.pumpWidget(
        ScorecardRecoveryHost(
          repository: restored,
          child: ValueListenableBuilder<String>(
            valueListenable: access,
            builder: (_, value, _) =>
                MaterialApp(home: Scaffold(body: Text(value))),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Unfinished scorecard found'), findsOneWidget);
      await t.tap(find.text('Resume scorecard'));
      await t.pumpAndSettle();
      expect(find.textContaining('3 : 0'), findsOneWidget);
      expect(find.text('Accept end 2'), findsOneWidget);
      expect(
        find.text('Last-jack deadline reached — complete the current end.'),
        findsOneWidget,
      );
      access.value = 'Club access expired / database offline';
      await t.pumpAndSettle();
      expect(find.text('Accept end 2'), findsOneWidget);
      expect(find.text('Club access expired / database offline'), findsNothing);
      expect((await restored.load()).single.startedAt, c.startedAt);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Not now keeps saved match and local scoring can be reopened independently',
    (t) async {
      final repo = ScorecardRepository(store: RecoveryMemoryStore());
      await repo.save(active());
      await t.pumpWidget(
        ScorecardRecoveryHost(
          repository: repo,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => openOfflineScorecards(context),
                  child: const Text('Local cards'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Not now — continue to Club App'));
      await t.pumpAndSettle();
      expect(find.text('Local cards'), findsOneWidget);
      expect((await repo.load()).single.complete, isFalse);
      await t.tap(find.text('Local cards'));
      await t.pumpAndSettle();
      expect(find.text('Electronic Scorecards'), findsOneWidget);
      expect(find.text('Interrupted match'), findsOneWidget);
      await t.tap(find.byTooltip('Return to Club App'));
      await t.pumpAndSettle();
      expect(find.text('Local cards'), findsOneWidget);
    },
  );
  testWidgets('Completed and unstarted cards do not trigger scoring recovery', (
    t,
  ) async {
    final repo = ScorecardRepository(store: RecoveryMemoryStore());
    final c = active();
    c.recordEnd(1, 0, 2);
    c.finish(DateTime.now().toUtc());
    await repo.save(c);
    await repo.save(Scorecard.create());
    await t.pumpWidget(
      ScorecardRecoveryHost(
        repository: repo,
        child: const MaterialApp(home: Scaffold(body: Text('Normal startup'))),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Normal startup'), findsOneWidget);
    expect(find.text('Unfinished scorecard found'), findsNothing);
  });
}
