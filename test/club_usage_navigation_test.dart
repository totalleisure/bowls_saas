import 'dart:convert';
import 'package:bowls_saas/features/reports/club_usage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TrackedScreen extends StatefulWidget {
  const TrackedScreen(this.name, {super.key});
  final String name;
  @override
  State<TrackedScreen> createState() => _TrackedScreenState();
}

class _TrackedScreenState extends State<TrackedScreen>
    with ClubScreenTracking<TrackedScreen> {
  @override
  String get usageClubId => 'club';
  @override
  String get usageScreen => widget.name;
  int redraws = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.name)),
    body: Column(
      children: [
        TextButton(
          onPressed: () => setState(() => redraws++),
          child: Text('Redraw $redraws'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const TrackedScreen('Day View'),
            ),
          ),
          child: const Text('Open day'),
        ),
      ],
    ),
  );
}

void main() {
  final calls = <Map<String, dynamic>>[];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final token =
        '${base64Url.encode(utf8.encode('{"alg":"HS256"}'))}.${base64Url.encode(utf8.encode('{"sub":"user","exp":2000000000}'))}.signature';
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'anon',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/token'))
          return http.Response(
            jsonEncode({
              'access_token': token,
              'refresh_token': 'refresh',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': 'user',
                'aud': 'authenticated',
                'created_at': '2026-01-01T00:00:00Z',
                'app_metadata': {},
                'user_metadata': {},
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        if (request.url.path.endsWith('/record_club_usage')) {
          calls.add(Map<String, dynamic>.from(jsonDecode(request.body)));
          return http.Response('', 204, request: request);
        }
        return http.Response('{}', 200);
      }),
    );
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'test@example.invalid',
      password: 'fake-only',
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  testWidgets(
    'Views count on entry and return; redraws and token refresh do not inflate visits',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [clubUsageObserver],
          home: const TrackedScreen('Month View'),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls.where((c) => c['p_kind'] == 'app_visit').length, 1);
      expect(calls.where((c) => c['p_kind'] == 'screen_view').length, 1);
      await tester.tap(find.text('Redraw 0'));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c['p_kind'] == 'screen_view').length, 1);
      await tester.tap(find.text('Open day'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(calls.where((c) => c['p_kind'] == 'app_visit').length, 1);
      expect(
        calls
            .where(
              (c) =>
                  c['p_kind'] == 'screen_view' && c['p_screen'] == 'Month View',
            )
            .length,
        2,
      );
      expect(
        calls
            .where(
              (c) =>
                  c['p_kind'] == 'screen_view' && c['p_screen'] == 'Day View',
            )
            .length,
        1,
      );
    },
  );
}

