import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'club_report.dart';
import 'report_excel.dart';

const _ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
String _col(int n) {
  var s = '';
  for (n++; n > 0; n ~/= 26) {
    n--;
    s = String.fromCharCode(65 + n % 26) + s;
  }
  return s;
}

String _norm(Object? v) => (v ?? '').toString().trim().toLowerCase().replaceAll(
  RegExp(r'[^a-z0-9]'),
  '',
);
String _email(Object? v) => (v ?? '').toString().trim().toLowerCase();

class _Book {
  _Book(Uint8List bytes) {
    if (bytes.length > 20 * 1024 * 1024) {
      throw const FormatException('Choose an Excel report smaller than 20 MB.');
    }
    archive = ZipDecoder().decodeBytes(bytes);
    if (archive.files.fold<int>(0, (n, f) => n + f.size) > 80 * 1024 * 1024) {
      throw const FormatException('The workbook is too large.');
    }
    workbook = read('xl/workbook.xml');
    rels = read('xl/_rels/workbook.xml.rels');
    final f = archive.findFile('xl/sharedStrings.xml');
    if (f != null) {
      strings = read(f.name)
          .findAllElements('si')
          .map((e) => e.findAllElements('t').map((t) => t.innerText).join())
          .toList();
    }
  }
  late Archive archive;
  late XmlDocument workbook, rels;
  List<String> strings = [];
  final changes = <String, String>{};
  final removed = <String>{};
  XmlDocument read(String p) {
    final text =
        changes[p] ??
        utf8.decode(
          archive.findFile(p)?.content as List<int>? ??
              (throw const FormatException(
                'This is not a supported Excel report.',
              )),
        );
    var doc = XmlDocument.parse(text);
    final prefix = doc.rootElement.name.prefix;
    if (prefix != null) {
      final namespace = doc.rootElement.getAttribute('xmlns:$prefix');
      if (namespace == _ns ||
          namespace ==
              'http://schemas.openxmlformats.org/package/2006/relationships' ||
          namespace ==
              'http://schemas.openxmlformats.org/package/2006/content-types') {
        doc = XmlDocument.parse(
          text.replaceAll('<$prefix:', '<').replaceAll('</$prefix:', '</'),
        );
        doc.rootElement.setAttribute('xmlns', namespace!);
      }
    }
    return doc;
  }

  void write(String p, XmlDocument x) => changes[p] = x.toXmlString();
  Map<String, String> get sheets {
    final result = <String, String>{};
    for (final s in workbook.findAllElements('sheet')) {
      final relation = rels
          .findAllElements('Relationship')
          .where((r) => r.getAttribute('Id') == s.getAttribute('r:id'))
          .first;
      result[s.getAttribute('name')!] = Uri.parse(
        'file:///xl/workbook.xml',
      ).resolve(relation.getAttribute('Target')!).path.substring(1);
    }
    return result;
  }

  String cell(XmlElement? c) {
    if (c == null) return '';
    if (c.getAttribute('t') == 'inlineStr') {
      return c.findAllElements('t').map((e) => e.innerText).join();
    }
    final v = c.getElement('v')?.innerText ?? '';
    return c.getAttribute('t') == 's' && v.isNotEmpty
        ? strings[int.parse(v)]
        : v;
  }

  Map<int, XmlElement> rows(XmlDocument x) => {
    for (final r in x.findAllElements('row'))
      int.parse(r.getAttribute('r')!): r,
  };
  Map<String, XmlElement> cells(XmlElement r) => {
    for (final c in r.findElements('c'))
      c.getAttribute('r')!.replaceAll(RegExp(r'\d'), ''): c,
  };
  void addSheet(String name) {
    if (sheets.containsKey(name)) return;
    final ids = workbook
        .findAllElements('sheet')
        .map((s) => int.parse(s.getAttribute('sheetId')!));
    final id = ids.fold<int>(0, (a, b) => a > b ? a : b) + 1;
    final rid = 'bowlsReport$id';
    final path = 'worksheets/bowls-report-$id.xml';
    workbook
        .findAllElements('sheets')
        .first
        .children
        .add(
          XmlElement(XmlName('sheet'), [
            XmlAttribute(XmlName('name'), name),
            XmlAttribute(XmlName('sheetId'), '$id'),
            XmlAttribute(XmlName('id', 'r'), rid),
          ]),
        );
    rels.rootElement.children.add(
      XmlElement(XmlName('Relationship'), [
        XmlAttribute(XmlName('Id'), rid),
        XmlAttribute(
          XmlName('Type'),
          'http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet',
        ),
        XmlAttribute(XmlName('Target'), path),
      ]),
    );
    final types = read('[Content_Types].xml');
    types.rootElement.children.add(
      XmlElement(XmlName('Override'), [
        XmlAttribute(XmlName('PartName'), '/xl/$path'),
        XmlAttribute(
          XmlName('ContentType'),
          'application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml',
        ),
      ]),
    );
    write('[Content_Types].xml', types);
    changes['xl/$path'] =
        '<?xml version="1.0"?><worksheet xmlns="$_ns"><sheetData/></worksheet>';
  }

