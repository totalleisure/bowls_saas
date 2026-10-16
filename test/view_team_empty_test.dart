import 'package:bowls_saas/features/team/manage_team_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('viewing an empty team never writes and refresh stays read only', (t) async {
    SharedPreferences.setMockInitialValues({});
    final writes = <String>[];
    await Supabase.initialize(
      url: 'https://test.invalid', anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.method != 'GET') writes.add(request.method);
        return http.Response('[]', 200,
          headers: {'content-type': 'application/json'}, request: request);
      }),
    );
    addTearDown(() => Supabase.instance.dispose());
    await t.pumpWidget(MaterialApp(home: ManageTeamScreen(
      fixture: {'id': 'fixture', 'club_id': 'club', 'requires_rsvp': true},
      readOnly: true,
    )));
    await t.pumpAndSettle();
    expect(find.text('No team has been selected yet.'), findsOneWidget);
    expect(find.text('Publish Team'), findsNothing);
    expect(find.byTooltip('Open Team Sheet'), findsNothing);
    await t.tap(find.byIcon(Icons.refresh));
    await t.pumpAndSettle();
    expect(find.text('No team has been selected yet.'), findsOneWidget);
    expect(writes, isEmpty);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
