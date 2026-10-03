import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/models/dashboard_fixture_filter.dart';
import 'package:bowls_saas/features/dashboard/dashboard_filter_screen.dart';

const types = <Map<String, dynamic>>[
  {
    'id': 'a',
    'name': 'County League',
    'tags': ['league'],
    'uses_rinks': true,
  },
  {
    'id': 'b',
    'name': 'Friendly League',
    'tags': ['league', 'friendly'],
    'uses_rinks': true,
  },
  {
    'id': 'c',
    'name': 'Social Evening',
    'tags': ['social'],
    'uses_rinks': false,
  },
  {
    'id': 'd',
    'name': 'Practice',
    'tags': ['training'],
    'selection_mode': 'open',
    'uses_rinks': true,
  },
];

void main() {
  test('All, None and reset have distinct meanings and survive saving', () {
    const all = DashboardFixtureFilter();
    expect(all.selectedIds(types), {'a', 'b', 'c', 'd'});
    final none = all.selectTypes({});
    expect(none.selectedIds(types), isEmpty);
    expect(none.isDefault, isFalse);
    expect(DashboardFixtureFilter.fromJson(none.toJson()), none);
    expect(none.clear(), all);
  });

  test('League shortcut then manually adding Social gives their union', () {
    var filter = const DashboardFixtureFilter().toggleTag('league', types);
    expect(filter.selectedIds(types), {'a', 'b'});
    filter = filter.toggleType('c', types);
    expect(filter.selectedIds(types), {'a', 'b', 'c'});
    filter = filter.toggleType('a', types);
    expect(filter.selectedIds(types), {'b', 'c'});
    expect(DashboardFixtureFilter.fromJson(filter.toJson()), filter);
  });

  test('Removing final type means None, never All', () {
    final filter = const DashboardFixtureFilter()
        .selectTypes({'a'})
        .toggleType('a', types);
    expect(filter.selectedIds(types), isEmpty);
    expect(filter.allTypesSelected, isFalse);
  });

  test('Overlapping groups reflect the definitive type selection', () {
    var filter = const DashboardFixtureFilter().toggleTag('league', types);
    filter = filter.toggleTag('friendly', types);
    expect(filter.selectedIds(types), {'a'});
    filter = filter.toggleTag('friendly', types);
    expect(filter.selectedIds(types), {'a', 'b'});
    filter = filter.toggleTag('social', types);
    expect(filter.selectedIds(types), {'a', 'b', 'c'});
    filter = filter.toggleTag('league', types);
    expect(filter.selectedIds(types), {'c'});
  });

  test('Events and open sessions use Dashboard definitions, not tags', () {
    expect(
      const DashboardFixtureFilter()
          .toggleTag('event', types)
          .selectedIds(types),
      {'c'},
    );
    expect(
      const DashboardFixtureFilter()
          .toggleTag('open_session', types)
          .selectedIds(types),
      {'d'},
    );
  });

  test(
    'Legacy tags and type restrictions retain their original intersection',
    () {
      final filter = DashboardFixtureFilter.fromJson({
        'categories': ['league'],
        'fixtureTypeIds': ['b', 'c'],
      });
      expect(filter.selectedIds(types), {'b'});
      expect(filter.toggleType('c', types).selectedIds(types), {'b', 'c'});
      expect(DashboardFixtureFilter.fromJson({}).allTypesSelected, isTrue);
    },
  );

  test('Explicit selection works even when embedded tags are absent', () {
    final filter = const DashboardFixtureFilter().selectTypes({'b'});
    expect(filter.includesType('b', {'id': 'b'}), isTrue);
    expect(filter.includesType('c', {'id': 'c'}), isFalse);
  });

  test('Sections apply independently, including explicit None and Open', () {
    final open = const DashboardFixtureFilter(
      sections: {'open'},
      explicitSections: true,
    );
    expect(open.matchesSection(null), isTrue);
    expect(open.matchesSection('open'), isTrue);
    expect(open.matchesSection('mixed'), isFalse);
    expect(open.copyWith(sections: {}).matchesSection('open'), isFalse);
    expect(const DashboardFixtureFilter().matchesSection('mens'), isTrue);
  });

  test('Next calendar month excludes current month and following month', () {
    const filter = DashboardFixtureFilter(period: 'next_month');
    final now = DateTime.utc(2026, 9, 28);
    expect(filter.matchesPeriod(DateTime.utc(2026, 9, 30), now), isFalse);
    expect(filter.matchesPeriod(DateTime.utc(2026, 10, 1), now), isTrue);
    expect(filter.matchesPeriod(DateTime.utc(2026, 10, 31), now), isTrue);
    expect(filter.matchesPeriod(DateTime.utc(2026, 11, 1), now), isFalse);
  });

  test('Three months includes corresponding date, excludes following day', () {
    const filter = DashboardFixtureFilter(period: 'three_months');
    final now = DateTime.utc(2026, 9, 28);
    expect(filter.matchesPeriod(DateTime.utc(2026, 9, 27), now), isFalse);
    expect(filter.matchesPeriod(now, now), isTrue);
    expect(
      filter.matchesPeriod(DateTime.utc(2026, 12, 28, 23, 59), now),
      isTrue,
    );
    expect(filter.matchesPeriod(DateTime.utc(2026, 12, 29), now), isFalse);
  });

  test('Three months clamps month ends and handles leap years', () {
    const filter = DashboardFixtureFilter(period: 'three_months');
    expect(
      filter.periodEnd(DateTime.utc(2026, 11, 30)),
      DateTime.utc(2027, 3, 1),
    );
    expect(
      filter.periodEnd(DateTime.utc(2027, 11, 30)),
      DateTime.utc(2028, 3, 1),
    );
    expect(
      filter.periodEnd(DateTime.utc(2026, 1, 31)),
      DateTime.utc(2026, 5, 1),
    );
  });

  testWidgets(
    'Tags tick types; manual additions remain visible; None and reset work',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: DashboardFilterScreen(
            initialFilter: const DashboardFixtureFilter(),
            clubId: 'test',
            fixtureTypesLoader: () async => types,
          ),
        ),
      );
      await tester.pumpAndSettle();
      bool selected(String label) => tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, label))
          .selected;
      await tester.tap(find.text('Leagues'));
      await tester.pumpAndSettle();
      expect(selected('County League'), isTrue);
      expect(selected('Social Evening'), isFalse);
      await tester.tap(find.text('Social Evening'));
      await tester.pumpAndSettle();
      expect(selected('County League'), isTrue);
      expect(selected('Social Evening'), isTrue);
      await tester.tap(find.text('County League'));
      await tester.pumpAndSettle();
      final league = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, 'Leagues (1 of 2)'),
      );
      expect(league.selected, isFalse);
      expect(league.avatar, isNull);
      expect(find.text('Leagues (1 of 2)'), findsOneWidget);
      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'No fixture types selected. Only protected fixtures will be shown.',
        ),
        findsOneWidget,
      );
      expect(selected('Friendly League'), isFalse);
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(selected('All types'), isTrue);
      expect(selected('Social Evening'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Load failure offers Retry and prevents saving incomplete options',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: DashboardFilterScreen(
            initialFilter: const DashboardFixtureFilter(),
            clubId: 'test',
            fixtureTypesLoader: () async {
              if (attempts++ == 0) throw StateError('test load failure');
              return types;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FloatingActionButton>(find.byType(FloatingActionButton))
            .onPressed,
        isNull,
      );
      await tester.scrollUntilVisible(find.text('Retry'), 200);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Retry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(
        tester
            .widget<FloatingActionButton>(find.byType(FloatingActionButton))
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Filters fit a narrow phone and show the selected date range', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardFilterScreen(
          initialFilter: const DashboardFixtureFilter(period: 'next_month'),
          clubId: 'test',
          fixtureTypesLoader: () async => types,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Next calendar month'), 150);
    expect(find.textContaining(RegExp(r'1 \w+ \d{4}')), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
