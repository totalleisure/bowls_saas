import 'package:bowls_saas/features/members/member_invitation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('personalised preview fits a narrow phone and opens supplied link', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MemberInvitationPreview(
              content: {
                'subject': 'Wayne, welcome to your Bowls Club App',
                'club': 'Lewisham & Crystal Palace Indoor Bowling Club',
                'greeting': 'Hello Wayne,',
                'introduction': 'Your account is ready.',
                'sections': [
                  {
                    'title': 'Your login details',
                    'text':
                        'wayne@example.com\nUse your current password or Forgotten password.',
                  },
                  {
                    'title': 'Get the app',
                    'text': 'iPhone or iPad',
                    'link':
                        'https://apps.apple.com/gb/app/total-leisure-bowls/id6762380407',
                    'link_label': 'Download for iPhone / iPad',
                  },
                ],
                'closing': 'Your club team',
              },
              onOpen: (url) => opened = url,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Hello Wayne,'), findsOneWidget);
    await tester.ensureVisible(find.text('Download for iPhone / iPad'));
    await tester.tap(find.text('Download for iPhone / iPad'));
    expect(opened, contains('id6762380407'));
    expect(tester.takeException(), isNull);
  });
}
