import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowls_saas/features/members/member_directory_loader.dart';

class _Budget {
  int bytes = 0;
}

class _CappedClient extends http.BaseClient {
  final _inner = http.Client();
  final _Budget budget;
  _CappedClient(this.budget);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    final stream = response.stream.map((chunk) {
      budget.bytes += chunk.length;
      if (budget.bytes > 32 * 1024 * 1024)
        throw StateError('32 MiB test budget exceeded');
      return chunk;
    });
    return http.StreamedResponse(
      stream,
      response.statusCode,
      headers: response.headers,
      request: response.request,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

void main() {
  test(
    '6000-member directory loads completely under mixed-account concurrency',
    () async {
      final budget = _Budget();
      final clients = <String, SupabaseClient>{};
      for (final actor in ['member', 'admin']) {
        final transport = _CappedClient(budget);
        addTearDown(transport.close);
        final client = SupabaseClient(
          'https://egxdkaotepgfjmszxlyn.supabase.co',
          Platform.environment['STAGING_PUBLISHABLE_KEY']!,
          httpClient: transport,
        );
        addTearDown(client.dispose);
        final auth = await client.auth.signInWithPassword(
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
        clients[actor] = client;
      }
      Future<void> load(String actor, int concurrency) async {
        final clock = Stopwatch()..start();
        final rows = await loadClubMembers(
          clients[actor]!,
          '8a1d4c4a-ef4b-9ff5-7ea4-e4f503591636',
        );
        expect(rows.length, 6000);
        expect(rows.map((r) => r['member_profile_id']).toSet().length, 6000);
        expect(
          rows.where((r) => r['member_profiles'] != null).length,
          actor == 'admin' ? 6000 : 5999,
        );
        print(
          'MIXED_LIVE actor=$actor concurrency=$concurrency rows=${rows.length} elapsed_ms=${clock.elapsedMilliseconds}',
        );
      }

      await load('member', 1);
      await load('admin', 1);
      await Future.wait([
        for (var i = 0; i < 5; i++) load(i.isEven ? 'member' : 'admin', 5),
      ]);
      print('MIXED_LIVE response_bytes=${budget.bytes}');
    },
    skip: Platform.environment['CAPACITY_MIXED_LIVE'] != '1',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
