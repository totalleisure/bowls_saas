import 'dart:async';
import 'package:bowls_saas/features/auth/recovery_password_form.dart';
import 'package:bowls_saas/features/auth/login_autofill_group.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> show(
    WidgetTester tester,
    Future<void> Function(String) update, {
    VoidCallback? complete,
  }) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: RecoveryPasswordForm(
              email: 'member@example.test',
              onComplete: complete ?? () {},
              updatePassword: update,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<dynamic> finishes(WidgetTester tester) => tester.testTextInput.log
      .where((call) => call.method == 'TextInput.finishAutofillContext')
      .map((call) => call.arguments)
      .toList();

  Future<void> fill(
    WidgetTester tester,
    String password,
    String confirm,
  ) async {
    await tester.enterText(find.byType(TextFormField).at(1), password);
    await tester.enterText(find.byType(TextFormField).at(2), confirm);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Save new password'));
    await tester.tap(find.text('Save new password'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'new password context contains account and new-password hints; AutoFill never submits',
    (tester) async {
      var calls = 0;
      await show(tester, (_) async {
        calls++;
      });
      await tester.tap(find.byType(TextFormField).at(1));
      await tester.pump();
      final fields = tester.testTextInput.setClientArgs!['fields'] as List;
      expect(fields, hasLength(3));
      final configs = fields.map((f) => (f as Map)['autofill'] as Map).toList();
      expect(configs.map((f) => f['hints']).toList(), [
        [AutofillHints.username],
        [AutofillHints.newPassword],
        [AutofillHints.newPassword],
      ]);
      expect(
        (configs.first['editingValue'] as Map)['text'],
        'member@example.test',
      );
      final scope = tester.state<AutofillGroupState>(
        find.byType(LoginAutofillGroup),
      );
      for (final config in configs.skip(1)) {
        scope
            .getAutofillClient(config['uniqueIdentifier'] as String)!
            .autofill(const TextEditingValue(text: 'generated-password'));
      }
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(finishes(tester), isNot(contains(true)));
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('validation prevents submission and displays actionable errors', (
    tester,
  ) async {
    var calls = 0;
    await show(tester, (_) async {
      calls++;
    });
    await fill(tester, 'short', 'different');
    await save(tester);
    expect(calls, 0);
    expect(find.text('Enter at least 8 characters.'), findsOneWidget);
    expect(
      find.text('Enter the same new password in both boxes.'),
      findsOneWidget,
    );
    expect(finishes(tester), isNot(contains(true)));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'successful update commits once, retains fields while awaiting response, then shows guidance',
    (tester) async {
      final response = Completer<void>();
      var calls = 0;
      var continued = false;
      await show(
        tester,
        (value) {
          calls++;
          expect(value, 'new-password');
          return response.future;
        },
        complete: () {
          continued = true;
        },
      );
      await fill(tester, 'new-password', 'new-password');
      tester.testTextInput.log.clear();
      await save(tester);
      expect(calls, 1);
      expect(finishes(tester), isEmpty);
      expect(find.text('Changing password…'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(1))
            .controller!
            .text,
        'new-password',
      );
      response.complete();
      await tester.pumpAndSettle();
      expect(finishes(tester), [true]);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('Password changed'), findsOneWidget);
      expect(find.textContaining('If Apple Passwords asks'), findsOneWidget);
      expect(continued, false);
      await tester.ensureVisible(find.text('Continue to the app'));
      await tester.tap(find.text('Continue to the app'));
      expect(continued, true);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(finishes(tester), [true]);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'rejected password stays editable and cancels rather than saves on exit',
    (tester) async {
      await show(tester, (_) async {
        throw const AuthException('same', code: 'same_password');
      });
      await fill(tester, 'old-password', 'old-password');
      tester.testTextInput.log.clear();
      await save(tester);
      expect(
        find.text('Choose a password different from your old password.'),
        findsOneWidget,
      );
      expect(find.byType(TextFormField), findsNWidgets(3));
      expect(finishes(tester), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(finishes(tester), [false]);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
