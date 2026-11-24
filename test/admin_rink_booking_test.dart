import 'dart:convert';
import 'package:bowls_saas/core/utils/date_format.dart';
import 'package:bowls_saas/features/diary/rinks_day_view.dart';
import 'package:bowls_saas/features/fixtures/create_fixture_page.dart';
import 'package:bowls_saas/features/fixtures/member_fixture_creation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  var role = 'admin';
  var superuser = false;
  var multipleVenues = false;
  var requestedRinks = 1;
  var occupiedRinks = 0;
  var rinkCountLocked = false;
  Map<String, dynamic>? saved;
  final start = DateTime(2031, 1, 14, 10);
  final requests = <Uri>[];
  final types = [
    {
      'id': 'coaching',
      'name': 'Coaching Session',
      'is_internal': true,
      'section': 'open',
      'bookable_by_members': false,
      'is_active': true,
      'uses_rinks': true,
      'team_selection_enabled': true,
      'selection_mode': 'preselect',
      'default_duration_minutes': 90,
      'default_rinks_required': 1,
      'default_players_per_rink': 1,
      'default_format': 'singles',
    },
    {
      'id': 'practice',
      'name': 'Member Rink Booking',
      'is_internal': true,
      'section': 'open',
      'bookable_by_members': true,
      'is_active': true,
      'uses_rinks': true,
      'team_selection_enabled': true,
      'selection_mode': 'preselect',
      'default_duration_minutes': 150,
      'default_rinks_required': 1,
      'default_players_per_rink': 2,
      'default_format': 'pairs',
    },
    {
      'id': 'meeting',
      'name': 'Committee Meeting',
      'is_internal': true,
      'section': 'open',
      'bookable_by_members': false,
      'is_active': true,
      'uses_rinks': false,
      'team_selection_enabled': false,
      'selection_mode': null,
    },
  ];
  Map<String, dynamic> profile(String id, String first, String last) => {
    'id': id,
    'first_name': first,
    'last_name': last,
    'display_name': '$first $last',
    'sex_at_birth': 'female',
    'club_memberships': [
      {'id': 'membership', 'role': role},
    ],
  };
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.invalid',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        requests.add(r.url);
        final path = r.url.path, select = r.url.queryParameters['select'] ?? '';
        dynamic data = <Object>[];
        if (path.endsWith('/token')) {
          final header = base64Url.encode(utf8.encode('{"alg":"HS256"}'));
          final payload = base64Url.encode(
            utf8.encode('{"sub":"user","exp":2200000000}'),
          );
          final token = '$header.$payload.signature';
          data = {
            'access_token': token,
            'refresh_token': 'refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': 'user',
              'aud': 'authenticated',
              'created_at': '2026-01-01T00:00:00Z',
              'app_metadata': {},
              'user_metadata': {},
            },
          };
        } else if (path.endsWith('/my_member_profile_id')) {
          data = 'member';
        } else if (path.endsWith('/app_superusers')) {
          data = superuser
              ? [
                  {'user_id': 'user'},
                ]
              : [];
        } else if (path.endsWith('/club_memberships')) {
          data = select.contains('member_profile:')
              ? [
                  {'member_profile': profile('member', 'Alex', 'Admin')},
                  {'member_profile': profile('jeanette', 'Jeanette', 'Player')},
                ]
              : [
                  {'id': 'membership', 'role': role},
                ];
        } else if (path.endsWith('/member_profiles')) {
          data = [profile('member', 'Alex', 'Admin')];
        } else if (path.endsWith('/venues')) {
          data = r.url.queryParameters['is_home_venue'] == 'eq.false'
              ? []
              : [
                  if (multipleVenues && !select.contains('latitude,longitude'))
                    {'id': 'other-venue', 'name': 'A first venue'},
                  {
                    'id': 'venue',
                    'name': 'Selected venue',
                    'club_start_time': '09:00',
                    'club_end_time': '22:00',
                  },
                ];
        } else if (path.endsWith('/green_areas')) {
          data = [
            {
              'id': 'green',
              'venue_id': 'venue',
              'name': 'Selected green',
              'rink_count': 6,
              'scheme_type': 'numeric',
              'scheme_prefix': 'R',
              'is_outdoor': false,
              'orientation_mode': 'off',
            },
          ];
        } else if (path.endsWith('/competition_types')) {
          types[0]['default_rinks_required'] = requestedRinks;
          types[1]['default_rinks_required'] = requestedRinks;
          types[0]['lock_rinks'] = rinkCountLocked;
          types[1]['lock_rinks'] = rinkCountLocked;
          data = r.url.queryParameters.containsKey('bookable_by_members')
              ? types.where((t) => t['bookable_by_members'] == true).toList()
              : types;
          if (r.url.queryParameters['uses_rinks'] == 'eq.true') {
            data = (data as List)
                .where((t) => t['uses_rinks'] == true)
                .toList();
          }
        } else if (path.endsWith('/fixtures') && occupiedRinks > 0) {
          data = [
            {
              'id': 'existing-booking',
              'start_at': clubTimeToUtc(start).toIso8601String(),
              'end_at': clubTimeToUtc(
                start.add(const Duration(hours: 3)),
              ).toIso8601String(),
              'rinks_required': occupiedRinks,
              'competition_types': {'name': 'Existing fixture'},
              'fixture_rinks': [
                {'home_rink_label': 'R1'},
                {'home_rink_label': 'R3'},
              ],
            },
          ];
        } else if (path.endsWith('/get_green_rink_availability')) {
          data = List.generate(
            6,
            (i) => {
              'rink_label': 'R${i + 1}',
              'is_available': true,
              'is_booked': occupiedRinks > 0 && (i == 0 || i == 2),
              'free_capacity_rinks': 6 - occupiedRinks,
              'total_rinks': 6,
            },
          );
        } else if (path.endsWith('/create_fixture_with_booking_policy')) {
          saved = jsonDecode(r.body) as Map<String, dynamic>;
          // Stop after the real form's save payload; no communication or database writes.
          return http.Response(
            jsonEncode({'message': 'Synthetic save stopped', 'code': 'P0001'}),
            400,
            headers: {'content-type': 'application/json'},
          );
        } else if (path.contains('/rpc/') && path.contains('picker')) {
          data = [
            {
              'member_profile_id': 'jeanette',
              'picker_name': 'Player, Jeanette',
              'sex_at_birth': 'female',
            },
          ];
        }
        return http.Response(
          jsonEncode(data),
          200,
          headers: {'content-type': 'application/json'},
          request: r,
        );
      }),
    );
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'test@example.invalid',
      password: 'test',
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() {
    role = 'admin';
    superuser = false;
    multipleVenues = false;
    requestedRinks = 1;
    occupiedRinks = 0;
    rinkCountLocked = false;
    saved = null;
    requests.clear();
  });

  testWidgets(
    'Internal types skip location; external types retain Home/Away choice',
    (t) async {
      t.view.physicalSize = const Size(1300, 2000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      types.add({
        ...types.first,
        'id': 'friendly',
        'name': 'Friendly Match',
        'is_internal': false,
        'selection_mode': 'rsvp',
        'default_rinks_required': 4,
        'default_players_per_rink': 4,
        'default_format': 'rinks',
      });
      addTearDown(() => types.removeWhere((type) => type['id'] == 'friendly'));
      await t.pumpWidget(
        const MaterialApp(
          home: MemberFixtureCreationPage(clubId: 'club', clubName: 'Club'),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Coaching Session'));
      await t.pumpAndSettle();
      expect(find.text('Book a rink'), findsOneWidget);
      expect(find.byKey(const Key('start-away-fixture')), findsNothing);
      // Back to the same type chooser, then take the external fixture path.
      await t.tap(find.byKey(const Key('member-fixture-type')));
      await t.pumpAndSettle();
      await t.tap(find.text('Friendly Match').last);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('start-home-fixture')), findsOneWidget);
      expect(find.byKey(const Key('start-away-fixture')), findsOneWidget);
      await t.tap(find.byKey(const Key('start-home-fixture')));
      await t.pumpAndSettle();
      expect(find.text('Book a rink'), findsOneWidget);
      expect(find.text('4 rinks'), findsOneWidget);
      await t.tap(find.byKey(const Key('member-fixture-type')));
      await t.pumpAndSettle();
      await t.tap(find.text('Friendly Match').last);
      await t.pumpAndSettle();
      requests.clear();
      await t.tap(find.byKey(const Key('start-away-fixture')));
      await t.pumpAndSettle();
      final page = t.widget<CreateFixturePage>(find.byType(CreateFixturePage));
      expect(page.initialLocation, FixtureLocationType.away);
      expect(page.initialFixtureTypeId, 'friendly');
      expect(page.initialRinkBooking, isNull);
      expect(find.text('Away'), findsOneWidget);
      expect(find.text('Book a rink'), findsNothing);
      expect(
        requests.where(
          (uri) => uri.path.endsWith('/get_green_rink_availability'),
        ),
        isEmpty,
      );
      expect(saved, isNull);
      expect(t.takeException(), isNull);
    },
  );
  Future<void> openRink(WidgetTester t, {bool book = true}) async {
    t.view.physicalSize = const Size(1300, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: RinkDayViewScreen(
          clubId: 'club',
          clubName: 'Club',
          date: start,
          greenAreaId: 'green',
        ),
      ),
    );
    await t.pumpAndSettle();
    final lane = find.byKey(const ValueKey('rink-timeline-R2'));
    expect(lane, findsOneWidget);
    await t.tapAt(t.getTopLeft(lane) + const Offset(81, 20));
    await t.pumpAndSettle();
    if (!book) return;
    await t.tap(find.text('Book Fixture'));
    await t.pumpAndSettle();
  }

  testWidgets(
    'Away button works on a fully booked diary and retains its date',
    (t) async {
      occupiedRinks = 6;
      types.add({
        ...types.first,
        'id': 'friendly-away',
        'name': 'Friendly Away Test',
        'is_internal': false,
        'selection_mode': 'rsvp',
      });
      addTearDown(
        () => types.removeWhere((type) => type['id'] == 'friendly-away'),
      );
      t.view.physicalSize = const Size(1300, 2000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          home: RinkDayViewScreen(
            clubId: 'club',
            clubName: 'Club',
            date: start,
            greenAreaId: 'green',
          ),
        ),
      );
      await t.pumpAndSettle();
      requests.clear();
      await t.tap(find.byKey(const Key('book-away-fixture')));
      await t.pumpAndSettle();
      expect(find.text('Coaching Session'), findsNothing);
      await t.tap(find.text('Friendly Away Test'));
      await t.pumpAndSettle();
      final page = t.widget<CreateFixturePage>(find.byType(CreateFixturePage));
      expect(page.initialLocation, FixtureLocationType.away);
      expect(DateUtils.isSameDay(page.initialDate, start), isTrue);
      expect(page.initialRinkBooking, isNull);
      expect(find.text('Away'), findsOneWidget);
      expect(
        requests.where(
          (uri) => uri.path.endsWith('/get_green_rink_availability'),
        ),
        isEmpty,
      );
      expect(saved, isNull);
      expect(t.takeException(), isNull);
    },
  );

  for (final access in ['admin', 'selector', 'superuser']) {
    testWidgets(
      '$access rink booking offers coaching and retains the chosen slot',
      (t) async {
        role = access == 'superuser' ? 'guest' : access;
        superuser = access == 'superuser';
        await openRink(t);
        expect(find.byType(MemberFixtureCreationPage), findsOneWidget);
        expect(find.text('Coaching Session'), findsOneWidget);
        expect(find.text('Committee Meeting'), findsNothing);
        await t.tap(find.text('Coaching Session'));
        await t.pumpAndSettle();
        await t.tap(find.text('Continue to fixture details'));
        await t.pumpAndSettle();
        expect(find.text(formatClubDateTime(start)), findsOneWidget);
        expect(
          find.text(formatClubDateTime(start.add(const Duration(minutes: 90)))),
          findsOneWidget,
        );
        if (access == 'admin') {
          final player = find
              .widgetWithText(OutlinedButton, 'Admin, Alex')
              .first;
          await t.ensureVisible(player);
          await t.tap(player);
          await t.pumpAndSettle();
          await t.tap(find.text('Select a club member'));
          await t.pumpAndSettle();
          await t.tap(find.text('Player, Jeanette'));
          await t.pumpAndSettle();
          expect(
            find.widgetWithText(OutlinedButton, 'Player, Jeanette'),
            findsOneWidget,
          );
        }
        await t.tap(find.text('Save'));
        await t.pumpAndSettle();
        expect(saved, isNotNull);
        final booking = saved!['p_booking'] as Map<String, dynamic>;
        expect(booking['p_competition_type_id'], 'coaching');
        expect(booking['p_green_area_id'], 'green');
        expect(booking['p_venue_id'], 'venue');
        expect(booking['p_start_at'], clubTimeToUtc(start).toIso8601String());
        expect(booking['p_home_rink_labels'], [
          {'team_no': 1, 'home_rink_label': 'R2'},
        ]);
        if (access == 'admin') {
          expect(booking['p_rink_assignments'], [
            {'team_no': 1, 'member_profile_id': 'jeanette', 'position': 1},
          ]);
        }
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets('ordinary member retains the restricted booking route', (
    t,
  ) async {
    role = 'member';
    await openRink(t);
    expect(find.byType(MemberFixtureCreationPage), findsOneWidget);
    expect(find.text('Member Rink Booking'), findsOneWidget);
    expect(find.text('Coaching Session'), findsNothing);
    final query = requests.lastWhere(
      (u) => u.path.endsWith('/competition_types'),
    );
    expect(query.queryParameters['bookable_by_members'], 'eq.true');
    expect(query.queryParameters['is_internal'], 'eq.true');
    expect(t.takeException(), isNull);
  });
  testWidgets('guest cannot book from a rink slot', (t) async {
    role = 'guest';
    await openRink(t, book: false);
    expect(find.text('Book Fixture'), findsNothing);
    expect(saved, isNull);
    expect(t.takeException(), isNull);
  });
  for (final member in [false, true]) {
    testWidgets(
      '${member ? 'member' : 'admin'} selects two rinks before continuing and saves both',
      (t) async {
        role = member ? 'member' : 'admin';
        requestedRinks = 2;
        t.view.physicalSize = const Size(1300, 2400);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(
          MaterialApp(
            home: MemberFixtureCreationPage(
              clubId: 'club',
              clubName: 'Club',
              initialDate: start,
              initialGreenId: 'green',
              initialRinkLabel: 'R2',
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(
          find.text(member ? 'Member Rink Booking' : 'Coaching Session'),
        );
        await t.pumpAndSettle();
        expect(find.textContaining('1 of 2 rinks selected'), findsOneWidget);
        expect(
          t
              .widget<FilledButton>(
                find.widgetWithText(
                  FilledButton,
                  'Continue to fixture details',
                ),
              )
              .onPressed,
          isNull,
        );
        await t.ensureVisible(find.byKey(const ValueKey('choose-rink-R4')));
        await t.tap(find.byKey(const ValueKey('choose-rink-R4')));
        await t.pumpAndSettle();
        expect(find.textContaining('2 of 2 rinks selected'), findsOneWidget);
        await t.tap(find.text('Continue to fixture details'));
        await t.pumpAndSettle();
        expect(find.byType(CreateFixturePage), findsOneWidget);
        expect(find.text(formatClubDateTime(start)), findsOneWidget);
        await t.tap(find.text('Save'));
        await t.pumpAndSettle();
        expect(saved, isNotNull);
        final booking = saved!['p_booking'] as Map<String, dynamic>;
        expect(booking['p_rinks_required'], 2);
        expect(booking['p_is_home'], true);
        expect(booking['p_start_at'], clubTimeToUtc(start).toIso8601String());
        expect(booking['p_home_rink_labels'], [
          {'team_no': 1, 'home_rink_label': 'R2'},
          {'team_no': 2, 'home_rink_label': 'R4'},
        ]);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'rink count can grow and shrink without losing time or first selections',
    (t) async {
      requestedRinks = 2;
      t.view.physicalSize = const Size(1300, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          home: MemberFixtureCreationPage(
            clubId: 'club',
            clubName: 'Club',
            initialDate: start,
            initialGreenId: 'green',
            initialRinkLabel: 'R2',
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Coaching Session'));
      await t.pumpAndSettle();
      Future<void> count(int old, int next) async {
        final button = find.byKey(
          Key(next > old ? 'more-rinks' : 'fewer-rinks'),
        );
        await t.ensureVisible(button);
        for (var i = 0; i < (next - old).abs(); i++) {
          await t.tap(button);
          await t.pumpAndSettle();
        }
      }

      await count(2, 4);
      for (final label in ['R4', 'R5', 'R6']) {
        final chip = find.byKey(ValueKey('choose-rink-$label'));
        await t.ensureVisible(chip);
        await t.tap(chip);
        await t.pumpAndSettle();
      }
      expect(find.textContaining('4 of 4 rinks selected'), findsOneWidget);
      expect(saved, isNull);
      await count(4, 2);
      expect(find.textContaining('2 of 2 rinks selected'), findsOneWidget);
      await count(2, 4);
      for (final label in ['R5', 'R6']) {
        final chip = find.byKey(ValueKey('choose-rink-$label'));
        await t.ensureVisible(chip);
        await t.tap(chip);
        await t.pumpAndSettle();
      }
      await t.tap(find.text('Continue to fixture details'));
      await t.pumpAndSettle();
      expect(find.text(formatClubDateTime(start)), findsOneWidget);
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(saved?['p_booking']['p_rinks_required'], 4);
      expect(saved?['p_booking']['p_home_rink_labels'], [
        {'team_no': 1, 'home_rink_label': 'R2'},
        {'team_no': 2, 'home_rink_label': 'R4'},
        {'team_no': 3, 'home_rink_label': 'R5'},
        {'team_no': 4, 'home_rink_label': 'R6'},
      ]);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'partly occupied green permits four free rinks and explains five cannot fit',
    (t) async {
      requestedRinks = 4;
      occupiedRinks = 2;
      t.view.physicalSize = const Size(1300, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          home: MemberFixtureCreationPage(
            clubId: 'club',
            clubName: 'Club',
            initialDate: start,
            initialGreenId: 'green',
            initialRinkLabel: 'R2',
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Coaching Session'));
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilterChip>(find.byKey(const ValueKey('choose-rink-R1')))
            .onSelected,
        isNull,
      );
      for (final label in ['R4', 'R5', 'R6']) {
        final chip = find.byKey(ValueKey('choose-rink-$label'));
        await t.ensureVisible(chip);
        await t.tap(chip);
        await t.pumpAndSettle();
      }
      expect(find.textContaining('4 of 4 rinks selected'), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('more-rinks')));
      await t.tap(find.byKey(const Key('more-rinks')));
      await t.pumpAndSettle();
      expect(find.textContaining('Only 4 of 6 rinks are free'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Continue to fixture details'),
            )
            .onPressed,
        isNull,
      );
      await t.tap(find.byKey(const Key('fewer-rinks')));
      await t.pumpAndSettle();
      expect(find.textContaining('4 of 4 rinks selected'), findsOneWidget);
      await t.tap(find.text('Continue to fixture details'));
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(saved?['p_booking']['p_home_rink_labels'], [
        {'team_no': 1, 'home_rink_label': 'R2'},
        {'team_no': 2, 'home_rink_label': 'R4'},
        {'team_no': 3, 'home_rink_label': 'R5'},
        {'team_no': 4, 'home_rink_label': 'R6'},
      ]);
      expect(t.takeException(), isNull);
    },
  );
  for (final administrator in [false, true]) {
    testWidgets(
      '${administrator ? 'admin override warns' : 'member cannot override'} a rink lock',
      (t) async {
        role = administrator ? 'admin' : 'member';
        requestedRinks = administrator ? 1 : 2;
        rinkCountLocked = true;
        t.view.physicalSize = const Size(1300, 2400);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(
          MaterialApp(
            home: MemberFixtureCreationPage(
              clubId: 'club',
              clubName: 'Club',
              initialDate: start,
              initialGreenId: 'green',
              initialRinkLabel: 'R2',
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(
          find.text(administrator ? 'Coaching Session' : 'Member Rink Booking'),
        );
        await t.pumpAndSettle();
        final more = find.byKey(const Key('more-rinks'));
        if (administrator) {
          expect(t.widget<IconButton>(more).onPressed, isNotNull);
          await t.tap(more);
          await t.pumpAndSettle();
          expect(
            find.textContaining(
              'Admin override: this Fixture Type normally allows 1 rink',
            ),
            findsOneWidget,
          );
        } else {
          expect(t.widget<IconButton>(more).onPressed, isNull);
          expect(
            t
                .widget<IconButton>(find.byKey(const Key('fewer-rinks')))
                .onPressed,
            isNull,
          );
        }
        final chip = find.byKey(const ValueKey('choose-rink-R4'));
        await t.ensureVisible(chip);
        await t.tap(chip);
        await t.pumpAndSettle();
        await t.tap(find.text('Continue to fixture details'));
        await t.pumpAndSettle();
        await t.ensureVisible(find.byKey(const ValueKey('rinks_0')));
        final decorator = find.byWidgetPredicate(
          (w) =>
              w is InputDecorator && w.decoration.labelText == 'Rinks required',
        );
        final dropdown = find.ancestor(
          of: decorator,
          matching: find.byType(DropdownButton<int>),
        );
        if (administrator) {
          expect(t.widget<DropdownButton<int>>(dropdown).onChanged, isNotNull);
          expect(
            find.textContaining(
              'Admin override: outside the normal member rink limit',
            ),
            findsOneWidget,
          );
        } else {
          expect(t.widget<DropdownButton<int>>(dropdown).onChanged, isNull);
        }
        await t.tap(find.text('Save'));
        await t.pumpAndSettle();
        expect(saved?['p_booking']['p_rinks_required'], 2);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'admin form resolves selected green venue instead of first venue',
    (t) async {
      multipleVenues = true;
      t.view.physicalSize = const Size(1300, 2000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          home: CreateFixturePage(
            clubId: 'club',
            clubName: 'Club',
            initialRinkBooking: InitialRinkBookingContext(
              greenAreaId: 'green',
              greenName: 'Selected green',
              rinkLabel: 'R2',
              startAt: start,
              latestEndAt: DateTime(2031, 1, 14, 22),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Coaching Session'));
      await t.pumpAndSettle();
      await t.tap(find.text('Continue to fixture details'));
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(saved?['p_booking']['p_venue_id'], 'venue');
      expect(saved?['p_booking']['p_home_rink_labels'], [
        {'team_no': 1, 'home_rink_label': 'R2'},
      ]);
      expect(t.takeException(), isNull);
    },
  );
}
