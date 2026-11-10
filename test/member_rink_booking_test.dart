import 'dart:convert';
import 'package:bowls_saas/core/utils/date_format.dart';
import 'package:bowls_saas/features/fixtures/member_booking_repository.dart';
import 'package:bowls_saas/features/fixtures/member_fixture_creation_page.dart';
import 'package:bowls_saas/features/fixtures/fixture_details_page.dart';
import 'package:bowls_saas/features/fixtures/create_fixture_page.dart';
import 'package:bowls_saas/features/fixtures/widgets/member_booking_timeline.dart';
import 'package:bowls_saas/features/communications/member_options_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeBookingRepository extends MemberBookingRepository {
  FakeBookingRepository() : super(Supabase.instance.client);
  bool conflict = false, full = false;
  int writes = 0;
  DateTime? bookedStart;
  String? bookedLabel;
  @override
  Future<String> memberId(String clubId) async => 'member';
  @override
  Future<List<Map<String, dynamic>>> fixtureTypes(String clubId) async => [
    {
      'id': 'type',
      'name': 'Member Practice',
      'section': 'mixed',
      'default_players_per_rink': 2,
      'colour_scheme': {
        'background_hex': '#fff0bc',
        'foreground_hex': '#503d08',
      },
    },
  ];
  @override
  Future<List<Map<String, dynamic>>> venues(String clubId) async => [
    {'id': 'venue', 'name': 'Home'},
  ];
  @override
  Future<List<Map<String, dynamic>>> greens(String venueId) async => [
    {
      'id': 'green',
      'name': 'Main green',
      'rink_count': 7,
      'scheme_type': 'numeric',
      'scheme_prefix': 'R',
    },
  ];
  @override
  Future<MemberBookingDay> day(
    String clubId,
    String greenId,
    DateTime date,
  ) async => MemberBookingDay(
    full
        ? [
            {
              'start_at': clubTimeToUtc(
                DateTime(date.year, date.month, date.day, 9),
              ).toIso8601String(),
              'end_at': clubTimeToUtc(
                DateTime(date.year, date.month, date.day, 22),
              ).toIso8601String(),
              'rinks_required': 7,
              'fixture_rinks': <Object>[],
              'competition_types': {'name': 'Club event'},
            },
          ]
        : [],
    [],
  );
  @override
  Future<void> checkSlot(String greenId, String label, DateTime start) async {
    if (conflict) throw StateError('That space is no longer available.');
  }

  @override
  Future<String> book({
    required String clubId,
    required String memberId,
    required Map<String, dynamic> type,
    required String venueId,
    required Map<String, dynamic> green,
    required String label,
    required DateTime start,
  }) async {
    if (conflict) throw StateError('That space is no longer available.');
    writes++;
    bookedStart = start;
    bookedLabel = label;
    return 'created-fixture';
  }
}

