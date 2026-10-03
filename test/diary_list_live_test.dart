import 'package:bowls_saas/features/diary/diary_involvement.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowls_saas/features/diary/diary_list_screen.dart';
import 'package:bowls_saas/features/diary/diary_list_repository.dart';

class _NetworkBinding extends LiveTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  if (Platform.environment['DIARY_LIVE'] != '1') {
    test('live staging Diary is opt-in', () {}, skip: true);
    return;
  }
  _NetworkBinding();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://egxdkaotepgfjmszxlyn.supabase.co',
      anonKey: Platform.environment['STAGING_PUBLISHABLE_KEY']!,
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });
  tearDownAll(() async {
    await Supabase.instance.dispose();
  });
  for (final role in ['member', 'admin']) {
    testWidgets('staging Diary List renders under $role permissions', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1100, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = Supabase.instance.client;
      await client.auth.signInWithPassword(
        email:
            Platform.environment[role == 'member'
                ? 'STAGING_TEST_EMAIL'
                : 'STAGING_ADMIN_EMAIL']!,
        password: Platform.environment['STAGING_TEST_PASSWORD']!,
      );
      const clubId = '8ae87bbe-cb16-4330-a5b0-e62366479f07';
      final repo = DiaryListRepository(client, clubId);
      final types = await repo.loadTypes();
      expect(types.length, greaterThan(1));
      final watch = Stopwatch()..start();
      await tester.pumpWidget(
        MaterialApp(
          home: DiaryListScreen(
            clubId: clubId,
            clubName: 'Staging test club',
            initialDate: DateTime(2026, 9, 30),
          ),
        ),
      );
      while (find.byType(LinearProgressIndicator).evaluate().isNotEmpty &&
          watch.elapsed < const Duration(seconds: 30)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        find.text('The diary could not be fully loaded. Please retry.'),
        findsNothing,
      );
      expect(find.byType(DiaryEntryCard), findsWidgets);
      expect(tester.takeException(), isNull);
      expect(
        find.text(
          'Personal markers could not be loaded. Refresh to try again.',
        ),
        findsNothing,
      );
      final renderMs = watch.elapsedMilliseconds;
      final nextWatch = Stopwatch()..start();
      final next = await DiaryInvolvementRepository(
        client,
        clubId,
      ).nextAccepted(DateTime.now().toUtc());
      print(
        'DIARY_PERSONAL_RESULT role=$role next_match_found=${next != null} lookup_ms=${nextWatch.elapsedMilliseconds}',
      );
      print(
        'DIARY_RESULT role=$role initial_render_ms=$renderMs types=${types.length}',
      );
      await tester.pumpWidget(const SizedBox());
      await client.auth.signOut();
    });
  }
}
