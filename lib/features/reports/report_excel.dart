import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'club_report.dart';

String _xml(Object? value) => (value?.toString() ?? '')
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
String _column(int index) {
  var result = '';
  var n = index + 1;
  while (n > 0) {
    n--;
    result = String.fromCharCode(65 + n % 26) + result;
    n ~/= 26;
  }
  return result;
}

/// Native XLSX with typed numeric/date cells, frozen headers and filters.
/// All user-supplied text is inline text, never an Excel formula.
Uint8List buildReportExcel(ClubReport report) {
  final archive = Archive();
  void add(String name, String text) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  final summary = report.summary;
  final sections = <String, List<List<Object?>>>{
    'Summary': [
      ['${report.data['club_name']} — Club reports', null],
      ['Reporting period', '${report.data['from']} to ${report.data['to']}'],
      ['Generated (UTC)', report.data['generated_at']],
      ['Measure', 'Value'],
      ['Active members', summary['active_members']],
      ['Inactive members', summary['inactive_members']],
      ['Active members ever signed in', summary['ever_signed_in']],
      ['Latest sign-in falls in period', summary['last_sign_in_in_period']],
      [
        'Active members without recorded sign-in',
        summary['no_recorded_sign_in'],
      ],
      ['Active members without email', summary['without_email']],
      ['Active members without phone', summary['without_phone']],
      ['Bookings created in period', summary['bookings_created']],
      ['Recorded logins in period', summary['recorded_logins']],
      ['Recorded App visits in period', summary['app_visits']],
      ['Recorded screen views in period', summary['screen_views']],
      ['Recorded unique App users in period', summary['active_app_users']],
      ['Usage recording starts (UTC)', report.data['recording_started_at']],
      ['Guest App role', report.guestMembers.length],
      [
        'Active members with recorded explicit starting view',
        summary['explicit_start_choices'],
      ],
      [
        'Top Users order',
        report.hasRecordedUsage
            ? 'Screen views, App visits and recorded logins, highest first; latest sign-in breaks ties.'
            : 'Usage ranking unavailable yet. Most recent sign-in first; this is not login frequency.',
      ],
      [
        'Spreadsheet refresh',
        'This is a dated snapshot. Generate a new export for later data; existing downloaded files are not live.',
      ],
      [
        'Explicit starting-view choices',
        'Future explicit choices are recorded by this App. Legacy device choices are not inferred. Blank means not recorded, not no preference.',
      ],
      ['Member type', 'App role. Club subscription categories are not stored.'],
      [
        'Login counts',
        'Recorded from the start date above; earlier totals are unavailable. Account-wide across Clubs.',
      ],
      [
        'App visits',
        'One per Club/account per App process. Returning with a saved session needs no new login.',
      ],
      [
        'Screen views',
        'Named screens opened, including returns. Requires this reporting-enabled App. No earlier history.',
      ],
      [
        'Booking totals',
        'Bookings created uses creation dates. The Bookings sheet uses fixture dates.',
      ],
      [
        'Assigned fixtures',
        'Distinct current team/rink assignments; excludes cancelled/archived fixtures. Not attendance.',
      ],
      [
        'Source',
        'Production or staging database selected by the App. Contact details are for authorised Club administration.',
      ],
    ],
    'Members': [
      reportMemberColumns.values.toList(),
      ...report.members.map(
        (m) => reportMemberColumns.keys.map<Object?>((key) {
          final v = m[key];
          if (v is bool) return v ? 'Yes' : 'No';
          if (const [
            'member_since',
            'last_sign_in',
            'last_app_activity',
            'start_view_recorded_at',
          ].contains(key)) {
            return v == null ? null : DateTime.parse(v.toString());
          }
          return v;
        }).toList(),
      ),
    ],
    'Bookings': [
      [
        'Fixture type',
        'Total fixtures',
        'Cancelled',
        'Archived',
        'Current fixtures',
      ],
      ...report.bookings.map(
        (r) => [
          r['fixture_type'],
          r['fixtures'],
          r['cancelled'],
          r['archived'],
          r['current_fixtures'],
        ],
      ),
    ],
    'Screen views': [
      ['Screen', 'Platform', 'Views', 'Unique members'],
      ...report.screens.map(
        (r) => [r['screen'], r['platform'], r['views'], r['members']],
      ),
    ],
    'Top Users': [
      [
        'Position',
        'Surname',
        'Forename',
        'App role',
        'Last sign-in (UTC)',
        'Recorded screen views',
        'Recorded App visits',
        'Recorded logins',
        'Last App activity (UTC)',
      ],
      ...report.topUsers.indexed.map((entry) {
        final m = entry.$2;
        return <Object?>[
          entry.$1 + 1,
          m['surname'],
          m['forename'],
          m['member_type'],
          m['last_sign_in'] == null ? null : DateTime.parse(m['last_sign_in']),
          m['screen_views'],
          m['app_visits'],
          m['recorded_logins'],
          m['last_app_activity'] == null
              ? null
              : DateTime.parse(m['last_app_activity']),
        ];
      }),
    ],
    'Guest Members': [
      reportMemberColumns.values.toList(),
      ...report.guestMembers.map(
        (m) => reportMemberColumns.keys.map<Object?>((key) {
          final v = m[key];
          if (v is bool) return v ? 'Yes' : 'No';
          if (const [
            'member_since',
            'last_sign_in',
            'last_app_activity',
            'start_view_recorded_at',
          ].contains(key)) {
            return v == null ? null : DateTime.parse(v.toString());
          }
          return v;
        }).toList(),
      ),
    ],
  };
  var i = 0;
  for (final entry in sections.entries) {
    i++;
    final rows = entry.value;
    final cols = rows.fold<int>(1, (a, r) => r.length > a ? r.length : a);
    final xmlRows = <String>[];
    for (var r = 0; r < rows.length; r++) {
      final cells = <String>[];
      for (var c = 0; c < rows[r].length; c++) {
        final v = rows[r][c];
        if (v == null) continue;
        final address = '${_column(c)}${r + 1}';
        final header = (i == 1 ? r == 3 : r == 0);
        if (v is DateTime) {
          final serial =
              v.toUtc().difference(DateTime.utc(1899, 12, 30)).inMilliseconds /
              86400000;
          cells.add('<c r="$address" s="2"><v>$serial</v></c>');
        } else if (v is num) {
          cells.add('<c r="$address" s="${header ? 1 : 0}"><v>$v</v></c>');
        } else {
          cells.add(
            '<c r="$address" s="${header ? 1 : 0}" t="inlineStr"><is><t xml:space="preserve">${_xml(v)}</t></is></c>',
          );
        }
      }
      xmlRows.add(
        '<row r="${r + 1}" ht="24" customHeight="1">${cells.join()}</row>',
      );
    }
    add(
      'xl/worksheets/sheet$i.xml',
      '<?xml version="1.0" encoding="UTF-8"?>'
          '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
          '<sheetViews><sheetView workbookViewId="0"><pane xSplit="${i == 2 ? 2 : 0}" ySplit="${i == 1 ? 4 : 1}" topLeftCell="${i == 2
              ? 'C2'
              : i == 1
              ? 'A5'
              : 'A2'}" state="frozen"/></sheetView></sheetViews>'
          '<cols>${List.generate(cols, (c) => '<col min="${c + 1}" max="${c + 1}" width="${i == 1
              ? (c == 0 ? 48 : 110)
              : i == 2 && c == 2
              ? 38
              : c == 0 && i == 3
              ? 40
              : c >= 20
              ? 36
              : 25}" customWidth="1"/>').join()}</cols>'
          '<sheetData>${xmlRows.join()}</sheetData>'
          '${i > 1 ? '<autoFilter ref="A1:${_column(cols - 1)}${rows.length}"/>' : ''}</worksheet>',
    );
  }
  add(
    '[Content_Types].xml',
    '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '${List.generate(i, (n) => '<Override PartName="/xl/worksheets/sheet${n + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>').join()}</Types>',
  );
  add(
    '_rels/.rels',
    '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
  );
  add(
    'xl/workbook.xml',
    '<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>${sections.keys.indexed.map((x) => '<sheet name="${_xml(x.$2)}" sheetId="${x.$1 + 1}" r:id="rId${x.$1 + 1}"/>').join()}</sheets></workbook>',
  );
  add(
    'xl/_rels/workbook.xml.rels',
    '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${List.generate(i, (n) => '<Relationship Id="rId${n + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${n + 1}.xml"/>').join()}<Relationship Id="styles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
  );
  add(
    'xl/styles.xml',
    '<?xml version="1.0"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="1"><numFmt numFmtId="164" formatCode="dd-mmm-yyyy hh:mm"/></numFmts><fonts count="2"><font><sz val="11"/><name val="Arial"/></font><font><b/><color rgb="FFFFFFFF"/><sz val="11"/><name val="Arial"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF194D85"/></patternFill></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="3"><xf fontId="0" fillId="0" borderId="0" numFmtId="0" xfId="0"/><xf fontId="1" fillId="2" borderId="0" numFmtId="0" xfId="0" applyFill="1" applyFont="1"/><xf fontId="0" fillId="0" borderId="0" numFmtId="164" xfId="0" applyNumberFormat="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>',
  );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