void main() {
  var admin = false;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.invalid',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        dynamic data = <Object>[];
        final path = r.url.path;
        if (path.endsWith('/token')) {
          final token =
              '${base64Url.encode(utf8.encode('{"alg":"HS256"}'))}.${base64Url.encode(utf8.encode('{"sub":"user","exp":2200000000}'))}.signature';
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
        } else if (path.endsWith('/club_memberships')) {
          data = [
            {'id': 'membership', 'role': admin ? 'admin' : 'member'},
          ];
        } else if (path.endsWith('/member_profiles')) {
          data = [
            {
              'id': 'member',
              'club_memberships': [
                {'id': 'membership', 'role': admin ? 'admin' : 'member'},
              ],
            },
          ];
        } else if (path.endsWith('/venues')) {
          data = [
            {'id': 'venue', 'name': 'Home'},
          ];
        } else if (path.endsWith('/green_areas')) {
          data = [
            {
              'id': 'green',
              'venue_id': 'venue',
              'name': 'Main green',
              'rink_count': 7,
              'scheme_type': 'numeric',
              'scheme_prefix': 'R',
            },
          ];
        } else if (path.endsWith('/competition_types')) {
          data = [
            {
              'id': 'type',
              'name': 'Member Practice',
              'is_internal': true,
              'bookable_by_members': true,
              'uses_rinks': true,
              'team_selection_enabled': true,
              'is_active': true,
              'selection_mode': 'preselect',
              'section': 'mixed',
              'default_players_per_rink': 2,
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

  for (final allowAdmin in [false, true]) {
    testWidgets('Member booking option admin visibility: $allowAdmin', (
      t,
    ) async {
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showMemberOptionsMenu(
                  context: context,
                  clubId: 'club',
                  clubName: 'Club',
                  allowAdmin: allowAdmin,
                  openMembershipDetails: () async {},
                ),
                child: const Text('Options'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Options'));
      await t.pumpAndSettle();
      final option = find.text('Member Fixture booking');
      if (allowAdmin) {
        await t.scrollUntilVisible(
          option,
          250,
          scrollable: find.byType(Scrollable).last,
        );
        await t.pumpAndSettle();
      }
      expect(option, allowAdmin ? findsOneWidget : findsNothing);
      if (allowAdmin) {
        await t.ensureVisible(option);
        await t.tap(option);
        await t.pumpAndSettle();
        expect(find.byType(MemberFixtureCreationPage), findsOneWidget);
        final page = t.widget<MemberFixtureCreationPage>(
          find.byType(MemberFixtureCreationPage),
        );
        expect(page.initialRinkLabel, isNull);
        expect(page.initialDate, isNull);
        expect(find.byType(MemberBookingTimeline), findsNothing);
        expect(find.widgetWithText(FilledButton, 'Book rink'), findsNothing);
        await t.tap(find.byKey(const ValueKey('member-type-type')));
        await t.pumpAndSettle();
        expect(
          t
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Book rink'),
              )
              .onPressed,
          isNull,
        );
      }
      expect(t.takeException(), isNull);
    });
  }

  testWidgets(
    'Existing ordinary member creation entry opens the new booking screen',
    (t) async {
      admin = false;
      await t.pumpWidget(
        const MaterialApp(
          home: CreateFixturePage(clubId: 'club', clubName: 'Club'),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(MemberFixtureCreationPage), findsOneWidget);
      expect(find.text('Choose Member Fixture Type'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Admin normal creation retains its form; explicit member mode uses booking',
    (t) async {
      admin = true;
      await t.pumpWidget(
        const MaterialApp(
          home: CreateFixturePage(clubId: 'club', clubName: 'Club'),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(MemberFixtureCreationPage), findsNothing);
      // Close the existing admin type sheet before replacing its route.
      await t.tap(find.text('Member Practice').last);
      await t.pumpAndSettle();
      await t.pumpWidget(
        const MaterialApp(
          home: CreateFixturePage(
            key: ValueKey('member-mode'),
            clubId: 'club',
            clubName: 'Club',
            memberBookingMode: true,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(MemberFixtureCreationPage), findsOneWidget);
      expect(t.takeException(), isNull);
      admin = false;
    },
  );

  test('Rink rows follow numeric, alpha and custom green configuration', () {
    expect(
      memberBookingRinkLabels({
        'rink_count': 7,
        'scheme_type': 'numeric',
        'scheme_prefix': 'R',
        'scheme_padding': 2,
      }),
      ['R01', 'R02', 'R03', 'R04', 'R05', 'R06', 'R07'],
    );
    expect(
      memberBookingRinkLabels({
        'rink_count': 6,
        'scheme_type': 'alpha',
        'scheme_prefix': '',
      }),
      ['A', 'B', 'C', 'D', 'E', 'F'],
    );
    expect(
      memberBookingRinkLabels({
        'rink_count': 2,
        'scheme_type': 'custom_list',
        'custom_labels': ['East', 'West', 'Spare'],
      }),
      ['East', 'West'],
    );
  });
  test(
    'Availability accounts for physical occupancy, unallocated capacity, maintenance and boundaries',
    () {
      final start = DateTime(2031, 1, 14, 10);
      Map<String, dynamic> interval(int a, int b) => {
        'start_at': '2031-01-14T${a.toString().padLeft(2, '0')}:00:00Z',
        'end_at': '2031-01-14T${b.toString().padLeft(2, '0')}:00:00Z',
      };
      final day = MemberBookingDay([
        {...interval(9, 10), 'rinks_required': 2, 'fixture_rinks': []},
      ], []);
      expect(day.canBook('R1', start, ['R1', 'R2']), isTrue);
      expect(
        MemberBookingDay([
          {...interval(10, 12), 'rinks_required': 2, 'fixture_rinks': []},
        ], []).canBook('R1', start, ['R1', 'R2']),
        isFalse,
      );
      expect(
        MemberBookingDay([
          {
            ...interval(10, 12),
            'rinks_required': 1,
            'fixture_rinks': [
              {'home_rink_label': 'R1'},
            ],
          },
        ], []).canBook('R1', start, ['R1', 'R2']),
        isFalse,
      );
      expect(
        MemberBookingDay([], [
          {...interval(10, 12), 'rink_number': 1},
        ]).canBook('R1', start, ['R1', 'R2']),
        isFalse,
      );
      final staggered = MemberBookingDay([
        {...interval(10, 11), 'rinks_required': 1, 'fixture_rinks': []},
        {...interval(11, 12), 'rinks_required': 1, 'fixture_rinks': []},
      ], []);
      expect(staggered.canBook('R2', start, ['R1', 'R2']), isTrue);
    },
  );
  test(
    'Only member-bookable internal preselect rink types are requested',
    () async {
      late Uri uri;
      final client = SupabaseClient(
        'https://example.invalid',
        'test',
        httpClient: MockClient((r) async {
          uri = r.url;
          return http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
            request: r,
          );
        }),
      );
      await MemberBookingRepository(client).fixtureTypes('club');
      for (final key in [
        'bookable_by_members',
        'is_active',
        'is_internal',
        'uses_rinks',
        'team_selection_enabled',
      ]) {
        expect(uri.queryParameters[key], 'eq.true');
      }
      expect(uri.queryParameters['selection_mode'], 'eq.preselect');
      await client.dispose();
    },
  );
  test(
    'Saving rechecks slot and calls member-only RPC with London UTC time',
    () async {
      final paths = <String>[];
      Map<String, dynamic>? payload;
      final client = SupabaseClient(
        'https://example.invalid',
        'test',
        httpClient: MockClient((r) async {
          paths.add(r.url.path);
          if (r.url.path.endsWith('get_green_rink_availability')) {
            return http.Response(
              jsonEncode([
                {
                  'rink_label': 'R7',
                  'is_booked': false,
                  'free_capacity_rinks': 1,
                },
              ]),
              200,
              headers: {'content-type': 'application/json'},
              request: r,
            );
          }
          payload = jsonDecode(r.body) as Map<String, dynamic>;
          return http.Response(
            '"saved"',
            200,
            headers: {'content-type': 'application/json'},
            request: r,
          );
        }),
      );
      final id = await MemberBookingRepository(client).book(
        clubId: 'club',
        memberId: 'member',
        type: {'id': 'type'},
        venueId: 'venue',
        green: {'id': 'green'},
        label: 'R7',
        start: DateTime(2031, 7, 14, 10),
      );
      expect(id, 'saved');
      expect(paths.last, endsWith('/create_member_rink_booking'));
      expect(payload!['p_start_at'], '2031-07-14T09:00:00.000Z');
      expect(payload!['p_rink_label'], 'R7');
      expect(paths.length, 2);
      await client.dispose();
    },
  );

  Future<void> open(WidgetTester t, FakeBookingRepository repo) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: MemberFixtureCreationPage(
          clubId: 'club',
          clubName: 'Club',
          repository: repo,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(MemberBookingTimeline), findsNothing);
    await t.tap(find.byKey(const ValueKey('member-type-type')));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Next day'));
    await t.pumpAndSettle();
  }

  Future<void> chooseType(WidgetTester t) async {
    await t.tap(find.byKey(const Key('member-fixture-type')));
    await t.pumpAndSettle();
    await t.tap(find.text('Member Practice').last);
    await t.pumpAndSettle();
  }

  Future<void> chooseSlot(WidgetTester t) async {
    final slot = find.text('09:00–11:30 · R1');
    await t.ensureVisible(slot);
    await t.tap(slot);
    await t.pumpAndSettle();
  }

  testWidgets('Book rink stays visible while availability scrolls', (t) async {
    await open(t, FakeBookingRepository());
    final button = find.widgetWithText(FilledButton, 'Book rink');
    final before = t.getRect(button);
    await t.drag(find.byType(ListView), const Offset(0, -350));
    await t.pumpAndSettle();
    expect(t.getRect(button), before);
    expect(button.hitTestable(), findsOneWidget);
    expect(before.bottom, lessThanOrEqualTo(844));
    expect(t.takeException(), isNull);
  });
  testWidgets('Booking controls and all seven lanes fit a narrow phone', (
    t,
  ) async {
    await open(t, FakeBookingRepository());
    t.view.physicalSize = const Size(320, 740);
    await t.pumpAndSettle();
    expect(find.text('R7'), findsOneWidget);
    await t.tap(find.byTooltip('Choose booking date'));
    await t.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'Phone booking shows 7 rink rows, density choices and flows into Fixture Details',
    (t) async {
      final repo = FakeBookingRepository();
      await open(t, repo);
      expect(find.text('R7'), findsOneWidget);
      expect(find.text('Rinks required'), findsNothing);
      expect(find.text('Duration'), findsNothing);
      expect(find.text('Home venue'), findsNothing);
      await t.tap(find.byTooltip('Timeline density'));
      await t.pumpAndSettle();
      expect(find.text('Fit Day'), findsOneWidget);
      expect(find.text('Detailed'), findsOneWidget);
      await t.tap(find.text('Fit Day'));
      await t.pumpAndSettle();
      expect(
        t
            .widget<MemberBookingTimeline>(find.byType(MemberBookingTimeline))
            .density,
        MemberTimelineDensity.fit,
      );
      await chooseType(t);
      await chooseSlot(t);
      final book = find.widgetWithText(FilledButton, 'Book rink');
      await t.ensureVisible(book);
      await t.tap(book);
      await t.pumpAndSettle();
      expect(repo.writes, 1);
      expect(repo.bookedLabel, 'R1');
      expect(find.byType(FixtureDetailsPage), findsOneWidget);
      expect(
        t.widget<FixtureDetailsPage>(find.byType(FixtureDetailsPage)).fixtureId,
        'created-fixture',
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Slot lost before save refreshes availability without navigation',
    (t) async {
      final repo = FakeBookingRepository();
      await open(t, repo);
      await chooseType(t);
      await chooseSlot(t);
      repo.conflict = true;
      final book = find.widgetWithText(FilledButton, 'Book rink');
      await t.ensureVisible(book);
      await t.tap(book);
      await t.pumpAndSettle();
      expect(repo.writes, 0);
      expect(find.byType(FixtureDetailsPage), findsNothing);
      expect(find.textContaining('no longer available'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('A full day shows a next-day action and cannot be booked', (
    t,
  ) async {
    final repo = FakeBookingRepository()..full = true;
    await open(t, repo);
    expect(
      find.text('No rink is free for 2½ hours on this date.'),
      findsOneWidget,
    );
    expect(find.text('Try next day →'), findsOneWidget);
    expect(
      t
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Book rink'))
          .onPressed,
      isNull,
    );
    expect(t.takeException(), isNull);
  });
}
