import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bowls_saas/features/fixtures/fixtures_screen.dart';
import 'package:bowls_saas/features/fixtures/fixture_display.dart';

class DetailsRoute extends StatefulWidget {
  const DetailsRoute({super.key});
  @override
  State<DetailsRoute> createState() => DetailsRouteState();
}

class DetailsRouteState extends State<DetailsRoute> {
  bool changed = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Fixture Details'),
      leading: BackButton(onPressed: () => Navigator.pop(context, changed)),
    ),
    body: TextButton(
      child: const Text('Manage Team'),
      onPressed: () async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Team Manager')),
              body: ListView(
                children: List.generate(40, (i) => Text('Player $i')),
              ),
            ),
          ),
        );
        if (mounted) setState(() => changed = true);
      },
    ),
  );
}

void main() {
  final requests = <Uri>[];
  String? opened;
  String outcome = 'changed';
  final first = DateTime.now().toUtc().add(const Duration(days: 30));
  Map<String, dynamic> row(int i) => {
    'id': 'f$i',
    'club_id': 'club',
    'start_at': first.add(Duration(days: i)).toIso8601String(),
    'is_home': true,
    'section': 'mixed',
    'rinks_required': 2,
    'players_per_rink': 4,
    'team_name': 'Friendly $i',
    'competition_type': {
      'id': 'friendly',
      'name': 'Friendly',
      'uses_rinks': true,
    },
    'captain_member_profile_id': 'member',
  };
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final token =
        '${base64Url.encode(utf8.encode('{"alg":"HS256"}'))}.${base64Url.encode(utf8.encode('{"sub":"user","exp":2000000000}'))}.signature';
    await Supabase.initialize(
      url: 'https://example.invalid',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((req) async {
        dynamic data;
        requests.add(req.url);
        final path = req.url.path;
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
        else if (path.endsWith('/app_superusers'))
          data = null;
        else if (path.endsWith('/club_memberships'))
          data = {'id': 'membership', 'role': 'member'};
        else if (path.endsWith('/clubs'))
          data = {
            'name': 'Test Club',
            'primary_color_hex': '#194d85',
            'secondary_color_hex': '#ffff00',
          };
        else if (path.endsWith('/team_selection_members') || path.endsWith('/club_competitions'))
          data = [];
        else if (path.endsWith('/fixtures')) {
          final id = req.url.queryParameters['id'];
          if (id == null) {
            data = List.generate(30, row);
          } else if (outcome == 'failed')
            return http.Response(
              '{"message":"offline"}',
              500,
              request: req,
              headers: {'content-type': 'application/json'},
            );
          else if (outcome == 'deleted')
            data = null;
          else
            data = {
              ...row(int.parse(id.substring(4))),
              'team_name': 'Updated friendly',
            };
        } else
          data = {};
        return http.Response(
          jsonEncode(data),
          200,
          request: req,
          headers: {'content-type': 'application/json', if (path.endsWith('/team_selection_members')) 'content-range': '*/0'},
        );
      }),
    );
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'test@example.invalid',
      password: 'fake',
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  for (final mode in ['changed', 'deleted', 'failed']) {
    testWidgets(
      'Fixtures list survives direct visit then Team Manager round trip: $mode',
      (t) async {
        requests.clear();
        outcome = mode;
        t.view.physicalSize = const Size(1000, 1100);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(
          MaterialApp(
            home: FixturesScreen(
              clubId: 'club',
              clubName: 'Test Club',
              memberBookingsOnly: true,
              fixturePageBuilder: (id) {
                opened = id;
                return const DetailsRoute();
              },
            ),
          ),
        );
        await t.pumpAndSettle();
        final list = find.byType(ListView).first;
        final scroll = t.widget<ListView>(list).controller!;
        scroll.jumpTo(1200);
        await t.pumpAndSettle();
        final offset = scroll.offset;
        await t.tap(find.byType(UnifiedFixtureCard).hitTestable().first);
        await t.pumpAndSettle();
        await t.tap(find.byType(BackButton));
        await t.pumpAndSettle();
        expect(scroll.offset, closeTo(offset, 0.1));
        expect(requests.where((r) => r.path.endsWith('/fixtures')).length, 1);
        // A second fixture, not the first, goes through Team Manager and reports changes.
        await t.tap(find.byType(UnifiedFixtureCard).hitTestable().at(1));
        await t.pumpAndSettle();
        await t.tap(find.text('Manage Team'));
        await t.pumpAndSettle();
        expect(find.text('Team Manager'), findsOneWidget);
        await t.pageBack();
        await t.pumpAndSettle();
        expect(find.text('Fixture Details'), findsOneWidget);
        await t.tap(find.byType(BackButton));
        await t.pumpAndSettle();
        final queries = requests
            .where((r) => r.path.endsWith('/fixtures'))
            .toList();
        expect(queries, hasLength(2));
        expect(queries.last.queryParameters['id'], 'eq.$opened');
        expect(queries.last.queryParameters['club_id'], 'eq.club');
        expect(
          requests.singleWhere((r) => r.path.endsWith('/team_selection_members')).queryParameters['member_profile_id'],
          'eq.member',
        );
        expect(requests.where((r) => r.path.endsWith('/clubs')), hasLength(1));
        expect(scroll.offset, closeTo(offset, 0.1));
        expect(find.byType(CircularProgressIndicator), findsNothing);
        if (mode == 'changed') {
          expect(
            t
                .widget<UnifiedFixtureCard>(
                  find.byKey(ValueKey('fixture:$opened')),
                )
                .fixture['team_name'],
            'Updated friendly',
          );
        }
        if (mode == 'deleted') {
          expect(find.byKey(ValueKey('fixture:$opened')), findsNothing);
        }
        if (mode == 'failed') {
          expect(
            find.textContaining('Your list position has been kept'),
            findsOneWidget,
          );
        }
        expect(t.takeException(), isNull);
      },
    );
  }
}
