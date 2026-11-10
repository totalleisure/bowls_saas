import 'dart:async';
import 'dart:convert';
import 'package:bowls_saas/features/members/admin_email_change_dialog.dart';
import 'package:bowls_saas/features/members/member_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EmailDialogObserver extends NavigatorObserver {
  final popped = Completer<void>();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute && !popped.isCompleted) popped.complete();
    super.didPop(route, previousRoute);
  }
}

void main() {
  final requests = <Map<String, dynamic>>[];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.invalid',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        if (r.url.path.endsWith('/admin-change-member-email')) {
          requests.add(jsonDecode(r.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({'changed': true, 'email': 'new@example.invalid'}),
            200,
            headers: {'content-type': 'application/json'},
            request: r,
          );
        }
        return http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
          request: r,
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  Future<void> openDialog(
    WidgetTester t,
    Future<String> Function(String) change,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (_) => AdminEmailChangeDialog(
                  clubId: 'club',
                  memberProfileId: 'member',
                  memberName: 'Alex Bowler',
                  currentEmail: 'old@example.invalid',
                  changeEmail: change,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
  }

  Future<void> enter(WidgetTester t, String a, String b) async {
    await t.enterText(find.widgetWithText(TextField, 'New login email'), a);
    await t.enterText(find.widgetWithText(TextField, 'Confirm new email'), b);
    await t.tap(find.widgetWithText(FilledButton, 'Change email'));
    await t.pumpAndSettle();
  }

  testWidgets(
    'Validates address, repeated address and confirmation before calling server',
    (t) async {
      var calls = 0;
      await openDialog(t, (email) async {
        calls++;
        return email;
      });
      await enter(t, 'bad', 'bad');
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      await enter(t, 'new@example.invalid', 'other@example.invalid');
      expect(find.textContaining('do not match'), findsOneWidget);
      await enter(t, 'old@example.invalid', 'old@example.invalid');
      expect(find.text('Enter a different email address.'), findsOneWidget);
      expect(calls, 0);
    },
  );
  testWidgets('Shows global account scope and normalizes a successful change', (
    t,
  ) async {
    String? requested;
    await openDialog(t, (email) async {
      requested = email;
      return email;
    });
    expect(find.textContaining('every club'), findsOneWidget);
    await enter(t, ' NEW@EXAMPLE.INVALID ', 'new@example.invalid');
    expect(requested, 'new@example.invalid');
    expect(find.byType(AdminEmailChangeDialog), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'Duplicate/server denial remains visible without closing the dialog',
    (t) async {
      await openDialog(
        t,
        (_) async => throw FunctionException(
          status: 409,
          details: {'error': 'That email address is already used.'},
        ),
      );
      await enter(t, 'new@example.invalid', 'new@example.invalid');
      expect(find.text('That email address is already used.'), findsOneWidget);
      expect(find.byType(AdminEmailChangeDialog), findsOneWidget);
    },
  );
  testWidgets(
    'Disables repeated submit and cancellation while request is pending',
    (t) async {
      final done = Completer<String>();
      var calls = 0;
      await openDialog(t, (_) {
        calls++;
        return done.future;
      });
      await t.enterText(
        find.widgetWithText(TextField, 'New login email'),
        'new@example.invalid',
      );
      await t.enterText(
        find.widgetWithText(TextField, 'Confirm new email'),
        'new@example.invalid',
      );
      await t.tap(find.widgetWithText(FilledButton, 'Change email'));
      await t.pump();
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Changing…'),
            )
            .onPressed,
        isNull,
      );
      expect(
        t
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .onPressed,
        isNull,
      );
      done.complete('new@example.invalid');
      await t.pumpAndSettle();
      expect(calls, 1);
    },
  );
  Widget member(bool admin, {NavigatorObserver? observer}) => MaterialApp(
    navigatorObservers: observer == null ? const [] : [observer],
    home: MemberEditScreen(
      memberProfileId: 'member',
      clubId: 'club',
      initial: const {
        'first_name': 'Alex',
        'last_name': 'Bowler',
        'email_address': 'old@example.invalid',
      },
      initialRole: 'member',
      initialActive: true,
      canManageMembers: admin,
      initialIsCoach: false,
      isOwnRecord: false,
    ),
  );
  testWidgets(
    'Admin changes member email through the real profile dialog and updates displayed address',
    (t) async {
      requests.clear();
      final observer = EmailDialogObserver();
      await t.pumpWidget(member(true, observer: observer));
      await t.pumpAndSettle();
      final action = find.text('Change member login email');
      await t.ensureVisible(action);
      await t.tap(action);
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextField, 'New login email'),
        'new@example.invalid',
      );
      await t.enterText(
        find.widgetWithText(TextField, 'Confirm new email'),
        'new@example.invalid',
      );
      await t.tap(find.widgetWithText(FilledButton, 'Change email'));
      // FunctionsClient uses a JSON isolate; drain both real isolate events and
      // Flutter's fake clock rather than advancing only one of them.
      for (var i = 0; i < 50 && !observer.popped.isCompleted; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await t.pump(const Duration(milliseconds: 20));
      }
      expect(observer.popped.isCompleted, isTrue);
      await t.pumpAndSettle();
      expect(requests.single, {
        'club_id': 'club',
        'member_profile_id': 'member',
        'expected_email': 'old@example.invalid',
        'email': 'new@example.invalid',
      });
      await t.scrollUntilVisible(
        find.text('Login email (read only)'),
        -120,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      final fields = t.widgetList<TextField>(find.byType(TextField));
      expect(
        fields.any((f) => f.controller?.text == 'new@example.invalid'),
        isTrue,
      );
      expect(find.byType(AdminEmailChangeDialog), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('Ordinary member cannot see admin email-change action', (
    t,
  ) async {
    await t.pumpWidget(member(false));
    await t.pumpAndSettle();
    expect(find.text('Change member login email'), findsNothing);
    expect(find.text('Assist with email change'), findsOneWidget);
  });
}
