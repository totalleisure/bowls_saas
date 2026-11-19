import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowls_saas/features/diary/month_diary_repository.dart';

void main() {
  test(
    'Month View fetches every page even when the server imposes a smaller cap',
    () async {
      final requests = <Uri>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'anon',
        httpClient: MockClient((req) async {
          requests.add(req.url);
          final offset = int.parse(req.url.queryParameters['offset'] ?? '0');
          final end = (offset + 200).clamp(0, 1201);
          return http.Response(
            jsonEncode([
              for (var n = offset; n < end; n++)
                {'id': 'fixture-$n', 'start_at': '2026-10-01T08:00:00Z'},
            ]),
            200,
            headers: {'content-range': '$offset-${end - 1}/1201'},
            request: req,
          );
        }),
      );
      addTearDown(client.dispose);
      final rows = await MonthDiaryRepository(
        client,
        'club',
      ).load(DateTime(2026, 10));
      expect(rows.length, 1201);
      expect(
        requests.every(
          (u) => (u.queryParameters['select'] ?? '')
              .split(',')
              .contains('team_name'),
        ),
        isTrue,
      );
      expect(requests.length, 7);
      expect(
        requests.every((u) => u.queryParameters['club_id'] == 'eq.club'),
        isTrue,
      );
      expect(
        requests.every(
          (u) => RegExp(
            r'^start_at\.asc(?:\.nulls(?:first|last))?,id\.asc(?:\.nulls(?:first|last))?$',
          ).hasMatch(u.queryParameters['order'] ?? ''),
        ),
        isTrue,
      );
      expect(requests.first.queryParameters['start_at'], isNotNull);
    },
  );
  test(
    'single-day refresh queries only that UK day across daylight-saving boundaries',
    () async {
      final requests = <Uri>[];
      final client = SupabaseClient(
        'https://example.invalid',
        'anon',
        httpClient: MockClient((r) async {
          requests.add(r.url);
          return http.Response(
            '[]',
            200,
            headers: {'content-range': '*/0'},
            request: r,
          );
        }),
      );
      addTearDown(client.dispose);
      await MonthDiaryRepository(client, 'club').loadDay(DateTime(2026, 3, 29));
      expect(
        requests.single.queryParametersAll['start_at'],
        containsAll([
          'gte.2026-03-29T00:00:00.000Z',
          'lt.2026-03-29T23:00:00.000Z',
        ]),
      );
      requests.clear();
      await MonthDiaryRepository(
        client,
        'club',
      ).loadDay(DateTime(2026, 10, 25));
      expect(
        requests.single.queryParametersAll['start_at'],
        containsAll([
          'gte.2026-10-24T23:00:00.000Z',
          'lt.2026-10-26T00:00:00.000Z',
        ]),
      );
    },
  );
  test(
    'moved and rescheduled fixtures identify only their affected days',
    () async {
      final client = SupabaseClient(
        'https://example.invalid',
        'anon',
        httpClient: MockClient((r) async {
          final next = (r.url.queryParameters['id'] ?? '').contains(
            'successor',
          );
          return http.Response(
            jsonEncode([
              {
                'id': next ? 'successor' : 'original',
                'start_at': next
                    ? '2026-07-04T09:00:00Z'
                    : '2026-07-02T09:00:00Z',
                'rescheduled_to_fixture_id': next ? null : 'successor',
              },
            ]),
            200,
            request: r,
          );
        }),
      );
      addTearDown(client.dispose);
      final days = await MonthDiaryRepository(
        client,
        'club',
      ).affectedDays({DateTime(2026, 7, 1)}, ['original']);
      expect(days, {
        DateTime(2026, 7, 1),
        DateTime(2026, 7, 2),
        DateTime(2026, 7, 4),
      });
    },
  );
}
