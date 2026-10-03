import 'dart:convert';
import 'package:bowls_saas/features/admin/audit_journal_screen.dart';
import 'package:bowls_saas/features/admin/superuser_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var allowed = true;
  final calls = <http.Request>[];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.test',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        calls.add(r);
        Object data;
        if (r.url.path.endsWith('is_app_superuser')) {
          data = allowed;
        } else if (r.url.path.endsWith('audit_filter_options')) {
          data = {
            'clubs': [
              {'id': 'club', 'name': 'Lewisham'},
            ],
            'actors': [
              {'actor_user_id': 'actor', 'actor_name': 'Carol'},
            ],
          };
        } else if (r.url.path.endsWith('audit_journal')) {
          data = [
            {
              'id': 1,
              'occurred_at': '2026-09-20T10:00:00Z',
              'actor_name': 'Carol',
              'record_label': 'Ladies friendly / 2026-10-06 09:00:00+00',
              'record_id': 'fixture',
              'record_type': 'fixtures',
              'action': 'insert',
              'club_name': 'Lewisham',
              'origin': 'app',
              'operation_id': 1,
              'before_values': null,
              'after_values': {'team_name': 'Ladies friendly'},
            },
          ];
        } else {
          throw StateError('Unexpected ${r.url}');
        }
        return http.Response(
          jsonEncode(data),
          200,
          request: r,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() {
    calls.clear();
    allowed = true;
  });
  testWidgets(
    'superuser menu contains the three existing tools and audit tools',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: SuperuserScreen(clubId: 'club')),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      for (final title in [
        'Feature releases',
        'Queue Administration',
        'Communications Control Centre',
        'Audit journal',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('ordinary user cannot open the administration menu', (
    tester,
  ) async {
    allowed = false;
    await tester.pumpWidget(
      const MaterialApp(home: SuperuserScreen(clubId: 'club')),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('Superuser access required.'), findsOneWidget);
    expect(find.text('Audit journal'), findsNothing);
  });
  testWidgets(
    'journal loads on phone, filters by users and opens retained details',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(home: AuditJournalScreen(clubId: 'club')),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.text(
          'insert — Ladies friendly / Tuesday 6 October 2026 at 10:00 a.m.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Action date and time:'), findsOneWidget);
      expect(
        find.textContaining(
          'Action date and time: Sunday 20 September 2026 at 11:00 a.m.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Filters'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('All users'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('Carol'));
      await tester.tap(find.text('Apply'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(
        calls.last.url.queryParameters['actor_user_id'],
        contains('actor'),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Filters'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(
          'insert — Ladies friendly / Tuesday 6 October 2026 at 10:00 a.m.',
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('After: Ladies friendly'), findsOneWidget);
      expect(find.textContaining('Action date and time:'), findsWidgets);
      expect(find.textContaining(' at '), findsWidgets);
      await tester.tap(find.text('Full record history'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(calls.last.url.queryParameters['record_id'], 'eq.fixture');
      expect(
        calls.last.url.queryParameters.containsKey('actor_user_id'),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
