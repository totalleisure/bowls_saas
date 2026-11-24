import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/clubs/club_registration_screen.dart';

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Future<void> tap(WidgetTester t, String text) async {
  await t.ensureVisible(find.text(text));
  await t.pumpAndSettle();
  await t.tap(find.text(text));
  await t.pumpAndSettle();
}

Future<void> enter(WidgetTester t, String label, String value) async {
  await t.ensureVisible(field(label));
  await t.pumpAndSettle();
  await t.enterText(field(label), value);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('Secretary can verify own website after a missing Maps match', (
    t,
  ) async {
    final calls = <Map<String, dynamic>>[];
    await t.pumpWidget(
      MaterialApp(
        home: ClubRegistrationScreen(
          request: (data) async {
            calls.add(data);
            if (data['action'] == 'website')
              return {
                'request_id': 'request',
                'places': [
                  {
                    'source': 'website',
                    'placeId': 'web_test',
                    'name': 'Coney Hall Bowling Club',
                    'formattedAddress':
                        'Coney Hall Recreation Ground, West Wickham, BR4 9JJ',
                    'websiteUrl': 'https://coneyhall.bowlsclub.net/',
                    'evidenceUrl': 'https://coneyhall.bowlsclub.net/contact',
                  },
                ],
              };
            return {'request_id': 'request', 'places': []};
          },
        ),
      ),
    );
    await enter(t, 'Club name and town or postcode', 'Coney Hall');
    await tap(t, 'Find my club');
    await enter(t, 'Club website address', 'coneyhall.bowlsclub.net');
    await tap(t, 'Check club website');
    expect(find.text('Coney Hall Bowling Club'), findsOneWidget);
    expect(find.text('Confirmed from the club’s website'), findsOneWidget);
    expect(calls.last['website_url'], 'coneyhall.bowlsclub.net');
    await t.ensureVisible(find.byType(ListTile));
    await t.pumpAndSettle();
    await t.tap(find.byType(ListTile));
    await t.pumpAndSettle();
    expect(find.text('Send my verification code'), findsOneWidget);
    expect(find.text('Verify email and continue'), findsNothing);
  });

  testWidgets('Both modest entry links open the same staging journey', (
    t,
  ) async {
    for (final welcome in [true, false]) {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ClubSetupEntry(welcome: welcome)),
        ),
      );
      await tap(t, 'Set up your club');
      expect(find.text('Let’s bring your club online'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    }
  });
  testWidgets('Registered Google club offers contact before email', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: ClubRegistrationScreen(
          request: (data) async => {
            'request_id': 'request',
            'places': [
              {
                'placeId': 'place',
                'name': 'South Hill Wood Bowling Club',
                'formattedAddress': 'Club Road',
                'duplicates': ['South Hill Woods Bowling Club'],
              },
            ],
          },
        ),
      ),
    );
    await enter(t, 'Club name and town or postcode', 'South Hill Woods');
    await tap(t, 'Find my club');
    await t.ensureVisible(find.byType(ListTile));
    await t.pumpAndSettle();
    await t.tap(find.byType(ListTile));
    await t.pumpAndSettle();
    expect(find.text('Let’s help you get your club online'), findsOneWidget);
    expect(find.text('Send my verification code'), findsNothing);
  });
  testWidgets('No Google match offers contact and retains the search', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: ClubRegistrationScreen(
          request: (data) async => {'request_id': 'request', 'places': []},
        ),
      ),
    );
    await enter(t, 'Club name and town or postcode', 'Fictional Bowls Club');
    await tap(t, 'Find my club');
    expect(find.text('Let’s help you get your club online'), findsOneWidget);
    expect(find.text('Call Wayne'), findsOneWidget);
    expect(find.text('Email Wayne'), findsOneWidget);
    expect(
      t
          .widget<TextField>(field('Club name and town or postcode'))
          .controller!
          .text,
      'Fictional Bowls Club',
    );
    expect(find.text('Verify email and continue'), findsNothing);
  });
  testWidgets(
    'Code must be accepted before entering setup; failures retain details',
    (t) async {
      var accepted = false, signins = 0;
      await t.pumpWidget(
        MaterialApp(
          home: ClubRegistrationScreen(
            request: (d) async => switch (d['action']) {
              'search' => {
                'request_id': 'request',
                'places': [
                  {
                    'placeId': 'place',
                    'name': 'Real Bowls Club',
                    'formattedAddress': 'Club Road',
                  },
                ],
              },
              'send' => {
                'sent': true,
                'place': {'placeId': 'place', 'name': 'Real Bowls Club'},
              },
              _ =>
                accepted
                    ? {'verified': true, 'token_hash': 'private-sign-in-hash'}
                    : {'error': 'That code was not recognised.'},
            },
            verifySignIn: (_) async {
              signins++;
            },
            setupBuilder: (_) => const Scaffold(body: Text('Verified setup')),
          ),
        ),
      );
      await enter(t, 'Club name and town or postcode', 'Real Bowls Club');
      await tap(t, 'Find my club');
      await t.ensureVisible(find.byType(ListTile));
      await t.pumpAndSettle();
      await t.tap(find.byType(ListTile));
      await t.pumpAndSettle();
      await enter(t, 'First name', 'Test');
      await enter(t, 'Surname', 'Secretary');
      await enter(t, 'Email address', 'wayne.s.sayers+member001@gmail.com');
      await enter(t, 'Telephone number', '07700123456');
      await tap(t, 'I am authorised to set up this club');
      await tap(t, 'Send my verification code');
      await enter(t, 'Verification code', '111111');
      await tap(t, 'Verify email and continue');
      expect(signins, 0);
      expect(find.text('That code was not recognised.'), findsOneWidget);
      accepted = true;
      await tap(t, 'Verify email and continue');
      expect(signins, 1);
      expect(find.text('Verified setup'), findsOneWidget);
    },
  );
}
