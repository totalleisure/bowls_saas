import 'dart:convert';
import 'package:bowls_saas/features/auth/password_recovery_progress.dart';
import 'package:bowls_saas/features/auth/forgot_password_screen.dart';
import 'package:flutter/material.dart';
import 'package:bowls_saas/features/members/admin_password_reset_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('hourly email limit is distinct from the request cooldown', () {
    expect(recoveryRateLimitMessage('over_email_send_rate_limit'), contains('hourly'));
    expect(recoveryRateLimitMessage('over_email_send_rate_limit'), isNot(contains('wait a minute')));
    expect(recoveryRateLimitMessage('over_request_rate_limit'), contains('at least a minute'));
    expect(recoveryRateLimitMessage('unknown'), isNot(contains('minute')));
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PasswordRecoveryProgress.verifyingEmail = null;
  });
  testWidgets('code entry survives Mail switching and screen recreation', (
    tester,
  ) async {
    await PasswordRecoveryProgress.save('member@example.invalid');
    await tester.pumpWidget(const MaterialApp(home: ForgotPasswordScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Enter your recovery code'), findsOneWidget);
    expect(find.text('Reset password · Step 2 of 3'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '123456');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('123456'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const MaterialApp(home: ForgotPasswordScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Enter your recovery code'), findsOneWidget);
    expect(find.textContaining('member@example.invalid'), findsOneWidget);
    expect(find.text('123456'), findsNothing);
  });
  test(
    'recovery survives recreation without persisting codes or passwords',
    () async {
      await PasswordRecoveryProgress.save('member@example.invalid');
      final saved = await PasswordRecoveryProgress.read();
      expect(saved!['email'], 'member@example.invalid');
      expect(saved['verified'], false);
      expect(saved.keys.toSet(), {'email', 'verified', 'requested_at'});
      await PasswordRecoveryProgress.save(
        'member@example.invalid',
        verified: true,
      );
      expect((await PasswordRecoveryProgress.read())!['verified'], true);
      await PasswordRecoveryProgress.clear();
      expect(await PasswordRecoveryProgress.read(), isNull);
    },
  );
  test('stale recovery is discarded', () async {
    SharedPreferences.setMockInitialValues({
      PasswordRecoveryProgress.key: jsonEncode({
        'email': 'member@example.invalid',
        'verified': false,
        'requested_at': DateTime.now()
            .subtract(const Duration(hours: 2))
            .millisecondsSinceEpoch,
      }),
    });
    expect(await PasswordRecoveryProgress.read(), isNull);
  });
  test('generated passwords meet requirements and vary', () {
    final values = List.generate(30, (_) => generateMemberPassword());
    expect(values.toSet().length, 30);
    for (final value in values) {
      expect(RegExp(r'^[A-Z][a-z]{2}[0-9]{5}$').hasMatch(value), true);
    }
  });

  testWidgets('admin resets once then sees sharing controls on a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminPasswordResetDialog(
            clubId: 'club',
            memberProfileId: 'member',
            memberName: 'Example Member',
            resetPassword: (password) async {
              calls++;
              expect(password.length, greaterThanOrEqualTo(8));
              return 'member@example.invalid';
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Reset password'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Copy login details'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Reset password'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
