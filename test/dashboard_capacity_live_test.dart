import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowls_saas/features/clubs/club_dashboard_screen.dart';

class _NetworkBinding extends LiveTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

class _MeasuredClient extends http.BaseClient {
  final inner = http.Client();
  final calls = <Map<String, dynamic>>[];
  int bytes = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final timer = Stopwatch()..start();
    final response = await inner.send(request);
    final body = await response.stream.toBytes();
    bytes += body.length;
    if (bytes > 32 * 1024 * 1024)
      throw StateError('Dashboard test exceeded 32 MiB');
    Object? data;
    try {
      data = jsonDecode(utf8.decode(body));
    } catch (_) {}
    calls.add({
      'path': request.url.path,
      'ms': timer.elapsedMilliseconds,
      'status': response.statusCode,
      'rows': data is List ? data.length : null,
    });
    return http.StreamedResponse(
      Stream.value(body),
      response.statusCode,
      headers: response.headers,
      request: response.request,
    );
  }

  @override
  void close() {
    inner.close();
    super.close();
  }
}

void main() {
  if (Platform.environment['DASHBOARD_CAPACITY_LIVE'] != '1') {
    test('live dashboard capacity is opt-in', () {}, skip: true);
    return;
  }
  _NetworkBinding();
  final transport = _MeasuredClient();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://egxdkaotepgfjmszxlyn.supabase.co',
      anonKey: Platform.environment['STAGING_PUBLISHABLE_KEY']!,
      httpClient: transport,
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });
  tearDownAll(() async {
    await Supabase.instance.dispose();
    transport.close();
  });
  final ordinaryAdmin = Platform.environment['DASHBOARD_ORDINARY_ADMIN'] == '1';
  final actorOrder = ordinaryAdmin ? ['member'] : Platform.environment['DASHBOARD_ADMIN_FIRST'] == '1'
      ? ['admin', 'member']
      : ['member', 'admin'];
  for (final actor in actorOrder) {
    testWidgets(
      'live Dashboard renders for $actor',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await (() async {
          final auth = await Supabase.instance.client.auth.signInWithPassword(
            email:
                Platform.environment[actor == 'member'
                    ? 'STAGING_TEST_EMAIL'
                    : 'STAGING_ADMIN_EMAIL']!,
            password: Platform.environment['STAGING_TEST_PASSWORD']!,
          );
          expect(
            auth.user!.id,
            actor == 'member'
                ? 'dc435edc-0968-470f-8a5a-2a9463bf2cb9'
                : '34fc64d9-b1e3-4be7-b09b-439bd999772e',
          );
        })();
        if (ordinaryAdmin) {
          expect(await Supabase.instance.client.rpc('is_app_superuser'), false);
          expect(await Supabase.instance.client.rpc('is_club_admin', params: {'p_club_id': '8a1d4c4a-ef4b-9ff5-7ea4-e4f503591636'}), true);
        }
        final repeats = int.parse(Platform.environment['DASHBOARD_REPEATS'] ?? '3');
        expect(repeats, inInclusiveRange(1, 15));
        for (var run = 1; run <= repeats; run++) {
          final begin = transport.calls.length;
          final clock = Stopwatch()..start();
          await tester.pumpWidget(
            MaterialApp(
              home: ClubDashboardScreen(
                key: UniqueKey(),
                clubId: '8a1d4c4a-ef4b-9ff5-7ea4-e4f503591636',
                clubName: 'Capacity test club',
              ),
            ),
          );
          while (find
                  .text('Fixtures needing your Acceptance')
                  .evaluate()
                  .isEmpty &&
              clock.elapsedMilliseconds < 40000) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump();
            final errors = find.byWidgetPredicate(
              (w) => w is Text && (w.data ?? '').startsWith('Error:'),
            );
            expect(errors, findsNothing);
          }
          expect(find.text('Fixtures needing your Acceptance'), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          final firstContentMs = clock.elapsedMilliseconds;
          if (find.byType(AlertDialog).evaluate().isNotEmpty) {
            await tester.tap(find.text('OK'));
            await tester.pumpAndSettle();
          }
          expect(find.text('Tap to RSVP'), findsWidgets);
          final elapsed = clock.elapsedMilliseconds;
          final calls = transport.calls.skip(begin).toList();
          expect(
            calls.any(
              (c) => c['path'] == '/rest/v1/fixtures' && c['rows'] == 300,
            ),
            true,
            reason: 'Dashboard must fetch all 300 club fixtures',
          );
          expect(calls.where((c) => (c['status'] as int) >= 400), isEmpty);
          print(
            'DASHBOARD_RESULT ' +
                jsonEncode({
                  'actor': ordinaryAdmin ? 'ordinary_admin' : actor,
                  'club_size': int.parse(
                    Platform.environment['DASHBOARD_CLUB_SIZE']!,
                  ),
                  'run': run,
                  'rendered_ms': elapsed,
                'first_content_ms': firstContentMs,
                  'calls': calls,
                }),
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(
            () => Future<void>.delayed(Duration(milliseconds: Platform.environment['DASHBOARD_REPEATS'] == '15' ? 1000 : 150)),
          );
          await tester.pump();
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
