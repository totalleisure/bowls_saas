import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/clubs/staging_club_onboarding_screen.dart';
import 'package:bowls_saas/features/clubs/onboarding_member_import.dart';

const secretary = OnboardingMember(
  firstName: 'Test',
  surname: 'Secretary',
  email: 'test@example.invalid',
  role: 'admin',
  active: true,
);
Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
String value(WidgetTester t, String label) =>
    t.widget<TextField>(field(label)).controller!.text;
Future<void> tap(WidgetTester t, String text) async {
  await t.ensureVisible(find.text(text));
  await t.tap(find.text(text));
  await t.pumpAndSettle();
}

Future<void> enter(WidgetTester t, String label, String text) async {
  await t.ensureVisible(field(label));
  await t.enterText(field(label), text);
  await t.pumpAndSettle();
}

Future<void> openVenue(
  WidgetTester t, {
  Future<Map<String, dynamic>> Function(String, String)? lookup,
  Future<Map<String, dynamic>> Function(Map<String, dynamic>)? places,
}) async {
  await t.pumpWidget(
    MaterialApp(
      home: StagingClubOnboardingScreen(
        secretaryLoader: () async => secretary,
        lookup: lookup ?? (name, postcode) async => {'clubs': [], 'venues': []},
        placeLookup: places,
      ),
    ),
  );
  await t.pumpAndSettle();
  await tap(t, 'Let’s begin');
  await t.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Club name'), 'New staging test club');
  await t.pumpAndSettle();
  await tap(t, 'Continue');
}

