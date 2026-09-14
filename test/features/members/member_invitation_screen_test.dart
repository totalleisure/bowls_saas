import 'dart:convert';
import 'package:bowls_saas/features/members/member_invitation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Offline Supabase transport, supplied by its existing dependency.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <Map<String, dynamic>>[];
  final guides = [
    for (final kind in ['introduction', 'android'])
      {
        'kind': kind,
        'name': '$kind.pdf',
        'url': 'https://example.test/$kind.pdf',
      },
  ];
  var missingGuide = false;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.test',
      anonKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        calls.add(body);
        expect(request.url.path, '/functions/v1/member_invitations');
        final result = switch (body['action']) {
          'guides' => {
            'guides': missingGuide ? [guides.first] : guides,
          },
          'preview' => {
            'guides': guides,
            'recipients': [
              for (final n in [1, 2])
                {
                  'id': 'invitation-$n',
                  'name': 'Member $n',
                  'email': 'member$n@example.test',
                  'resend': false,
                  'preview': {
                    'subject': 'Welcome Member $n',
                    'club': 'Club',
                    'greeting': 'Hello Member $n,',
                    'introduction': 'Your account is ready.',
                    'sections': <dynamic>[],
                    'closing': 'Club team',
                  },
                },
            ],
            'exceptions': [
              {
                'row': '4',
                'name': 'Inactive Person',
                'email': 'inactive@example.test',
                'reason': 'Inactive membership — activate before inviting',
              },
            ],
          },
          'send' => {'status': 'sent'},
          _ => throw StateError('Unexpected action'),
        };
        return http.Response(
          jsonEncode(result),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());
  // FunctionsClient encodes/decodes in a real isolate, outside the fake test clock.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
    }
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    calls.clear();
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: MemberInvitationScreen(
          clubId: 'club',
          storagePath: 'club/committee.csv',
          excludedEmails: ['failed@example.test'],
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets(
    'review never sends until final confirmation and only sends selected recipients',
    (tester) async {
      missingGuide = false;
      await open(tester);
      expect(calls.map((c) => c['action']), ['guides']);
      await tester.tap(find.text('Prepare invitation review'));
      await settle(tester);
      expect(calls.last['excluded_emails'], ['failed@example.test']);
      expect(calls.last['resend'], isFalse);
      expect(find.textContaining('Inactive membership'), findsOneWidget);
      await tester.tap(find.text('Preview personalised email').first);
      await settle(tester);
      expect(find.text('Hello Member 1,'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await settle(tester);
      await tester.tap(find.text('Member 2'));
      await settle(tester);
      await tester.tap(find.text('Send invitations'));
      await settle(tester);
      expect(find.text('Send 1 invitations now?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(calls.where((c) => c['action'] == 'send'), isEmpty);
      await tester.tap(find.text('Send invitations'));
      await settle(tester);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Send invitations').last,
      );
      await settle(tester);
      final sent = calls.where((c) => c['action'] == 'send').toList();
      expect(sent.length, 1);
      expect(sent.single['invitation_id'], 'invitation-1');
      expect(sent.single['confirm'], isTrue);
      expect(find.text('Accepted by the email service'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('missing second guide prevents invitation preparation', (
    tester,
  ) async {
    missingGuide = true;
    await open(tester);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Prepare invitation review'),
          )
          .onPressed,
      isNull,
    );
    expect(calls.where((c) => c['action'] == 'preview'), isEmpty);
    expect(find.text('Add guide'), findsOneWidget);
  });
}
