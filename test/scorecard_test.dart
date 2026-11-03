import 'package:flutter/gestures.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/scorecards/scorecard.dart';
import 'package:bowls_saas/features/scorecards/local_scorecard_store_io.dart';
import 'package:bowls_saas/features/scorecards/scorecard_repository.dart';
import 'package:bowls_saas/features/scorecards/scorecard_screen.dart';
import 'package:bowls_saas/features/scorecards/scorecard_pdf.dart';
import 'package:bowls_saas/features/scorecards/scorecard_table.dart';

class MemoryScorecardStore extends LocalScorecardStore {
  List<dynamic> cards = [];
  @override
  Future<List<dynamic>> read() async => jsonDecode(jsonEncode(cards)) as List;
  @override
  Future<void> write(List<dynamic> value) async {
    cards = jsonDecode(jsonEncode(value)) as List;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final start = DateTime.utc(2026, 11, 3, 10);
  Scorecard make() => Scorecard.create()
    ..title = 'Offline test match'
    ..sideA = 'Blue'
    ..sideB = 'Gold';
  final signature = <List<Map<String, double>>>[
    [
      {'x': .1, 'y': .3},
      {'x': .5, 'y': .7},
      {'x': .9, 'y': .2},
    ],
  ];
  test(
    'Last jack blocks a new end at cutoff but current end and earlier corrections remain writable',
    () {
      final c = make()..lastJackMinutes = 140;
      c.startMatch(start);
      c.startEnd(start);
      c.recordEnd(0, 2, 0);
      c.startEnd(start.add(const Duration(minutes: 139, seconds: 59)));
      expect(
        c.deadlineReached(start.add(const Duration(minutes: 140))),
        isTrue,
      );
      c.recordEnd(1, 0, 3);
      c.recordEnd(0, 4, 0);
      expect(c.totalA, 4);
      expect(c.totalB, 3);
      expect(
        () => c.startEnd(start.add(const Duration(minutes: 140))),
        throwsStateError,
      );
      expect(
        c.history.where((h) => h['action'] == 'Score recorded: end 1').length,
        2,
      );
    },
  );
  test(
    'Accepting the current end advances once; corrections never append an end',
    () {
      final c = make()..maxEnds = 3;
      c.startMatch(start);
      c.startEnd(start);
      c.acceptEndScore(0, 2, 0, start);
      expect(c.ends.length, 2);
      expect(c.endInProgress, isTrue);
      c.acceptEndScore(0, 3, 0, start);
      expect(c.ends.length, 2);
      c.acceptEndScore(1, 0, 1, start);
      expect(c.ends.length, 3);
      c.acceptEndScore(2, 1, 0, start);
      expect(c.ends.length, 3);
      expect(c.endInProgress, isFalse);
      expect(c.cannotStartEnd(start), contains('ends'));
    },
  );
  test(
    'Auto-advance respects last-jack deadline and target; finishing discards unused auto-end',
    () {
      final c = make()..lastJackMinutes = 140;
      c.startMatch(start);
      c.startEnd(start);
      c.acceptEndScore(0, 1, 0, start.add(const Duration(minutes: 140)));
      expect(c.ends.length, 1);
      final target = make()..target = 2;
      target.startMatch(start);
      target.startEnd(start);
      target.acceptEndScore(0, 2, 0, start);
      expect(target.ends.length, 1);
      final unlimited = make();
      unlimited.startMatch(start);
      unlimited.startEnd(start);
      unlimited.acceptEndScore(0, 1, 0, start);
      unlimited.finish(start);
      expect(unlimited.ends.length, 1);
      expect(unlimited.complete, isTrue);
    },
  );
  test(
    'Normal shots rejects scoring on both sides; 100 Up accepts both and validates ten',
    () {
      final c = make();
      c.startMatch(start);
      c.startEnd(start);
      expect(() => c.recordEnd(0, 4, 6), throwsStateError);
      c.scoring = '100up';
      c.recordEnd(0, 4, 6);
      expect([c.totalA, c.totalB], [4, 6]);
      expect(() => c.recordEnd(0, 4, 5), throwsStateError);
      expect(() => c.recordEnd(0, -1, 11), throwsStateError);
    },
  );
  test(
    'Signed handicap, target and ends limit apply without starting an extra end',
    () {
      final c = make()
        ..handicapA = -2
        ..handicapB = 3
        ..target = 5;
      c.startMatch(start);
      c.startEnd(start);
      c.recordEnd(0, 0, 2);
      expect([c.totalA, c.totalB], [-2, 5]);
      expect(c.cannotStartEnd(start), contains('target'));
      c.target = null;
      c.maxEnds = 1;
      expect(c.cannotStartEnd(start), contains('ends'));
    },
  );
  test('Restored timer uses saved UTC start; backward clock is flagged', () {
    final c = make()..lastJackMinutes = 140;
    c.startMatch(start);
    final restored = Scorecard.fromJson(jsonDecode(jsonEncode(c.toJson())));
    expect(
      restored.elapsedSeconds(start.add(const Duration(minutes: 139))),
      139 * 60,
    );
    expect(
      restored.cannotStartEnd(start.subtract(const Duration(seconds: 1))),
      contains('clock'),
    );
  });
  test(
    'Signatures bind to finished revision; reopen and correction clear both signatures',
    () {
      final c = make();
      c.startMatch(start);
      c.startEnd(start);
      c.recordEnd(0, 2, 0);
      expect(() => c.sign(true, 'Player A', signature), throwsStateError);
      c.finish(start.add(const Duration(minutes: 5)));
      c.sign(true, 'Player A', signature);
      c.sign(false, 'Player B', signature);
      expect(c.signatureA!['revision'], c.revision);
      expect(c.signatureB, isNotNull);
      expect(() => c.recordEnd(0, 0, 3), throwsStateError);
      c.reopen();
      expect(c.signatureA, isNull);
      expect(c.signatureB, isNull);
      c.recordEnd(0, 0, 3);
      expect(c.totalB, 3);
      final restored = Scorecard.fromJson(jsonDecode(jsonEncode(c.toJson())));
      expect(restored.history.length, c.history.length);
    },
  );
  test(
    'Repository survives new instance, serialises concurrent saves and retains another card',
    () async {
      final d = await Directory.systemTemp.createTemp('bowls-scorecard-test-');
      addTearDown(() => d.delete(recursive: true));
      final repo = ScorecardRepository(
        store: LocalScorecardStore(directory: d),
      );
      final a = make(), b = make();
      a.startMatch(start);
      a.startEnd(start);
      a.recordEnd(0, 1, 0);
      await Future.wait([repo.save(a), repo.save(b)]);
      final reopened = ScorecardRepository(
        store: LocalScorecardStore(directory: d),
      );
      final cards = await reopened.load();
      expect(cards.length, 2);
      expect(cards.singleWhere((c) => c.id == a.id).totalA, 1);
    },
  );
  test('A stale editor cannot overwrite a newer saved scorecard', () async {
    final repo = ScorecardRepository(store: MemoryScorecardStore());
    final card = make();
    await repo.save(card);
    final first = (await repo.load()).single,
        stale = (await repo.load()).single;
    first.startMatch(start);
    await repo.save(first);
    stale.title = 'Old copy';
    await expectLater(repo.save(stale), throwsStateError);
    expect((await repo.load()).single.startedAt, start);
  });
  test(
    'Interrupted latest save falls back to previous generation; total corruption never silently resets',
    () async {
      final d = await Directory.systemTemp.createTemp(
        'bowls-scorecard-recovery-',
      );
      addTearDown(() => d.delete(recursive: true));
      final store = LocalScorecardStore(directory: d);
      await store.write([
        {'saved': 1},
      ]);
      await store.write([
        {'saved': 2},
      ]);
      await File('${d.path}/cards-0.json').writeAsString('{broken');
      expect((await store.read()).single['saved'], 1);
      await File('${d.path}/cards-1.json').writeAsString('{broken');
      expect(store.read(), throwsFormatException);
    },
  );
  test(
    'PDF exports Unicode names, scores and both signatures in paper-card format',
    () async {
      final c = make()
        ..playersA = 'André — Lead'
        ..playersB = 'O’Connor — Skip';
      c.startMatch(start);
      c.startEnd(start);
      c.recordEnd(0, 2, 0);
      c.finish(start.add(const Duration(minutes: 5)));
      c.sign(true, 'André', signature);
      c.sign(false, 'O’Connor', signature);
      final bytes = await scorecardPdf(c);
      expect(ascii.decode(bytes.take(4).toList()), '%PDF');
      expect(bytes.length, greaterThan(1000));
      if (const bool.fromEnvironment('SCORECARD_QA_EXPORT')) {
        await File('tmp/scorecard-qa.pdf').writeAsBytes(bytes);
      }
      expect(signatureSvg(c.signatureA!), contains('polyline'));
    },
  );
  testWidgets(
    'Portrait scorecard starts, records an end and reopens the locally saved score',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final repo = ScorecardRepository(store: MemoryScorecardStore());
      final c = make();
      await repo.save(c);
      await t.pumpWidget(
        MaterialApp(
          home: ScorecardScreen(card: c, repository: repo),
        ),
      );
      await t.tap(find.text('Start match timer'));
      await t.pumpAndSettle();
      await t.tap(find.text('Jack delivered / Start end 1'));
      await t.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await t.tap(find.byTooltip('Add shot for Blue'));
        await t.pump();
      }
      await t.tap(find.text('Accept end 1'));
      await t.pumpAndSettle();
      expect(find.text('Accept end 2'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      final saved = (await repo.load()).single;
      expect(saved.totalA, 3);
      expect(saved.endInProgress, isTrue);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'A drawn signature and printed name are returned for the reviewed score',
    (t) async {
      SignatureResult? result;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<SignatureResult>(
                    MaterialPageRoute(
                      builder: (_) => const SignatureScreen(
                        sideName: 'Blue',
                        score: '21 : 15',
                      ),
                    ),
                  );
                },
                child: const Text('Sign'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Sign'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'A Player');
      t.testTextInput.hide();
      await t.pumpAndSettle();
      final pad = find.byKey(const ValueKey('scorecard-signature-pad'));
      final point = t.getCenter(pad);
      final gesture = await t.startGesture(point - const Offset(60, 20));
      await gesture.moveBy(const Offset(80, 35));
      await gesture.moveBy(const Offset(40, -30));
      await gesture.up();
      await t.pump();
      await t.ensureVisible(find.text('Accept and save signature'));
      await t.tap(find.text('Accept and save signature'));
      await t.pumpAndSettle();
      expect(result?.name, 'A Player');
      expect(result!.strokes.single.length, greaterThan(1));
      expect(
        result!.strokes.single.every(
          (p) => p['x']! >= 0 && p['x']! <= 1 && p['y']! >= 0 && p['y']! <= 1,
        ),
        isTrue,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Static controls remain visible while paper card scrolls; earlier end edits use the same bar',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final repo = ScorecardRepository(store: MemoryScorecardStore());
      final c = make()
        ..sideB = 'Lewisham & Crystal Palace Bowls Club'
        ..handicapA = -2
        ..handicapB = 2;
      final time = DateTime.now().toUtc();
      c.startMatch(time);
      for (var i = 0; i < 24; i++) {
        c.startEnd(time);
        c.recordEnd(i, 1, 0);
      }
      await repo.save(c);
      await t.pumpWidget(
        MaterialApp(
          home: ScorecardScreen(card: c, repository: repo),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Shots'), findsNWidgets(2));
      expect(find.text('End'), findsOneWidget);
      final header = find.byKey(
        const ValueKey('scorecard-fixed-column-header'),
      );
      final headerY = t.getTopLeft(header).dy;
      expect(
        t.getCenter(find.byTooltip('Add shot for Blue')).dy,
        t
            .getCenter(
              find.byTooltip(
                'Add shot for Lewisham & Crystal Palace Bowls Club',
              ),
            )
            .dy,
      );
      final startEnd = find.text('Jack delivered / Start end 25');
      expect(startEnd.hitTestable(), findsOneWidget);
      await t.drag(find.byType(ListView), const Offset(0, -1600));
      await t.pumpAndSettle();
      expect(startEnd.hitTestable(), findsOneWidget);
      expect(header.hitTestable(), findsOneWidget);
      expect(t.getTopLeft(header).dy, headerY);
      await t.drag(find.byType(ListView), const Offset(0, 2500));
      await t.pumpAndSettle();
      final first = find.byKey(const ValueKey('scorecard-row-0-2'));
      await t.ensureVisible(first);
      await t.pumpAndSettle();
      expect(first.hitTestable(), findsOneWidget);
      await t.tap(first);
      await t.pumpAndSettle();
      expect(find.text('Correct end 1'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await t.tap(find.byTooltip('Add shot for Blue'));
      await t.pump();
      await t.tap(find.text('Save correction'));
      await t.pumpAndSettle();
      final saved = (await repo.load()).single;
      expect(saved.ends.first['a'], 2);
      expect(saved.totalA, 23);
      expect(saved.totalB, 2);
      expect(saved.ends.length, 24);
      expect(find.text('Jack delivered / Start end 25'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Final end is highlighted in the scoring pill', (t) async {
    final c = make()..maxEnds = 18;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EndScoreControls(
            card: c,
            end: 18,
            a: 0,
            b: 0,
            enabled: true,
            onChanged: (_, _) {},
            onAccept: () {},
          ),
        ),
      ),
    );
    expect(find.text('Score end 18 · LAST END'), findsOneWidget);
  });
  for (final kind in [
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
  ]) {
    testWidgets(
      'Signature coordinates follow ${kind.name} exactly at scaled display size',
      (t) async {
        t.view.physicalSize = const Size(900, 1300);
        t.view.devicePixelRatio = 2;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        SignatureResult? result;
        await t.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await Navigator.of(context).push<SignatureResult>(
                      MaterialPageRoute(
                        builder: (_) => const SignatureScreen(
                          sideName: 'Left side',
                          score: '21 : 15',
                        ),
                      ),
                    );
                  },
                  child: const Text('Open signature'),
                ),
              ),
            ),
          ),
        );
        await t.tap(find.text('Open signature'));
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField), 'A Player');
        t.testTextInput.hide();
        await t.pumpAndSettle();
        final pad = find.byKey(const ValueKey('scorecard-signature-pad'));
        final canvas = find.descendant(
          of: pad,
          matching: find.byType(CustomPaint),
        );
        final rect = t.getRect(canvas);
        final first = rect.topLeft + Offset(rect.width * .2, rect.height * .3);
        final last = rect.topLeft + Offset(rect.width * .7, rect.height * .8);
        final gesture = await t.startGesture(first, kind: kind);
        await gesture.moveTo(last);
        await t.pump();
        expect(
          t.getTopLeft(canvas),
          rect.topLeft,
          reason: 'Drawing must not scroll the signature surface',
        );
        await gesture.up();
        await t.pump();
        await t.ensureVisible(find.text('Accept and save signature'));
        await t.pumpAndSettle();
        await t.tap(find.text('Accept and save signature'));
        await t.pumpAndSettle();
        expect(result!.strokes.single.first['x'], closeTo(.2, .001));
        expect(result!.strokes.single.first['y'], closeTo(.3, .001));
        expect(result!.strokes.single.last['x'], closeTo(.7, .001));
        expect(result!.strokes.single.last['y'], closeTo(.8, .001));
        expect(t.takeException(), isNull);
      },
    );
  }
  test(
    'Paper card fits 21 ends per page; continuation and audit exports retain the format',
    () async {
      final c = make()
        ..playersA = 'Player One (Lead)\nPlayer Two (Skip)'
        ..playersB = 'Player Three (Lead)\nPlayer Four (Skip)'
        ..sideB = 'Lewisham & Crystal Palace Indoor Bowls Club'
        ..notes = '18 ends or 2.5 hours; last jack before 2 hr 20 min.'
        ..format = 'Pairs'
        ..durationMinutes = 150
        ..lastJackMinutes = 140;
      c.startMatch(start);
      for (var i = 0; i < 21; i++) {
        c.startEnd(start);
        c.recordEnd(i, i.isEven ? 2 : 0, i.isEven ? 0 : 1);
      }
      expect(scorecardPdfPageCount(c), 1);
      if (const bool.fromEnvironment('SCORECARD_QA_EXPORT')) {
        final one = Scorecard.fromJson(jsonDecode(jsonEncode(c.toJson())));
        one.finish(start);
        one.sign(true, 'Player One', signature);
        one.sign(false, 'Player Three', signature);
        await File(
          'tmp/scorecard-qa-21.pdf',
        ).writeAsBytes(await scorecardPdf(one));
      }
      for (var i = 21; i < 43; i++) {
        c.startEnd(start);
        c.recordEnd(i, 1, 0);
      }
      expect(scorecardPdfPageCount(c), 3);
      c.finish(start);
      c.sign(true, 'Player One', signature);
      c.sign(false, 'Player Three', signature);
      final plain = await scorecardPdf(c);
      final audit = await scorecardPdf(c, includeAudit: true);
      expect(audit.length, greaterThan(plain.length));
      if (const bool.fromEnvironment('SCORECARD_QA_EXPORT')) {
        await File('tmp/scorecard-qa-43.pdf').writeAsBytes(audit);
      }
    },
  );
}
