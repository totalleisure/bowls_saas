import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowls_saas/features/clubs/club_start_screen.dart';

void main() {
  final calls = <Map<String, dynamic>>[];
  var fail = false;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final token =
        '${base64Url.encode(utf8.encode('{"alg":"HS256"}'))}.${base64Url.encode(utf8.encode('{"sub":"user","exp":2000000000}'))}.signature';
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'anon',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/token')) {
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
        }
        if (request.url.path.endsWith('/record_club_start_choice')) {
          calls.add(Map<String, dynamic>.from(jsonDecode(request.body)));
          return http.Response(
            fail ? '{"message":"Offline"}' : '',
            fail ? 503 : 204,
            request: request,
            headers: {'content-type': 'application/json'},
          );
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
  setUp(() {
    calls.clear();
    fail = false;
    SharedPreferences.setMockInitialValues({});
  });
  Future<void> settle() async =>
      Future<void>.delayed(const Duration(milliseconds: 100));
  test(
    'automatic fallback and legacy preference reads never report explicit choices',
    () async {
      await ClubStartPreference.save(
        'user',
        'club',
        ClubStartView.dashboard,
        explicit: false,
      );
      await ClubStartPreference.loadSaved('user', 'club');
      await ClubStartPreference.flushReport('user', 'club');
      expect(calls, isEmpty);
    },
  );
  test(
    'explicit choice is scoped and cleared with no duplicate retry',
    () async {
      await ClubStartPreference.save('user', 'club', ClubStartView.month);
      await settle();
      expect(calls.single['p_view'], 'month');
      await ClubStartPreference.flushReport('user', 'club');
      expect(calls, hasLength(1));
      await ClubStartPreference.clear('user', 'club');
      await settle();
      expect(calls.last['p_view'], isNull);
      expect(calls.last['p_event_id'], isNot(calls.first['p_event_id']));
    },
  );
  test(
    'failed reporting preserves local choice and retries same event ID',
    () async {
      fail = true;
      await ClubStartPreference.save('user', 'club', ClubStartView.list);
      await settle();
      expect(
        await ClubStartPreference.loadSaved('user', 'club'),
        ClubStartView.list,
      );
      final id = calls.first['p_event_id'];
      fail = false;
      await ClubStartPreference.flushReport('user', 'club');
      expect(calls.last['p_event_id'], id);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(
          '${ClubStartPreference.key('user', 'club')}.pending-report',
        ),
        isNull,
      );
    },
  );
  test(
    'another account pending choice is never sent under current user',
    () async {
      await ClubStartPreference.save('other', 'club', ClubStartView.month);
      await settle();
      expect(calls, isEmpty);
    },
  );
}
