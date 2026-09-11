import 'dart:convert';

import 'package:bowls_saas/features/members/member_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Supabase's HTTP transport is replaced for these offline tests.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final saved = <Map<String, dynamic>>[];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.test',
      anonKey: 'test-key',
      httpClient: MockClient((request) async {
        if (request.method == 'PATCH') {
          saved.add(jsonDecode(request.body) as Map<String, dynamic>);
        }
        return http.Response(
          jsonEncode([
            {'id': 'p', 'first_name': 'A', 'last_name': 'Person'},
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());

  Finder field(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );

  Future<void> open(
    WidgetTester tester,
    Map<String, dynamic> initial, {
    bool canManageMembers = false,
  }) async {
    saved.clear();
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MemberEditScreen(
          memberProfileId: 'p',
          initial: {'first_name': 'A', 'last_name': 'Person', ...initial},
          clubId: 'c',
          initialRole: 'member',
          initialActive: true,
          canManageMembers: canManageMembers,
          initialIsCoach: false,
          isOwnRecord: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('loads title and club and saves explicit changes', (
    tester,
  ) async {
    await open(tester, {
      'title': 'Dr',
      'outdoor_club': 'Original',
      'gender': 'female',
    });
    expect(
      tester.widget<TextField>(field('Title (optional)')).controller!.text,
      'Dr',
    );
    expect(
      tester
          .widget<TextField>(field('Outdoor club (optional)'))
          .controller!
          .text,
      'Original',
    );
    await tester.enterText(field('Title (optional)'), '  Ms  ');
    await tester.enterText(field('Outdoor club (optional)'), '  New Club  ');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved.single['title'], 'Ms');
    expect(saved.single['outdoor_club'], 'New Club');
    expect(saved.single['gender'], 'female');
  });

  testWidgets(
    'clearing all three fields saves null without validation failure',
    (tester) async {
      await open(tester, {
        'title': 'Dr',
        'outdoor_club': 'Club',
        'gender': 'male',
      });
      await tester.enterText(field('Title (optional)'), ' ');
      await tester.enterText(field('Outdoor club (optional)'), '');
      await tester.tap(find.text('Male').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not supplied').last);
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved.single['title'], isNull);
      expect(saved.single['outdoor_club'], isNull);
      expect(saved.single['gender'], isNull);
    },
  );

  testWidgets('absent optional values load and remain null on unrelated edit', (
    tester,
  ) async {
    await open(tester, {});
    expect(
      tester.widget<TextField>(field('Title (optional)')).controller!.text,
      '',
    );
    expect(
      tester
          .widget<TextField>(field('Outdoor club (optional)'))
          .controller!
          .text,
      '',
    );
    await tester.enterText(field('First name'), 'Another');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved.single['title'], isNull);
    expect(saved.single['outdoor_club'], isNull);
    expect(saved.single['gender'], isNull);
  });

  testWidgets(
    'administrator tiles render and toggle without hidden ink warnings',
    (tester) async {
      await open(tester, {}, canManageMembers: true);
      expect(tester.takeException(), isNull);
      final active = find.widgetWithText(CheckboxListTile, 'Active member');
      await tester.tap(active);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(active).value, isFalse);
      final coach = find.widgetWithText(CheckboxListTile, 'Coach');
      await tester.scrollUntilVisible(
        coach,
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(coach);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(coach).value, isTrue);
      expect(find.text('Coaching award'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
