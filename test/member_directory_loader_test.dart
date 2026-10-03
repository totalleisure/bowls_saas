import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowls_saas/features/members/member_directory_loader.dart';

void main() {
  for (final total in [0, 601, 1000, 6000]) {
    test(
      'returns all $total members even if server caps batches at 500',
      () async {
        final client = SupabaseClient(
          'https://example.supabase.co',
          'test',
          httpClient: MockClient((req) async {
            expect(req.url.queryParameters['club_id'], 'eq.club');
            expect(
              req.url.queryParameters['order'],
              'role.asc.nullslast,member_profile_id.asc.nullslast',
            );
            final offset = int.parse(req.url.queryParameters['offset'] ?? '0');
            final end = (offset + 500).clamp(0, total);
            final rows = [
              for (var i = offset; i < end; i++) {'member_profile_id': 'id-$i'},
            ];
            return http.Response(
              jsonEncode(rows),
              200,
              request: req,
              headers: {
                'content-range': rows.isEmpty
                    ? '*/$total'
                    : '$offset-${end - 1}/$total',
              },
            );
          }),
        );
        addTearDown(client.dispose);
        final rows = await loadClubMembers(client, 'club');
        expect(rows.length, total);
        expect(rows.map((r) => r['member_profile_id']).toSet().length, total);
      },
    );
  }
  test('guest restriction is sent on every batch', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test',
      httpClient: MockClient((req) async {
        expect(req.url.queryParameters['member_profile_id'], 'eq.self');
        return http.Response(
          '[{"member_profile_id":"self"}]',
          200,
          request: req,
          headers: {'content-range': '0-0/1'},
        );
      }),
    );
    addTearDown(client.dispose);
    expect(
      (await loadClubMembers(
        client,
        'club',
        onlyMemberProfileId: 'self',
      )).length,
      1,
    );
  });
  test('partial response never silently becomes the complete list', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test',
      httpClient: MockClient(
        (req) async => http.Response(
          '[]',
          200,
          request: req,
          headers: {'content-range': '*/6000'},
        ),
      ),
    );
    addTearDown(client.dispose);
    await expectLater(loadClubMembers(client, 'club'), throwsStateError);
  });
}
