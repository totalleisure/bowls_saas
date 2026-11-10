import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/reports/report_excel.dart';
import 'package:bowls_saas/features/reports/report_workbook_refresh.dart';
import 'package:bowls_saas/features/reports/club_report.dart';
import 'club_reports_test.dart' as fixtures;

ClubReport report({
  String name = 'Anne',
  String surname = 'Example',
  String email = 'a@example.invalid',
  bool extra = false,
}) {
  final base = fixtures.sample();
  base.data['club_id'] = 'club';
  final m = {
    ...base.members.single,
    'member_profile_id': 'member-1',
    'forename': name,
    'surname': surname,
    'email': email,
    'screen_views': 12,
    'explicit_start_view': 'month',
    'start_view_status': 'Explicit choice',
    'start_view_recorded_at': '2026-10-27T10:00:00Z',
    'app_visits': 4,
    'recorded_logins': 2,
  };
  return ClubReport(base.data, [
    m,
    if (extra)
      {
        ...m,
        'member_profile_id': 'member-2',
        'forename': 'Bob',
        'surname': 'New',
        'email': 'b@example.invalid',
        'member_type': 'guest',
      },
  ]);
}

Uint8List withNote(Uint8List bytes) {
  final a = ZipDecoder().decodeBytes(bytes);
  final out = Archive();
  for (final f in a.files) {
    if (f.name != 'xl/worksheets/sheet2.xml') {
      out.addFile(f);
      continue;
    }
    final doc = XmlDocument.parse(utf8.decode(f.content as List<int>));
    final row = doc
        .findAllElements('row')
        .firstWhere((r) => r.getAttribute('r') == '2');
    row.children.add(
      XmlElement(
        XmlName('c'),
        [
          XmlAttribute(XmlName('r'), 'X2'),
          XmlAttribute(XmlName('t'), 'inlineStr'),
        ],
        [
          XmlElement(XmlName('is'), [], [
            XmlElement(XmlName('t'), [], [XmlText('Keep my Club note')]),
          ]),
        ],
      ),
    );
    final b = utf8.encode(doc.toXmlString());
    out.addFile(ArchiveFile(f.name, b.length, b));
  }
  return Uint8List.fromList(ZipEncoder().encode(out));
}

