import 'dart:async';
import 'package:bowls_saas/features/members/admin_confirmation_email_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  Future<void> show(
    WidgetTester t,
    Future<Map<String, dynamic>> Function(String, String?) request,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminConfirmationEmailAction(
            clubId: 'club',
            memberProfileId: 'member',
            request: request,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('Confirmed and unlinked accounts offer no resend', (t) async {
    await show(
      t,
      (action, email) async => {'eligible': false, 'reason': 'confirmed'},
    );
    expect(find.text('Resend confirmation email'), findsNothing);
  });
  testWidgets(
    'Admin confirms the server address; sends once and shows success',
    (t) async {
      final actions = <String>[];
      final sent = Completer<Map<String, dynamic>>();
      await show(t, (action, email) async {
        actions.add(action);
        if (action == 'status') {
          return {'eligible': true, 'email': 'member@example.invalid'};
        }
        expect(email, 'member@example.invalid');
        return sent.future;
      });
      expect(actions, ['status']);
      await t.tap(find.text('Resend confirmation email'));
      await t.pumpAndSettle();
      expect(find.textContaining('member@example.invalid'), findsOneWidget);
      await t.tap(find.text('Send confirmation'));
      await t.pump();
      final button = t.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(button.onPressed, isNull);
      expect(actions, ['status', 'resend']);
      sent.complete({'sent': true, 'email': 'member@example.invalid'});
      await t.pumpAndSettle();
      expect(
        find.text('Confirmation email sent to member@example.invalid'),
        findsOneWidget,
      );
    },
  );
  testWidgets('Provider error remains visible with retry', (t) async {
    await show(t, (action, email) async {
      if (action == 'status') {
        return {'eligible': true, 'email': 'member@example.invalid'};
      }
      throw const FunctionException(
        status: 429,
        details: {'error': 'Please wait a minute.'},
      );
    });
    await t.tap(find.text('Resend confirmation email'));
    await t.pumpAndSettle();
    await t.tap(find.text('Send confirmation'));
    await t.pumpAndSettle();
    expect(find.text('Please wait a minute.'), findsOneWidget);
    expect(find.text('Resend confirmation email'), findsOneWidget);
  });
}
