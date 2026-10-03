import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowls_saas/features/diary/diary_involvement.dart';
import 'package:bowls_saas/features/diary/diary_list_screen.dart';
import 'package:bowls_saas/features/diary/diary_list_filter.dart';
import 'package:bowls_saas/models/dashboard_fixture_filter.dart';

Map<String, dynamic> selection(
  String id, {
  String status = 'published',
  String acceptance = 'accepted',
  String role = 'player',
  bool selected = true,
  bool cancelled = false,
  String date = '2026-10-02T12:00:00Z',
}) => {
  'id': 'selection-$id',
  'is_selected': selected,
  'acceptance': acceptance,
  'role': role,
  'team_selections': {
    'status': status,
    'fixture': {
      'id': id,
      'start_at': date,
      'cancelled_at': cancelled ? '2026-09-30T10:00:00Z' : null,
    },
  },
};
Map<String, dynamic> fixture(
  String id, {
  String date = '2026-10-02T12:00:00Z',
}) => {
  'id': id,
  'start_at': date,
  'competition_type_id': 'match',
  'team_name': 'My $id',
  'competition_type': {
    'name': 'Club competition',
    'is_internal': true,
    'uses_rinks': true,
  },
  'section': 'mixed',
  'is_home': true,
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'published involvement distinguishes player, reserve and acceptance; hides drafts, declined, unselected and cancelled',
    () {
      final data = DiaryInvolvement.fromRows('me', [
        selection('player'),
        selection('reserve', role: 'reserve'),
        selection('pending', acceptance: 'pending'),
        selection('draft', status: 'draft'),
        selection('declined', acceptance: 'declined'),
        selection('unselected', selected: false),
        selection('cancelled', cancelled: true),
      ]);
      expect(data.badgesFor(fixture('player')), ["You're playing"]);
      expect(data.badgesFor(fixture('reserve')), ["You're a reserve"]);
      expect(data.badgesFor(fixture('pending')), ['Awaiting your acceptance']);
      for (final id in ['draft', 'declined', 'unselected', 'cancelled']) {
        expect(data.badgesFor(fixture(id)), isEmpty);
      }
      expect(
        data.badgesFor({
          ...fixture('player'),
          'vice_captain_member_profile_id': 'me',
        }),
        ["You're playing", "You're managing"],
      );
      expect(
        data.badgesFor({
          ...fixture('event'),
          'captain_member_profile_id': 'me',
          'competition_type': {'uses_rinks': false},
        }),
        ["You're organising"],
      );
      expect(
        data.badgesFor({...fixture('player'), 'cancelled_at': 'now'}),
        isEmpty,
      );
    },
  );
  test(
    'personal queries stay scoped, page fully and find earliest match beyond a short first page',
    () async {
      var selectedQueries = 0;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test',
        httpClient: MockClient((req) async {
          final q = req.url.queryParameters;
          if (req.url.path.endsWith('fixtures')) {
            expect(q['club_id'], 'eq.club');
            expect(q['id'], 'eq.earliest');
            expect(q['cancelled_at'], 'is.null');
            return http.Response(
              jsonEncode(fixture('earliest')),
              200,
              request: req,
            );
          }
          expect(q['member_profile_id'], 'eq.me');
          expect(q['is_selected'], 'eq.true');
          expect(q['team_selections.status'], 'eq.published');
          expect(q['team_selections.fixture.club_id'], 'eq.club');
          final next = q['acceptance'] == 'eq.accepted';
          if (next) {
            expect(q['team_selections.fixture.cancelled_at'], 'is.null');
          } else {
            expect(
              req
                  .url
                  .queryParametersAll['team_selections.fixture.start_at']!
                  .length,
              2,
            );
          }
          final offset = int.parse(q['offset'] ?? '0');
          selectedQueries++;
          return http.Response(
            jsonEncode([
              selection(
                offset == 0 ? 'later' : 'earliest',
                date: offset == 0
                    ? '2027-01-01T10:00:00Z'
                    : '2026-10-02T12:00:00Z',
              ),
            ]),
            200,
            request: req,
            headers: {'content-range': '$offset-$offset/2'},
          );
        }),
      );
      addTearDown(client.dispose);
      final repo = DiaryInvolvementRepository(
        client,
        'club',
        memberIdLoader: () async => 'me',
      );
      final personal = await repo.load(
        DateTime(2026, 9, 30),
        DateTime(2027, 2),
      );
      expect(personal.selectionBadges.length, 2);
      expect(
        (await repo.nextAccepted(DateTime.utc(2026, 9, 30)))!['id'],
        'earliest',
      );
      expect(selectedQueries, 4);
    },
  );
  Widget screen({
    required Future<Map<String, dynamic>?> Function() next,
    Future<DiaryInvolvement> Function(DateTime, DateTime)? personal,
  }) => MaterialApp(
    home: DiaryListScreen(
      clubId: 'club',
      clubName: 'Club',
      userId: 'me',
      initialDate: DateTime(2026, 9, 30),
      now: () => DateTime(2026, 9, 30),
      nextMatchLoader: next,
      involvementLoader:
          personal ??
          (a, b) async => DiaryInvolvement.fromRows('me', [selection('match')]),
      typesLoader: () async => [],
      teamsLoader: () async => [],
      entriesLoader: (a, b) async =>
          [
            fixture('earlier', date: '2026-10-02T08:00:00Z'),
            fixture('match'),
          ].where((e) {
            final d = DateTime.parse(e['start_at'] as String);
            return !d.isBefore(a) && d.isBefore(b);
          }).toList(),
    ),
  );
  testWidgets(
    'next match jumps past earlier same-day activity without changing filters',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(screen(next: () async => fixture('match')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next match'));
      await tester.pumpAndSettle();
      expect(find.text('My match').hitTestable(), findsOneWidget);
      expect(find.text('My earlier').hitTestable(), findsNothing);
      expect(find.text("You're playing").hitTestable(), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'filtered next match explains and preserves explicit None after dismissal',
    (tester) async {
      final saved = jsonEncode(
        const DiaryListFilter(
          fixtures: DashboardFixtureFilter(explicitTypes: true),
        ).toJson(),
      );
      SharedPreferences.setMockInitialValues({
        DiaryListFilter.storageKey('me', 'club'): saved,
      });
      await tester.pumpWidget(screen(next: () async => fixture('match')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next match'));
      await tester.pumpAndSettle();
      expect(find.text('Your next match is hidden'), findsOneWidget);
      expect(find.text('Open details'), findsOneWidget);
      await tester.tap(find.text('Keep browsing'));
      await tester.pumpAndSettle();
      expect(find.text('My match'), findsNothing);
      expect(
        (await SharedPreferences.getInstance()).getString(
          DiaryListFilter.storageKey('me', 'club'),
        ),
        saved,
      );
    },
  );
  testWidgets(
    'personal lookup failure keeps club diary visible and next-match errors are distinct from no match',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        screen(
          next: () async => throw StateError('offline'),
          personal: (a, b) async => throw StateError('offline'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('My match'), findsOneWidget);
      expect(
        find.text(
          'Personal markers could not be loaded. Refresh to try again.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Next match'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not find your next match. Please try again.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(screen(next: () async => null));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next match'));
      await tester.pumpAndSettle();
      expect(
        find.text('You have no upcoming accepted fixtures.'),
        findsOneWidget,
      );
    },
  );
}
