import 'dart:async';
import 'dart:convert';
import 'package:bowls_saas/features/team/team_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('team refresh keeps card height and scroll offset without parent reload', (tester) async {
    SharedPreferences.setMockInitialValues({});
    Completer<http.Response>? pending;
    await Supabase.initialize(url: 'https://test.invalid', anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('my_member_profile_id')) {
          if (pending != null) return pending!.future.then((response) => http.Response(response.body, response.statusCode, headers: {'content-type':'application/json'}, request: request));
          return http.Response(jsonEncode('profile'), 200, headers: {'content-type':'application/json'}, request: request);
        }
        if (request.url.path.endsWith('club_memberships')) {
          return http.Response(jsonEncode({'role':'member','is_active':true}),200, headers: {'content-type':'application/json'}, request: request);
        }
        return http.Response('[]',200, headers: {'content-type':'application/json'}, request: request);
      }),
    );
    addTearDown(() => Supabase.instance.dispose());
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var parentRefreshes = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView(
      controller: controller,
      children: [
        const SizedBox(height: 1500),
        TeamSection(fixture: const {'id':'fixture','club_id':'club'}, readOnly:true,
          onTeamChanged: () async {parentRefreshes++;}),
      ],
    ))));
    await tester.pumpAndSettle();
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final before = controller.offset;
    pending = Completer<http.Response>();
    await tester.tap(find.byTooltip('Refresh team'));
    await tester.pump();
    expect(find.text('Team'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(controller.offset,before);
    expect(tester.widget<IconButton>(find.byWidgetPredicate((widget) => widget is IconButton && widget.tooltip == 'Refresh team')).onPressed,isNull);
    pending!.complete(http.Response(jsonEncode('profile'),200, headers: {'content-type':'application/json'}));
    await tester.pumpAndSettle();
    expect(controller.offset,before);
    expect(parentRefreshes,0);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
