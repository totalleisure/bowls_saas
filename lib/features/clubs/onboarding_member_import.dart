import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

class OnboardingMember {
  const OnboardingMember({
    required this.firstName,
    required this.surname,
    this.email = '',
    this.phone = '',
    this.role = 'member',
    this.active = false,
  });
  final String firstName, surname, email, phone, role;
  final bool active;
  String get name => '$firstName $surname'.trim();
  String get emailKey => email.trim().toLowerCase();
  String get nameKey => name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

enum MemberImportStatus {
  ready,
  existing,
  duplicate,
  possibleDuplicate,
  needsAttention,
}

class MemberImportRow {
  const MemberImportRow(this.row, this.member, this.status, this.note);
  final int row;
  final OnboardingMember member;
  final MemberImportStatus status;
  final String note;
  bool get canImport => status == MemberImportStatus.ready;
}

/// Reads only literal member data. No formula evaluation, account creation or invitations.
List<List<String>> memberSpreadsheetRows(Uint8List bytes, String filename) {
  if (bytes.length > 5 * 1024 * 1024) {
    throw const FormatException('Choose a member file smaller than 5 MB.');
  }
  if (!filename.toLowerCase().endsWith('.xlsx')) {
    return memberDelimitedRows(utf8.decode(bytes).replaceFirst('\uFEFF', ''));
  }
  final archive = ZipDecoder().decodeBytes(bytes);
  if (archive.files.fold<int>(0, (n, f) => n + f.size) > 30 * 1024 * 1024) {
    throw const FormatException('The workbook is too large.');
  }
  XmlDocument read(String path) {
    final f = archive.findFile(path);
    if (f == null) {
      throw const FormatException('The member workbook could not be read.');
    }
    return XmlDocument.parse(utf8.decode(f.content as List<int>));
  }

  Iterable<XmlElement> elements(XmlNode node, String name) => node.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == name);
  final sheet = elements(
    read('xl/workbook.xml'),
    'sheet',
  ).where((s) => s.getAttribute('name') == 'Members').firstOrNull;
  if (sheet == null) {
    throw const FormatException('Use a workbook with a Members sheet.');
  }
  final relationId = sheet.attributes
      .where((a) => a.name.local == 'id')
      .firstOrNull
      ?.value;
  final relation = elements(
    read('xl/_rels/workbook.xml.rels'),
    'Relationship',
  ).where((r) => r.getAttribute('Id') == relationId).firstOrNull;
  final target = relation?.getAttribute('Target');
  if (target == null || relation?.getAttribute('TargetMode') == 'External') {
    throw const FormatException('The Members sheet could not be located.');
  }
  final path = Uri.parse(
    'file:///xl/workbook.xml',
  ).resolve(target).path.substring(1);
  final strings = archive.findFile('xl/sharedStrings.xml') == null
      ? <String>[]
      : elements(
          read('xl/sharedStrings.xml'),
          'si',
        ).map((s) => elements(s, 't').map((t) => t.innerText).join()).toList();
  final result = <List<String>>[];
  for (final row in elements(read(path), 'row')) {
    if (result.length > 5000) {
      throw const FormatException('Import at most 5,000 members at a time.');
    }
    final values = List.filled(4, '');
    for (final cell in row.childElements.where((e) => e.name.local == 'c')) {
      final ref = cell.getAttribute('r') ?? '';
      final column = RegExp(r'^[A-Z]+').firstMatch(ref)?.group(0) ?? '';
      var index = 0;
      for (final ch in column.codeUnits) {
        index = index * 26 + ch - 64;
      }
      index--;
      if (index < 0) continue;
      if (index >= 4) {
        if (cell.innerText.trim().isNotEmpty) {
          throw const FormatException(
            'Use only the four columns in the member template.',
          );
        }
        continue;
      }
      if (elements(cell, 'f').isNotEmpty) {
        throw FormatException(
          'Cell $ref contains a formula. Paste its value before importing.',
        );
      }
      final type = cell.getAttribute('t');
      final raw = elements(cell, 'v').firstOrNull?.innerText ?? '';
      if (type == 's') {
        final i = int.tryParse(raw);
        if (i == null || i < 0 || i >= strings.length) {
          throw const FormatException(
            'The workbook contains an unreadable text cell.',
          );
        }
        values[index] = strings[i];
      } else if (type == 'inlineStr') {
        values[index] = elements(cell, 't').map((e) => e.innerText).join();
      } else {
        values[index] = raw;
      }
    }
    result.add(values);
  }
  return result;
}

