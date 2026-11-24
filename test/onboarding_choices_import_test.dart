import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/clubs/onboarding_member_import.dart';
import 'package:bowls_saas/features/clubs/onboarding_members_screen.dart';
import 'package:bowls_saas/features/clubs/onboarding_activities_screen.dart';

const secretary = OnboardingMember(
  firstName: 'Test',
  surname: 'Secretary',
  email: 'secretary@example.invalid',
  phone: '02000000000',
  role: 'admin',
  active: true,
);
const headings = 'First name,Surname,Email,Telephone\n';

Uint8List workbook(String cells) {
  final archive = Archive();
  final files = {
    'xl/workbook.xml':
        '<workbook xmlns:r="urn:rels"><sheets><sheet name="Members" r:id="rId1"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels':
        '<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>',
    'xl/worksheets/sheet1.xml':
        '<worksheet><sheetData><row r="1">'
        '<c r="A1" t="inlineStr"><is><t>First name</t></is></c>'
        '<c r="B1" t="inlineStr"><is><t>Surname</t></is></c>'
        '<c r="C1" t="inlineStr"><is><t>Email</t></is></c>'
        '<c r="D1" t="inlineStr"><is><t>Telephone</t></is></c>'
        '</row>$cells</sheetData></worksheet>',
  };
  for (final f in files.entries) {
    final bytes = utf8.encode(f.value);
    archive.addFile(ArchiveFile(f.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  test(
    'review preserves Secretary and flags duplicates, invalid data and missing email',
    () {
      final rows = memberDelimitedRows(
        '${headings}Test,Secretary,SECRETARY@example.invalid,\n'
        'Ann,Player,ann@example.invalid,01234567890\n'
        'Another,Person,ANN@example.invalid,\n'
        'Noemail,Player,,01234567890\n'
        'Bad,Email,bad,\n'
        'Ann,Player,different@example.invalid,\n',
      );
      final review = reviewOnboardingMembers(rows, [secretary]);
      expect(review.map((r) => r.status), [
        MemberImportStatus.existing,
        MemberImportStatus.ready,
        MemberImportStatus.duplicate,
        MemberImportStatus.ready,
        MemberImportStatus.needsAttention,
        MemberImportStatus.possibleDuplicate,
      ]);
      final result = applyReviewedMembers(
        [secretary],
        review,
        review.map((r) => r.row).toSet(),
      );
      expect(result, hasLength(3));
      expect(identical(result.first, secretary), isTrue);
      expect(result.first.role, 'admin');
      expect(result.first.active, isTrue);
      expect(result[1].phone, '01234567890');
      expect(result[2].email, '');
      expect(result[2].role, 'member');
      expect(result[2].active, isFalse);
    },
  );

  test('CSV quotes and Excel paste work and password columns are rejected', () {
    final rows = memberDelimitedRows(
      'First name\tSurname\tEmail\nJean\t"O\'Neil"\t\n',
    );
    expect(reviewOnboardingMembers(rows, []).single.member.surname, "O'Neil");
    expect(memberDelimitedRows('a,b\n"c,d","e""f"').last, ['c,d', 'e"f']);
    expect(
      () => memberDelimitedRows('a,b\n"unfinished'),
      throwsFormatException,
    );
    expect(
      () => reviewOnboardingMembers(
        memberDelimitedRows('First name,Surname,Password\nA,B,x'),
        [],
      ),
      throwsFormatException,
    );
  });

  test('actual downloadable workbook has correct empty import sheet', () {
    final bytes = File(
      'assets/templates/Club-member-template.xlsx',
    ).readAsBytesSync();
    final rows = memberSpreadsheetRows(bytes, 'members.xlsx');
    expect(rows.first, ['First name', 'Surname', 'Email', 'Telephone']);
    expect(reviewOnboardingMembers(rows, [secretary]), isEmpty);
  });

  test('xlsx parser preserves literal identifiers and refuses formulas', () {
    final bytes = workbook(
      '<row r="2"><c r="A2" t="inlineStr"><is><t>Ann</t></is></c>'
      '<c r="B2" t="inlineStr"><is><t>Player</t></is></c>'
      '<c r="D2" t="inlineStr"><is><t>01234567890</t></is></c></row>',
    );
    final member = reviewOnboardingMembers(
      memberSpreadsheetRows(bytes, 'members.xlsx'),
      [],
    ).single.member;
    expect(member.phone, '01234567890');
    expect(
      () => memberSpreadsheetRows(
        workbook('<row r="2"><c r="A2"><f>1+1</f><v>2</v></c></row>'),
        'members.xlsx',
      ),
      throwsFormatException,
    );
  });

  Future<void> tap(WidgetTester t, String text) async {
    final f = find.text(text);
    await t.scrollUntilVisible(
      f,
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(f);
    await t.pumpAndSettle();
  }

  testWidgets(
    'activity choices require review before saving and keep events separate',
    (t) async {
      Set<String>? saved;
      await t.pumpWidget(
        MaterialApp(
          home: OnboardingActivitiesScreen(
            initial: {},
            onSave: (s) => saved = s,
          ),
        ),
      );
      await tap(t, 'Roll-ups and open sessions');
      await tap(t, 'Committee meetings');
      await tap(t, 'Review selected activities');
      expect(saved, isNull);
      expect(find.text('General club events'), findsOneWidget);
      expect(find.textContaining('No rinks by default'), findsOneWidget);
      await tap(t, 'Use these activities');
      expect(saved, {'rollups', 'committee'});
    },
  );

  testWidgets(
    'member import only applies selected reviewed rows and never changes the Secretary',
    (t) async {
      List<OnboardingMember>? saved;
      await t.pumpWidget(
        MaterialApp(
          home: OnboardingMembersScreen(
            initial: [secretary],
            onSave: (s) => saved = s,
          ),
        ),
      );
      final paste = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Paste member rows',
      );
      await t.ensureVisible(paste);
      await t.enterText(
        paste,
        '${headings}Test,Secretary,secretary@example.invalid,\n'
        'Ann,Player,ann@example.invalid,\nNoemail,Player,,\n',
      );
      await tap(t, 'Review pasted members');
      expect(saved, isNull);
      expect(
        find.textContaining('Already added to this setup list'),
        findsOneWidget,
      );
      await tap(t, 'Row 4: Noemail Player');
      await tap(t, 'Add 1 selected person');
      expect(saved, hasLength(2));
      expect(identical(saved!.first, secretary), isTrue);
      expect(saved!.last.name, 'Ann Player');
      expect(find.textContaining('No invitations were sent.'), findsOneWidget);
    },
  );
  testWidgets(
    'already included rows explain duplicates and continue without importing',
    (t) async {
      final people = List.generate(
        7,
        (i) => OnboardingMember(
          firstName: 'Person',
          surname: '$i',
          email: 'person$i@example.invalid',
          phone: '',
        ),
      );
      List<OnboardingMember>? saved;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => OnboardingMembersScreen(
                      initial: [secretary, ...people],
                      rehearsal: false,
                      onSave: (v) => saved = v,
                      memberLookup: (members) async => members
                          .map((_) => <String, dynamic>{'status': 'not_found'})
                          .toList(),
                    ),
                  ),
                ),
                child: const Text('Open members'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open members'));
      await t.pumpAndSettle();
      final paste = find.byType(TextField);
      await t.ensureVisible(paste);
      await t.enterText(
        paste,
        '$headings${people.map((p) => '${p.firstName},${p.surname},${p.email},').join('\n')}',
      );
      await tap(t, 'Review pasted members');
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.byIcon(Icons.check_circle_outline), findsNWidgets(7));
      expect(
        find.textContaining('7 already added · 0 needing attention'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Everyone in this file is already'),
        findsOneWidget,
      );
      expect(
        find.textContaining('No existing profile was found'),
        findsNothing,
      );
      expect(find.textContaining('Already a member.'), findsNothing);
      await t.tap(find.text('Continue with 8 people'));
      await t.pumpAndSettle();
      expect(find.text('Open members'), findsOneWidget);
      expect(saved, isNull);
    },
  );

  testWidgets('footer adds checked new people and returns to club setup', (
    t,
  ) async {
    List<OnboardingMember>? saved;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => OnboardingMembersScreen(
                    initial: [secretary],
                    onSave: (v) => saved = v,
                  ),
                ),
              ),
              child: const Text('Open members'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open members'));
    await t.pumpAndSettle();
    final paste = find.byType(TextField);
    await t.ensureVisible(paste);
    await t.enterText(paste, '${headings}Ann,Player,ann@example.invalid,\n');
    await tap(t, 'Review pasted members');
    expect(
      t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isTrue,
    );
    await t.tap(find.text('Add 1 selected person and continue'));
    await t.pumpAndSettle();
    expect(find.text('Open members'), findsOneWidget);
    expect(saved, hasLength(2));
    expect(identical(saved!.first, secretary), isTrue);
    expect(saved!.last.active, isFalse);
  });

  testWidgets(
    'pending file selection permits pasting and ignores a late file',
    (t) async {
      final pending = Completer<FilePickerResult?>();
      await t.pumpWidget(
        MaterialApp(
          home: OnboardingMembersScreen(
            initial: [secretary],
            onSave: (_) {},
            pickMemberFile: () => pending.future,
          ),
        ),
      );
      await tap(t, 'Upload member spreadsheet');
      expect(find.byType(LinearProgressIndicator), findsNothing);
      final paste = find.byType(TextField);
      await t.ensureVisible(paste);
      await t.enterText(paste, '${headings}Ann,Player,ann@example.invalid,\n');
      await tap(t, 'Review pasted members');
      expect(find.textContaining('Pasted members · 1'), findsOneWidget);
      pending.complete(
        FilePickerResult([
          PlatformFile(
            name: 'other.csv',
            size: 1,
            bytes: Uint8List.fromList(
              utf8.encode('${headings}Other,Player,other@example.invalid,\n'),
            ),
          ),
        ]),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('Pasted members · 1'), findsOneWidget);
      expect(find.textContaining('Row 2: Other'), findsNothing);
      expect(find.textContaining('A file window is open.'), findsNothing);
    },
  );
  testWidgets(
    'existing members show source clubs, Secretary remains active and import waits for lookup',
    (t) async {
      final lookup = Completer<List<Map<String, dynamic>>>();
      List<OnboardingMember>? saved;
      await t.pumpWidget(
        MaterialApp(
          home: OnboardingMembersScreen(
            initial: [secretary],
            rehearsal: false,
            onSave: (v) => saved = v,
            memberLookup: (members) async {
              if (members.single.role == 'admin')
                return [
                  {
                    'status': 'matched',
                    'display_name': 'Test Secretary',
                    'clubs': [
                      {'name': 'Original Club', 'active': true},
                    ],
                  },
                ];
              return lookup.future;
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('Original Club (active)'), findsOneWidget);
      expect(
        find.textContaining('Secretary · Administrator · Active'),
        findsOneWidget,
      );
      final paste = find.byType(TextField);
      await t.ensureVisible(paste);
      await t.enterText(paste, '${headings}Ann,Player,ann@example.invalid,\n');
      await tap(t, 'Review pasted members');
      expect(
        find.text('Checking existing members and their clubs…'),
        findsOneWidget,
      );
      final waiting = t.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Add 1 selected person'),
      );
      expect(waiting.onPressed, isNull);
      lookup.complete([
        {
          'status': 'matched',
          'display_name': 'Ann Player',
          'clubs': [
            {'name': 'Other Club', 'active': true},
          ],
        },
      ]);
      await t.pumpAndSettle();
      expect(
        find.textContaining('Found at: Other Club (active)'),
        findsOneWidget,
      );
      await tap(t, 'Add 1 selected person');
      expect(saved, hasLength(2));
      expect(saved!.first.active, isTrue);
      expect(saved!.last.active, isFalse);
    },
  );
}
