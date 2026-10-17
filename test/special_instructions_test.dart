import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/team/publication_instructions_dialog.dart';
import 'package:bowls_saas/features/fixtures/next_fixture_reminder.dart';
void main() {
  for (final action in ['Cancel','Continue to publish']) {
    testWidgets('publication review prefills and $action returns safely', (t) async {
      String? result = 'not closed';
      await t.pumpWidget(MaterialApp(home: Builder(builder:(context)=>Scaffold(body:TextButton(
        onPressed:() async {result=await showDialog<String>(context:context,builder:(_)=>const PublicationInstructionsDialog(initialInstructions:'Arrive at 09:30'));},child:const Text('Open'))))));
      await t.tap(find.text('Open'));await t.pumpAndSettle();
      expect(find.text('Arrive at 09:30'),findsOneWidget);
      await t.enterText(find.byType(TextField),'  Wear whites\nBring lunch  ');
      await t.tap(find.text(action));await t.pumpAndSettle();
      expect(result,action=='Cancel'?null:'Wear whites\nBring lunch');
    });
  }
  testWidgets('reminder shows saved multiline instructions', (t) async {
    await t.pumpWidget(MaterialApp(home: Builder(builder:(context)=>Scaffold(body:TextButton(
      onPressed:()=>NextFixtureReminder(context:context,clubName:'Club',
        nextMatch:{'id':'fixture','start_at':'2026-10-20T10:00:00Z','notes':'Arrive early\nWear whites'},
        now:()=>DateTime.utc(2026,10,17),openFixture:(_)async{}).show(),child:const Text('Open'))))));
    await t.tap(find.text('Open'));await t.pumpAndSettle();
    expect(find.text('Special instructions: Arrive early\nWear whites'),findsOneWidget);
    expect(find.text('Special instructions: none at the moment'),findsNothing);
  });
}
