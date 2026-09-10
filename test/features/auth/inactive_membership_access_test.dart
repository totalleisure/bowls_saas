import 'dart:io';

import 'package:bowls_saas/features/auth/app_entry_access_service.dart';
import 'package:bowls_saas/features/auth/auth_gate.dart';
import 'package:bowls_saas/features/auth/auth_failure_policy.dart';
import 'package:bowls_saas/features/clubs/club_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Widget boundary(AppEntryAccess access) {
  return MaterialApp(
    home: AuthenticatedMembershipBoundary(
      loadAccess: () async => access,
      onSignOut: () async {},
      child: const Text('My clubs'),
    ),
  );
}

void main() {
  const inactive = AppEntryAccess(
    isSuperuser: false,
    hasActiveMembership: false,
  );
  const active = AppEntryAccess(isSuperuser: false, hasActiveMembership: true);

  test('invalid credentials remain an authentication failure', () {
    final presentation = AuthFailurePolicy.invalidCredentials(
      const AuthException('Invalid login credentials'),
    );
    expect(presentation?.title, 'Sign in unsuccessful');
    expect(
      presentation?.message,
      'The email address or password was not recognised. '
      'Please check both entries and try again.',
    );
    expect(presentation?.actionLabel, 'Check details');
    expect(
      AuthFailurePolicy.invalidCredentials(
        Exception('Your membership is inactive'),
      ),
      isNull,
    );
  });

  testWidgets('inactive member fresh login is denied app access', (
    tester,
  ) async {
    await tester.pumpWidget(boundary(inactive));
    await tester.pump();

    expect(find.text('Membership inactive'), findsOneWidget);
    expect(
      find.text(
        'Your membership is inactive. Please contact your club administrator.',
      ),
      findsOneWidget,
    );
    expect(find.text('My clubs'), findsNothing);
  });

  testWidgets('inactive member restored session is denied app access', (
    tester,
  ) async {
    await tester.pumpWidget(boundary(inactive));
    await tester.pump();

    expect(find.text('My clubs'), findsNothing);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('active Member enters the app', (tester) async {
    await tester.pumpWidget(boundary(active));
    await tester.pump();
    expect(find.text('My clubs'), findsOneWidget);
  });

  testWidgets(
    'active Guest enters the app and remains governed by ClubAccess',
    (tester) async {
      await tester.pumpWidget(boundary(active));
      await tester.pump();
      expect(find.text('My clubs'), findsOneWidget);
      const guestAccess = ClubAccess(
        currentMemberId: 'guest-id',
        isSuperuser: false,
        isClubAdmin: false,
        isSelector: false,
        membershipRole: 'guest',
        hasActiveMembership: true,
      );
      expect(guestAccess.canWrite, isFalse);
    },
  );

  testWidgets('SuperUser enters without a club membership', (tester) async {
    await tester.pumpWidget(
      boundary(
        const AppEntryAccess(isSuperuser: true, hasActiveMembership: false),
      ),
    );
    await tester.pump();
    expect(find.text('My clubs'), findsOneWidget);
  });

  testWidgets('membership lookup failure does not grant access', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthenticatedMembershipBoundary(
          loadAccess: () async => throw Exception('network failure'),
          onSignOut: () async {},
          child: const Text('My clubs'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Unable to verify membership'), findsOneWidget);
    expect(find.text('My clubs'), findsNothing);
  });

  test('AuthGate applies the boundary to restored and fresh sessions', () {
    final source = File('lib/features/auth/auth_gate.dart').readAsStringSync();
    expect(source, contains('auth.onAuthStateChange'));
    expect(source, contains('auth.currentSession'));
    expect(source, contains('AuthenticatedMembershipBoundary('));
  });
}
