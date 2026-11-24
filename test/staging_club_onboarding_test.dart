import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/clubs/staging_club_onboarding_screen.dart';
import 'package:bowls_saas/features/clubs/onboarding_member_import.dart';
import 'package:bowls_saas/features/clubs/onboarding_activities_screen.dart';

const secretary = OnboardingMember(
  firstName: 'Test',
  surname: 'Secretary',
  email: 'secretary@example.invalid',
  role: 'admin',
  active: true,
);
Future<void> tap(WidgetTester t, String text) async {
  final target = find.text(text);
  await t.ensureVisible(target);
  await t.tap(target);
  await t.pumpAndSettle();
}

Future<void> review(WidgetTester t) async {
  await tap(t, 'Let’s begin');
  await t.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Club name'), 'New staging test club');
  await t.pumpAndSettle();
  await tap(t, 'Continue');
  final address = find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == 'Address line 1',
  );
  await t.enterText(address, '1 Example Green');
  await tap(t, 'Continue');
  await tap(t, 'Continue');
  await tap(t, 'Continue');
  await tap(t, 'Choose your fixture types');
  await tap(t, 'Review selected activities');
  await tap(t, 'Use these activities');
  for (var i = 5; i < 9; i++) {
    await tap(t, 'Continue');
  }
}

void main() {
  testWidgets('guides are not offered when Secretary access fails', (t) async {
    await t.pumpWidget(MaterialApp(home: StagingClubOnboardingScreen(
      secretaryLoader: () async => throw StateError('Not verified'),
    )));
    await t.pumpAndSettle();
    expect(find.text('Your guides to getting started'), findsNothing);
  });

  testWidgets('discard leaves setup without creating or deleting a club', (t) async {
    var creations = 0;
    await t.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => StagingClubOnboardingScreen(
          secretaryLoader: () async => secretary,
          creator: (id, payload) async { creations++; return {}; },
        ),
      )), child: const Text('My existing clubs')),
    ))));
    await tap(t, 'My existing clubs');
    await t.tap(find.byIcon(Icons.close));
    await t.pumpAndSettle();
    expect(find.text('Discard draft and leave'), findsOneWidget);
    await tap(t, 'Keep setting up');
    expect(find.text('Welcome to your club setup'), findsOneWidget);
    await t.tap(find.byIcon(Icons.close));
    await t.pumpAndSettle();
    await tap(t, 'Discard draft and leave');
    expect(find.text('My existing clubs'), findsOneWidget);
    expect(creations, 0);
  });

  testWidgets(
    'real staging draft writes once only after review, then enters club',
    (t) async {
      var calls = 0;
      Map<String, dynamic>? saved;
      await t.pumpWidget(
        MaterialApp(
          home: StagingClubOnboardingScreen(
            secretaryLoader: () async => secretary,
            lookup: (name, postcode) async => {'clubs': [], 'venues': []},
            creator: (id, payload) async {
              calls++;
              saved = payload;
              return {
                'club_id': 'new-club',
                'name': payload['name'],
                'pending_members': 0,
              };
            },
            clubBuilder: (id, name) =>
                Scaffold(body: Text('Normal club home: $id')),
          ),
        ),
      );
      await t.pumpAndSettle();
      await review(t);
      expect(calls, 0);
      await tap(t, 'Create club and finish');
      expect(calls, 1);
      expect(saved!['members'], isEmpty);
      expect(
        saved!['activities'],
        unorderedEquals(onboardingActivities.map((a) => a.id)),
      );
      expect(saved!['address_line1'], '1 Example Green');
      expect(saved!['address_line2'], '');
      expect(saved!.containsKey('address'), isFalse);
      expect(saved!.containsKey('send_invitations'), isFalse);
      expect(find.text('Your club setup is complete'), findsOneWidget);
      await tap(t, 'Go to my club');
      expect(find.text('Normal club home: new-club'), findsOneWidget);
      expect(find.text('Create club and finish'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('an uncertain save reuses the same request and frozen payload', (
    t,
  ) async {
    final ids = <String>[];
    final payloads = <Map<String, dynamic>>[];
    await t.pumpWidget(
      MaterialApp(
        home: StagingClubOnboardingScreen(
          secretaryLoader: () async => secretary,
          lookup: (name, postcode) async => {'clubs': [], 'venues': []},
          creator: (id, payload) async {
            ids.add(id);
            payloads.add(payload);
            if (ids.length == 1) throw Exception('network');
            return {
              'club_id': 'one-club',
              'name': payload['name'],
              'reused': true,
            };
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    await review(t);
    await tap(t, 'Create club and finish');
    expect(
      find.textContaining('result could not be confirmed'),
      findsOneWidget,
    );
    await tap(t, 'Create club and finish');
    expect(ids, hasLength(2));
    expect(ids.first, ids.last);
    expect(identical(payloads.first, payloads.last), isTrue);
    expect(find.text('Your club setup is complete'), findsOneWidget);
  });
  testWidgets('missing address stops at the exact field before creation', (
    t,
  ) async {
    var calls = 0;
    await t.pumpWidget(
      MaterialApp(
        home: StagingClubOnboardingScreen(
          secretaryLoader: () async => secretary,
          lookup: (name, postcode) async => {'clubs': [], 'venues': []},
          creator: (id, payload) async {
            calls++;
            return {};
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    await tap(t, 'Let’s begin');
  await t.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Club name'), 'New staging test club');
  await t.pumpAndSettle();
    await tap(t, 'Continue');
    await tap(t, 'Continue');
    expect(find.text('Step 3 of 10'), findsOneWidget);
    expect(find.text('Enter your venue name and address'), findsOneWidget);
    expect(calls, 0);
  });
}
