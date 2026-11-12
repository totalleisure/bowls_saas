import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/competitions/screens/competition_season_screen.dart';
import 'package:bowls_saas/features/competitions/screens/competition_arrangement_screen.dart';
import 'competition_arrangement_screen_test.dart' show FakeArrangement;
import 'competition_player_result_screen_test.dart' show ResultRepository;

const action = ValueKey('admin-arrange-competition-fixture');

Future<void> open(
  WidgetTester t,
  ResultRepository repo,
  FakeArrangement booking, {
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
        repository: repo,
        arrangementRepository: booking,
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'Admin opens the linked booking route; no rink lookup before choosing time; return reloads booking',
    (t) async {
      final repo = ResultRepository(), booking = FakeArrangement();
      await open(t, repo, booking);
      await t.ensureVisible(find.byKey(action));
      await t.tap(find.byKey(action));
      await t.pumpAndSettle();
      expect(find.byType(CompetitionArrangementScreen), findsOneWidget);
      expect(find.text('Choose date and time'), findsOneWidget);
      expect(booking.greenLoads, 0);
      expect(booking.bookings, 0);
      repo.data.matches.first['fixture_id'] = 'booked-fixture';
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byKey(action), findsNothing);
      expect(find.textContaining('Fixture arranged'), findsOneWidget);
    },
  );

  for (final state in [
    'player',
    'draft',
    'bye',
    'completed',
    'result_pending',
    'awaiting_opponent',
    'already_booked',
  ]) {
    testWidgets('Admin booking action excluded for $state', (t) async {
      final repo = ResultRepository(), booking = FakeArrangement();
      if (state == 'draft') repo.data.competition['status'] = 'draft';
      if (['bye', 'completed', 'result_pending'].contains(state))
        repo.data.matches.first['status'] = state;
      if (state == 'awaiting_opponent')
        repo.data.matches.first['side_b_entry_id'] = null;
      if (state == 'already_booked')
        repo.data.matches.first['fixture_id'] = 'fixture';
      await open(t, repo, booking, admin: state != 'player');
      expect(find.byKey(action), findsNothing);
    });
  }
}
