import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowls_saas/features/diary/month_overview_screen.dart';
import 'package:bowls_saas/features/diary/diary_day_screen.dart';
import 'package:bowls_saas/features/diary/month_calendar.dart';
import 'package:bowls_saas/features/fixtures/fixture_details_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'anon',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/fixtures')) {
          final rows = List.generate(
            8,
            (n) => {
              'id': 'fixture-$n',
              'club_id': 'club',
              'start_at':
                  '2026-10-01T${(8 + n).toString().padLeft(2, '0')}:00:00Z',
              'end_at': '2026-10-01T20:00:00Z',
              'is_home': n != 1,
              'section': n == 1 ? 'mens' : 'mixed',
              'dress_code': n == 1 ? ['whites'] : ['greys'],
              'rinks_required': 4,
              'notes': 'Special message only for fixture details',
              'cancelled_at': n == 0 ? '2026-09-30T12:00:00Z' : null,
              'venue': {'id': 'away-venue', 'name': 'White Oak Bowls Club'},
              'opponent_name': 'Friendly game $n',
              'fixture_rinks': [],
              'competition_types': {'name': 'Roll-up', 'is_internal': false},
              'competition_type': {
                'name': 'Roll-up',
                'is_internal': false,
                'uses_rinks': true,
              },
            },
          );
          return http.Response(
            jsonEncode(rows),
            200,
            headers: {'content-range': '0-7/8'},
            request: request,
          );
        }
        return http.Response(
          '[]',
          200,
          headers: {'content-range': '*/0'},
          request: request,
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  testWidgets(
    'Month fixture label opens Day View, returns to Month, and empty dates also open Day View',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: MonthOverviewScreen(
            clubId: 'club',
            clubName: 'Our Bowls Club',
            initialDate: DateTime(2026, 10),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('A • White Oak Bowls Club'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('month-floating-navigation')),
        findsOneWidget,
      );
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('November 2026'), findsOneWidget);
      await tester.tap(find.text('Previous'));
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);
      final fixture = find.byKey(const ValueKey('month-fixture-fixture-0'));
      await tester.ensureVisible(fixture);
      await tester.tap(fixture);
      await tester.pumpAndSettle();
      expect(find.byType(DiaryDayScreen), findsOneWidget);
      expect(
        tester.widget<DiaryDayScreen>(find.byType(DiaryDayScreen)).date,
        DateTime(2026, 10),
      );
      expect(find.textContaining('Cancelled · '), findsOneWidget);
      final cancelledCard = tester.widget<Card>(
        find
            .ancestor(
              of: find.textContaining('Cancelled · '),
              matching: find.byType(Card),
            )
            .first,
      );
      final shape = cancelledCard.shape! as RoundedRectangleBorder;
      expect(shape.side.color, Colors.grey.shade300.withOpacity(.6));
      expect(find.text('White Oak Bowls Club'), findsNothing);
      expect(find.text('Away at White Oak Bowls Club'), findsOneWidget);
      expect(find.text('Mens'), findsOneWidget);
      expect(
        find.text('Special message only for fixture details'),
        findsNothing,
      );
      expect(find.text('4 teams'), findsWidgets);
      expect(find.text('Whites'), findsOneWidget);
      final pillText = tester.widget<Text>(find.text('Whites'));
      final pill = tester.widget<Container>(
        find
            .ancestor(of: find.text('Whites'), matching: find.byType(Container))
            .first,
      );
      final pillBackground = (pill.decoration! as BoxDecoration).color!;
      final contrast =
          (pillBackground.computeLuminance() + .05) /
          (pillText.style!.color!.computeLuminance() + .05);
      expect(contrast, greaterThan(4.5));
      expect(find.byType(FixtureDetailsPage), findsNothing);
      await tester.tap(find.byIcon(Icons.arrow_back).last);
      await tester.pumpAndSettle();
      expect(find.byType(MonthCalendar), findsOneWidget);
      final empty = find.byKey(
        ValueKey('month-day-${DateTime(2026, 10, 2).toIso8601String()}'),
      );
      await tester.ensureVisible(empty);
      await tester.tapAt(tester.getTopLeft(empty) + const Offset(30, 60));
      await tester.pumpAndSettle();
      expect(
        tester.widget<DiaryDayScreen>(find.byType(DiaryDayScreen)).date,
        DateTime(2026, 10, 2),
      );
      expect(find.byType(FixtureDetailsPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'small phone Month and Day headings stay fixed while content scrolls',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: MonthOverviewScreen(
            clubId: 'club',
            clubName: 'Lewisham and Crystal Palace Indoor Bowls Club',
            initialDate: DateTime(2026, 10),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);
      final pill = find.byKey(const ValueKey('month-floating-navigation'));
      expect(find.text('Previous'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      final pillPosition = tester.getTopLeft(pill);
      final before = tester.getTopLeft(find.byType(AppBar)).dy;
      await tester.drag(find.byType(MonthCalendar), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byType(AppBar)).dy, before);
      expect(tester.getTopLeft(pill), pillPosition);
      final fixture = find.byKey(const ValueKey('month-fixture-fixture-0'));
      await tester.ensureVisible(fixture);
      await tester.pumpAndSettle();
      await tester.tap(fixture);
      await tester.pumpAndSettle();
      expect(find.byType(DiaryDayScreen), findsOneWidget);
      expect(find.byType(AppBar), findsWidgets);
      final dayBarPosition = tester.getTopLeft(find.byType(AppBar).last);
      final dateText = find.text('Thursday 1 Oct 2026');
      expect(tester.widget<Text>(dateText).maxLines, 1);
      final datePosition = tester.getTopLeft(dateText);
      final clubText = find.text(
        'Lewisham and Crystal Palace Indoor Bowls Club',
      );
      final clubPosition = tester.getTopLeft(clubText);
      await tester.drag(find.byType(ListView).last, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byType(AppBar).last), dayBarPosition);
      expect(tester.getTopLeft(dateText), datePosition);
      expect(tester.getTopLeft(clubText), clubPosition);
      expect(tester.takeException(), isNull);
    },
  );
}
