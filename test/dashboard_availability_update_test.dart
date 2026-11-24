import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowls_saas/features/clubs/club_dashboard_screen.dart';
import 'package:bowls_saas/features/fixtures/widgets/fixture_response_panel.dart';

void main() {
  final requests = <http.Request>[];
  var fail = false;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.invalid',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        requests.add(r);
        final path = r.url.path;
        dynamic data = [];
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
        } else if (path.endsWith('/app_superusers') ||
            path.endsWith('/user_club_dashboard_filters')) {
          data = null;
        } else if (path.endsWith('/club_memberships')) {
          data = {'id': 'membership', 'role': 'member'};
        } else if (path.endsWith('/member_profiles')) {
          data = {'sex_at_birth': 'male'};
        } else if (path.endsWith('/clubs')) {
          data = {'name': 'Club'};
        } else if (path.endsWith('/fixtures')) {
          data = List.generate(
            12,
            (i) => {
              'id': 'fixture-$i',
              'club_id': 'club',
              'start_at': DateTime.now()
                  .toUtc()
                  .add(Duration(days: i + 1))
                  .toIso8601String(),
              'is_home': false,
              'section': 'open',
              'rinks_required': 4,
              'players_per_rink': 3,
              'requires_rsvp': true,
              'competition_type_id': 'friendly',
              'competition_type': {
                'id': 'friendly',
                'name': 'Friendly',
                'is_internal': false,
                'selection_mode': 'rsvp',
                'uses_rinks': true,
              },
              'venue': {'name': 'Bromley Town'},
              'opponent_venue': {'name': 'Club'},
            },
          );
        } else if (path.endsWith('/set_my_fixture_availability')) {
          if (fail)
            return http.Response(
              '{"message":"offline"}',
              500,
              request: r,
              headers: {'content-type': 'application/json'},
            );
          final payload = jsonDecode(r.body) as Map;
          data = {
            'saved': true,
            'changes': [
              {
                'fixture_id': payload['p_fixture'],
                'status': payload['p_status'],
              },
            ],
          };
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
      password: 'test',
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  testWidgets(
    'Dashboard availability changes preserve list and scroll; failures keep saved response',
    (t) async {
      t.view.physicalSize = const Size(1000, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        const MaterialApp(
          home: ClubDashboardScreen(clubId: 'club', clubName: 'Club'),
        ),
      );
      await t.pumpAndSettle();
      if (find.text('OK').evaluate().isNotEmpty) {
        await t.tap(find.text('OK'));
        await t.pumpAndSettle();
      }
      final card = find.byKey(const ValueKey('dashboard-rsvp-fixture-5'));
      await t.scrollUntilVisible(
        card,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await t.ensureVisible(card);
      await t.pumpAndSettle();
      final scroll = t.state<ScrollableState>(find.byType(Scrollable).first);
      final position = scroll.position;
      final offset = position.pixels;
      requests.clear();
      Future<void> respond(String label, String expected) async {
        await t.tap(find.descendant(of: card, matching: find.text(label)));
        await t.pumpAndSettle();
        expect(
          t.state<ScrollableState>(find.byType(Scrollable).first).position,
          same(position),
        );
        expect(position.pixels, closeTo(offset, .1));
        expect(
          t
              .widget<FixtureResponsePanel>(
                find.descendant(
                  of: card,
                  matching: find.byType(FixtureResponsePanel),
                ),
              )
              .status,
          expected,
        );
      }

      await respond('Available', 'yes');
      await respond('Not available', 'no');
      fail = true;
      await respond('Available', 'no');
      expect(
        find.textContaining('Failed to save availability'),
        findsOneWidget,
      );
      expect(requests.where((r) => r.url.path.endsWith('/fixtures')), isEmpty);
      expect(
        requests.where(
          (r) => r.url.path.endsWith('/set_my_fixture_availability'),
        ),
        hasLength(3),
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}
