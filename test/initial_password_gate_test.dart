import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bowls_saas/features/auth/initial_password_gate.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> show(
    WidgetTester t, {
    bool needed = true,
    Future<bool> Function()? load,
    Future<void> Function(String)? decide,
    Future<void> Function(String)? update,
  }) async {
    await t.pumpWidget(
      MaterialApp(
        home: InitialPasswordGate(
          email: 'test@example.invalid',
          loadChoice: load ?? () => Future.value(needed),
          decide: decide ?? (_) async {},
          updatePassword: update,
          child: const Scaffold(body: Text('My clubs')),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('existing account continues without a password prompt', (
    t,
  ) async {
    await show(t, needed: false);
    expect(find.text('My clubs'), findsOneWidget);
    expect(find.text('Change my password'), findsNothing);
  });
  testWidgets(
    'keep records the choice before continuing, without accepting invitation',
    (t) async {
      String? choice;
      await show(
        t,
        decide: (v) async {
          choice = v;
        },
      );
      expect(find.textContaining('separately in My clubs'), findsOneWidget);
      await t.tap(find.text('Keep this password and continue'));
      await t.pumpAndSettle();
      expect(choice, 'kept');
      expect(find.text('My clubs'), findsOneWidget);
    },
  );
  testWidgets('failed check offers retry and never assumes keep', (t) async {
    var tries = 0;
    await show(
      t,
      load: () async {
        if (tries++ == 0) throw Exception('offline');
        return false;
      },
    );
    expect(find.text('Keep this password and continue'), findsNothing);
    expect(find.text('My clubs'), findsNothing);
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(find.text('My clubs'), findsOneWidget);
  });
  testWidgets('failed keep remains at password choice', (t) async {
    await show(
      t,
      decide: (_) async {
        throw Exception('offline');
      },
    );
    await t.tap(find.text('Keep this password and continue'));
    await t.pumpAndSettle();
    expect(find.text('My clubs'), findsNothing);
    expect(find.textContaining('choice could not be saved'), findsOneWidget);
  });
  testWidgets(
    'change uses verified password form and completes only after save',
    (t) async {
      String? changed, choice;
      const channel = MethodChannel('bowls/saved_login');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => true);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await show(
        t,
        update: (v) async {
          changed = v;
        },
        decide: (v) async {
          choice = v;
        },
      );
      await t.tap(find.text('Change my password'));
      await t.pumpAndSettle();
      final password = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'New password',
      );
      final confirmation = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'Confirm new password',
      );
      await t.enterText(password, 'MyNewPass123');
      await t.enterText(confirmation, 'MyNewPass123');
      final save = find.text('Save new password');
      await t.ensureVisible(save);
      await t.tap(save);
      await t.pumpAndSettle();
      expect(changed, 'MyNewPass123');
      expect(choice, isNull);
      expect(find.text('Password changed'), findsOneWidget);
      await t.tap(find.text('Continue to the app'));
      await t.pumpAndSettle();
      expect(choice, 'changed');
      expect(find.text('My clubs'), findsOneWidget);
    },
  );
}