void main() {
  testWidgets(
    'typing venue name searches automatically and ignores late older results',
    (t) async {
      final names = <String>[];
      await openVenue(
        t,
        lookup: (name, postcode) async {
          names.add(name);
          if (name == 'Old venue') {
            await Future<void>.delayed(const Duration(milliseconds: 900));
            return {
              'clubs': [],
              'venues': [
                {'name': 'Old result', 'source_club_name': 'Other'},
              ],
            };
          }
          if (name == 'New venue')
            return {
              'clubs': [],
              'venues': [
                {'name': 'New result', 'source_club_name': 'Other'},
              ],
            };
          return {'clubs': [], 'venues': []};
        },
      );
      await t.enterText(field('Venue name'), 'Old venue');
      await t.pump(const Duration(milliseconds: 450));
      expect(t.widget<TextField>(field('Venue name')).enabled, isTrue);
      await t.enterText(field('Venue name'), 'New venue');
      await t.pump(const Duration(milliseconds: 450));
      await t.pump();
      expect(find.text('New result'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 1000));
      await t.pumpAndSettle();
      expect(find.text('Old result'), findsNothing);
      expect(find.text('New result'), findsOneWidget);
      expect(names.where((n) => n == 'Old venue'), hasLength(1));
      expect(names.where((n) => n == 'New venue'), hasLength(1));
      expect(find.text('Find an existing venue'), findsNothing);
    },
  );
  testWidgets(
    'Continue presents existing matches and lets the user keep the manual address',
    (t) async {
      await openVenue(
        t,
        lookup: (name, postcode) async => {
          'clubs': [],
          'venues': [
            {
              'name': 'Saved venue',
              'address_line1': 'Different address',
              'source_club_name': 'Other',
              'is_home_venue': false,
            },
          ],
        },
      );
      await enter(t, 'Address line 1', 'My chosen address');
      await tap(t, 'Continue');
      expect(find.text('Step 3 of 10'), findsOneWidget);
      expect(find.textContaining('We found saved venues'), findsOneWidget);
      expect(value(t, 'Address line 1'), 'My chosen address');
      await tap(t, 'Keep my entered address');
      expect(find.text('Step 4 of 10'), findsOneWidget);
      await tap(t, 'Back');
      expect(value(t, 'Address line 1'), 'My chosen address');
    },
  );
  testWidgets(
    'typing a club name also offers existing club and venue records before Continue',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: StagingClubOnboardingScreen(
            secretaryLoader: () async => secretary,
            lookup: (name, postcode) async => {
              'clubs': [
                {
                  'id': 'existing',
                  'name': 'South Hill Woods Bowling Club',
                  'same_name': true,
                  'can_open': false,
                },
              ],
              'venues': [
                {
                  'name': 'South Hill Woods pavilion',
                  'source_club_name': 'Other',
                  'is_home_venue': false,
                },
              ],
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, 'Let’s begin');
  await t.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Club name'), 'New staging test club');
  await t.pumpAndSettle();
      await t.enterText(field('Club name'), 'South Hill Woods');
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      expect(find.text('South Hill Woods Bowling Club'), findsOneWidget);
      expect(find.text('South Hill Woods pavilion'), findsOneWidget);
      expect(find.text('Step 2 of 10'), findsOneWidget);
    },
  );
  testWidgets('existing club variant stops early and explains the match', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: StagingClubOnboardingScreen(
          secretaryLoader: () async => secretary,
          lookup: (n, p) async => {
            'clubs': [
              {
                'id': 'existing',
                'name': 'South Hill Woods Bowling Club',
                'same_name': true,
                'can_open': false,
              },
            ],
            'venues': [],
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    await tap(t, 'Let’s begin');
  await t.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Club name'), 'New staging test club');
  await t.pumpAndSettle();
    await enter(t, 'Club name', 'South Hill Woods');
    await tap(t, 'Continue');
    expect(find.text('Step 2 of 10'), findsOneWidget);
    expect(find.text('South Hill Woods Bowling Club'), findsOneWidget);
    expect(find.textContaining('already registered'), findsWidgets);
  });
  testWidgets('failed club check keeps the name and stops before creation', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: StagingClubOnboardingScreen(
          secretaryLoader: () async => secretary,
          lookup: (n, p) async => throw Exception('offline'),
        ),
      ),
    );
    await t.pumpAndSettle();
    await tap(t, 'Let’s begin');
  await t.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Club name'), 'New staging test club');
  await t.pumpAndSettle();
    await enter(t, 'Club name', 'Keep this name');
    await tap(t, 'Continue');
    expect(value(t, 'Club name'), 'Keep this name');
    expect(find.text('Step 2 of 10'), findsOneWidget);
    expect(
      find.textContaining('existing-club check could not finish'),
      findsOneWidget,
    );
  });
  testWidgets(
    'opponent venue suggestion changes address only when explicitly selected',
    (t) async {
      await openVenue(
        t,
        lookup: (n, p) async => {
          'clubs': [],
          'venues': [
            {
              'name': 'Example Opponent',
              'address_line1': '1 Green Road',
              'address_line2': 'Clubhouse',
              'town_city': 'Test Town',
              'postcode': 'TE1 1ST',
              'is_home_venue': false,
              'source_club_name': 'Other Club',
            },
          ],
        },
      );
      expect(value(t, 'Venue name'), 'New staging test club');
      await enter(t, 'Address line 1', 'Keep my address');
      expect(find.text('Find an existing venue'), findsNothing);
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      expect(value(t, 'Address line 1'), 'Keep my address');
      await tap(t, 'Use address');
      expect(value(t, 'Venue name'), 'Example Opponent');
      expect(value(t, 'Address line 1'), '1 Green Road');
      expect(value(t, 'Address line 2 (optional)'), 'Clubhouse');
      expect(value(t, 'Town / city'), 'Test Town');
      expect(value(t, 'Postcode'), 'TE1 1ST');
      expect(
        find.textContaining('No existing venue record has been changed'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'Google no-match and outage preserve a manual fictional address',
    (t) async {
      var calls = 0;
      Map<String, dynamic>? query;
      await openVenue(
        t,
        places: (body) async {
          query = body;
          calls++;
          if (calls == 2) throw Exception('offline');
          return {'places': []};
        },
      );
      await enter(t, 'Address line 1', 'Private manual address');
      await enter(t, 'Town / city', 'Private town');
      await tap(t, 'Search Google for a club');
      expect(query, {'action': 'search', 'query': 'New staging test club'});
      expect(value(t, 'Address line 1'), 'Private manual address');
      expect(find.textContaining('No bowls club was found'), findsOneWidget);
      await tap(t, 'Search Google for a club');
      expect(value(t, 'Address line 1'), 'Private manual address');
      expect(
        find.textContaining('Google lookup is unavailable'),
        findsOneWidget,
      );
    },
  );
  testWidgets('selected Google club fills separate address fields for review', (
    t,
  ) async {
    await openVenue(
      t,
      places: (body) async => body['action'] == 'search'
          ? {
              'places': [
                {
                  'placeId': 'google-id',
                  'name': 'Found Bowls Club',
                  'formattedAddress': '1 Google Road, Found Town',
                },
              ],
            }
          : {
              'place': {
                'placeId': 'google-id',
                'name': 'Found Bowls Club',
                'addressLine1': '1 Google Road',
                'addressLine2': 'Pavilion',
                'townCity': 'Found Town',
                'postcode': 'FO1 1ND',
              },
            },
    );
    await tap(t, 'Search Google for a club');
    await tap(t, 'Use Google address');
    expect(value(t, 'Address line 1'), '1 Google Road');
    expect(value(t, 'Address line 2 (optional)'), 'Pavilion');
    expect(value(t, 'Town / city'), 'Found Town');
    expect(value(t, 'Postcode'), 'FO1 1ND');
    expect(find.textContaining('Address filled in for review'), findsOneWidget);
  });
}
