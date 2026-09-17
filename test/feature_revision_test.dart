import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/releases/feature_revision_controller.dart';
import 'package:bowls_saas/features/releases/feature_revision_scope.dart';

void main() {
  test(
    'baseline remains available; off/on/off follows remote policy',
    () async {
      var revision = 0;
      final c = FeatureRevisionController(loadRevision: () async => revision);
      addTearDown(c.dispose);
      expect(c.allows(0), isTrue);
      expect(c.allows(1), isFalse);
      await c.refresh();
      expect(c.allows(1), isFalse);
      revision = 1;
      await c.refresh();
      expect(c.allows(1), isTrue);
      revision = 0;
      await c.refresh();
      expect(c.allows(1), isFalse);
      expect(c.allows(0), isTrue);
    },
  );
  test(
    'unknown future capabilities never enabled by a higher remote revision',
    () async {
      final c = FeatureRevisionController(loadRevision: () async => 99);
      addTearDown(c.dispose);
      await c.refresh();
      expect(c.allows(1), isTrue);
      expect(c.allows(2), isFalse);
      expect(c.allows(-1), isFalse);
    },
  );
  test(
    'failed refresh clears previously enabled new feature but preserves baseline',
    () async {
      var fail = false;
      final c = FeatureRevisionController(
        loadRevision: () async {
          if (fail) throw StateError('offline');
          return 1;
        },
      );
      addTearDown(c.dispose);
      await c.refresh();
      fail = true;
      await c.refresh();
      expect(c.allows(1), isFalse);
      expect(c.allows(0), isTrue);
      expect(c.error, isNotNull);
      expect(c.loading, isFalse);
    },
  );
  test('late response cannot restore access after logout', () async {
    final pending = Completer<int>();
    final c = FeatureRevisionController(loadRevision: () => pending.future);
    addTearDown(c.dispose);
    final request = c.refresh();
    c.clear();
    pending.complete(1);
    await request;
    expect(c.allows(1), isFalse);
    expect(c.loading, isFalse);
  });
  test('latest refresh wins when earlier request completes later', () async {
    final first = Completer<int>();
    var calls = 0;
    final c = FeatureRevisionController(
      loadRevision: () => ++calls == 1 ? first.future : Future.value(0),
    );
    addTearDown(c.dispose);
    final old = c.refresh();
    await c.refresh();
    first.complete(1);
    await old;
    expect(c.enabledRevision, 0);
  });
  test(
    'disposing during a request does not notify a disposed controller',
    () async {
      final pending = Completer<int>();
      final c = FeatureRevisionController(loadRevision: () => pending.future);
      final request = c.refresh();
      c.dispose();
      pending.complete(1);
      await request;
    },
  );
  testWidgets(
    'UI demonstration appears at revision 1 and disappears at revision 0',
    (tester) async {
      var revision = 0;
      final c = FeatureRevisionController(loadRevision: () async => revision);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        FeatureRevisionScope(
          controller: c,
          child: const MaterialApp(
            home: FeatureRevisionGate(
              revision: 1,
              fallback: Text('Disabled'),
              child: Text('Available'),
            ),
          ),
        ),
      );
      await c.refresh();
      await tester.pump();
      expect(find.text('Disabled'), findsOneWidget);
      revision = 1;
      await c.refresh();
      await tester.pump();
      expect(find.text('Available'), findsOneWidget);
      revision = 0;
      await c.refresh();
      await tester.pump();
      expect(find.text('Available'), findsNothing);
      expect(find.text('Disabled'), findsOneWidget);
    },
  );
}
