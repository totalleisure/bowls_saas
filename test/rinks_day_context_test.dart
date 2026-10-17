import 'dart:convert';
import 'package:bowls_saas/features/diary/rinks_day_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  for (final selectCallingFixture in [false, true]) {
  testWidgets('fixture day context returns via ${selectCallingFixture ? 'calling rink' : 'Back'}', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Uri>[];
    await Supabase.initialize(url: 'https://test.invalid', anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request.url);
        dynamic data = [];
        if (request.url.path.endsWith('/venues')) {
          data = [{'id':'venue', 'name':'Home'}];
        } else if (request.url.path.endsWith('/green_areas')) {
          data = [{'id':'green-two','name':'Second green','rink_count':6}];
        } else if (request.url.path.endsWith('/fixtures')) {
          data = [{'id':'calling-fixture','start_at':'2026-10-31T10:00:00Z',
            'end_at':'2026-10-31T12:00:00Z','opponent_name':'Calling match',
            'rinks_required':1,'fixture_rinks':[{'home_rink_label':'R1'}]}];
        }
        return http.Response(jsonEncode(data),200,headers:{'content-type':'application/json'}, request:request);
      }),
    );
    addTearDown(() => Supabase.instance.dispose());
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => RinkDayViewScreen(clubId:'club',clubName:'Test club',
          date:DateTime(2026,10,31),greenAreaId:'green-two',fixtureId:'calling-fixture'),
      )),child:const Text('Fixture')),
    ))));
    await tester.tap(find.text('Fixture'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final green = requests.singleWhere((uri) => uri.path.endsWith('/green_areas'));
    expect(green.queryParameters['id'], 'eq.green-two');
    final fixtures = requests.singleWhere((uri) => uri.path.endsWith('/fixtures'));
    expect(fixtures.queryParameters['green_area_id'], 'eq.green-two');
    expect(fixtures.queryParametersAll['start_at'],
      containsAll(['gte.2026-10-31T00:00:00.000Z','lt.2026-11-01T00:00:00.000Z']));
    await tester.tap(selectCallingFixture ? find.text('Calling match').first : find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Fixture'), findsOneWidget);
    expect(find.byType(RinkDayViewScreen), findsNothing);
  });
  }
}
