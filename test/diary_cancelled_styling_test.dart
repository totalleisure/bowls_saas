import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/diary/diary_list_screen.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final cancelled in [false,true]) {
      testWidgets('List fixture styling: $brightness, cancelled=$cancelled', (tester) async {
        var opened=false;
        await tester.pumpWidget(MaterialApp(theme:ThemeData(brightness:brightness),home:Scaffold(body:DiaryEntryCard(
          clubName:'Club',onTap:()=>opened=true,
          entry:{'id':'fixture','start_at':'2026-10-22T14:00:00Z','is_home':true,'team_name':'Club Match','_involvement':['Playing'],
            if(cancelled)'cancelled_at':'2026-10-21T10:00:00Z',
            'competition_type':{'name':'League','is_internal':true,'colour_scheme':{'background_hex':'#FFCC00','foreground_hex':'#003399'}}},
        ))));
        expect(tester.widget<Card>(find.byType(Card)).color,cancelled?Colors.grey.shade300:const Color(0xffffcc00));
        expect(find.text('Cancelled'),cancelled?findsOneWidget:findsNothing);
        expect(tester.widget<Icon>(find.byIcon(Icons.chevron_right)).color,cancelled?Colors.grey.shade800:const Color(0xff003399));
        expect(tester.widget<Text>(find.text('Playing')).style?.color,cancelled?Colors.grey.shade800:const Color(0xff003399));
        await tester.tap(find.byType(InkWell));
        expect(opened,isTrue);
        expect(tester.takeException(),isNull);
      });
    }
  }
}
