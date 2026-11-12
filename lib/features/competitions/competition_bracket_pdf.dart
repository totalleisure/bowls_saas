import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'competition_repository.dart';

enum CompetitionPrintLayout { readableA4, wholeA3, compactA4 }

enum CompetitionPrintOrientation { portrait, landscape }

PdfPageFormat competitionPageFormat(
  CompetitionPrintLayout layout,
  CompetitionPrintOrientation orientation,
) {
  final paper = layout == CompetitionPrintLayout.wholeA3
      ? PdfPageFormat.a3
      : PdfPageFormat.a4;
  return orientation == CompetitionPrintOrientation.landscape
      ? paper.landscape
      : paper.portrait;
}

String competitionRoundDeadline(CompetitionRow round) {
  final date = DateTime.tryParse('${round['play_by']}');
  if (date != null) return 'Play by ${DateFormat('d MMM yyyy').format(date)}';
  final note = (round['rule_overrides'] as Map?)?['rules']?.toString().trim();
  if (note == null || note.isEmpty) return 'Play-by date not set';
  final prefix = '${round['name']}: ';
  return note.startsWith(prefix) ? note.substring(prefix.length) : note;
}

class CompetitionBracketSheet {
  final int startRound, endRound, firstMatch, matchCount;
  final String title;
  const CompetitionBracketSheet(
    this.startRound,
    this.endRound,
    this.firstMatch,
    this.matchCount,
    this.title,
  );
}

List<CompetitionBracketSheet> competitionBracketSheets(
  CompetitionData data,
  CompetitionPrintLayout layout,
) {
  final rounds = data.orderedRounds;
  if (rounds.isEmpty) return [];
  final baseCount = data.matchesForRound(rounds.first['id'].toString()).length;
  if (layout != CompetitionPrintLayout.readableA4 && baseCount > 32) {
    throw ArgumentError(
      'Use readable A4 sections for draws larger than 64 entries.',
    );
  }
  if (layout != CompetitionPrintLayout.readableA4 || rounds.length == 1) {
    return [
      CompetitionBracketSheet(
        0,
        rounds.length - 1,
        0,
        baseCount,
        'Complete draw',
      ),
    ];
  }
  final sheets = <CompetitionBracketSheet>[];
  var start = 0;
  while (start < rounds.length - 1) {
    final count = baseCount >> start;
    final end = math.min(start + 3, rounds.length - 1);
    final pages = (count / 8).ceil();
    for (var offset = 0; offset < count; offset += 8) {
      final title = start == 0 && pages == 4
          ? 'Quarter ${offset ~/ 8 + 1} of 4'
          : end == rounds.length - 1 && pages == 1 && start > 0
          ? 'Final stages'
          : pages == 1
          ? 'Complete draw'
          : 'Draw section ${offset ~/ 8 + 1} of $pages';
      sheets.add(
        CompetitionBracketSheet(
          start,
          end,
          offset,
          math.min(8, count - offset),
          title,
        ),
      );
    }
    if (end == rounds.length - 1) break;
    start = end;
  }
  return sheets;
}

Future<pw.ThemeData>? _embeddedTheme;
Future<pw.ThemeData> _fontTheme() => _embeddedTheme ??= () async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
  );
  return pw.ThemeData.withFont(
    base: regular,
    bold: bold,
    italic: regular,
    boldItalic: bold,
  );
}();

String competitionMatchCode(CompetitionData data, CompetitionRow match) {
  final rounds = data.orderedRounds;
  final r = rounds.indexWhere((r) => r['id'] == match['round_id']);
  final remaining = rounds.length - r;
  final prefix = remaining == 1
      ? 'F'
      : remaining == 2
      ? 'SF'
      : remaining == 3
      ? 'QF'
      : '${rounds[r]['name']}'.toLowerCase().contains('prelim')
      ? 'P'
      : 'R${1 << remaining}-';
  return '$prefix${match['match_number']}';
}

