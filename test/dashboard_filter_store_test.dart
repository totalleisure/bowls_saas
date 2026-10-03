import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowls_saas/features/dashboard/dashboard_filter_store.dart';
import 'package:bowls_saas/models/dashboard_fixture_filter.dart';

void main() {
  test(
    'Repeated saves use the user/club key and keep exact JSON for restart',
    () async {
      Map<String, dynamic>? saved;
      var writes = 0;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/user_club_dashboard_filters');
          expect(request.url.queryParameters['on_conflict'], 'user_id,club_id');
          expect(
            request.headers['Prefer'],
            contains('resolution=merge-duplicates'),
          );
          saved = jsonDecode(request.body) as Map<String, dynamic>;
          writes++;
          return http.Response('', 201, request: request);
        }),
      );
      addTearDown(client.dispose);
      final store = DashboardFilterStore(client);
      await store.save(
        'user',
        'club',
        const DashboardFixtureFilter().selectTypes({'old'}),
      );
      final wanted = const DashboardFixtureFilter(
        period: 'next_month',
      ).selectTypes({'event', 'open'});
      await store.save('user', 'club', wanted);
      expect(writes, 2);
      expect(saved!['user_id'], 'user');
      expect(saved!['club_id'], 'club');
      expect(DashboardFixtureFilter.fromJson(saved!['filter_json']), wanted);
    },
  );

  test(
    'Save failures propagate instead of pretending persistence succeeded',
    () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test',
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'code': '23505',
              'message': 'duplicate key',
              'details': null,
              'hint': null,
            }),
            409, request: request,
          ),
        ),
      );
      addTearDown(client.dispose);
      await expectLater(
        DashboardFilterStore(
          client,
        ).save('user', 'club', const DashboardFixtureFilter().selectTypes({})),
        throwsA(isA<PostgrestException>()),
      );
    },
  );

  test('Reset deletes only the current user and club preference', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test',
      httpClient: MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.queryParameters['user_id'], 'eq.user');
        expect(request.url.queryParameters['club_id'], 'eq.club');
        return http.Response('', 204, request: request);
      }),
    );
    addTearDown(client.dispose);
    await DashboardFilterStore(
      client,
    ).save('user', 'club', DashboardFixtureFilter.empty);
  });
}
