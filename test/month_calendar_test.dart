import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/diary/month_calendar.dart';

final october = DateTime(2026, 10);
MonthDiaryItem fixture(
  int n, {
  int day = 1,
  bool cancelled = false,
}) => MonthDiaryItem(
  fixtureId: 'f$n',
  startAt: DateTime(2026, 10, day, 8 + n ~/ 4, n % 4 * 15),
  endAt: DateTime(2026, 10, day, 12),
  label:
      '${n.toString().padLeft(2, '0')}:00 H · Friendly indoor competition $n',
  backgroundColor: const Color(0xfffef3c7),
  foregroundColor: const Color(0xff78350f),
  isMine: n == 0,
  rinksUsed: 1,
  isCancelled: cancelled,
);
Finder day(int number) => find.byKey(
  ValueKey('month-day-${DateTime(2026, 10, number).toIso8601String()}'),
);
Widget calendar(
  List<MonthDiaryItem> items,
  ValueChanged<DateTime> open, {
  double textScale = 1,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: StatefulBuilder(
      builder: (context, setState) {
        return MonthCalendar(
          month: october,
          selectedDate: october,
          items: items,
          onDayTap: open,
          zoom: 1,
          onZoomChanged: (_) {},
        );
      },
    ),
  ),
);

void main() {
  testWidgets('size controls expand the calendar without hiding fixtures', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var zoom = 1.0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => MonthCalendar(
              month: october,
              selectedDate: october,
              items: List.generate(8, fixture),
              onDayTap: (_) {},
              zoom: zoom,
              onZoomChanged: (value) => setState(() => zoom = value),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final fontSize = tester
        .widget<Text>(find.text(fixture(0).label))
        .style!
        .fontSize!;
    await tester.tap(find.byTooltip('Larger calendar'));
    await tester.pumpAndSettle();
    expect(find.text('110%'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text(fixture(0).label)).style!.fontSize!,
      greaterThan(fontSize),
    );
    expect(find.byKey(const ValueKey('month-fixture-f7')), findsOneWidget);
    expect(
      tester.getBottomRight(find.byKey(const ValueKey('month-fixture-f7'))).dy,
      lessThan(tester.getBottomRight(day(1)).dy),
    );
    await tester.tap(find.byTooltip('Smaller calendar'));
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('busy weeks grow; every fixture is shown in time order', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final items = List.generate(12, fixture).reversed.toList();
    await tester.pumpWidget(calendar(items, (_) {}));
    await tester.pumpAndSettle();
    for (var n = 0; n < 12; n++) {
      expect(find.byKey(ValueKey('month-fixture-f$n')), findsOneWidget);
    }
    expect(find.textContaining('more'), findsNothing);
    final first = tester.getTopLeft(
      find.byKey(const ValueKey('month-fixture-f0')),
    );
    final second = tester.getTopLeft(
      find.byKey(const ValueKey('month-fixture-f1')),
    );
    expect(second.dx, greaterThan(first.dx));
    expect(second.dy, first.dy);
    expect(tester.getSize(day(1)).width, tester.getSize(day(2)).width * 2);
    expect(tester.getSize(day(1)).height, greaterThan(400));
    expect(tester.getSize(day(2)).height, tester.getSize(day(1)).height);
    final busyHeight = tester.getSize(day(1)).height;
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('month-fixture-f0'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('month-fixture-f11'))).dy,
      ),
    );
    await tester.ensureVisible(day(8));
    await tester.pumpAndSettle();
    expect(tester.getSize(day(8)).height, lessThan(busyHeight));
    expect(tester.takeException(), isNull);
  });

  testWidgets('two columns start at ten fixtures and read across then down', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final count in [9, 10, 15]) {
      await tester.pumpWidget(calendar(List.generate(count, fixture), (_) {}));
      await tester.pumpAndSettle();
      Offset position(int n) =>
          tester.getTopLeft(find.byKey(ValueKey('month-fixture-f$n')));
      if (count == 9) {
        expect(position(1).dx, position(0).dx);
        expect(position(1).dy, greaterThan(position(0).dy));
      } else {
        for (var n = 0; n + 1 < count; n += 2) {
          expect(position(n + 1).dy, position(n).dy);
          expect(position(n + 1).dx, greaterThan(position(n).dx));
          if (n + 2 < count)
            expect(position(n + 2).dy, greaterThan(position(n).dy));
        }
      }
      expect(find.textContaining('read across'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'fixture label, day number and empty space all open the same day',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final opened = <DateTime>[];
      await tester.pumpWidget(calendar([fixture(0)], opened.add));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('month-fixture-f0')));
      await tester.tap(
        find.descendant(of: day(1), matching: find.text('01-Oct-26')).first,
      );
      await tester.tapAt(tester.getTopLeft(day(2)) + const Offset(50, 55));
      expect(opened, [october, october, DateTime(2026, 10, 2)]);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(320, 568),
    const Size(768, 1024),
    const Size(1024, 768),
    const Size(1920, 1080),
  ]) {
    testWidgets('all fixtures remain reachable with large text at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      DateTime? opened;
      await tester.pumpWidget(
        calendar(
          List.generate(30, fixture),
          (date) => opened = date,
          textScale: 1.5,
        ),
      );
      await tester.pumpAndSettle();
      final last = find.byKey(const ValueKey('month-fixture-f29'));
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      await tester.tap(last);
      expect(opened, october);
      final text = tester.widget<Text>(find.text(fixture(29).label));
      expect(text.maxLines, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'cancelled fixtures stay grey with a visible cancellation label',
    (tester) async {
      await tester.pumpWidget(calendar([fixture(0, cancelled: true)], (_) {}));
      await tester.pumpAndSettle();
      final chip = tester.widget<Container>(
        find.byKey(const ValueKey('month-fixture-f0')),
      );
      expect((chip.decoration as BoxDecoration).color, Colors.grey.shade300);
      expect(find.textContaining('Cancelled · '), findsOneWidget);
    },
  );
}
