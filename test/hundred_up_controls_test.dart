import 'dart:convert';
import 'package:bowls_saas/features/scorecards/local_scorecard_store.dart';
import 'package:bowls_saas/features/scorecards/scorecard.dart';
import 'package:bowls_saas/features/scorecards/scorecard_table.dart';
import 'package:bowls_saas/features/scorecards/scorecard_repository.dart';
import 'package:bowls_saas/features/scorecards/scorecard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class HundredUpMemoryStore extends LocalScorecardStore {
  List<dynamic> cards = [];
  @override
  Future<List<dynamic>> read() async => jsonDecode(jsonEncode(cards)) as List;
  @override
  Future<void> write(List<dynamic> value) async {
    cards = jsonDecode(jsonEncode(value)) as List;
  }
}

void main() {
  Finder point(String side, int value) =>
      find.byKey(ValueKey('100up-$side-$value'));

  for (final width in [360.0, 1100.0]) {
    testWidgets(
      '100 Up toggles, hides counterparts and resets at width $width',
      (t) async {
        t.view.physicalSize = Size(width, 1000);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final card = Scorecard.create()
          ..sideA = 'Blue'
          ..sideB = 'Gold'
          ..scoring = '100up';
        var a = 0, b = 0, end = 1;
        final accepted = <List<int>>[];
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, update) => EndScoreControls(
                  card: card,
                  end: end,
                  a: a,
                  b: b,
                  enabled: true,
                  onChanged: (nextA, nextB) => update(() {
                    a = nextA;
                    b = nextB;
                  }),
                  onAccept: () => update(() {
                    accepted.add([a, b]);
                    end++;
                    a = b = 0;
                  }),
                ),
              ),
            ),
          ),
        );
        FilledButton accept() => t.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Accept end $end'),
        );
        expect(accept().onPressed, isNull);
        await t.tap(point('a', 4));
        await t.pump();
        expect(a, 4);
        expect(point('b', 4), findsNothing);
        expect(point('a', 4), findsOneWidget);
        await t.tap(point('a', 4));
        await t.pump();
        expect([a, b], [0, 0]);
        expect(point('b', 4), findsOneWidget);
        await t.tap(point('a', 4));
        await t.pump();
        await t.tap(point('b', 3));
        await t.pump();
        await t.tap(point('b', 2));
        await t.pump();
        expect(accept().onPressed, isNull);
        await t.tap(point('a', 1));
        await t.pump();
        expect([a, b], [5, 5]);
        expect(accept().onPressed, isNotNull);
        // Releasing an award disables acceptance, and permits moving it.
        await t.tap(point('a', 1));
        await t.pump();
        expect(accept().onPressed, isNull);
        await t.tap(point('b', 1));
        await t.pump();
        expect([a, b], [4, 6]);
        await t.tap(find.text('Accept end 1'));
        await t.pump();
        expect(accepted, [
          [4, 6],
        ]);
        expect(accept().onPressed, isNull);
        for (final side in ['a', 'b']) {
          for (final value in [4, 3, 2, 1]) {
            expect(point(side, value), findsOneWidget);
          }
        }
        // 10–0 and 0–10 remain valid; each value is still assigned once.
        for (final side in ['a', 'b']) {
          for (final value in [4, 3, 2, 1]) {
            await t.tap(point(side, value));
            await t.pump();
          }
          expect(accept().onPressed, isNotNull);
          await t.tap(find.text('Accept end $end'));
          await t.pump();
        }
        expect(accepted, [
          [4, 6],
          [10, 0],
          [0, 10],
        ]);
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Existing totals do not invent awards when correcting a saved end',
    (t) async {
      final card = Scorecard.create()..scoring = '100up';
      var a = 5, b = 5;
      var accepted = false;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, update) => EndScoreControls(
                card: card,
                end: 1,
                a: a,
                b: b,
                enabled: true,
                onChanged: (nextA, nextB) => update(() {
                  a = nextA;
                  b = nextB;
                }),
                onAccept: () => accepted = true,
                onCancel: () {},
              ),
            ),
          ),
        ),
      );
      FilledButton save() => t.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save correction'),
      );
      expect(save().onPressed, isNull);
      for (final value in [4, 3, 2, 1]) {
        await t.tap(point(value == 4 ? 'a' : 'b', value));
        await t.pump();
      }
      expect([a, b], [4, 6]);
      await t.tap(find.text('Save correction'));
      expect(accepted, isTrue);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('Real scorecard saves totals and corrects without advancing', (
    t,
  ) async {
    t.view.physicalSize = const Size(1100, 1500);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final repository = ScorecardRepository(store: HundredUpMemoryStore());
    final card = Scorecard.create()..scoring = '100up';
    final now = DateTime.now().toUtc();
    card.startMatch(now);
    card.startEnd(now);
    await repository.save(card);
    await t.pumpWidget(
      MaterialApp(
        home: ScorecardScreen(card: card, repository: repository),
      ),
    );
    await t.pumpAndSettle();
    for (final value in [4, 3, 2, 1]) {
      await t.tap(point(value == 4 ? 'a' : 'b', value));
      await t.pump();
    }
    await t.tap(find.text('Accept end 1'));
    await t.pumpAndSettle();
    var saved = (await repository.load()).single;
    expect([saved.totalA, saved.totalB], [4, 6]);
    expect(saved.ends.length, 2);
    expect(saved.endInProgress, isTrue);
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Accept end 2'),
          )
          .onPressed,
      isNull,
    );
    final firstEnd = find.byKey(const ValueKey('scorecard-row-0-2'));
    await t.ensureVisible(firstEnd);
    await t.tap(firstEnd);
    await t.pumpAndSettle();
    expect(find.text('Correct end 1'), findsOneWidget);
    for (final value in [4, 3, 2, 1]) {
      await t.tap(point(value == 3 || value == 2 ? 'a' : 'b', value));
      await t.pump();
    }
    await t.tap(find.text('Save correction'));
    await t.pumpAndSettle();
    saved = (await repository.load()).single;
    expect([saved.totalA, saved.totalB], [5, 5]);
    expect(saved.ends.length, 2);
    expect(saved.ends.last['a'], isNull);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