  int dateStyle() {
    final x = read('xl/styles.xml');
    final root = x.rootElement;
    var fmts = root.getElement('numFmts');
    if (fmts == null) {
      fmts = XmlElement(XmlName('numFmts'), [
        XmlAttribute(XmlName('count'), '0'),
      ]);
      root.children.insert(0, fmts);
    }
    final found = fmts
        .findElements('numFmt')
        .where((f) => f.getAttribute('formatCode') == 'dd-mmm-yyyy hh:mm');
    final id = found.isNotEmpty
        ? int.parse(found.first.getAttribute('numFmtId')!)
        : fmts
                  .findElements('numFmt')
                  .map((f) => int.parse(f.getAttribute('numFmtId')!))
                  .fold<int>(163, (a, b) => a > b ? a : b) +
              1;
    if (found.isEmpty) {
      fmts.children.add(
        XmlElement(XmlName('numFmt'), [
          XmlAttribute(XmlName('numFmtId'), '$id'),
          XmlAttribute(XmlName('formatCode'), 'dd-mmm-yyyy hh:mm'),
        ]),
      );
      fmts.setAttribute('count', '${fmts.findElements('numFmt').length}');
    }
    final xfs = root.getElement('cellXfs')!;
    final list = xfs.findElements('xf').toList();
    var index = list.indexWhere((e) => e.getAttribute('numFmtId') == '$id');
    if (index < 0) {
      index = list.length;
      xfs.children.add(
        XmlElement(XmlName('xf'), [
          XmlAttribute(XmlName('numFmtId'), '$id'),
          XmlAttribute(XmlName('fontId'), '0'),
          XmlAttribute(XmlName('fillId'), '0'),
          XmlAttribute(XmlName('borderId'), '0'),
          XmlAttribute(XmlName('xfId'), '0'),
          XmlAttribute(XmlName('applyNumberFormat'), '1'),
        ]),
      );
      xfs.setAttribute('count', '${index + 1}');
    }
    write('xl/styles.xml', x);
    return index;
  }

  void widths(XmlDocument doc, Map<int, int> sizes) {
    var cols = doc.rootElement.getElement('cols');
    if (cols == null) {
      cols = XmlElement(XmlName('cols'));
      final data = doc.rootElement.getElement('sheetData')!;
      doc.rootElement.children.insert(
        doc.rootElement.children.indexOf(data),
        cols,
      );
    }
    for (final entry in sizes.entries) {
      cols.children.removeWhere(
        (c) =>
            c is XmlElement &&
            c.getAttribute('min') == '${entry.key}' &&
            c.getAttribute('max') == '${entry.key}',
      );
      cols.children.add(
        XmlElement(XmlName('col'), [
          XmlAttribute(XmlName('min'), '${entry.key}'),
          XmlAttribute(XmlName('max'), '${entry.key}'),
          XmlAttribute(XmlName('width'), '${entry.value}'),
          XmlAttribute(XmlName('customWidth'), '1'),
        ]),
      );
    }
    cols.children.sort(
      (a, b) => int.parse(
        (a as XmlElement).getAttribute('min')!,
      ).compareTo(int.parse((b as XmlElement).getAttribute('min')!)),
    );
  }

  void value(XmlElement row, String column, int n, Object? v, int dateStyle) {
    final c = cells(row)[column] ?? XmlElement(XmlName('c'));
    if (c.parent == null) row.children.add(c);
    c.setAttribute('r', '$column$n');
    c.removeAttribute('t');
    c.children.clear();
    if (v == null) return;
    if (v is DateTime) {
      c.setAttribute('s', '$dateStyle');
      c.children.add(
        XmlElement(XmlName('v'), [], [
          XmlText(
            '${v.toUtc().difference(DateTime.utc(1899, 12, 30)).inMilliseconds / 86400000}',
          ),
        ]),
      );
    } else if (v is num) {
      c.children.add(XmlElement(XmlName('v'), [], [XmlText('$v')]));
    } else {
      c.setAttribute('t', 'inlineStr');
      c.children.add(
        XmlElement(XmlName('is'), [], [
          XmlElement(
            XmlName('t'),
            [XmlAttribute(XmlName('space', 'xml'), 'preserve')],
            [XmlText(v is bool ? (v ? 'Yes' : 'No') : v.toString())],
          ),
        ]),
      );
    }
  }

