import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/members/captain_managed_member_dialog.dart';

void main() {
  Future<void> open(WidgetTester tester, Future<void> Function(Map<String,dynamic>) save) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => showDialog<bool>(context: context,
        builder: (_) => CaptainManagedMemberDialog(clubId: 'club', saveMember: save)),
        child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('requires names and telephone, then saves without email or account', (tester) async {
    Map<String,dynamic>? saved;
    await open(tester, (p) async { saved=p; });
    await tester.tap(find.text('Add member'));
    await tester.pumpAndSettle();
    expect(saved,isNull);
    expect(find.text('Enter first name'),findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0),'Alex');
    await tester.enterText(find.byType(TextFormField).at(1),'Example');
    await tester.enterText(find.byType(TextFormField).at(2),'07700 900123');
    await tester.tap(find.text('Add member'));
    await tester.pumpAndSettle();
    expect(saved, {'p_club_id':'club','p_first_name':'Alex','p_last_name':'Example','p_phone':'07700 900123','p_sex_at_birth':null});
    expect(find.byType(CaptainManagedMemberDialog),findsNothing);
  });

  testWidgets('failed save keeps entered details and permits retry', (tester) async {
    var attempts=0;
    await open(tester, (_) async { attempts++; if(attempts==1) throw Exception('offline'); });
    await tester.enterText(find.byType(TextFormField).at(0),'Alex');
    await tester.enterText(find.byType(TextFormField).at(1),'Example');
    await tester.enterText(find.byType(TextFormField).at(2),'07700 900123');
    await tester.tap(find.text('Add member'));
    await tester.pumpAndSettle();
    expect(find.text('Could not add the member. Please try again.'),findsOneWidget);
    expect(find.text('Alex'),findsOneWidget);
    await tester.tap(find.text('Add member'));
    await tester.pumpAndSettle();
    expect(attempts,2);
    expect(find.byType(CaptainManagedMemberDialog),findsNothing);
  });
}
