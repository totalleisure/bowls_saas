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

  for (final action in ['Save', 'Send Update', 'Cancel']) {
    testWidgets('published instructions $action is explicit', (t) async {
      final calls = <bool>[];
      await t.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
        onPressed: () => showDialog<String>(context: context, builder: (_) => PublicationInstructionsDialog(
          initialInstructions: 'Old instructions', published: true,
          onSave: (notes, send) async { expect(notes, 'New instructions'); calls.add(send); })),
        child: const Text('Open'))))));
      await t.tap(find.text('Open')); await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'New instructions');
      expect(calls, isEmpty);
      await t.tap(find.text(action)); await t.pumpAndSettle();
      expect(calls, action == 'Cancel' ? isEmpty : equals([action == 'Send Update']));
      expect(find.byType(AlertDialog), findsNothing);
    });
  }
  testWidgets('members can read but cannot send or edit', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: PublicationInstructionsDialog(
      initialInstructions: 'Wear whites', published: true, readOnly: true))));
    expect(find.text('Wear whites'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Send Update'), findsNothing);
    expect(find.text('Save'), findsNothing);
  });
  testWidgets('send failure preserves text and permits retry', (t) async {
    var attempts = 0;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: PublicationInstructionsDialog(
      initialInstructions: 'Wear whites', published: true,
      onSave: (_, send) async { attempts++; throw Exception('Network unavailable'); }))));
    await t.tap(find.text('Send Update')); await t.pumpAndSettle();
    expect(find.text('Wear whites'), findsOneWidget);
    expect(find.textContaining('Network unavailable'), findsOneWidget);
    await t.tap(find.text('Send Update')); await t.pumpAndSettle();
    expect(attempts, 2);
  });
}