  Uint8List save() {
    // Excel's saved calculation chain refers to the old formulas/row layout.
    // Let Excel rebuild it and all cached formula results after this refresh.
    for (final relation in rels.findAllElements('Relationship').toList()) {
      if ((relation.getAttribute('Type') ?? '').endsWith('/calcChain')) {
        removed.add(
          Uri.parse(
            'file:///xl/workbook.xml',
          ).resolve(relation.getAttribute('Target')!).path.substring(1),
        );
        relation.remove();
      }
    }
    removed.add('xl/calcChain.xml');
    final types = read('[Content_Types].xml');
    for (final part in types.findAllElements('Override').toList()) {
      if (removed.contains(
        (part.getAttribute('PartName') ?? '').replaceFirst(RegExp(r'^/'), ''),
      )) {
        part.remove();
      }
    }
    write('[Content_Types].xml', types);
    var calculation = workbook.rootElement.getElement('calcPr');
    if (calculation == null) {
      calculation = XmlElement(XmlName('calcPr'));
      final ext = workbook.rootElement.getElement('extLst');
      if (ext == null) {
        workbook.rootElement.children.add(calculation);
      } else {
        workbook.rootElement.children.insert(
          workbook.rootElement.children.indexOf(ext),
          calculation,
        );
      }
    }
    calculation.setAttribute('calcMode', 'auto');
    calculation.setAttribute('fullCalcOnLoad', '1');
    calculation.setAttribute('forceFullCalc', '1');
    for (final path in sheets.values) {
      final doc = read(path);
      final formulas = doc
          .findAllElements('c')
          .where((c) => c.getElement('f') != null)
          .toList();
      if (formulas.isNotEmpty) {
        for (final cell in formulas) {
          cell.getElement('v')?.remove();
        }
        write(path, doc);
      }
    }
    write('xl/workbook.xml', workbook);
    write('xl/_rels/workbook.xml.rels', rels);
    final out = Archive();
    for (final f in archive.files) {
      if (!changes.containsKey(f.name) && !removed.contains(f.name)) {
        final bytes = f.content;
        out.addFile(ArchiveFile(f.name, bytes.length, bytes));
      }
    }
    for (final e in changes.entries) {
      final b = utf8.encode(e.value);
      out.addFile(ArchiveFile(e.key, b.length, b));
    }
    return Uint8List.fromList(ZipEncoder().encode(out));
  }
}

