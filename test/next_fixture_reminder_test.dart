import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/fixtures/next_fixture_reminder_button.dart';
import 'package:bowls_saas/features/fixtures/next_fixture_reminder.dart';

void main() {
  testWidgets('urgent response precedes accepted card and opens response details', (tester) async {
    String? opened;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => NextFixtureReminder(
        context: context, clubName: 'Club', nextMatch: null,
        now: () => DateTime.utc(2026, 10, 10, 12),
        fixtures: [
          {'id': 'accepted', 'start_at': '2026-10-16T12:00:00Z', 'competition_type': {'is_internal': true}, 'team_name': 'Later accepted'},
          {'id': 'pending', 'start_at': '2026-10-13T12:00:00Z', 'competition_type': {'is_internal': true}, 'team_name': 'Earlier pending', '_reminderAcceptance': 'pending'},
        ], openFixture: (id) async => opened = id,
      ).show(), child: const Text('Open')),
    ))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Response needed • Match in 3 days time'), findsOneWidget);
    expect(tester.getTopLeft(find.textContaining('Earlier pending')).dy,
      lessThan(tester.getTopLeft(find.textContaining('Later accepted')).dy));
    await tester.tap(find.text('Review and respond'));
    await tester.pumpAndSettle();
    expect(opened, 'pending');
  });
  final fixture = <String, dynamic>{
    'id': 'match-1',
    'start_at': '2026-10-10T13:00:00Z',
    'is_home': true,
  };
  Widget app({required Future<Map<String, dynamic>?> Function() loader,
    bool automatic = false, Future<void> Function(String)? open}) => MaterialApp(
    home: Scaffold(appBar: AppBar(actions: [NextFixtureReminderButton(
      clubId: 'club', clubName: 'Bowls', loader: loader,
      showOnOpen: automatic,
      now: () => DateTime.parse('2026-10-10T12:49:00+01:00'),
      openFixture: open,
    )])),
  );

  testWidgets('manual reminder uses corrected countdown and opens fixture', (tester) async {
    String? opened;
    await tester.pumpWidget(app(loader: () async => fixture,
      open: (id) async => opened = id));
    await tester.tap(find.byTooltip('Next match'));
    await tester.pumpAndSettle();
    expect(find.text('Your next match is in 1 hour 11 mins time'), findsOneWidget);
    expect(find.text('Saturday 10 October 2026 • 14:00'), findsOneWidget);
    await tester.tap(find.text('View fixture'));
    await tester.pumpAndSettle();
    expect(opened, 'match-1');
  });

  for (final status in ['accepted', 'pending']) {
    testWidgets('cancelled $status selection opens cancellation notice', (tester) async {
      String? opened;
      await tester.pumpWidget(app(automatic: true, loader: () async => {
        ...fixture, 'cancelled_at': '2026-10-09T12:00:00Z',
        '_reminderAcceptance': status,
      }, open: (id) async => opened = id));
      await tester.pumpAndSettle();
      expect(find.text('CANCELLED'), findsOneWidget);
      expect(find.textContaining('This fixture was due in'), findsOneWidget);
      expect(find.textContaining('Your next match is in'), findsNothing);
      expect(find.textContaining('Response needed'), findsNothing);
      expect(find.text('Review and respond'), findsNothing);
      expect(find.text('Navigate'), findsNothing);
      await tester.tap(find.text('View fixture'));
      await tester.pumpAndSettle();
      expect(opened, 'match-1');
    });
  }

  testWidgets('start-screen reminder opens automatically only once', (tester) async {
    var loads = 0;
    await tester.pumpWidget(app(automatic: true, loader: () async {
      loads++;
      return fixture;
    }));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your next match is in'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(loads, 1);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('no match is quiet automatically and explained when requested', (tester) async {
    await tester.pumpWidget(app(automatic: true, loader: () async => null));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.byTooltip('Next match'));
    await tester.pumpAndSettle();
    expect(find.text('You have no upcoming accepted matches or responses due within seven days.'), findsOneWidget);
  });

  testWidgets('failed loading can be retried', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(app(loader: () async {
      if (++attempts == 1) throw StateError('offline');
      return fixture;
    }));
    await tester.tap(find.byTooltip('Next match'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load your next match. Please try again.'), findsOneWidget);
    await tester.tap(find.byTooltip('Next match'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your next match is in'), findsOneWidget);
  });

  testWidgets('away reminder displays the playing venue, not our club', (tester) async {
    await tester.pumpWidget(app(loader: () async => {
      ...fixture,
      'is_home': false,
      'venue': {'id': 'away', 'name': 'White Oak', 'address_line1': 'Away address'},
      'opponent_venue': {'id': 'home', 'name': 'Lewisham', 'address_line1': 'Westerley Crescent'},
    }));
    await tester.tap(find.byTooltip('Next match'));
    await tester.pumpAndSettle();
    expect(find.text('White Oak'), findsOneWidget);
    expect(find.text('Away address'), findsOneWidget);
    expect(find.text('Westerley Crescent'), findsNothing);
  });
}
