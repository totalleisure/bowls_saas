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
}