List<List<String>> memberDelimitedRows(String text) {
  final delimiter = text.split(RegExp(r'[\r\n]')).first.contains('\t')
      ? '\t'
      : ',';
  final rows = <List<String>>[];
  var row = <String>[], field = StringBuffer(), quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (ch == '"') {
      if (quoted && i + 1 < text.length && text[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (ch == delimiter && !quoted) {
      row.add(field.toString());
      field = StringBuffer();
    } else if ((ch == '\n' || ch == '\r') && !quoted) {
      row.add(field.toString());
      rows.add(row);
      row = [];
      field = StringBuffer();
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
    } else {
      field.write(ch);
    }
  }
  if (quoted) {
    throw const FormatException(
      'A quoted cell is incomplete. Check the pasted rows.',
    );
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  if (rows.length > 5001) {
    throw const FormatException('Import at most 5,000 members at a time.');
  }
  return rows;
}

List<MemberImportRow> reviewOnboardingMembers(
  List<List<String>> rows,
  List<OnboardingMember> existing,
) {
  if (rows.isEmpty) throw const FormatException('The member list is empty.');
  String norm(String v) =>
      v.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final headers = rows.first.map(norm).toList();
  final first = headers.indexOf('firstname'), last = headers.indexOf('surname');
  if (first < 0 || last < 0) {
    throw const FormatException(
      'Keep the template headings, including First name and Surname.',
    );
  }
  if (headers.any((h) => h.contains('password'))) {
    throw const FormatException(
      'Remove password columns. No passwords are needed for onboarding.',
    );
  }
  String value(List<String> row, String header) {
    final i = headers.indexOf(header);
    return i < 0 || i >= row.length ? '' : row[i].trim();
  }

  final seenEmail = <String>{}, seenName = <String>{};
  final result = <MemberImportRow>[];
  for (var i = 1; i < rows.length; i++) {
    final row = rows[i];
    if (row.every((v) => v.trim().isEmpty)) continue;
    final m = OnboardingMember(
      firstName: value(row, 'firstname'),
      surname: value(row, 'surname'),
      email: value(row, 'email'),
      phone: value(row, 'telephone'),
    );
    var status = MemberImportStatus.ready;
    var note = m.email.isEmpty
        ? 'No email: import without an email invitation.'
        : 'Ready to import.';
    if (m.firstName.isEmpty || m.surname.isEmpty) {
      status = MemberImportStatus.needsAttention;
      note = 'First name and surname are required.';
    } else if (m.email.isNotEmpty &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(m.email)) {
      status = MemberImportStatus.needsAttention;
      note = 'Check the email address.';
    } else if (existing.any(
      (e) => m.emailKey.isNotEmpty && e.emailKey == m.emailKey,
    )) {
      status = MemberImportStatus.existing;
      note = 'Already added to this setup list. No duplicate will be added.';
    } else if (m.emailKey.isNotEmpty && seenEmail.contains(m.emailKey)) {
      status = MemberImportStatus.duplicate;
      note = 'Repeated email in this file.';
    } else if (existing.any((e) => e.nameKey == m.nameKey) ||
        seenName.contains(m.nameKey)) {
      status = MemberImportStatus.possibleDuplicate;
      note = 'A matching name needs a check before import.';
    }
    if (status == MemberImportStatus.ready ||
        status == MemberImportStatus.existing) {
      if (m.emailKey.isNotEmpty) seenEmail.add(m.emailKey);
      seenName.add(m.nameKey);
    }
    result.add(MemberImportRow(i + 1, m, status, note));
  }
  return result;
}

List<OnboardingMember> applyReviewedMembers(
  List<OnboardingMember> existing,
  List<MemberImportRow> review,
  Set<int> selected,
) => [
  ...existing,
  for (final row in review)
    if (row.canImport &&
        selected.contains(row.row) &&
        !existing.any(
          (e) =>
              row.member.emailKey.isNotEmpty &&
              e.emailKey == row.member.emailKey,
        ))
      row.member,
];
