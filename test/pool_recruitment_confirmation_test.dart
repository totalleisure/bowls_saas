import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/team/pool_recruitment_confirmation.dart';
void main() {
 for (final declined in [false,true]) {
  for (final accept in [false,true]) {
   testWidgets('existing confirmation declined=$declined accept=$accept', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:() async {
      result=await showDialog<bool>(context:context,builder:(_)=>PoolRecruitmentConfirmation(declinedNames:declined?['Test Player']:[],unavailableNames:declined?[]:['Test Player']));
    },child:const Text('Recruit'))))));
    await tester.tap(find.text('Recruit'));await tester.pumpAndSettle();
    expect(find.text(declined?'Add previously declined players?':'Override Not available?'),findsOneWidget);
    expect(find.textContaining('does not put them in the team or mark them as accepted'),findsOneWidget);
    await tester.tap(find.text(accept?'Confirm and add to pool':'Cancel'));await tester.pumpAndSettle();
    expect(result,accept);
   });
  }
 }
}
