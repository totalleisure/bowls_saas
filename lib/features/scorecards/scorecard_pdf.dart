import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'scorecard.dart';

String signatureSvg(Map<String, dynamic> signature) {
  final strokes = signature['strokes'] as List;
  final lines = strokes.map((stroke) {
    final points = (stroke as List)
        .map((p) => '${(p['x'] as num) * 1000},${(p['y'] as num) * 300}')
        .join(' ');
    return '<polyline points="$points" fill="none" stroke="#153f72" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>';
  }).join();
  return '<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="300" viewBox="0 0 1000 300">$lines</svg>';
}

const scorecardPdfEndsPerPage = 21;
const scorecardPdfPageFormat = PdfPageFormat(
  100 * PdfPageFormat.mm,
  210 * PdfPageFormat.mm,
);
int scorecardPdfPageCount(Scorecard card) =>
    (card.ends.length / scorecardPdfEndsPerPage).ceil().clamp(1, 1000000);

Future<Uint8List> scorecardPdf(
  Scorecard card, {
  bool includeAudit = false,
}) async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
  );
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );
  final pageCount = scorecardPdfPageCount(card);
  final title = card.title.trim().isEmpty ? 'Scorecard' : card.title;
  const mm = PdfPageFormat.mm;
  const width = 91 * mm;
  final red = PdfColor.fromHex('#fff4f3'), blue = PdfColor.fromHex('#f1f6fc');
  final ink = PdfColor.fromHex('#243b4d');
  String time(DateTime? value) => value == null
      ? '—'
      : '${value.toLocal().hour.toString().padLeft(2, '0')}:${value.toLocal().minute.toString().padLeft(2, '0')}';
  pw.Widget fitted(pw.Widget child, double height) => pw.SizedBox(
    height: height,
    child: pw.FittedBox(
      fit: pw.BoxFit.scaleDown,
      alignment: pw.Alignment.topLeft,
      // FittedBox divides by the child dimensions when painting. Empty text
      // can have zero height, so reserve a finite minimum before scaling.
      child: pw.ConstrainedBox(
        constraints: const pw.BoxConstraints(minHeight: 1),
        child: pw.SizedBox(width: width, child: child),
      ),
    ),
  );
  int runningA = card.handicapA, runningB = card.handicapB;
  pw.Widget signature(bool home) {
    final signed = home ? card.signatureA : card.signatureB;
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              home ? card.sideA : card.sideB,
              maxLines: 1,
              style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(
              height: 7 * mm,
              child: signed == null
                  ? pw.Align(
                      alignment: pw.Alignment.centerLeft,
                      child: pw.Text(
                        'Not signed',
                        style: const pw.TextStyle(fontSize: 6),
                      ),
                    )
                  : pw.SvgImage(svg: signatureSvg(signed)),
            ),
            pw.Text(
              signed == null
                  ? 'Signature'
                  : '${signed['name']} · ${time(DateTime.parse(signed['at'] as String))}',
              maxLines: 1,
              style: const pw.TextStyle(fontSize: 5.5),
            ),
          ],
        ),
      ),
    );
  }

  for (var page = 0; page < pageCount; page++) {
    final first = page * scorecardPdfEndsPerPage;
    final rows = <List<String>>[
      [
        page == 0 ? '${card.handicapA}' : '–',
        '$runningA',
        page == 0 ? '0' : 'B/F',
        page == 0 ? '${card.handicapB}' : '–',
        '$runningB',
      ],
    ];
    for (var offset = 0; offset < scorecardPdfEndsPerPage; offset++) {
      final index = first + offset;
      if (index < card.ends.length) {
        final e = card.ends[index];
        runningA += e['a'] as int? ?? 0;
        runningB += e['b'] as int? ?? 0;
        String shots(dynamic n) => n == null
            ? '…'
            : n == 0
            ? '–'
            : '$n';
        rows.add([
          shots(e['a']),
          '$runningA',
          '${index + 1}',
          shots(e['b']),
          '$runningB',
        ]);
      } else {
        rows.add(['', '', '${index + 1}', '', '']);
      }
    }
    doc.addPage(
      pw.Page(
        pageFormat: scorecardPdfPageFormat,
        margin: const pw.EdgeInsets.all(4.5 * mm),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // Every card page uses the same bounded header and column geometry.
            pw.SizedBox(
              height: 60 * mm,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  fitted(
                    pw.Text(
                      title,
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: ink,
                      ),
                    ),
                    12 * mm,
                  ),
                  fitted(
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        pw.Text(
                          '${card.date} · ${card.venue.isEmpty ? 'Venue not specified' : card.venue} · Rink ${card.rink.isEmpty ? '—' : card.rink}',
                          style: const pw.TextStyle(fontSize: 7.5),
                        ),
                        pw.Text(
                          '${card.format} · ${card.woods} woods · ${card.scoring == '100up' ? '100 Up' : 'Shots'} · Target ${card.target ?? '—'} · ${card.maxEnds ?? 'Unlimited'} ends',
                          style: const pw.TextStyle(fontSize: 7),
                        ),
                        pw.Text(
                          'Playing time: ${card.durationMinutes == null ? 'untimed' : '${card.durationMinutes} min'} · Last jack: ${card.lastJackMinutes == null ? '—' : '${card.lastJackMinutes} min'}',
                          style: const pw.TextStyle(fontSize: 7),
                        ),
                        pw.Text(
                          'Start ${time(card.startedAt)} · Finish ${time(card.finishedAt)} · Marker: ${card.marker.isEmpty ? '—' : card.marker}',
                          style: const pw.TextStyle(fontSize: 7),
                        ),
                      ],
                    ),
                    17 * mm,
                  ),
                  fitted(
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            for (final home in [true, false])
                              pw.Expanded(
                                child: pw.Container(
                                  padding: const pw.EdgeInsets.all(4),
                                  decoration: pw.BoxDecoration(
                                    color: home ? red : blue,
                                    border: pw.Border.all(
                                      color: PdfColors.blueGrey,
                                      width: .4,
                                    ),
                                  ),
                                  child: pw.Column(
                                    crossAxisAlignment:
                                        pw.CrossAxisAlignment.stretch,
                                    children: [
                                      pw.Text(
                                        home ? card.sideA : card.sideB,
                                        style: pw.TextStyle(
                                          fontSize: 8,
                                          fontWeight: pw.FontWeight.bold,
                                        ),
                                      ),
                                      pw.Text(
                                        home ? card.playersA : card.playersB,
                                        style: const pw.TextStyle(fontSize: 7),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (card.playerNotes.isNotEmpty)
                          pw.Text(
                            'Notes: ${card.playerNotes}',
                            style: const pw.TextStyle(fontSize: 6.5),
                          ),
                      ],
                    ),
                    27 * mm,
                  ),
                  pw.Text(
                    '${card.complete ? 'Finished' : 'In progress'} · ${card.sideA} ${card.totalA} : ${card.totalB} ${card.sideB}',
                    maxLines: 1,
                    style: pw.TextStyle(
                      fontSize: 7,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.blueGrey, width: .4),
              columnWidths: const {
                0: pw.FlexColumnWidth(),
                1: pw.FlexColumnWidth(),
                2: pw.FixedColumnWidth(22),
                3: pw.FlexColumnWidth(),
                4: pw.FlexColumnWidth(),
              },
              children: [
                pw.TableRow(
                  children: [
                    for (final entry in [
                      'Shots',
                      'Total',
                      'End',
                      'Shots',
                      'Total',
                    ].asMap().entries)
                      pw.Container(
                        height: 6 * mm,
                        color: entry.key < 2
                            ? red
                            : entry.key > 2
                            ? blue
                            : PdfColors.grey100,
                        alignment: pw.Alignment.center,
                        child: pw.Text(
                          entry.value,
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                for (final row in rows)
                  pw.TableRow(
                    children: [
                      for (var col = 0; col < 5; col++)
                        pw.Container(
                          height: 5 * mm,
                          color: col < 2
                              ? red
                              : col > 2
                              ? blue
                              : PdfColors.white,
                          alignment: pw.Alignment.center,
                          child: pw.Text(
                            row[col],
                            style: pw.TextStyle(
                              fontSize: 8.5,
                              fontWeight: col == 2
                                  ? pw.FontWeight.bold
                                  : pw.FontWeight.normal,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            pw.Spacer(),
            pw.Container(
              height: 14 * mm,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.blueGrey, width: .4),
              ),
              child: pw.Row(
                children: [
                  signature(true),
                  pw.Container(width: .4, color: PdfColors.blueGrey),
                  signature(false),
                ],
              ),
            ),
            pw.SizedBox(height: 2 * mm),
            pw.Text(
              'Card ${page + 1}/$pageCount · Ends ${first + 1}–${first + 21} · Rev ${card.revision} · ${card.id.substring(0, 8)}',
              style: const pw.TextStyle(fontSize: 6),
            ),
            pw.Text(
              'Local scorecard · not an official confirmed competition result',
              style: const pw.TextStyle(fontSize: 5.5),
            ),
          ],
        ),
      ),
    );
  }
  if (includeAudit && card.history.isNotEmpty) {
    doc.addPage(
      pw.MultiPage(
        pageFormat: scorecardPdfPageFormat,
        margin: const pw.EdgeInsets.all(4.5 * mm),
        maxPages: 1000,
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'AUDIT HISTORY · ${card.date}',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
            pw.Row(
              children: [
                for (final home in [true, false])
                  pw.Expanded(
                    child: pw.Container(
                      color: home ? red : blue,
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text(
                        home ? card.sideA : card.sideB,
                        style: const pw.TextStyle(fontSize: 7),
                      ),
                    ),
                  ),
              ],
            ),
            pw.SizedBox(height: 8),
          ],
        ),
        footer: (context) => pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Container(
              height: 14 * mm,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.blueGrey, width: .4),
              ),
              child: pw.Row(
                children: [
                  signature(true),
                  pw.Container(width: .4, color: PdfColors.blueGrey),
                  signature(false),
                ],
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Audit page ${context.pageNumber - pageCount} · Rev ${card.revision} · ${card.id.substring(0, 8)}',
              style: const pw.TextStyle(fontSize: 6),
            ),
          ],
        ),
        build: (_) => [
          for (final e in card.history)
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 6),
              padding: const pw.EdgeInsets.only(bottom: 4),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.grey300, width: .4),
                ),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Text(
                    '${e['at']} · Rev ${e['revision']}',
                    style: const pw.TextStyle(fontSize: 6),
                  ),
                  pw.Text(
                    '${e['action']}',
                    style: pw.TextStyle(
                      fontSize: 7.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if (e['before'] is Map &&
                      (e['before'] as Map).containsKey('a'))
                    pw.Text(
                      'Score ${e['before']['a'] ?? "—"} : ${e['before']['b'] ?? "—"}  to  ${e['after']['a']} : ${e['after']['b']}',
                      style: const pw.TextStyle(fontSize: 7),
                    )
                  else if (e['after'] != null)
                    pw.Text(
                      '${e['after']}',
                      style: const pw.TextStyle(fontSize: 7),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
  return doc.save();
}
