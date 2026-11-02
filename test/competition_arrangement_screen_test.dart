import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowls_saas/features/competitions/competition_repository.dart';
import 'package:bowls_saas/features/competitions/competition_arrangement_repository.dart';
import 'package:bowls_saas/features/competitions/screens/competition_arrangement_screen.dart';
import 'package:bowls_saas/features/competitions/screens/competition_rink_selection_screen.dart';

const match = <String, dynamic>{
  'id': 'm',
  'competition_id': 'c',
  'round_id': 'r',
  'match_number': 1,
  'side_a_entry_id': 'a',
  'side_b_entry_id': 'b',
  'status': 'to_be_arranged',
};
final data = CompetitionData(
  {
    'id': 'c',
    'club_id': 'club',
    'name': 'Mixed Pairs',
    'fixture_type': {'name': 'Club Competition'},
    'settings': {
      'players_per_entry': 2,
      'rinks_required': 1,
      'booking_minutes': 150,
      'playing_format': 'pairs',
      'section': 'mixed',
      'dress': 'Greys',
    },
  },
  [
    {'id': 'a', 'name': 'Alex One / Blair Two'},
    {'id': 'b', 'name': 'Chris Three / Drew Four'},
  ],
  [
    {
      'id': 'r',
      'name': 'Preliminary',
      'play_by': '2030-12-13',
      'rule_overrides': <String, dynamic>{},
    },
  ],
  [match],
);

class FakeArrangement extends CompetitionArrangementRepository {
  FakeArrangement()
    : super(
        SupabaseClient(
          'https://example.invalid',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  int bookings = 0, availabilityLoads = 0, greenLoads = 0;
  bool fail = false;
  CompetitionBookingChoice? saved;
  @override
  Future<List<CompetitionRow>> players(CompetitionRow match) async => [
    for (final item in [
      ('a', 'Alex', 'One'),
      ('a', 'Blair', 'Two'),
      ('b', 'Chris', 'Three'),
      ('b', 'Drew', 'Four'),
    ])
      {
        'entry_id': item.$1,
        'member_profile': {'first_name': item.$2, 'last_name': item.$3},
      },
  ];
  @override
  Future<List<CompetitionRow>> greens(String clubId) async {
    greenLoads++;
    return [
      {'id': 'g', 'name': 'Indoor Green', 'orientation_mode': 'not_applicable'},
    ];
  }

  @override
  Future<List<CompetitionRow>> availability(
    String green,
    DateTime start,
    DateTime end,
  ) async {
    availabilityLoads++;
    return [
      {
        'rink_label': 'R1',
        'is_booked': true,
        'free_capacity_rinks': 2,
        'booked_text': 'Existing fixture',
      },
      for (final label in ['R2', 'R3'])
        {'rink_label': label, 'is_booked': false, 'free_capacity_rinks': 2},
    ];
  }

  @override
  Future<String> book(String id, CompetitionBookingChoice choice) async {
    bookings++;
    saved = choice;
    if (fail) throw Exception('The selected rinks are no longer available.');
    return 'fixture';
  }
}

Future<void> open(
  WidgetTester tester,
  FakeArrangement repo, {
  bool cancelWindow = false,
  bool invalidWindow = false,
}) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: CompetitionArrangementScreen(
        data: data,
        match: match,
        repository: repo,
        windowPicker: (context, start, end, minutes) async => cancelWindow
            ? null
            : (
                start: DateTime(2030, 7, 1, 10),
                end: invalidWindow
                    ? DateTime(2030, 7, 1, 9)
                    : DateTime(2030, 7, 1, 12, 30),
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester) async {
  await tester.tap(find.text('Choose date and time'));
  await tester.pumpAndSettle();
  expect(find.byType(CompetitionRinkSelectionScreen), findsOneWidget);
  expect(find.text('Existing fixture'), findsOneWidget);
  final unavailable = tester.widget<ListTile>(
    find.widgetWithText(ListTile, 'Unavailable'),
  );
  expect(unavailable.onTap, isNull);
  await tester.tap(find.text('R2'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Use selected rinks'));
  await tester.tap(find.text('Use selected rinks'));
  await tester.pumpAndSettle();
}

void main() {
  for (final invalid in [false, true]) {
    testWidgets(
      'Rinks stay hidden when date/time is ${invalid ? 'invalid' : 'cancelled'}',
      (tester) async {
        final repo = FakeArrangement();
        await open(
          tester,
          repo,
          cancelWindow: !invalid,
          invalidWindow: invalid,
        );
        expect(repo.greenLoads, 0);
        expect(repo.availabilityLoads, 0);
        expect(find.byType(CompetitionRinkSelectionScreen), findsNothing);
        await tester.tap(find.text('Choose date and time'));
        await tester.pumpAndSettle();
        expect(repo.greenLoads, 0);
        expect(repo.availabilityLoads, 0);
        expect(repo.bookings, 0);
        expect(find.byType(CompetitionRinkSelectionScreen), findsNothing);
        expect(find.text('R2'), findsNothing);
      },
    );
  }

  testWidgets(
    'Draw players and explicit booking confirmation; cancelling confirmation does not book',
    (tester) async {
      final repo = FakeArrangement();
      await open(tester, repo);
      for (final name in ['Alex One', 'Blair Two', 'Chris Three', 'Drew Four'])
        expect(find.text(name), findsOneWidget);
      expect(find.text('Player 1'), findsOneWidget);
      expect(find.text('Opponent 2'), findsOneWidget);
      expect(find.text('Entries'), findsNothing);
      expect(find.text('Draw'), findsNothing);
      await choose(tester);
      expect(repo.bookings, 0);
      await tester.tap(find.text('Confirm fixture'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep arranging'));
      await tester.pumpAndSettle();
      expect(repo.bookings, 0);
      await tester.tap(find.text('Confirm fixture'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Book fixture'));
      await tester.pumpAndSettle();
      expect(repo.bookings, 1);
      expect(repo.saved?.rinkLabels, ['R2']);
      expect(find.text('Fixture booked'), findsOneWidget);
      expect(find.text('Open fixture'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Rink picker cancel never books and a booking conflict retains the choices',
    (tester) async {
      final repo = FakeArrangement()..fail = true;
      await open(tester, repo);
      await tester.tap(find.text('Choose date and time'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.bookings, 0);
      expect(find.text('Confirm fixture'), findsNothing);
      await choose(tester);
      await tester.tap(find.text('Confirm fixture'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Book fixture'));
      await tester.pumpAndSettle();
      expect(find.textContaining('no longer available'), findsOneWidget);
      expect(find.text('Change date, time or rink'), findsOneWidget);
      expect(find.text('Fixture booked'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Arrangement players fit on a small phone', (tester) async {
    final repo = FakeArrangement();
    await open(tester, repo);
    tester.view.physicalSize = const Size(320, 650);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Opponent 2'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