/// Update managed report data only. Retain source sheets, extra columns, notes,
/// workbook styles and other package parts. Save to a reviewed copy in the UI.
Uint8List refreshReportWorkbook(Uint8List bytes, ClubReport report) {
  final b = _Book(bytes);
  final membersPath = b.sheets['Members'];
  if (membersPath == null) {
    throw const FormatException(
      'Choose a Bowls membership report containing the Members sheet.',
    );
  }
  final metadata = b.archive.findFile('customXml/bowls-report.xml');
  XmlDocument? meta = metadata == null ? null : b.read(metadata.name);
  if (meta != null &&
      meta.rootElement.getAttribute('club_id') != report.data['club_id']) {
    throw const FormatException('This workbook belongs to a different Club.');
  }
  if (meta == null) {
    final overview = b.sheets['Overview'] ?? b.sheets['Summary'];
    if (overview == null) {
      throw const FormatException('The workbook Club cannot be verified.');
    }
    final text = b.read(overview).findAllElements('c').map(b.cell).join('\n');
    if (!text.contains(report.data['club_name'].toString())) {
      throw const FormatException(
        'The workbook does not match the selected Club.',
      );
    }
  }
  final x = b.read(membersPath);
  final rows = b.rows(x);
  final header = rows.entries
      .where(
        (e) =>
            b.cell(b.cells(e.value)['A']) == 'Surname' &&
            b.cell(b.cells(e.value)['B']) == 'Forename',
      )
      .firstOrNull;
  if (header == null) {
    throw const FormatException('The member headers are not recognised.');
  }
  final h = header.key;
  final columnNames = b
      .cells(header.value)
      .map((k, v) => MapEntry(b.cell(v), k));
  final addedColumns = <String, String>{};
  for (final label in const [
    'Explicit starting view',
    'Starting view recorded (UTC)',
    'Starting view report status',
  ]) {
    if (!columnNames.containsKey(label)) {
      var index = 0;
      for (final col in columnNames.values) {
        var n = 0;
        for (final ch in col.codeUnits) {
          n = n * 26 + ch - 64;
        }
        if (n > index) index = n;
      }
      final col = _col(index);
      columnNames[label] = col;
      addedColumns[label] = col;
      b.value(header.value, col, h, label, b.dateStyle());
      final headerStyle = b.cells(header.value)['A']?.getAttribute('s');
      if (headerStyle != null) {
        b.cells(header.value)[col]!.setAttribute('s', headerStyle);
      }
      b.widths(x, {index + 1: 36});
    }
  }
  for (final label in reportMemberColumns.values) {
    if (!columnNames.containsKey(label)) {
      throw FormatException('Missing report column: $label');
    }
  }
  final old = rows.entries
      .where((e) => e.key > h && b.cell(b.cells(e.value)['A']).isNotEmpty)
      .toList();
  if (old.any((r) => r.value.findAllElements('f').isNotEmpty)) {
    throw const FormatException(
      'Member rows contain custom formulas. Keep that workbook and export a fresh report instead.',
    );
  }
  final ids = <String, int>{
    if (meta != null)
      for (final m in meta.findAllElements('member'))
        m.getAttribute('id')!: int.parse(m.getAttribute('row')!),
  };
  final used = <int>{};
  final currentRows = <XmlElement>[];
  final keys = <XmlElement>[];
  String key(XmlElement r) =>
      '${_norm(b.cell(b.cells(r)['A']))}|${_norm(b.cell(b.cells(r)['B']))}';
  final sourcePath = b.sheets['Club Source'];
  final sources = <String, List<String>>{};
  if (sourcePath != null) {
    for (final r
        in b.rows(b.read(sourcePath)).entries.where((e) => e.key > 6)) {
      final c = b.cells(r.value);
      final sourceRow = b.cell(c['A']);
      if (sourceRow.isEmpty) continue;
      sources[sourceRow] = [for (var n = 1; n <= 8; n++) b.cell(c[_col(n)])];
    }
  }
  final usedSources = <String>{};
  // Reserve source links on existing identities before considering new rows.
  final matches = <String, MapEntry<int, XmlElement>>{};
  for (final m in report.members) {
    final id = m['member_profile_id'].toString();
    var candidates = old.where((e) => e.key == ids[id]).toList();
    if (candidates.isEmpty && meta == null) {
      candidates = old
          .where(
            (e) =>
                key(e.value) ==
                '${_norm(m['surname'])}|${_norm(m['forename'])}',
          )
          .toList();
      if (candidates.length != 1) {
        final mail = _email(m['email']);
        candidates = mail.isEmpty
            ? []
            : old
                  .where((e) => _email(b.cell(b.cells(e.value)['C'])) == mail)
                  .toList();
      }
    }
    if (candidates.length > 1) {
      throw const FormatException(
        'Duplicate member identities need review before this workbook can be refreshed.',
      );
    }
    if (candidates.length == 1) {
      final r = candidates.single;
      if (!used.add(r.key)) {
        throw const FormatException(
          'Two members match one workbook row. Please review duplicates.',
        );
      }
      matches[id] = r;
      final link = b.cell(b.cells(r.value)['W']);
      if (link.isNotEmpty) usedSources.add(link);
    }
  }
  final style = b.dateStyle();
  for (var i = 0; i < report.members.length; i++) {
    final m = report.members[i];
    final id = m['member_profile_id'].toString();
    final n = h + i + 1;
    final prior = matches[id];
    final row = prior?.value.copy() ?? XmlElement(XmlName('row'));
    row.setAttribute('r', '$n');
    for (final c in row.findElements('c')) {
      final col = c.getAttribute('r')!.replaceAll(RegExp(r'\d'), '');
      c.setAttribute('r', '$col$n');
    }
    for (final e in reportMemberColumns.entries) {
      Object? v = m[e.key];
      if (v != null &&
          const [
            'member_since',
            'last_sign_in',
            'last_app_activity',
            'start_view_recorded_at',
          ].contains(e.key)) {
        v = DateTime.parse(v.toString());
      }
      b.value(row, columnNames[e.value]!, n, v, style);
    }
    if (sources.isNotEmpty &&
        columnNames.containsKey('Club list match') &&
        prior == null) {
      var candidates = sources.entries
          .where(
            (s) =>
                !usedSources.contains(s.key) &&
                _norm(s.value[1]) == _norm(m['surname']) &&
                _norm(s.value[0]) == _norm(m['forename']),
          )
          .toList();
      final mail = _email(m['email']);
      if (candidates.length != 1 && mail.isNotEmpty) {
        candidates = sources.entries
            .where((s) => _email(s.value[5]) == mail)
            .toList();
      }
      if (candidates.length == 1 &&
          !usedSources.contains(candidates.single.key) &&
          (mail.isEmpty ||
              report.members.where((m) => _email(m['email']) == mail).length ==
                  1)) {
        final s = candidates.single;
        usedSources.add(s.key);
        b.value(row, 'U', n, 'Matched', style);
        b.value(row, 'V', n, 'Workbook refresh: unique name or email', style);
        b.value(row, 'W', n, int.tryParse(s.key) ?? s.key, style);
        for (var k = 0; k < 8; k++) {
          b.value(row, _col(k + 24), n, s.value[k], style);
        }
      } else {
        b.value(
          row,
          'U',
          n,
          candidates.isEmpty
              ? 'Not found in Club list'
              : 'Needs matching review',
          style,
        );
        b.value(
          row,
          'X',
          n,
          'New App record; review against original Club list.',
          style,
        );
      }
    }
    row.children.sort((a, c) {
      if (a is! XmlElement || c is! XmlElement) return 0;
      final l = (a.getAttribute('r') ?? '').replaceAll(RegExp(r'\d'), '');
      final r = (c.getAttribute('r') ?? '').replaceAll(RegExp(r'\d'), '');
      return l.length != r.length
          ? l.length.compareTo(r.length)
          : l.compareTo(r);
    });
    currentRows.add(row);
    keys.add(
      XmlElement(XmlName('member'), [
        XmlAttribute(XmlName('id'), id),
        XmlAttribute(XmlName('row'), '$n'),
      ]),
    );
  }
  final previous = old
      .where((e) => !used.contains(e.key))
      .map((e) => e.value)
      .toList();
  if (previous.isNotEmpty) {
    b.addSheet('Previous App rows');
    final pp = b.sheets['Previous App rows']!;
    final history = b.read(pp);
    final hd = history.findAllElements('sheetData').first;
    var n = b.rows(history).keys.fold<int>(0, (a, c) => a > c ? a : c);
    if (n == 0) {
      final hr = header.value.copy();
      hr.setAttribute('r', '1');
      for (final c in hr.findElements('c')) {
        c.setAttribute(
          'r',
          '${c.getAttribute('r')!.replaceAll(RegExp(r'\d'), '')}1',
        );
      }
      hd.children.add(hr);
      n = 1;
    }
    for (final oldRow in previous) {
      n++;
      final r = oldRow.copy();
      r.setAttribute('r', '$n');
      for (final c in r.findElements('c')) {
        c.setAttribute(
          'r',
          '${c.getAttribute('r')!.replaceAll(RegExp(r'\d'), '')}$n',
        );
      }
      hd.children.add(r);
    }
    b.write(pp, history);
  }
  final sd = x.findAllElements('sheetData').first;
  sd.children.removeWhere(
    (e) =>
        e is XmlElement &&
        e.name.local == 'row' &&
        int.parse(e.getAttribute('r')!) > h,
  );
  sd.children.addAll(currentRows);
  final last = h + currentRows.length;
  final lastCol = columnNames.values.reduce(
    (a, c) => a.length > c.length || a.length == c.length && a.compareTo(c) > 0
        ? a
        : c,
  );
  x
      .findAllElements('dimension')
      .firstOrNull
      ?.setAttribute('ref', 'A1:$lastCol$last');
  x
      .findAllElements('autoFilter')
      .firstOrNull
      ?.setAttribute('ref', 'A$h:$lastCol${last > h ? last : h}');
  for (final cf in x.findAllElements('conditionalFormatting')) {
    final range = cf.getAttribute('sqref');
    if (range != null) {
      cf.setAttribute(
        'sqref',
        range.replaceAllMapped(
          RegExp(r'([A-Z]+)\d+:([A-Z]+)\d+'),
          (m) => '${m[1]}${h + 1}:${m[2]}${last > h ? last : h + 1}',
        ),
      );
    }
  }
  b.write(membersPath, x);
  // Keep existing table names/styles and extend only the Members table bounds.
  for (final f in b.archive.files.where(
    (f) => f.name.startsWith('xl/tables/') && f.name.endsWith('.xml'),
  )) {
    final t = b.read(f.name);
    if (t.rootElement.getAttribute('name') == 'ClubMembers') {
      final columns = t.findAllElements('tableColumns').first;
      for (final label in addedColumns.keys) {
        columns.children.add(
          XmlElement(XmlName('tableColumn'), [
            XmlAttribute(
              XmlName('id'),
              '${columns.findElements('tableColumn').length + 1}',
            ),
            XmlAttribute(XmlName('name'), label),
          ]),
        );
      }
      columns.setAttribute(
        'count',
        '${columns.findElements('tableColumn').length}',
      );
      t.rootElement.setAttribute('ref', 'A$h:$lastCol$last');
      t
          .findAllElements('autoFilter')
          .firstOrNull
          ?.setAttribute('ref', 'A$h:$lastCol$last');
      b.write(f.name, t);
    }
  }
  final unmatchedPath = b.sheets['Club List Only'];
  if (unmatchedPath != null && sources.isNotEmpty) {
    final doc = b.read(unmatchedPath);
    final data = doc.findAllElements('sheetData').first;
    data.children.removeWhere(
      (e) => e is XmlElement && int.parse(e.getAttribute('r')!) > 6,
    );
    var rowNumber = 7;
    for (final source in sources.entries.where(
      (s) => !usedSources.contains(s.key),
    )) {
      final row = XmlElement(XmlName('row'), [
        XmlAttribute(XmlName('r'), '$rowNumber'),
      ]);
      final shared = report.members
          .where(
            (m) =>
                _email(m['email']).isNotEmpty &&
                _email(m['email']) == _email(source.value[5]),
          )
          .map((m) => '${m['forename']} ${m['surname']}')
          .join('; ');
      final values = <Object?>[
        int.tryParse(source.key) ?? source.key,
        ...source.value,
        shared.isEmpty
            ? 'No confirmed App match'
            : 'Shared email; separate member requires review',
        shared,
      ];
      for (var i = 0; i < values.length; i++) {
        b.value(row, _col(i), rowNumber, values[i], style);
      }
      data.children.add(row);
      rowNumber++;
    }
    final end = rowNumber > 7 ? rowNumber - 1 : 6;
    doc
        .findAllElements('dimension')
        .firstOrNull
        ?.setAttribute('ref', 'A1:K$end');
    doc
        .findAllElements('autoFilter')
        .firstOrNull
        ?.setAttribute('ref', 'A6:K$end');
    b.write(unmatchedPath, doc);
    for (final f in b.archive.files.where(
      (f) => f.name.startsWith('xl/tables/') && f.name.endsWith('.xml'),
    )) {
      final table = b.read(f.name);
      if (table.rootElement.getAttribute('name') == 'ClubListOnlyTable') {
        table.rootElement.setAttribute('ref', 'A6:K$end');
        table
            .findAllElements('autoFilter')
            .firstOrNull
            ?.setAttribute('ref', 'A6:K$end');
        b.write(f.name, table);
      }
    }
  }
  final fresh = _Book(buildReportExcel(report));
  for (final name in [
    'Bookings',
    'Screen views',
    'Top Users',
    'Guest Members',
  ]) {
    b.addSheet(name);
    final target = b.sheets[name]!;
    final dest = b.read(target);
    final oldRows = b.rows(dest);
    final tableHeader = oldRows.entries
        .where(
          (e) => e.value
              .findElements('c')
              .any(
                (c) => [
                  'Fixture type',
                  'Screen',
                  'Position',
                  'Surname',
                ].contains(b.cell(c)),
              ),
        )
        .firstOrNull;
    final offset = tableHeader == null ? 0 : tableHeader.key - 1;
    final generated = fresh.read(fresh.sheets[name]!);
    final newData = XmlElement(XmlName('sheetData'));
    if (offset > 0) {
      for (final row in oldRows.entries.where((e) => e.key <= offset)) {
        newData.children.add(row.value.copy());
      }
    }
    var maxCols = 1;
    for (final r in fresh.rows(generated).entries) {
      final n = r.key + offset;
      final row = XmlElement(XmlName('row'), [
        XmlAttribute(XmlName('r'), '$n'),
      ]);
      for (final c in fresh.cells(r.value).entries) {
        Object? v = fresh.cell(c.value);
        if (c.value.getAttribute('t') == null && v.toString().isNotEmpty) {
          final numeric = num.tryParse(v.toString());
          if (numeric != null) {
            v = c.value.getAttribute('s') == '2'
                ? DateTime.utc(
                    1899,
                    12,
                    30,
                  ).add(Duration(milliseconds: (numeric * 86400000).round()))
                : numeric;
          }
        }
        b.value(row, c.key, n, v, style);
      }
      newData.children.add(row);
      if (row.findElements('c').length > maxCols) {
        maxCols = row.findElements('c').length;
      }
    }
    final headingStyle = b.cells(header.value)['A']?.getAttribute('s');
    for (final row
        in newData
            .findElements('row')
            .where((r) => int.parse(r.getAttribute('r')!) > offset)) {
      final rn = int.parse(row.getAttribute('r')!);
      for (final cell in row.findElements('c')) {
        final column = cell.getAttribute('r')!.replaceAll(RegExp(r'\d'), '');
        final existing = b
            .cells(
              oldRows[rn == offset + 1 ? offset + 1 : offset + 2] ??
                  XmlElement(XmlName('row')),
            )[column]
            ?.getAttribute('s');
        if (cell.getAttribute('s') != '$style' &&
            (existing != null || rn == offset + 1 && headingStyle != null)) {
          cell.setAttribute('s', existing ?? headingStyle!);
        }
      }
    }
    if (offset > 0) {
      final rr = b.rows(XmlDocument([newData.copy()]));
      if (rr[4] != null) {
        b.value(
          rr[4]!,
          'A',
          4,
          'Refreshed ${report.data['generated_at']}. Period ${report.data['from']} to ${report.data['to']}.',
          style,
        );
      }
      if (rr[5] != null && name == 'Top Users') {
        b.value(
          rr[5]!,
          'A',
          5,
          report.hasRecordedUsage
              ? 'Highest screen views, App visits and recorded logins first; latest sign-in breaks ties.'
              : 'Usage ranking unavailable. Most recent sign-in first; this is not login frequency.',
          style,
        );
      }
      if (rr[5] != null && name == 'Guest Members') {
        b.value(
          rr[5]!,
          'A',
          5,
          report.guestMembers.isEmpty
              ? 'No member has the Guest App role in this snapshot.'
              : 'Members with the Guest App role in the current snapshot.',
          style,
        );
      }
      // rr belongs to its own document; replace only the retained note rows.
      for (final n in [4, 5]) {
        if (rr[n] != null) {
          final oldNote = newData
              .findElements('row')
              .where((r) => r.getAttribute('r') == '$n')
              .firstOrNull;
          if (oldNote != null) oldNote.replace(rr[n]!.copy());
        }
      }
    }
    final endRow =
        offset +
        (fresh.rows(generated).length < 2 ? 2 : fresh.rows(generated).length);
    if (fresh.rows(generated).length < 2) {
      final emptyRow = XmlElement(XmlName('row'), [
        XmlAttribute(XmlName('r'), '$endRow'),
      ]);
      for (var col = 0; col < maxCols; col++) {
        b.value(emptyRow, _col(col), endRow, null, style);
      }
      newData.children.add(emptyRow);
    }
    final oldData = dest.findAllElements('sheetData').first;
    oldData.replace(newData);
    dest
        .findAllElements('autoFilter')
        .firstOrNull
        ?.setAttribute('ref', 'A${offset + 1}:${_col(maxCols - 1)}$endRow');
    if (name == 'Guest Members') b.widths(dest, {21: 36, 22: 36, 23: 36});
    b.write(target, dest);
    for (final f in b.archive.files.where(
      (f) => f.name.startsWith('xl/tables/') && f.name.endsWith('.xml'),
    )) {
      final t = b.read(f.name);
      final table = t.rootElement.getAttribute('name') ?? '';
      if ({
            'Bookings': 'BookingsByType',
            'Screen views': 'ScreenViews',
            'Top Users': 'TopUsersTable',
            'Guest Members': 'GuestMembersTable',
          }[name] ==
          table) {
        final ref = 'A${offset + 1}:${_col(maxCols - 1)}$endRow';
        final columns = t.findAllElements('tableColumns').first;
        final existingColumns = columns
            .findElements('tableColumn')
            .map((c) => c.copy())
            .toList();
        final headingCells = fresh.cells(fresh.rows(generated)[1]!);
        columns.children.clear();
        for (var index = 0; index < maxCols; index++) {
          final column = index < existingColumns.length
              ? existingColumns[index]
              : XmlElement(XmlName('tableColumn'));
          column.setAttribute('id', '${index + 1}');
          column.setAttribute('name', fresh.cell(headingCells[_col(index)]));
          columns.children.add(column);
        }
        columns.setAttribute('count', '$maxCols');
        t.rootElement.setAttribute('ref', ref);
        t.findAllElements('autoFilter').firstOrNull?.setAttribute('ref', ref);
        b.write(f.name, t);
      }
    }
  }
  // Refresh the managed overview values, leaving all other notes/cells intact.
  final summaryPath = b.sheets['Overview'] ?? b.sheets['Summary'];
  if (summaryPath != null) {
    final s = b.read(summaryPath);
    for (final row in b.rows(s).entries) {
      final c = b.cells(row.value);
      final label = b.cell(c['A']);
      final labels = <String, String>{
        'Active members': 'active_members',
        'Active members with recorded explicit starting view':
            'explicit_start_choices',
        'Members explicitly choosing a starting view': 'explicit_start_choices',
        'Inactive members': 'inactive_members',
        'Active members ever signed in': 'ever_signed_in',
        'Active members without recorded sign-in': 'no_recorded_sign_in',
        'Active members without email': 'without_email',
        'Active members without telephone': 'without_phone',
        'Active members without phone': 'without_phone',
        'Bookings created during period': 'bookings_created',
        'Bookings created in period': 'bookings_created',
        'Recorded logins in period': 'recorded_logins',
        'Recorded logins in selected period': 'recorded_logins',
        'Recorded App visits in selected period': 'app_visits',
        'Recorded screen views in selected period': 'screen_views',
        'Recorded unique App users in period': 'active_app_users',
        'Latest sign-in falls in period (active members)':
            'last_sign_in_in_period',
        'Latest sign-in falls in period': 'last_sign_in_in_period',
      };
      if (labels.containsKey(label)) {
        b.value(row.value, 'B', row.key, report.summary[labels[label]], style);
      }
      if (label == 'Report date' || label == 'Generated (UTC)') {
        b.value(
          row.value,
          'B',
          row.key,
          DateTime.parse(report.data['generated_at']),
          style,
        );
      }
      if (label == 'Reporting period' || label == 'Activity period') {
        b.value(
          row.value,
          'B',
          row.key,
          '${report.data['from']} to ${report.data['to']}',
          style,
        );
      }
      if (label == 'Starting-view coverage' ||
          label == 'Explicit starting-view choices') {
        b.value(
          row.value,
          'B',
          row.key,
          'Future explicit choices recorded by this App only. Earlier device preferences and automatic defaults are not inferred. Latest recorded choice, outside the activity date filter.',
          style,
        );
      }
      if (label == 'Source') {
        b.value(
          row.value,
          'B',
          row.key,
          'Club database report snapshot ${report.data['generated_at']}. Contact details are for authorised Club administration.',
          style,
        );
      }
      if (label == 'Guest App role') {
        b.value(row.value, 'B', row.key, report.guestMembers.length, style);
      }
      if (label == 'App membership records') {
        b.value(row.value, 'B', row.key, report.members.length, style);
      }
      final matchLabels = {
        'Confirmed matches': currentRows
            .where((r) => b.cell(b.cells(r)['U']).startsWith('Matched'))
            .length,
        'App records not found in Club list': currentRows
            .where((r) => b.cell(b.cells(r)['U']) == 'Not found in Club list')
            .length,
        'App records needing matching review': currentRows
            .where((r) => b.cell(b.cells(r)['U']) == 'Needs matching review')
            .length,
        'Unmatched Club-list entries': sources.keys
            .where((k) => !usedSources.contains(k))
            .length,
        'Name variants matched with corroboration': currentRows
            .where((r) => b.cell(b.cells(r)['U']) == 'Matched — check name')
            .length,
      };
      if (matchLabels.containsKey(label)) {
        b.value(row.value, 'B', row.key, matchLabels[label], style);
      }
      for (final f in row.value.findAllElements('f')) {
        f.innerText = f.innerText.replaceAllMapped(
          RegExp(r"('Members'|Members)!\$(\w+)\$\d+:\$(\w+)\$\d+"),
          (m) => '${m[1]}!\$${m[2]}\$${h + 1}:\$${m[3]}\$$last',
        );
      }
    }
    b.write(summaryPath, s);
  }
  final metaDoc = XmlDocument([
    XmlElement(XmlName('report'), [
      XmlAttribute(XmlName('xmlns'), 'urn:totalleisure:club-report:v1'),
      XmlAttribute(XmlName('club_id'), report.data['club_id'].toString()),
      XmlAttribute(
        XmlName('generated_at'),
        report.data['generated_at'].toString(),
      ),
    ], keys),
  ]);
  b.write('customXml/bowls-report.xml', metaDoc);
  final rootRels = b.read('_rels/.rels');
  if (!rootRels
      .findAllElements('Relationship')
      .any((e) => e.getAttribute('Id') == 'bowlsReportMetadata')) {
    rootRels.rootElement.children.add(
      XmlElement(XmlName('Relationship'), [
        XmlAttribute(XmlName('Id'), 'bowlsReportMetadata'),
        XmlAttribute(
          XmlName('Type'),
          'http://schemas.openxmlformats.org/officeDocument/2006/relationships/customXml',
        ),
        XmlAttribute(XmlName('Target'), 'customXml/bowls-report.xml'),
      ]),
    );
  }
  b.write('_rels/.rels', rootRels);
  return b.save();
}
