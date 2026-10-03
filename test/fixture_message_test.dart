import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowls_saas/features/fixtures/fixture_message_screen.dart';

void main() {
  final queued = <dynamic>[];
  var published = true;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.invalid',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        final path = r.url.path;
        dynamic data;
        if (path.endsWith('/fixtures')) {
          data = {
            'id': 'fixture',
            'start_at': '2026-09-30T13:00:00Z',
            'competition_types': {'name': 'Friendly'},
          };
        } else if (path.endsWith('/team_selections')) {
          data = {
            'id': 'selection',
            'status': published ? 'published' : 'draft',
          };
        } else if (path.endsWith('/team_selection_members')) {
          expect(r.url.queryParameters['is_selected'], 'eq.true');
          data = [
            {
              'member_profile_id': 'player',
              'role': 'player',
              'member_profile': {'display_name': 'Player'},
            },
          ];
        } else if (path.endsWith('/notification_queue')) {
          queued.add(jsonDecode(r.body));
          return http.Response('', 201, request: r);
        } else if (path.endsWith('/get_authorized_team_sheet_data')) {
          return http.Response(
            jsonEncode({'message': 'Team sheet unavailable'}),
            400,
            request: r,
            headers: {'content-type': 'application/json'},
          );
        } else {
          throw StateError('Unexpected request $path');
        }
        return http.Response(
          jsonEncode(data),
          200,
          request: r,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() {
    queued.clear();
    published = true;
  });

  Future<void> open(WidgetTester t) async {
    t.view.physicalSize = const Size(900, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      const MaterialApp(
        home: FixtureMessageScreen(
          fixtureId: 'fixture',
          currentMemberProfileId: 'actor',
          senderName: 'Admin',
        ),
      ),
    );
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pumpAndSettle();
  }

  Future<void> fill(WidgetTester t) async {
    await t.enterText(find.byType(TextField).at(0), 'Position update');
    await t.enterText(
      find.byType(TextField).at(1),
      'Please see the latest positions.',
    );
  }

  testWidgets('attachment defaults off and plain message queues without PDF', (
    t,
  ) async {
    await open(t);
    final tile = find.widgetWithText(
      CheckboxListTile,
      'Attach current team sheet',
    );
    expect(t.widget<CheckboxListTile>(tile).value, isFalse);
    await fill(t);
    await t.ensureVisible(find.text('Send Message'));
    await t.tap(find.text('Send Message'));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pumpAndSettle();
    expect(queued.length, 1);
    expect(queued.single.single['payload'].containsKey('attachments'), isFalse);
  });
  testWidgets('requested PDF failure keeps message open and queues nothing', (
    t,
  ) async {
    await open(t);
    await fill(t);
    await t.ensureVisible(find.text('Attach current team sheet'));
    await t.tap(find.text('Attach current team sheet'));
    await t.pump();
    await t.ensureVisible(find.text('Send Message'));
    await t.tap(find.text('Send Message'));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pumpAndSettle();
    expect(queued, isEmpty);
    expect(find.byType(FixtureMessageScreen), findsOneWidget);
    expect(
      find.textContaining('Team sheet unavailable', skipOffstage: false),
      findsOneWidget,
    );
  });
  testWidgets('unpublished fixture cannot request team sheet', (t) async {
    published = false;
    await open(t);
    final tile = t.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Attach current team sheet'),
    );
    expect(tile.onChanged, isNull);
    expect(tile.value, isFalse);
  });
}
