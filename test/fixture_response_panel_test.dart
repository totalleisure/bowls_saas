import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/fixtures/widgets/fixture_response_panel.dart';

Widget app({
  bool acceptance = false,
  String? status,
  required Future<void> Function(String) save,
}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: FixtureResponsePanel(
        acceptance: acceptance,
        status: status,
        onResponse: save,
      ),
    ),
  ),
);

void main() {
  for (final embedded in [true, false]) {
    for (final status in <String?>[null, 'yes', 'no', 'maybe']) {
      testWidgets('RSVP colours, borders and legacy state: $embedded / $status', (tester) async {
        tester.view.physicalSize = const Size(320, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(backgroundColor: Colors.red, body: SingleChildScrollView(
            child: FixtureResponsePanel(embedded: embedded, status: status, onResponse: (_) async {}),
          )),
        )));
        expect(find.text('Maybe'), findsNothing);
        expect(find.textContaining('Your response:'), findsNothing);
        final buttons = tester.widgetList<FilledButton>(find.byType(FilledButton)).toList();
        expect(buttons, hasLength(2));
        for (var i = 0; i < 2; i++) {
          final selected = status == (i == 0 ? 'yes' : 'no');
          expect(buttons[i].style!.side!.resolve({})!.color, Colors.black);
          expect(buttons[i].style!.backgroundColor!.resolve({}), selected
            ? (i == 0 ? const Color(0xFF2E7D32) : const Color(0xFFB71C1C)) : Colors.white);
        }
        if (status == 'maybe') expect(find.textContaining('Previously answered Maybe'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('RSVP choices send correct persisted values', (tester) async {
    final responses = <String>[];
    await tester.pumpWidget(app(save: (value) async => responses.add(value)));
    expect(find.text('Let the Fixture Captain know if you are:'), findsOneWidget);
    for (final label in ['Available', 'Not available']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    expect(responses, ['yes', 'no']);
  });

  testWidgets('acceptance is explicit and distinct from availability', (
    tester,
  ) async {
    final responses = <String>[];
    await tester.pumpWidget(
      app(
        acceptance: true,
        status: 'pending',
        save: (value) async => responses.add(value),
      ),
    );
    expect(find.text('You’ve been selected—please respond'), findsOneWidget);
    expect(find.text('Maybe'), findsNothing);
    await tester.tap(find.text('Accept selection'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Decline selection'));
    await tester.pumpAndSettle();
    expect(responses, ['accepted', 'declined']);
  });

  testWidgets('saving prevents duplicate or conflicting submissions', (
    tester,
  ) async {
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      app(
        save: (_) {
          calls++;
          return pending.future;
        },
      ),
    );
    await tester.tap(find.text('Available'));
    await tester.pump();
    await tester.tap(find.text('Not available'));
    expect(calls, 1);
    expect(find.text('Saving response…'), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not available'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('failure retains prior choice and permits retry', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      app(
        status: 'maybe',
        save: (_) async {
          if (++calls == 1) throw StateError('offline');
        },
      ),
    );
    await tester.tap(find.text('Available'));
    await tester.pumpAndSettle();
    expect(
      find.text('Previously answered Maybe—please update.'),
      findsOneWidget,
    );
    expect(
      find.text('Could not save your response. Please try again.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Not available'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(
      find.text('Could not save your response. Please try again.'),
      findsNothing,
    );
  });

  testWidgets('saved response stays visible and can be changed', (
    tester,
  ) async {
    var status = 'yes';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => FixtureResponsePanel(
              status: status,
              onResponse: (value) async => update(() => status = value),
            ),
          ),
        ),
      ),
    );
    expect(find.text("You've told the Fixture Captain you are:"), findsOneWidget);
    await tester.tap(find.text('Not available'));
    await tester.pumpAndSettle();
    expect(find.text("You've told the Fixture Captain you are:"), findsOneWidget);
    expect(find.text('✓ Not available'), findsOneWidget);
  });

  testWidgets('phone width and enlarged text fit without overflow', (
    tester,
  ) async {
    tester.view.resetPhysicalSize();
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: FixtureResponsePanel(
                acceptance: true,
                status: 'pending',
                onResponse: (_) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
