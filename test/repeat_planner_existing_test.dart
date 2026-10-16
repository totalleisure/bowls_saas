import 'package:bowls_saas/features/fixtures/repeat_fixture_planner_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final existing in [true, false]) {
    testWidgets('repeat planner excludes source date only for existing=$existing', (t) async {
      final start = DateTime(2026, 11, 19, 14);
      await t.pumpWidget(MaterialApp(home: RepeatFixturePlannerPage(
        startDateTime: start, excludedDate: existing ? start : null,
        requiresOpponent: false, opponentVenues: const [],
      )));
      await t.tap(find.text('Add date'));
      await t.pumpAndSettle();
      final picker = t.widget<CalendarDatePicker>(find.byType(CalendarDatePicker));
      if (existing) {
        expect(picker.selectableDayPredicate!(start), isFalse);
        expect(picker.selectableDayPredicate!(DateTime(2026, 11, 26)), isTrue);
      } else {
        expect(picker.selectableDayPredicate!(start), isTrue);
      }
      await t.tap(find.text('Cancel').last);
      await t.pumpAndSettle();
      final buttons = find.byType(OutlinedButton);
      await t.tap(buttons.at(1));
      await t.pumpAndSettle();
      await t.tap(find.text('26').last);
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(find.text(existing ? '1 fixture selected' : '2 fixtures selected'), findsOneWidget);
    });
  }
}
