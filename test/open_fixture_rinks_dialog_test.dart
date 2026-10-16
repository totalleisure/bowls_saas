import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/fixtures/open_fixture_rinks_dialog.dart';

void main() {
  Future<void> open(WidgetTester tester, Future<void> Function(int) save,
      {int required = 4, int assigned = 3}) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
      Scaffold(body: TextButton(onPressed: () => showDialog<bool>(
        context: context, builder: (_) => OpenFixtureRinksDialog(
          initialRequired: required, assigned: assigned, maximum: 6, onSave: save,
        )), child: const Text('Open'))))));
    await tester.tap(find.text('Open')); await tester.pumpAndSettle();
  }

  testWidgets('reduce unused requirement and save, without unassigning a rink', (tester) async {
    int? saved;
    await open(tester, (n) async => saved = n);
    await tester.tap(find.byTooltip('Reduce rinks required')); await tester.pump();
    expect(find.text('0 awaiting assignment'), findsOneWidget);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.remove_circle_outline)).onPressed, isNull);
    await tester.tap(find.text('Save')); await tester.pumpAndSettle();
    expect(saved, 3); expect(find.byType(OpenFixtureRinksDialog), findsNothing);
  });

  testWidgets('all assigned prevents reduction; cancel does not save', (tester) async {
    var saved = false;
    await open(tester, (_) async => saved = true, assigned: 4);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.remove_circle_outline)).onPressed, isNull);
    await tester.tap(find.text('Cancel')); await tester.pumpAndSettle();
    expect(saved, false);
  });

  testWidgets('save is single flight and server error leaves dialog open', (tester) async {
    final pending = Completer<void>(); var calls = 0;
    await open(tester, (_) { calls++; return pending.future; });
    await tester.tap(find.byTooltip('Increase rinks required')); await tester.pump();
    await tester.tap(find.text('Save')); await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(calls, 1);
    pending.completeError('The rink assignments have changed.'); await tester.pumpAndSettle();
    expect(find.text('The rink assignments have changed.'), findsOneWidget);
    expect(find.byType(OpenFixtureRinksDialog), findsOneWidget);
  });
}