Future<Uint8List> buildCompetitionDrawPdf(
  CompetitionData data, {
  CompetitionPrintLayout layout = CompetitionPrintLayout.readableA4,
  CompetitionPrintOrientation orientation =
      CompetitionPrintOrientation.landscape,
  bool blankWinnerLabels = false,
  bool printBackground = false,
  bool printRules = false,
  PdfPageFormat? pageFormat,
}) async {
  final pdf = pw.Document(
    theme: await _fontTheme(),
    title: '${data.competition['name']} — competition draw',
  );
  final background = printBackground
      ? pw.MemoryImage(
          (await rootBundle.load(
            'assets/images/blank_bg_desktop_2.png',
          )).buffer.asUint8List(),
        )
      : null;
  final badge = competitionUsesLewishamBadge(data)
      ? pw.MemoryImage(
          (await rootBundle.load(
            'assets/images/Club_Badge_2.png',
          )).buffer.asUint8List(),
        )
      : null;
  final rules = competitionPrintRules(data);
  final sheets = competitionBracketSheets(data, layout);
  for (var page = 0; page < sheets.length; page++) {
    final sheet = sheets[page];
    final format = pageFormat ?? competitionPageFormat(layout, orientation);
    pdf.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(
          pageFormat: format,
          margin: pw.EdgeInsets.fromLTRB(
            math.max(26, format.marginLeft),
            math.max(26, format.marginTop),
            math.max(26, format.marginRight),
            math.max(26, format.marginBottom),
          ),
          buildBackground: background == null
              ? null
              : (_) => pw.FullPage(
                  ignoreMargins: true,
                  child: pw.Opacity(
                    opacity: 0.07,
                    child: pw.Image(background, fit: pw.BoxFit.cover),
                  ),
                ),
        ),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      if (badge != null) ...[
                        pw.Image(
                          badge,
                          width: 40,
                          height: 40,
                          fit: pw.BoxFit.contain,
                        ),
                        pw.SizedBox(width: 10),
                      ],
                      pw.Expanded(
                        child: pw.Text(
                          '${data.competition['name']}',
                          style: pw.TextStyle(
                            fontSize: 17,
                            fontWeight: pw.FontWeight.bold,
                            color: const PdfColor.fromInt(0xff163960),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (printRules && rules.isNotEmpty) ...[
                  pw.SizedBox(width: 14),
                  pw.Container(
                    width:
                        (format.width -
                            math.max(26, format.marginLeft) -
                            math.max(26, format.marginRight)) *
                        .48,
                    height: 76,
                    padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: PdfColors.blueGrey700,
                        width: .7,
                      ),
                    ),
                    child: pw.FittedBox(
                      fit: pw.BoxFit.scaleDown,
                      alignment: pw.Alignment.topLeft,
                      child: pw.SizedBox(
                        width:
                            (format.width -
                                    math.max(26, format.marginLeft) -
                                    math.max(26, format.marginRight)) *
                                .48 -
                            14,
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'Competition rules',
                              style: pw.TextStyle(
                                fontSize: 9,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            pw.SizedBox(height: 3),
                            pw.Text(
                              rules,
                              style: const pw.TextStyle(fontSize: 9),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${data.competition['season']}  ·  ${sheet.title}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
                pw.Text(
                  'Page ${page + 1} of ${sheets.length}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Expanded(
              child: pw.LayoutBuilder(
                builder: (_, constraints) =>
                    layout == CompetitionPrintLayout.compactA4
                    ? _compactGrid(
                        data,
                        constraints!.maxWidth,
                        constraints.maxHeight,
                        blankWinnerLabels,
                      )
                    : _bracket(
                        data,
                        sheet,
                        constraints!.maxWidth,
                        constraints.maxHeight,
                        blankWinnerLabels,
                      ),
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              layout == CompetitionPrintLayout.compactA4
                  ? 'Read top to bottom; winners advance to the next column. Blank spaces can be completed by hand.'
                  : 'Read top to bottom, then follow the lines to the right. Match references continue between sheets. Scores are blank until recorded.',
              style: const pw.TextStyle(
                fontSize: 8,
                color: PdfColors.blueGrey700,
              ),
            ),
          ],
        ),
      ),
    );
  }
  if (sheets.isEmpty) {
    pdf.addPage(
      pw.Page(build: (_) => pw.Text('Create a draw before printing.')),
    );
  }
  return pdf.save();
}

class _Box {
  final double left, top, width, height;
  final CompetitionRow match;
  const _Box(this.left, this.top, this.width, this.height, this.match);
}

pw.Widget _bracket(
  CompetitionData data,
  CompetitionBracketSheet sheet,
  double width,
  double height,
  bool blankWinnerLabels,
) {
  final rounds = data.orderedRounds;
  final allById = {for (final m in data.matches) m['id'].toString(): m};
  var start = sheet.startRound;
  while (start < sheet.endRound) {
    final first = sheet.firstMatch >> (start - sheet.startRound);
    final count = math.max(1, sheet.matchCount >> (start - sheet.startRound));
    if (data
        .matchesForRound(rounds[start]['id'].toString())
        .any(
          (m) =>
              (m['match_number'] as int) > first &&
              (m['match_number'] as int) <= first + count &&
              m['status'] != 'bye',
        )) {
      break;
    }
    start++;
  }
  final columns = sheet.endRound - start + 1;
  const gap = 22.0, headerHeight = 55.0;
  final boxWidth = (width - gap * (columns - 1)) / columns;
  final unit = (height - headerHeight) / sheet.matchCount;
  final compact = unit < 46;
  final boxHeight = math.min(42.0, math.max(17.0, unit - 3));
  final positions = <String, _Box>{};
  for (var r = start; r <= sheet.endRound; r++) {
    final scale = 1 << (r - sheet.startRound);
    final first = sheet.firstMatch ~/ scale;
    final count = math.max(1, sheet.matchCount ~/ scale);
    for (final m in data.matchesForRound(rounds[r]['id'].toString())) {
      final index = (m['match_number'] as int) - 1;
      if (index < first || index >= first + count || m['status'] == 'bye') {
        continue;
      }
      final y = ((index + .5) * scale - sheet.firstMatch) * unit;
      positions[m['id'].toString()] = _Box(
        (r - start) * (boxWidth + gap),
        headerHeight + y - boxHeight / 2,
        boxWidth,
        boxHeight,
        m,
      );
    }
  }
  return pw.Stack(
    children: [
      pw.Positioned(
        left: 0,
        top: 0,
        child: pw.CustomPaint(
          size: PdfPoint(width, height),
          painter: (canvas, size) {
            canvas.setStrokeColor(const PdfColor.fromInt(0xff607c99));
            canvas.setLineWidth(.7);
            for (final box in positions.values) {
              for (final side in ['a', 'b']) {
                final source = positions[box.match['side_${side}_source_id']];
                if (source == null) continue;
                final sy = source.top + source.height / 2;
                final ty = box.top + box.height * (side == 'a' ? .34 : .77);
                final elbow = source.left + source.width + gap / 2;
                canvas.moveTo(source.left + source.width, height - sy);
                canvas.lineTo(elbow, height - sy);
                canvas.lineTo(elbow, height - ty);
                canvas.lineTo(box.left, height - ty);
                canvas.strokePath();
              }
            }
          },
        ),
      ),
      for (var r = start; r <= sheet.endRound; r++)
        pw.Positioned(
          left: (r - start) * (boxWidth + gap),
          top: 0,
          child: pw.SizedBox(
            width: boxWidth,
            height: headerHeight - 6,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '${rounds[r]['name']}',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: const PdfColor.fromInt(0xff163960),
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  competitionRoundDeadline(rounds[r]),
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ],
            ),
          ),
        ),
      for (final box in positions.values)
        pw.Positioned(
          left: box.left,
          top: box.top,
          child: pw.SizedBox(
            width: box.width,
            height: box.height,
            child: _matchBox(
              data,
              box.match,
              allById,
              compact ? 7.8 : 9,
              compact,
              blankWinnerLabels,
            ),
          ),
        ),
    ],
  );
}

pw.Widget _matchBox(
  CompetitionData data,
  CompetitionRow match,
  Map<String, CompetitionRow> allById,
  double size,
  bool compact,
  bool blankWinnerLabels,
) {
  String name(String side) => competitionPrintedSide(
    data,
    match,
    side,
    blankWinnerLabels: blankWinnerLabels,
  );

  pw.Widget row(String side) => pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5),
      decoration: side == 'b'
          ? const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(color: PdfColors.blueGrey100, width: .4),
              ),
            )
          : null,
      child: pw.Row(
        children: [
          pw.Expanded(
            child: name(side).isEmpty
                ? pw.SizedBox()
                : pw.FittedBox(
                    fit: pw.BoxFit.scaleDown,
                    alignment: pw.Alignment.centerLeft,
                    child: pw.Text(
                      '${compact && side == 'a' ? '${competitionMatchCode(data, match)}  ' : ''}${name(side)}',
                      style: pw.TextStyle(
                        fontSize: size,
                        fontWeight:
                            match['winner_entry_id'] != null &&
                                match['winner_entry_id'] ==
                                    match['side_${side}_entry_id']
                            ? pw.FontWeight.bold
                            : pw.FontWeight.normal,
                      ),
                    ),
                  ),
          ),
          if (match['score_$side'] != null ||
              (match['result_kind'] == 'walkover' &&
                  match['winner_entry_id'] == match['side_${side}_entry_id']))
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 4),
              child: pw.Text(
                match['result_kind'] == 'walkover'
                    ? 'W/O'
                    : '${match['score_$side']}',
                style: pw.TextStyle(
                  fontSize: size,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    ),
  );
  return pw.Container(
    decoration: pw.BoxDecoration(
      color: PdfColors.white,
      border: pw.Border.all(
        color: const PdfColor.fromInt(0xff7e98b1),
        width: .65,
      ),
      borderRadius: pw.BorderRadius.circular(3),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (!compact)
          pw.Container(
            height: 11,
            padding: const pw.EdgeInsets.symmetric(horizontal: 5),
            color: const PdfColor.fromInt(0xffeaf1f8),
            child: pw.Text(
              competitionMatchCode(data, match),
              style: pw.TextStyle(
                fontSize: 7,
                fontWeight: pw.FontWeight.bold,
                color: const PdfColor.fromInt(0xff163960),
              ),
            ),
          ),
        row('a'),
        row('b'),
      ],
    ),
  );
}

