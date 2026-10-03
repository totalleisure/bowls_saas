import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowls_saas/features/diary/diary_list_filter.dart';
import 'package:bowls_saas/features/diary/diary_list_repository.dart';
import 'package:bowls_saas/features/diary/diary_list_screen.dart';
import 'package:bowls_saas/models/dashboard_fixture_filter.dart';

Map<String, dynamic> event(String id, String date, {bool home = true}) => {
  'id': id,
  'start_at': date,
  'is_home': home,
  'section': 'open',
  'team_name': 'Event $id',
  'competition_type_id': 'events',
  'competition_type': {
    'id': 'events',
    'name': 'Club Events',
    'uses_rinks': false,
  },
};
void main() {
  final today = DateTime(2026, 9, 30);
  test(
    'All dates includes past; explicit None hides even personal fixtures',
    () {
      final row = {
        ...event('1', '2026-09-01T10:00:00Z'),
        'accepted': true,
        'manager': true,
      };
      expect(const DiaryListFilter().matches(row, today), isTrue);
      expect(
        const DiaryListFilter(
          fixtures: DashboardFixtureFilter(explicitTypes: true),
        ).matches(row, today),
        isFalse,
      );
      expect(
        const DiaryListFilter(
          fixtures: DashboardFixtureFilter(explicitSections: true),
        ).matches(row, today),
        isFalse,
      );
    },
  );
  test('period, location, team and type combine strictly', () {
    final row = {...event('1', '2026-10-01T10:00:00Z'), 'team_id': 'team'};
    const filter = DiaryListFilter(
      fixtures: DashboardFixtureFilter(
        period: 'next_month',
        explicitTypes: true,
        fixtureTypeIds: {'events'},
      ),
      location: 'home',
      team: 'team',
    );
    expect(filter.matches(row, today), isTrue);
    expect(filter.matches({...row, 'is_home': false}, today), isFalse);
    expect(filter.matches({...row, 'team_id': null}, today), isFalse);
    expect(
      filter.matches({...row, 'start_at': '2026-09-30T10:00:00Z'}, today),
      isFalse,
    );
    expect(
      filter.matches({...row, 'competition_type_id': 'other'}, today),
      isFalse,
    );
    expect(DiaryListFilter.fromJson(filter.toJson()).toJson(), filter.toJson());
    expect(
      DiaryListFilter.storageKey('a', 'club'),
      isNot(DiaryListFilter.storageKey('b', 'club')),
    );
    expect(
      DiaryListFilter.storageKey('a', 'club'),
      isNot(DiaryListFilter.storageKey('a', 'other')),
    );
  });
  test(
    'repository includes all pages, scopes club and uses UK date boundaries',
    () async {
      final paths = <String>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test',
        httpClient: MockClient((req) async {
          paths.add(req.url.path);
          final q = req.url.queryParameters;
          final fixtures = req.url.path.endsWith('/fixtures');
          expect(
            q[fixtures ? 'club_id' : 'green_areas.venue.club_id'],
            'eq.club',
          );
          expect(
            req.url.queryParametersAll['start_at'],
            contains(
              fixtures
                  ? 'gte.2026-09-29T23:00:00.000Z'
                  : 'lt.2026-10-02T23:00:00.000Z',
            ),
          );
          if (fixtures) {
            expect(
              req.url.queryParametersAll['start_at'],
              contains('lt.2026-10-02T23:00:00.000Z'),
            );
          }
          final offset = int.parse(q['offset'] ?? '0');
          final total = fixtures ? 1201 : 0;
          final end = (offset + 200).clamp(0, total);
          return http.Response(
            jsonEncode([
              for (var i = offset; i < end; i++)
                event('$i', '2026-09-30T10:00:00Z'),
            ]),
            200,
            request: req,
            headers: {
              'content-range': total == 0 ? '*/0' : '$offset-${end - 1}/$total',
            },
          );
        }),
      );
      addTearDown(client.dispose);
      final rows = await DiaryListRepository(
        client,
        'club',
      ).load(today, DateTime(2026, 10, 3));
      expect(rows.length, 1201);
      expect(paths.where((p) => p.endsWith('/fixtures')).length, 7);
    },
  );
  test('pagination rejects duplicates and changing totals', () async {
    await expectLater(
      loadDiaryPages(
        (offset) async => const PostgrestResponse(
          data: [
            {'id': 'same'},
          ],
          count: 3,
        ),
      ),
      throwsStateError,
    );
    await expectLater(
      loadDiaryPages(
        (offset) async => PostgrestResponse(
          data: [
            {'id': '$offset'},
          ],
          count: offset == 0 ? 3 : 4,
        ),
      ),
      throwsStateError,
    );
    await expectLater(
      loadDiaryPages(
        (offset) async =>
            const PostgrestResponse(data: <Map<String, dynamic>>[], count: 3),
      ),
      throwsStateError,
    );
  });
  Widget screen({
    Future<List<Map<String, dynamic>>> Function(DateTime, DateTime)? loader,
  }) => MaterialApp(
    home: DiaryListScreen(
      clubId: 'club',
      clubName: 'Test Club',
      initialDate: today,
      userId: 'user',
      now: () => today,
      entriesLoader:
          loader ??
          (a, b) async => [
            event('1', '2026-09-30T10:00:00Z'),
            event('2', '2026-09-30T12:00:00Z', home: false),
          ],
      typesLoader: () async => [
        {'id': 'events', 'name': 'Club Events', 'uses_rinks': false},
      ],
      teamsLoader: () async => [],
    ),
  );
  testWidgets(
    'saved None shows accurate counts and Clear restores all without Dashboard exceptions',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        DiaryListFilter.storageKey('user', 'club'): jsonEncode(
          const DiaryListFilter(
            fixtures: DashboardFixtureFilter(explicitTypes: true),
          ).toJson(),
        ),
      });
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(
        find.text('Showing 0 of 2 diary entries · 2 filtered out'),
        findsOneWidget,
      );
      expect(find.text('Event 1'), findsNothing);
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(
        find.text('Showing 2 of 2 diary entries · 0 filtered out'),
        findsOneWidget,
      );
      expect(find.text('Event 1'), findsOneWidget);
      expect(find.textContaining('Singles'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(
        DiaryListFilter.fromJson(
          jsonDecode(
            prefs.getString(DiaryListFilter.storageKey('user', 'club'))!,
          ),
        ).isFiltered,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'earlier dates load backwards, later forwards; load errors remain visible',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final windows = <List<DateTime>>[];
      await tester.pumpWidget(
        screen(
          loader: (a, b) async {
            windows.add([a, b]);
            return [];
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Earlier dates').hitTestable().first);
      await tester.pumpAndSettle();
      expect(windows.last.first.isBefore(today), isTrue);
      await tester.tap(find.text('Later dates').hitTestable().first);
      await tester.pumpAndSettle();
      expect(windows.last.first.isAfter(today), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        screen(loader: (a, b) async => throw StateError('test failure')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('The diary could not be fully loaded. Please retry.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
    },
  );

  testWidgets(
    'filter choice survives remount independently for user and club',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'dashboard.unrelated': 'unchanged',
      });
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home & away'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Away').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Showing 1 of 2 diary entries · 1 filtered out'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(
        find.text('Showing 1 of 2 diary entries · 1 filtered out'),
        findsOneWidget,
      );
      expect(find.text('Event 1'), findsNothing);
      expect(find.text('Event 2'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('dashboard.unrelated'), 'unchanged');
    },
  );
  testWidgets(
    'earlier entries appear on request and Today returns to the anchor',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        screen(
          loader: (a, b) async => [
            if (!a.isAfter(DateTime(2026, 9, 29)) &&
                b.isAfter(DateTime(2026, 9, 29)))
              event('past', '2026-09-29T10:00:00Z'),
            if (!a.isAfter(today) && b.isAfter(today))
              event('today', '2026-09-30T10:00:00Z'),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Event past'), findsNothing);
      await tester.tap(find.text('Earlier dates').hitTestable().first);
      await tester.pumpAndSettle();
      expect(find.text('Event past').hitTestable(), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(find.text('Event today').hitTestable(), findsOneWidget);
      expect(find.text('Event past'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('search narrows entries and clear restores accurate counts', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'event 2');
    await tester.pumpAndSettle();
    expect(
      find.text('Showing 1 of 2 diary entries · 1 filtered out'),
      findsOneWidget,
    );
    expect(find.text('Event 1'), findsNothing);
    expect(find.text('Event 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(
      find.text('Showing 2 of 2 diary entries · 0 filtered out'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(
      find.text('Showing 2 of 2 diary entries · 0 filtered out'),
      findsOneWidget,
    );
  });
  test(
    'search includes joined opponents, venue and event labels case-insensitively',
    () {
      final entry = {
        ...event('quiz', '2026-09-30T10:00:00Z'),
        'opponent_venue': {'name': 'Bromley'},
        'venue': {'name': 'Main Hall'},
      };
      expect(diaryEntryMatchesSearch(entry, 'bROMley hall'), isTrue);
      expect(diaryEntryMatchesSearch(entry, 'quiz'), isTrue);
      expect(diaryEntryMatchesSearch(entry, 'Bromley missing'), isFalse);
    },
  );
  testWidgets(
    'phone width renders without overflow and opens dedicated Diary filter',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('All activity'));
      await tester.pumpAndSettle();
      expect(find.text('Filter diary'), findsOneWidget);
      expect(find.text('All dates'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('Diary filters apply to every entry'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      expect(
        find.textContaining('Diary filters apply to every entry'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
