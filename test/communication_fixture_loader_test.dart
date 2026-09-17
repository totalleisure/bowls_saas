import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
// Uses the HTTP test client already used by the queue regression tests.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowls_saas/features/communications/communication_fixture_loader.dart';
import 'package:bowls_saas/features/fixtures/open_session_communications.dart';

void main() {
  test(
    'includes open session without a selection and keeps latest published selection',
    () async {
      final client = SupabaseClient(
        'https://example.invalid',
        'test',
        httpClient: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/rest/v1/fixtures');
          expect(request.url.queryParameters['club_id'], 'eq.club-test');
          expect(
            request.url.queryParameters['select'],
            isNot(contains('!inner')),
          );
          return http.Response(
            jsonEncode([
              {
                'id': 'open-fixture',
                'created_at': '2026-09-18T00:00:00Z',
                'competition_type': {
                  'selection_mode': 'open',
                  'uses_rinks': true,
                },
                'selections': [],
              },
              {
                'id': 'team-fixture',
                'created_at': '2026-09-17T00:00:00Z',
                'competition_type': {'selection_mode': 'team'},
                'selections': [
                  {
                    'id': 'old',
                    'status': 'draft',
                    'created_at': '2026-09-17T00:00:00Z',
                  },
                  {
                    'id': 'latest',
                    'status': 'published',
                    'created_at': '2026-09-19T00:00:00Z',
                  },
                ],
              },
            ]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final rows = await loadCommunicationFixtures(client, 'club-test');
      expect(rows, hasLength(2));
      final open = rows.singleWhere(
        (r) => r['fixtures']['id'] == 'open-fixture',
      );
      expect(open['id'], isNull);
      expect(
        fixtureCommunicationStatus(open['fixtures'], open['status']),
        'Open',
      );
      final team = rows.singleWhere(
        (r) => r['fixtures']['id'] == 'team-fixture',
      );
      expect(team['id'], 'latest');
      expect(team['status'], 'published');
    },
  );

  test(
    'loads subsequent pages so older-created future fixtures are not lost',
    () async {
      var requests = 0;
      final client = SupabaseClient(
        'https://example.invalid',
        'test',
        httpClient: MockClient((request) async {
          requests++;
          final offset = request.url.queryParameters['offset'];
          expect(offset, requests == 1 ? '0' : '200');
          final rows = requests == 1
              ? List.generate(
                  200,
                  (i) => {'id': 'fixture-$i', 'selections': []},
                )
              : [
                  {'id': 'older-open', 'selections': []},
                ];
          return http.Response(
            jsonEncode(rows),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final rows = await loadCommunicationFixtures(client, 'club-test');
      expect(requests, 2);
      expect(rows, hasLength(201));
      expect(rows.any((row) => row['fixtures']['id'] == 'older-open'), isTrue);
    },
  );
}
