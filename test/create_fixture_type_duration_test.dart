import 'dart:convert';
import 'package:bowls_saas/core/utils/date_format.dart';
import 'package:bowls_saas/features/fixtures/create_fixture_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  var admin = true;
  var locked = false;
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
            {'id': 'membership', 'role': admin ? 'admin' : 'selector'},
          ];
        } else if (path.endsWith('/member_profiles')) {
          data = [
            {
              'id': 'member',
              'club_memberships': [
                {'id': 'membership', 'role': admin ? 'admin' : 'selector'},
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
              'default_duration_minutes': 150,
              'default_rinks_required': 1,
              'default_format': 'pairs',
              'lock_participation': locked,
              'lock_format': locked,
              'lock_rinks': locked,
              'lock_duration': locked,
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

  testWidgets(
    'Selecting a fixture type applies its 150 minute duration to the actual create form',
    (t) async {
      t.view.physicalSize = const Size(1100, 1800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final start = DateTime(2031, 1, 14, 10);
      await t.pumpWidget(
        MaterialApp(
          home: CreateFixturePage(
            clubId: 'club',
            clubName: 'Club',
            initialRinkBooking: InitialRinkBookingContext(
              greenAreaId: 'green',
              greenName: 'Main green',
              rinkLabel: 'R1',
              startAt: start,
              latestEndAt: DateTime(2031, 1, 14, 22),
              suggestedEndAt: DateTime(2031, 1, 14, 12),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Member Practice').last);
      await t.pumpAndSettle();
      expect(
        find.text(formatClubDateTime(DateTime(2031, 1, 14, 12, 30))),
        findsOneWidget,
      );
      expect(
        find.text(formatClubDateTime(DateTime(2031, 1, 14, 12))),
        findsNothing,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('Explicit end time survives fixture-type reselection', (t) async {
    t.view.physicalSize = const Size(1100, 1800);
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
            greenName: 'Main green',
            rinkLabel: 'R1',
            startAt: DateTime(2031, 1, 14, 10),
            latestEndAt: DateTime(2031, 1, 14, 22),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Member Practice').last);
    await t.pumpAndSettle();
    await t.tap(find.text(formatClubDateTime(DateTime(2031, 1, 14, 12, 30))));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.keyboard_outlined));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, '12');
    await t.enterText(find.byType(TextField).last, '15');
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(
      find.text(formatClubDateTime(DateTime(2031, 1, 14, 12, 15))),
      findsOneWidget,
    );
    await t.tap(find.text('Member Practice').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Member Practice').last);
    await t.pumpAndSettle();
    expect(
      find.text(formatClubDateTime(DateTime(2031, 1, 14, 12, 15))),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });
  testWidgets('Fixture-type duration respects the available rink slot', (
    t,
  ) async {
    t.view.physicalSize = const Size(1100, 1800);
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
            greenName: 'Main green',
            rinkLabel: 'R1',
            startAt: DateTime(2031, 1, 14, 10),
            latestEndAt: DateTime(2031, 1, 14, 11),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Member Practice').last);
    await t.pumpAndSettle();
    expect(
      find.text(formatClubDateTime(DateTime(2031, 1, 14, 11))),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });
  for (final privileged in [false, true]) {
    testWidgets(
      'locked create fields ${privileged ? 'allow Admin override' : 'are read-only for members'}',
      (t) async {
        admin = privileged;
        locked = true;
        addTearDown(() {
          admin = true;
          locked = false;
        });
        t.view.physicalSize = const Size(1100, 2400);
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
                greenName: 'Main green',
                rinkLabel: 'R1',
                startAt: DateTime(2031, 1, 14, 9),
                latestEndAt: DateTime(2031, 1, 14, 22),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.text('Member Practice').last);
        await t.pumpAndSettle();
        for (final label in ['Participation mode', 'Format']) {
          final field = t
              .widgetList<DropdownButtonFormField<String>>(
                find.byType(DropdownButtonFormField<String>),
              )
              .firstWhere((w) => w.decoration.labelText == label);
          expect(field.onChanged != null, privileged, reason: label);
        }
        final rinks = t
            .widgetList<DropdownButtonFormField<int>>(
              find.byType(DropdownButtonFormField<int>),
            )
            .firstWhere((w) => w.decoration.labelText == 'Rinks required');
        expect(rinks.onChanged != null, privileged);
        expect(t.takeException(), isNull);
      },
    );
  }
}
