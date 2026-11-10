import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/competitions/widgets/competition_deadline_warning.dart';
import 'competition_arrangement_screen_test.dart'
    show data, open, choose, FakeArrangement;

void main() {
  test(
    'Play-by warning compares calendar dates and includes the whole deadline day',
    () {
      expect(
        competitionBookingAfterDeadline(
          DateTime(2026, 11, 28, 23, 59),
          '2026-11-29',
        ),
        false,
      );
      expect(
        competitionBookingAfterDeadline(
          DateTime(2026, 11, 29, 23, 59),
          '2026-11-29',
        ),
        false,
      );
      expect(
        competitionBookingAfterDeadline(DateTime(2026, 11, 30), '2026-11-29'),
        true,
      );
      expect(
        competitionBookingAfterDeadline(
          DateTime(2026, 11, 30, 10),
          '2026-11-29',
        ),
        true,
      );
      expect(competitionBookingAfterDeadline(null, '2026-11-29'), false);
      expect(
        competitionBookingAfterDeadline(DateTime(2026, 11, 30), null),
        false,
      );
    },
  );
  testWidgets('Yellow warning uses the requested wording and date', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompetitionDeadlineWarning(
            scheduledClubTime: DateTime(2026, 11, 30),
            playBy: '2026-11-29',
          ),
        ),
      ),
    );
    expect(
      find.text('Warning : This match should be played by 29th Nov 2026'),
      findsOneWidget,
    );
    expect(t.widget<Card>(find.byType(Card)).color, const Color(0xfffff1ad));
  });
  testWidgets(
    'Late booking is warned before confirmation and remains permitted',
    (t) async {
      final old = data.rounds.first['play_by'];
      data.rounds.first['play_by'] = '2030-06-30';
      addTearDown(() => data.rounds.first['play_by'] = old);
      final repo = FakeArrangement();
      await open(t, repo);
      await choose(t);
      expect(
        find.text('Warning : This match should be played by 30th Jun 2030'),
        findsOneWidget,
      );
      await t.ensureVisible(find.text('Confirm fixture'));
      await t.tap(find.text('Confirm fixture'));
      await t.pumpAndSettle();
      expect(
        find
            .text('Warning : This match should be played by 30th Jun 2030')
            .last,
        findsOneWidget,
      );
      await t.tap(find.text('Book fixture'));
      await t.pumpAndSettle();
      expect(repo.bookings, 1);
    },
  );
}
