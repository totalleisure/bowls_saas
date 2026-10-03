import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowls_saas/features/members/member_directory_loader.dart';

void main() {
  test(
    'staging real member receives all 6000 directory memberships',
    () async {
      final client = SupabaseClient(
        'https://egxdkaotepgfjmszxlyn.supabase.co',
        Platform.environment['STAGING_PUBLISHABLE_KEY']!,
      );
      addTearDown(client.dispose);
      final session = await client.auth.signInWithPassword(
        email: Platform.environment['STAGING_TEST_EMAIL']!,
        password: Platform.environment['STAGING_TEST_PASSWORD']!,
      );
      expect(session.user!.id, 'dc435edc-0968-470f-8a5a-2a9463bf2cb9');
      for (var run = 1; run <= 2; run++) {
        final timer = Stopwatch()..start();
        final rows = await loadClubMembers(
          client,
          '8a1d4c4a-ef4b-9ff5-7ea4-e4f503591636',
        );
        expect(rows.length, 6000);
        expect(rows.map((r) => r['member_profile_id']).toSet().length, 6000);
        expect(rows.where((r) => r['member_profiles'] != null).length, 5999);
        print(
          'LIVE DIRECTORY run=$run rows=${rows.length} elapsed_ms=${timer.elapsedMilliseconds}',
        );
      }
    },
    skip: Platform.environment['CAPACITY_LIVE'] != '1',
  );
}
