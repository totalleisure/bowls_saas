import 'dart:convert';
import 'package:bowls_saas/features/members/member_invitation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sent = <String>[];
  var outcome = 'sent';
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.test',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        final body = jsonDecode(r.body) as Map;
        Object result;
        switch (body['action']) {
          case 'guides':
            result = {
              'guides': [
                {'kind': 'introduction', 'url': 'https://example.test/a'},
                {'kind': 'android', 'url': 'https://example.test/b'},
              ],
            };
          case 'preview':
            expect(body['resend'], false);
            result = {
              'recipients': [
                for (var i = 1; i <= 3; i++)
                  {
                    'id': '$i',
                    'name': 'Member $i',
                    'email': '$i@example.test',
                    'preview': {},
                  },
              ],
              'exceptions': [],
              'guides': [
                {'kind': 'introduction'},
                {'kind': 'android'},
              ],
            };
          case 'send':
            sent.add(body['invitation_id'] as String);
            result = {
              'status': outcome,
              'message': 'Please wait 120 seconds before reviewing again.',
            };
          default:
            throw StateError('Unexpected action');
        }
        return http.Response(
          jsonEncode(result),
          200,
          request: r,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  Future<void> flush(WidgetTester t) async {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pump();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pump();
  }

  Future<void> start(WidgetTester t) async {
    sent.clear();
    await t.binding.setSurfaceSize(const Size(1000, 2000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      const MaterialApp(
        home: MemberInvitationScreen(
          clubId: 'club',
          storagePath: 'club/test.csv',
        ),
      ),
    );
    await flush(t);
    await t.tap(find.text('Prepare invitation review'));
    await flush(t);
    await t.ensureVisible(find.text('Send invitations'));
    await t.tap(find.text('Send invitations'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Send invitations').last);
    await flush(t);
  }

  testWidgets('batch spaces sends at least three seconds apart', (t) async {
    outcome = 'sent';
    await start(t);
    expect(sent, ['1']);
    await t.pump(const Duration(milliseconds: 2999));
    expect(sent, ['1']);
    await t.pump(const Duration(milliseconds: 1));
    await flush(t);
    expect(sent, ['1', '2']);
    await t.pump(const Duration(seconds: 3));
    await flush(t);
    expect(sent, ['1', '2', '3']);
    await t.pump(const Duration(seconds: 3));
    await flush(t);
    expect(find.text('Invitations complete'), findsOneWidget);
    expect(find.textContaining('Accepted by email service: 3'), findsWidgets);
    await t.tap(find.text('OK')); await t.pumpAndSettle();
    expect(find.textContaining('All selected invitations were accepted'), findsOneWidget);
  });
  for (final status in ['failed', 'unknown']) {
    testWidgets(
      '$status stops the batch without retrying or sending remaining members',
      (t) async {
        outcome = status;
        await start(t);
        expect(sent, ['1']);
        await t.pump(const Duration(minutes: 3));
        await flush(t);
        expect(sent, ['1']);
        expect(find.text('Invitations need attention'), findsOneWidget);
        expect(find.textContaining('Not attempted: 2'), findsWidgets);
        expect(find.textContaining(status == 'failed' ? 'Failed: 1' : 'Outcome uncertain: 1'), findsWidgets);
        expect(
          find.text('Please wait 120 seconds before reviewing again.'),
          findsOneWidget,
        );
      },
    );
  }
}
