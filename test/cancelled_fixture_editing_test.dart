import 'package:bowls_saas/features/fixtures/widgets/fixture_timing_controls.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowls_saas/features/fixtures/fixture_details_page.dart';
import 'package:bowls_saas/features/team/manage_team_screen.dart';

void main() {
  bool cancelled = true,
      superuser = true,
      normalMember = false,
      sharedCompetition = false,
      captainDelete = false,
      participating = true;
  var savedLabel = 'Recorded fixture label';
  var labelSaveFailure = false;
  final writes = <String>[];
  final timingWrites = <Map<String, dynamic>>[];
  Map<String, dynamic> fixture() => {
    'id': 'fixture',
    'club_id': 'club',
    'created_by_user_id': normalMember ? 'creator-user' : 'user',
    'captain_member_profile_id': captainDelete
        ? 'member'
        : (normalMember ? 'creator-member' : 'member'),
    'start_at': '2026-11-19T10:00:00Z',
    'end_at': '2026-11-19T12:00:00Z',
    'cancelled_at': cancelled ? '2026-10-28T00:00:00Z' : null,
    'cancellation_reason': 'Cancelled test',
    'is_home': true,
    'section': 'mixed',
    'rinks_required': 1,
    'players_per_rink': 1,
    'team_name': savedLabel,
    'requires_rsvp': false,
    'competition_type_id': 'type',
    'competition_type': {
      'id': 'type',
      'name': 'Club Competition',
      'is_internal': true,
      'uses_rinks': true,
      'selection_mode': 'preselect',
    },
    'fixture_rinks': [],
  };
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final token =
        '${base64Url.encode(utf8.encode('{"alg":"HS256"}'))}.${base64Url.encode(utf8.encode('{"sub":"user","exp":2000000000}'))}.signature';
    await Supabase.initialize(
      url: 'https://example.invalid',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        final path = r.url.path;
        final sel = r.url.queryParameters['select'] ?? '';
        dynamic data;
        if (path.endsWith('/token')) {
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
        } else if (path.endsWith('/my_member_profile_id'))
          data = 'member';
        else if (path.endsWith('/fixture_deletion_preview'))
          data = {
            'can_delete': captainDelete,
            'can_force_delete': false,
            'captain_member_delete': captainDelete,
            'has_players': true,
            'selected_members': 2,
          };
        else if (path.endsWith('/save_fixture_label_safe')) {
          if (labelSaveFailure)
            return http.Response(
              jsonEncode({'message': 'Label save denied', 'code': '42501'}),
              403,
              headers: {'content-type': 'application/json'},
            );
          final params = jsonDecode(r.body) as Map;
          savedLabel = params['p_label'] as String;
          data = {
            'id': 'fixture',
            'team_name': savedLabel,
            'dress_code': params['p_dress_code'] ?? [],
          };
        } else if (path.endsWith('/change_fixture_time_safe')) {
          timingWrites.add(
            Map<String, dynamic>.from(jsonDecode(r.body) as Map),
          );
          data = true;
        } else if (path.endsWith('/delete_fixture')) {
          writes.add('delete_fixture');
          data = true;
        } else if (path.endsWith('/competition_fixture_access'))
          data = {
            'is_competition': sharedCompetition,
            'can_manage': sharedCompetition && !cancelled,
            'is_creator': !normalMember,
          };
        else if (path.endsWith('/competition_fixture_management_state'))
          data = {
            'fixture': {
              'id': 'fixture',
              'club_id': 'club',
              'name': 'Competition booking',
              'round': 'Final 1',
              'start_at': '2030-07-02T10:00:00Z',
              'end_at': '2030-07-02T12:30:00Z',
              'green_area_id': 'green',
              'rinks_required': 1,
            },
            'rinks': [
              {
                'id': 'rink',
                'number': 1,
                'home_rink_label': 'R1',
                'marker_required': true,
              },
            ],
            'assigned_member_ids': ['member'],
          };
        else if (path.contains('/rpc/'))
          data = {};
        else if (path.endsWith('/fixtures'))
          data = fixture();
        else if (path.endsWith('/app_superusers'))
          data = superuser ? {'user_id': 'user'} : null;
        else if (path.endsWith('/club_memberships'))
          data = sel.contains('member_profile:')
              ? []
              : {'id': 'membership', 'role': normalMember ? 'member' : 'admin'};
        else if (path.endsWith('/member_profiles'))
          data = {
            'id': 'member',
            'first_name': 'Test',
            'last_name': 'Admin',
            'display_name': 'Test Admin',
            'sex_at_birth': 'male',
          };
        else if (path.endsWith('/fixture_rinks'))
          data = [
            {
              'id': 'rink',
              'fixture_rink_no': 1,
              'players_per_rink': 1,
              'marker_required': true,
            },
          ];
        else if (path.endsWith('/fixture_rink_assignments'))
          data = sel.contains('fixture_rink_id')
              ? [
                  {
                    'fixture_rink_id': 'rink',
                    'position': 1,
                    'member_profile_id': normalMember && participating
                        ? 'member'
                        : 'player',
                    'display_name': 'Recorded player',
                    'member': {
                      'id': 'player',
                      'display_name': 'Recorded player',
                    },
                  },
                  {
                    'fixture_rink_id': 'rink',
                    'position': 201,
                    'member_profile_id': 'marker',
                    'display_name': 'Recorded marker',
                    'member': {
                      'id': 'marker',
                      'display_name': 'Recorded marker',
                    },
                  },
                ]
              : [];
        else if (path.endsWith('/team_selections'))
          data = null;
        else if (path.endsWith('/fixture_rsvps'))
          data = sel == 'status' ? null : [];
        else
          data = [];
        if (path.startsWith('/rest/v1/') &&
            !path.contains('/rpc/') &&
            r.method != 'GET') {
          writes.add(path);
        }
        return http.Response(
          jsonEncode(data),
          200,
          request: r,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'test@example.invalid',
      password: 'fake',
    );
  });
  setUp(() {
    captainDelete = false;
    savedLabel = 'Recorded fixture label';
    labelSaveFailure = false;
  });
  testWidgets(
    'Member captain deletes with clear notice even with attached players',
    (t) async {
      captainDelete = true;
      normalMember = true;
      superuser = false;
      cancelled = false;
      sharedCompetition = false;
      writes.clear();
      t.view.physicalSize = const Size(1300, 1800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        const MaterialApp(home: FixtureDetailsPage(fixtureId: 'fixture')),
      );
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Delete fixture').first);
      await t.pumpAndSettle();
      expect(
        find.textContaining('including anyone who has confirmed'),
        findsOneWidget,
      );
      expect(find.textContaining('No players are attached'), findsNothing);
      expect(find.text('Force Delete'), findsNothing);
      await t.tap(find.widgetWithText(FilledButton, 'Delete'));
      await t.pumpAndSettle();
      expect(writes, contains('delete_fixture'));
      normalMember = false;
    },
  );
  testWidgets(
    'Fixture timing preserves duration and an unsaved label through reload',
    (t) async {
      cancelled = false;
      superuser = false;
      normalMember = false;
      sharedCompetition = false;
      timingWrites.clear();
      t.view.physicalSize = const Size(1300, 1800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        const MaterialApp(home: FixtureDetailsPage(fixtureId: 'fixture')),
      );
      await t.pumpAndSettle();
      final label = find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == 'Recorded fixture label',
      );
      await t.scrollUntilVisible(
        label,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await t.enterText(label, 'TEST - captain deletion');
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byType(FixtureTimingControls),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(
        find
            .descendant(
              of: find.byType(FixtureTimingControls),
              matching: find.byType(OutlinedButton),
            )
            .first,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('20'));
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(
        t.widget<TimePickerDialog>(find.byType(TimePickerDialog)).initialTime,
        const TimeOfDay(hour: 10, minute: 0),
      );
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      await t.tap(find.text('Change'));
      await t.pumpAndSettle();
      expect(timingWrites, hasLength(1));
      expect(timingWrites.single['p_new_start_at'], '2026-11-20T10:00:00.000Z');
      expect(timingWrites.single['p_new_end_at'], '2026-11-20T12:00:00.000Z');
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is TextField && w.controller?.text == 'TEST - captain deletion',
        ),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Captain label Save only clears dirty state after database confirmation',
    (t) async {
      normalMember = true;
      captainDelete = true;
      superuser = false;
      cancelled = false;
      sharedCompetition = false;
      t.view.physicalSize = const Size(1300, 1800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        const MaterialApp(home: FixtureDetailsPage(fixtureId: 'fixture')),
      );
      await t.pumpAndSettle();
      final field = find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == 'Recorded fixture label',
      );
      await t.scrollUntilVisible(
        field,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await t.enterText(field, 'TEST - captain deletion');
      await t.pumpAndSettle();
      final labelField = find.byWidgetPredicate(
        (w) =>
            w is TextField && w.controller?.text == 'TEST - captain deletion',
      );
      final section = find
          .ancestor(of: labelField, matching: find.byType(Card))
          .first;
      final save = find
          .descendant(
            of: section,
            matching: find.widgetWithText(ElevatedButton, 'Save'),
          )
          .first;
      final dirtyColor = t
          .widget<ElevatedButton>(save)
          .style
          ?.backgroundColor
          ?.resolve({});
      expect(dirtyColor, isNotNull);
      labelSaveFailure = true;
      await t.ensureVisible(save);
      await t.tap(save);
      await t.pumpAndSettle();
      expect(find.textContaining('Failed to save:'), findsOneWidget);
      expect(savedLabel, 'Recorded fixture label');
      expect(labelField, findsOneWidget);
      expect(
        t.widget<ElevatedButton>(save).style?.backgroundColor?.resolve({}),
        dirtyColor,
      );
      labelSaveFailure = false;
      await t.tap(save);
      await t.pumpAndSettle();
      expect(savedLabel, 'TEST - captain deletion');
      expect(
        t.widget<ElevatedButton>(save).style?.backgroundColor?.resolve({}),
        isNull,
      );
      expect(t.takeException(), isNull);
      normalMember = false;
    },
  );
  for (final isCancelled in [false, true]) {
    testWidgets(
      'Non-participating member can view internal players and rinks, cancelled=$isCancelled',
      (t) async {
        normalMember = true;
        participating = false;
        superuser = false;
        cancelled = isCancelled;
        sharedCompetition = false;
        writes.clear();
        addTearDown(() {
          normalMember = false;
          participating = true;
        });
        t.view.physicalSize = const Size(1300, 1800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(
          const MaterialApp(home: FixtureDetailsPage(fixtureId: 'fixture')),
        );
        await t.pumpAndSettle();
        await t.scrollUntilVisible(
          find.text('Players, opponents and rinks'),
          400,
          scrollable: find.byType(Scrollable).first,
        );
        final section = find
            .ancestor(
              of: find.text('Players, opponents and rinks'),
              matching: find.byType(Card),
            )
            .first;
        expect(find.textContaining('Team 1 (Rink'), findsOneWidget);
        expect(
          find.text('Current Pre-Select fixture assignments.'),
          findsOneWidget,
        );
        expect(find.text('Add Team/Rink'), findsNothing);
        expect(find.text('Team setup'), findsNothing);
        expect(find.byTooltip('Delete fixture'), findsNothing);
        expect(find.byTooltip('Cancel or reschedule fixture'), findsNothing);
        final controls = t.widgetList<OutlinedButton>(
          find.descendant(of: section, matching: find.byType(OutlinedButton)),
        );
        expect(controls, isNotEmpty);
        expect(controls.every((b) => b.onPressed == null), isTrue);
        expect(writes, isEmpty);
        expect(t.takeException(), isNull);
      },
    );
  }
  tearDownAll(() => Supabase.instance.dispose());
  for (final isSuper in [false, true])
    for (final isCancelled in [false, true]) {
      testWidgets(
        '${isSuper ? 'superuser' : 'admin'}: cancelled=$isCancelled settings and preselect editing',
        (t) async {
          superuser = isSuper;
          cancelled = isCancelled;
          writes.clear();
          t.view.physicalSize = const Size(1300, 1800);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          await t.pumpWidget(
            const MaterialApp(home: FixtureDetailsPage(fixtureId: 'fixture')),
          );
          await t.pumpAndSettle();
          expect(find.byTooltip('Cancel or reschedule fixture'), findsNothing);
          expect(find.byTooltip('Reschedule fixture'), findsNothing);
          final page = find.byKey(
            const PageStorageKey<String>('fixture-details-fixture'),
          );
          expect(page, findsOneWidget);
          expect(find.byTooltip('Cancel or reschedule fixture'), findsNothing);
          expect(find.byTooltip('Reschedule fixture'), findsNothing);
          final scroll = find
              .descendant(of: page, matching: find.byType(Scrollable))
              .first;
          await t.scrollUntilVisible(
            find.text('Fixture settings'),
            400,
            scrollable: scroll,
          );
          await t.pumpAndSettle();
          final settings = find
              .ancestor(
                of: find.text('Fixture settings'),
                matching: find.byType(Card),
              )
              .first;
          final fields = t
              .widgetList<TextField>(
                find.descendant(of: settings, matching: find.byType(TextField)),
              )
              .toList();
          expect(fields, isNotEmpty);
          expect(fields.every((f) => f.enabled == !isCancelled), isTrue);
          final dropdowns = t.widgetList<DropdownButton>(
            find.descendant(
              of: settings,
              matching: find.byType(DropdownButton),
            ),
          );
          if (isCancelled)
            for (final d in dropdowns) {
              expect(d.onChanged, isNull);
            }
          await t.scrollUntilVisible(
            find.text('Players, opponents and rinks'),
            400,
            scrollable: scroll,
          );
          await t.pumpAndSettle();
          expect(find.text('Players, opponents and rinks'), findsOneWidget);
          if (isCancelled) {
            final roster = find
                .ancestor(
                  of: find.text('Players, opponents and rinks'),
                  matching: find.byType(Card),
                )
                .first;
            final playerAndMarkerButtons = t
                .widgetList<OutlinedButton>(
                  find.descendant(
                    of: roster,
                    matching: find.byType(OutlinedButton),
                  ),
                )
                .toList();
            expect(playerAndMarkerButtons, isNotEmpty);
            expect(
              playerAndMarkerButtons.every((b) => b.onPressed == null),
              isTrue,
            );
            for (final toggle in t.widgetList<SwitchListTile>(
              find.descendant(
                of: roster,
                matching: find.byType(SwitchListTile),
              ),
            )) {
              expect(toggle.onChanged, isNull);
            }
            expect(find.text('Add Team/Rink'), findsNothing);
            expect(
              find.textContaining('Current Pre-Select fixture assignments.'),
              findsOneWidget,
            );
          } else {
            expect(find.text('Add Team/Rink'), findsOneWidget);
          }
          expect(writes, isEmpty);
          expect(t.takeException(), isNull);
        },
      );
    }
  testWidgets('cancelled team is read-only even without caller readOnly flag', (
    t,
  ) async {
    cancelled = true;
    superuser = true;
    writes.clear();
    await t.pumpWidget(MaterialApp(home: ManageTeamScreen(fixture: fixture())));
    await t.pumpAndSettle();
    expect(find.text('No team has been selected yet.'), findsOneWidget);
    expect(find.text('Publish Team'), findsNothing);
    expect(writes, isEmpty);
    expect(t.takeException(), isNull);
  });
  for (final linked in [false, true]) {
    testWidgets('Ordinary member shared competition controls: linked=$linked', (
      t,
    ) async {
      normalMember = true;
      sharedCompetition = linked;
      superuser = false;
      cancelled = false;
      addTearDown(() {
        normalMember = false;
        sharedCompetition = false;
      });
      t.view.physicalSize = const Size(1300, 1800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        const MaterialApp(home: FixtureDetailsPage(fixtureId: 'fixture')),
      );
      await t.pumpAndSettle();
      final button = find.widgetWithText(
        FilledButton,
        'Manage competition booking',
      );
      if (linked) {
        await t.ensureVisible(button);
        expect(button, findsOneWidget);
        expect(find.byTooltip('Cancel or reschedule fixture'), findsNothing);
        expect(find.text('Add Team/Rink'), findsNothing);
        await t.tap(button);
        await t.pumpAndSettle();
        expect(find.text('Change date, time, green or rink'), findsOneWidget);
        expect(find.text('Choose marker'), findsOneWidget);
        expect(find.text('Add Team/Rink'), findsNothing);
      } else {
        expect(button, findsNothing);
      }
      expect(t.takeException(), isNull);
    });
  }
}
