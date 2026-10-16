import 'package:bowls_saas/features/members/member_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget profile({bool own = true, bool admin = false}) => MaterialApp(
  home: MemberEditScreen(
    memberProfileId: 'profile-test',
    clubId: 'club-test',
    initial: const {
      'first_name': 'Alex',
      'last_name': 'Bowler',
      'email_address': 'alex@example.com',
      'phone': '07123456789',
      'gender': 'prefer_to_self_describe',
      'gender_self_described': 'Custom',
      'address_line1': '1 Green Lane',
      'preferred_position': 'lead',
    },
    initialRole: 'member',
    initialActive: true,
    canManageMembers: admin,
    initialIsCoach: true,
    initialCoachingAward: 'Level 1',
    isOwnRecord: own,
  ),
);

void main() {
  for (final width in [320.0, 768.0, 1200.0]) {
    testWidgets('profile retains fields without overflow at width $width', (
      t,
    ) async {
      t.view.physicalSize = Size(width, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(profile());
      await t.pumpAndSettle();
      expect(find.text('My Profile'), findsOneWidget);
      expect(find.text('AB'), findsOneWidget);
      expect(find.text('Login & Security'), findsOneWidget);
      expect(find.text('Manage login & security'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Custom'), findsOneWidget);
      expect(find.widgetWithText(TextField, '1 Green Lane'), findsOneWidget);
      expect(find.text('Role'), findsNothing);
      expect(find.text('Quick Unlock'), findsNothing);
      expect(find.text('Username'), findsNothing);
      final email = t.widget<TextField>(
        find.widgetWithText(TextField, 'alex@example.com'),
      );
      expect(email.readOnly, isTrue);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('large text stacks cards and keeps controls usable', (t) async {
    t.view.physicalSize = const Size(1200, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: (profile() as MaterialApp).home,
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('editing shows save and back retains discard confirmation', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => (profile() as MaterialApp).home!,
                ),
              ),
              child: const Text('Open profile'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open profile'));
    await t.pumpAndSettle();
    expect(find.text('Save'), findsNothing);
    await t.enterText(find.widgetWithText(TextField, 'Alex'), 'Jamie');
    await t.pump();
    expect(find.text('Save'), findsOneWidget);
    await t.tap(find.byTooltip('Back'));
    await t.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Jamie'), findsOneWidget);
  });

  testWidgets('admin controls remain gated; other records keep editor', (
    t,
  ) async {
    await t.pumpWidget(profile(admin: true));
    expect(find.text('Role'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Level 1'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(profile(own: false));
    await t.pumpAndSettle();
    expect(find.text('Edit member'), findsOneWidget);
    expect(find.text('My Profile'), findsNothing);
    final phone = t.widget<TextField>(
      find.widgetWithText(TextField, '07123456789'),
    );
    expect(phone.enabled, isFalse);
  });
}
