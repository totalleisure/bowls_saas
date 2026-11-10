import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/fixtures/widgets/fixture_time_picker.dart';

Future<void> enterTime(WidgetTester t, String hour, String minute) async {
  await t.tap(find.byIcon(Icons.keyboard_outlined));
  await t.pumpAndSettle();
  await t.enterText(find.byType(TextField).first, hour);
  await t.enterText(find.byType(TextField).last, minute);
  await t.tap(find.text('OK'));
  await t.pumpAndSettle();
}

void main() {
  final now = DateTime(2026, 11, 6, 12);
  test('Start moves preserve duration, including an earlier future date', () {
    final first = moveFixtureStart(
      DateTime(2026, 11, 16, 13),
      start: DateTime(2026, 11, 15, 13),
      end: DateTime(2026, 11, 15, 16),
    );
    expect(first.end, DateTime(2026, 11, 16, 16));
    final second = moveFixtureStart(
      DateTime(2026, 11, 16, 14),
      start: first.start,
      end: first.end,
    );
    expect(second.end, DateTime(2026, 11, 16, 17));
    final earlier = moveFixtureStart(
      DateTime(2026, 11, 14, 14),
      start: second.start,
      end: second.end,
    );
    expect(fixtureTimingError(earlier.start, earlier.end, now: now), isNull);
    expect(earlier.end, DateTime(2026, 11, 14, 17));
  });
  test(
    'Reject invalid times but shorten a duration that would cross midnight',
    () {
      expect(
        fixtureTimingError(now, now.add(const Duration(hours: 2)), now: now),
        isNotNull,
      );
      expect(
        fixtureTimingError(
          now.subtract(const Duration(minutes: 1)),
          now.add(const Duration(hours: 2)),
          now: now,
        ),
        isNotNull,
      );
      final start = DateTime(2026, 11, 16, 14);
      expect(fixtureTimingError(start, start, now: now), isNotNull);
      expect(
        fixtureTimingError(
          start,
          start.subtract(const Duration(hours: 1)),
          now: now,
        ),
        isNotNull,
      );
      final late = moveFixtureStart(
        DateTime(2026, 11, 16, 22),
        start: start,
        end: start.add(const Duration(hours: 3)),
      );
      expect(late.start, DateTime(2026, 11, 16, 22));
      expect(late.end, DateTime(2026, 11, 16, 23, 59));
      expect(fixtureTimingError(late.start, late.end, now: now), isNull);
      expect(
        fixtureTimingError(late.start, DateTime(2026, 11, 17, 1), now: now),
        contains('start date'),
      );
    },
  );
  test('An earlier slot limit shortens the end without shifting the start', () {
    final start = DateTime(2026, 11, 16, 21);
    final window = moveFixtureStart(
      start,
      defaultDuration: const Duration(hours: 4),
      latestEnd: DateTime(2026, 11, 16, 22),
    );
    expect(window.start, start);
    expect(window.end, DateTime(2026, 11, 16, 22));
    final otherDay = moveFixtureStart(
      start,
      defaultDuration: const Duration(hours: 4),
      latestEnd: DateTime(2026, 11, 15, 22),
    );
    expect(otherDay.end, DateTime(2026, 11, 16, 23, 59));
  });
  testWidgets(
    'Date retains start time, start edits shift end, end edit is time only',
    (t) async {
      var window = (
        start: DateTime(2026, 11, 15, 13),
        end: DateTime(2026, 11, 15, 16),
      );
      await t.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(alwaysUse24HourFormat: true),
                child: Column(
                  children: [
                    TextButton(
                      onPressed: () async {
                        final picked = await pickFixtureStart(
                          context,
                          start: window.start,
                          end: window.end,
                          now: now,
                        );
                        if (picked != null) window = picked;
                      },
                      child: const Text('Start'),
                    ),
                    TextButton(
                      onPressed: () async {
                        final end = await pickFixtureEndTime(
                          context,
                          start: window.start,
                          end: window.end,
                        );
                        if (end != null) {
                          window = (start: window.start, end: end);
                        }
                      },
                      child: const Text('End'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Start'));
      await t.pumpAndSettle();
      expect(
        t.widget<DatePickerDialog>(find.byType(DatePickerDialog)).firstDate,
        DateTime(2026, 11, 6),
      );
      await t.tap(find.text('16'));
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(
        t.widget<TimePickerDialog>(find.byType(TimePickerDialog)).initialTime,
        const TimeOfDay(hour: 13, minute: 0),
      );
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(window.end, DateTime(2026, 11, 16, 16));
      await t.tap(find.text('Start'));
      await t.pumpAndSettle();
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      await enterTime(t, '14', '00');
      expect(window.start, DateTime(2026, 11, 16, 14));
      expect(window.end, DateTime(2026, 11, 16, 17));
      await t.tap(find.text('End'));
      await t.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsNothing);
      expect(
        t.widget<TimePickerDialog>(find.byType(TimePickerDialog)).initialTime,
        const TimeOfDay(hour: 17, minute: 0),
      );
      await enterTime(t, '18', '00');
      expect(window.end, DateTime(2026, 11, 16, 18));
      await t.tap(find.text('End'));
      await t.pumpAndSettle();
      await enterTime(t, '13', '00');
      expect(window.end, DateTime(2026, 11, 16, 18));
      expect(
        find.text('End time must be after the start time.'),
        findsOneWidget,
      );
      await t.tap(find.text('Start'));
      await t.pumpAndSettle();
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      await enterTime(t, '22', '00');
      expect(window.start, DateTime(2026, 11, 16, 22));
      expect(window.end, DateTime(2026, 11, 16, 23, 59));
      expect(
        find.textContaining('shorter than a normal session'),
        findsOneWidget,
      );
    },
  );
}