String sheet(Uint8List bytes, String path) => utf8.decode(
  ZipDecoder().decodeBytes(bytes).findFile(path)!.content as List<int>,
);
void main() {
  test('Excel-saved calculation chains and old report table headings are rebuilt', () {
    final original = ZipDecoder().decodeBytes(buildReportExcel(report()));
    final out = Archive();
    void add(String name, String value) {
      final bytes = utf8.encode(value);
      out.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    for (final f in original.files) {
      var text = utf8.decode(f.content as List<int>);
      if (f.name == 'xl/workbook.xml') {
        text = text.replaceFirst(
          '</workbook>',
          '<calcPr calcMode="manual"/></workbook>',
        );
      }
      if (f.name == 'xl/_rels/workbook.xml.rels') {
        text = text.replaceFirst(
          '</Relationships>',
          '<Relationship Id="oldCalc" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/calcChain" Target="calcChain.xml"/></Relationships>',
        );
      }
      if (f.name == '[Content_Types].xml') {
        text = text.replaceFirst(
          '</Types>',
          '<Override PartName="/xl/calcChain.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.calcChain+xml"/></Types>',
        );
      }
      if (f.name == 'xl/worksheets/sheet1.xml') {
        text = text.replaceFirst(
          '</sheetData>',
          '<row r="40"><c r="B40"><f>SUM(B5:B6)</f><v>999</v></c></row></sheetData>',
        );
      }
      add(f.name, text);
    }
    add(
      'xl/calcChain.xml',
      '<calcChain xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><c r="B40" i="1"/></calcChain>',
    );
    for (final e in {
      'BookingsByType': 3,
      'TopUsersTable': 5,
      'GuestMembersTable': 6,
    }.entries) {
      add(
        'xl/tables/test${e.value}.xml',
        '<table xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" id="${e.value}" name="${e.key}" displayName="${e.key}" ref="A1:A2"><autoFilter ref="A1:A2"/><tableColumns count="1"><tableColumn id="1" name="Old heading"/></tableColumns></table>',
      );
    }
    final result = refreshReportWorkbook(
      Uint8List.fromList(ZipEncoder().encode(out)),
      report(),
    );
    final archive = ZipDecoder().decodeBytes(result);
    expect(archive.findFile('xl/calcChain.xml'), isNull);
    expect(
      sheet(result, 'xl/_rels/workbook.xml.rels'),
      isNot(contains('/calcChain')),
    );
    expect(
      sheet(result, '[Content_Types].xml'),
      isNot(contains('/calcChain.xml')),
    );
    expect(sheet(result, 'xl/workbook.xml'), contains('calcMode="auto"'));
    expect(sheet(result, 'xl/workbook.xml'), contains('fullCalcOnLoad="1"'));
    expect(
      sheet(result, 'xl/worksheets/sheet1.xml'),
      contains('<f>SUM(B5:B6)</f>'),
    );
    expect(
      sheet(result, 'xl/worksheets/sheet1.xml'),
      isNot(contains('<v>999</v>')),
    );
    expect(
      sheet(result, 'xl/tables/test3.xml'),
      contains('name="Total fixtures"'),
    );
    expect(
      sheet(result, 'xl/tables/test5.xml'),
      contains('name="Last sign-in (UTC)"'),
    );
    expect(sheet(result, 'xl/tables/test6.xml'), contains('ref="A1:W2"'));
    expect(sheet(result, 'xl/worksheets/sheet6.xml'), contains('<row r="2">'));
  });
  test('repair user workbook with its exact snapshot when locally supplied', () {
    final data = File('tmp/excel-repair-snapshot.json');
    if (!data.existsSync()) return;
    final d = Map<String, dynamic>.from(jsonDecode(data.readAsStringSync()));
    final r = ClubReport(d, List<Map<String, dynamic>>.from(d['members']));
    final result = refreshReportWorkbook(
      File('tmp/excel-repair-input.xlsx').readAsBytesSync(),
      r,
    );
    Directory('outputs/excel-refresh-correction').createSync(recursive: true);
    File(
      'outputs/excel-refresh-correction/LCPIBC-Reports-2026-10-27-Corrected.xlsx',
    ).writeAsBytesSync(result);
  });
  test(
    'refresh preserves added notes, updates data, and later identifies renamed members by stable ID',
    () {
      final original = withNote(buildReportExcel(report()));
      final first = refreshReportWorkbook(
        original,
        report(email: 'new@example.invalid', extra: true),
      );
      expect(
        sheet(first, 'xl/worksheets/sheet2.xml'),
        contains('Keep my Club note'),
      );
      expect(
        sheet(first, 'xl/worksheets/sheet2.xml'),
        contains('new@example.invalid'),
      );
      expect(sheet(first, 'xl/worksheets/sheet2.xml'), contains('Bob'));
      final second = refreshReportWorkbook(
        first,
        report(
          name: 'Annie',
          surname: 'Changed',
          email: 'again@example.invalid',
          extra: true,
        ),
      );
      final members = sheet(second, 'xl/worksheets/sheet2.xml');
      expect(members, contains('Annie'));
      expect(members, contains('Explicit choice'));
      expect(members, contains('Starting view recorded (UTC)'));
      expect(members, contains('Keep my Club note'));
      expect(sheet(second, 'customXml/bowls-report.xml'), contains('member-1'));
      Directory('tmp').createSync(recursive: true);
      File('tmp/refreshed-report-test.xlsx').writeAsBytesSync(second);
    },
  );
  test('different Club workbook is rejected', () {
    final bytes = refreshReportWorkbook(buildReportExcel(report()), report());
    final other = report();
    other.data['club_id'] = 'different';
    expect(() => refreshReportWorkbook(bytes, other), throwsFormatException);
  });
  test('removed App members and their notes are retained separately', () {
    final original = withNote(buildReportExcel(report()));
    final empty = ClubReport(report().data, []);
    final updated = refreshReportWorkbook(original, empty);
    final files = ZipDecoder().decodeBytes(updated).files;
    expect(
      files.any(
        (f) =>
            f.name.endsWith('.xml') &&
            utf8.decode(f.content as List<int>).contains('Keep my Club note'),
      ),
      isTrue,
    );
    expect(sheet(updated, 'xl/workbook.xml'), contains('Previous App rows'));
  });
  test(
    'the supplied reconciled report can refresh while keeping imported source and highlights',
    () {
      final input = File(
        'outputs/club-reports-2026-10-26/LCPIBC-Members-and-Reports-2026-10-26.xlsx',
      );
      final data = File(
        'outputs/club-reports-2026-10-26/production-report.json',
      );
      if (!input.existsSync() || !data.existsSync()) return;
      final d = Map<String, dynamic>.from(jsonDecode(data.readAsStringSync()));
      d['club_id'] = '8ae87bbe-cb16-4330-a5b0-e62366479f07';
      final r = ClubReport(d, List<Map<String, dynamic>>.from(d['members']));
      final before = ZipDecoder().decodeBytes(input.readAsBytesSync());
      final result = refreshReportWorkbook(input.readAsBytesSync(), r);
      final after = ZipDecoder().decodeBytes(result);
      // All non-managed worksheets (including original source) remain byte-identical.
      for (final name in ['xl/worksheets/sheet8.xml']) {
        if (before.findFile(name) != null) {
          expect(after.findFile(name)!.content, before.findFile(name)!.content);
        }
      }
      expect(
        sheet(result, 'xl/worksheets/sheet2.xml'),
        contains('Not found in Club list'),
      );
      expect(
        sheet(result, 'xl/worksheets/sheet2.xml'),
        contains('conditionalFormatting'),
      );
      File('tmp/refreshed-reconciled-qa.xlsx').writeAsBytesSync(result);
    },
  );
}
