import 'package:bowls_saas/features/members/member_import_options_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    ValueChanged<MemberImportOptions?> onResult,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => onResult(
                await showMemberImportOptions(
                  context: context,
                  fileName: 'committee.csv',
                  bytes: 100,
                ),
              ),
              child: const Text('Choose CSV'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose CSV'));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String key, String text) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  testWidgets('defaults to importing inactive without sending', (tester) async {
    MemberImportOptions? result;
    await open(tester, (v) => result = v);
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(result!.importMembers, isTrue);
    expect(result!.newMembersActive, isFalse);
    expect(result!.sendInvitations, isFalse);
  });
  testWidgets(
    'active import with invitation review and defaults reset next time',
    (tester) async {
      MemberImportOptions? result;
      await open(tester, (v) => result = v);
      await choose(tester, 'active-choice', 'Active');
      await choose(tester, 'invite-choice', 'Yes — review invitations');
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(result!.newMembersActive, isTrue);
      expect(result!.sendInvitations, isTrue);
      await tester.tap(find.text('Choose CSV'));
      await tester.pumpAndSettle();
      expect(find.text('Inactive'), findsOneWidget);
    },
  );
  testWidgets('invite-only hides active choice and does not import', (
    tester,
  ) async {
    MemberImportOptions? result;
    await open(tester, (v) => result = v);
    await choose(tester, 'import-choice', 'No — existing members only');
    expect(find.byKey(const Key('active-choice')), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await choose(tester, 'invite-choice', 'Yes — review invitations');
    await tester.tap(find.text('Review invitations'));
    await tester.pumpAndSettle();
    expect(result!.importMembers, isFalse);
    expect(result!.sendInvitations, isTrue);
  });
  testWidgets('cancel performs neither action', (tester) async {
    MemberImportOptions? result = const MemberImportOptions(
      importMembers: true,
      newMembersActive: true,
      sendInvitations: true,
    );
    await open(tester, (v) => result = v);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