String competitionPrintedSide(
  CompetitionData data,
  CompetitionRow match,
  String side, {
  bool blankWinnerLabels = false,
  bool includeScore = false,
}) {
  final id = match['side_${side}_entry_id'] as String?;
  if (id != null) {
    final name = data.entrant(id);
    if (includeScore &&
        match['result_kind'] == 'walkover' &&
        match['winner_entry_id'] == id) {
      return '$name  (W/O)';
    }
    final score = match['score_$side'];
    return '$name${includeScore && score != null ? '  ($score)' : ''}';
  }
  if (blankWinnerLabels || match['side_${side}_kind'] == 'bye') return '';
  final source = data.matches
      .where((m) => m['id'] == match['side_${side}_source_id'])
      .firstOrNull;
  return source == null
      ? 'Awaiting entrant'
      : 'Winner of ${competitionMatchCode(data, source)}';
}

pw.Widget _compactGrid(
  CompetitionData data,
  double width,
  double height,
  bool blankWinnerLabels,
) {
  final rounds = data.orderedRounds;
  final slots = data.matchesForRound(rounds.first['id'].toString()).length * 2;
  const header = 43.0;
  final unit = (height - header) / slots;
  final firstWidth = width * (rounds.length == 1 ? 1 : .34);
  final otherWidth = rounds.length == 1
      ? 0.0
      : (width - firstWidth) / (rounds.length - 1);
  final children = <pw.Widget>[];
  for (var r = 0; r < rounds.length; r++) {
    final left = r == 0 ? 0.0 : firstWidth + (r - 1) * otherWidth;
    final columnWidth = r == 0 ? firstWidth : otherWidth;
    final scale = 1 << r;
    children.add(
      pw.Positioned(
        left: left,
        top: 0,
        child: pw.Container(
          width: columnWidth,
          height: header,
          padding: const pw.EdgeInsets.all(3),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: .5)),
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(
                '${rounds[r]['name']}',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                competitionRoundDeadline(rounds[r]),
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 7),
              ),
            ],
          ),
        ),
      ),
    );
    for (final match in data.matchesForRound(rounds[r]['id'].toString())) {
      final index = (match['match_number'] as int) - 1;
      for (var sideIndex = 0; sideIndex < 2; sideIndex++) {
        final side = sideIndex == 0 ? 'a' : 'b';
        final text = match['status'] == 'bye'
            ? ''
            : competitionPrintedSide(
                data,
                match,
                side,
                blankWinnerLabels: blankWinnerLabels,
                includeScore: true,
              );
        children.add(
          pw.Positioned(
            left: left,
            top: header + (index * 2 + sideIndex) * scale * unit,
            child: pw.Container(
              width: columnWidth,
              height: scale * unit,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 3,
                vertical: 1,
              ),
              alignment: pw.Alignment.centerLeft,
              decoration: pw.BoxDecoration(
                color: index.isOdd ? PdfColors.grey200 : null,
                border: pw.Border.all(width: .45, color: PdfColors.grey700),
              ),
              child: text.isEmpty
                  ? pw.SizedBox()
                  : r > 0
                  ? pw.Text(
                      text,
                      maxLines: 3,
                      style: const pw.TextStyle(fontSize: 8.5),
                    )
                  : pw.FittedBox(
                      fit: pw.BoxFit.scaleDown,
                      alignment: pw.Alignment.centerLeft,
                      child: pw.Text(
                        text,
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ),
            ),
          ),
        );
      }
    }
  }
  return pw.Stack(children: children);
}

String competitionPrintRules(CompetitionData data) {
  final settings = data.competition['settings'] as Map? ?? const {};
  final rules = settings['rules']?.toString().trim() ?? '';
  final general = rules.isNotEmpty
      ? rules
      : settings['scoring']?.toString().trim() ?? '';
  final handicapRule = settings['handicap']?.toString().trim() ?? '';
  return [
    if (general.isNotEmpty) general,
    if (settings['handicap_mode'] == 'team_difference' &&
        handicapRule.isNotEmpty &&
        !general.contains(handicapRule))
      handicapRule,
    for (final round in data.orderedRounds)
      if (((round['rule_overrides'] as Map?)?['rules']?.toString().trim() ?? '')
          .isNotEmpty)
        "${round['name']}: ${(round['rule_overrides'] as Map)['rules']}",
  ].join('\n');
}

bool competitionUsesLewishamBadge(CompetitionData data) =>
    data.competition['club_id'] == '8ae87bbe-cb16-4330-a5b0-e62366479f07';
