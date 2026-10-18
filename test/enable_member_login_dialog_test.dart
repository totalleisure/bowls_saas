import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/members/enable_member_login_dialog.dart';
void main() {
 for (final sent in [true,false]) {
 testWidgets('enable member validation and result sent=$sent', (tester) async {
  var calls=0; String? email;
  await tester.pumpWidget(MaterialApp(home: Scaffold(body:EnableMemberLoginDialog(clubId:'club',memberProfileId:'member',enableLogin:(value) async {calls++;email=value;return {'enabled':true,'setup_sent':sent};}))));
  expect(calls,0);
  await tester.tap(find.text('Enable login'));await tester.pump();
  expect(calls,0);expect(find.text('Enter the member’s unique email address.'),findsOneWidget);
  await tester.enterText(find.byType(TextField),' Member@Example.invalid ');
  await tester.tap(find.text('Enable login'));await tester.pumpAndSettle();
  expect(calls,1);expect(email,'member@example.invalid');
  expect(find.text('App login enabled'),findsOneWidget);
  expect(find.textContaining('Their existing membership has been kept.'),findsOneWidget);
  expect(find.textContaining('Request a code there'),findsOneWidget);
  expect(find.textContaining('code has been sent'),findsNothing);
  expect(find.text('Done'),findsOneWidget);
 });
 }
}
