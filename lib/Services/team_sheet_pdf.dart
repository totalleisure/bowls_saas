import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Simple DTOs you can build from Supabase rows
class TeamSheetRink {
  final int rinkNumber;
  final List<String> players;
  final String? homeRinkLabel;

  TeamSheetRink({
    required this.rinkNumber,
    required this.players,
    this.homeRinkLabel,
  });
}

class TeamSheetData {
  final String clubName;
  final String opponentName;
  final DateTime startAt;
  final bool isHome;
  final String section; // e.g. mixed/men/ladies
  final int rinksRequired;
  final int playersPerRink; // 2/3/4
  final String dress; // optional
  final String? mealInfo; // optional
  final String? notes; // optional (friendly triples etc.)
  final String? captainName; // optional
  final String? viceName; // optional
  final List<TeamSheetRink> rinks; // up to 6
  final List<String> reserves;

  // branding
  final int primaryColor;   // 0xFF......
  final int secondaryColor; // 0xFF......
  final Uint8List? logoBytes; // optional (download earlier or from storage)

  TeamSheetData({
    required this.clubName,
    required this.opponentName,
    required this.startAt,
    required this.isHome,
    required this.section,
    required this.rinksRequired,
    required this.playersPerRink,
    required this.dress,
    required this.rinks,
    required this.reserves,
    required this.primaryColor,
    required this.secondaryColor,
    this.logoBytes,
    this.mealInfo,
    this.notes,
    this.captainName,
    this.viceName,
  });
}

String _two(int n) => n.toString().padLeft(2, '0');
String _fmtDate(DateTime dt) {
  // UK-ish: Sat 07 Mar 2026
  const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  final d = dt.toLocal();
  final dow = days[d.weekday - 1];
  final mon = months[d.month - 1];
  return '$dow ${_two(d.day)} $mon ${d.year}';
}

String _fmtTime(DateTime dt) {
  final d = dt.toLocal();
  return '${_two(d.hour)}:${_two(d.minute)}';
}

pw.Widget _badge(String text, PdfColor bg, PdfColor fg) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: pw.BoxDecoration(
      color: bg,
      borderRadius: pw.BorderRadius.circular(6),
      border: pw.Border.all(color: fg, width: 0.8),
    ),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: 9, color: fg, fontWeight: pw.FontWeight.bold),
    ),
  );
}

pw.Widget _rinkBox({
  required TeamSheetRink rink,
  required int playersPerRink,
  required PdfColor primary,
  required PdfColor accent,
}) {
  // Ensure we always show the right number of lines (2/3/4)
  final lines = List<String>.from(rink.players);
  while (lines.length < playersPerRink) {
    lines.add('');
  }
  if (lines.length > playersPerRink) {
    lines.removeRange(playersPerRink, lines.length);
  }

  final label = (rink.homeRinkLabel ?? '').trim();
  final title = label.isNotEmpty
      ? 'RINK ${rink.rinkNumber}  -  HOME RINK: $label'
      : 'RINK ${rink.rinkNumber}';
      
  return pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: primary, width: 1),
      borderRadius: pw.BorderRadius.circular(10),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: pw.BoxDecoration(
            color: accent,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: primary,
            ),
          ),
        ),
        pw.SizedBox(height: 8),
        ...lines.map((p) {
          return pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.8),
              ),
            ),
            child: pw.Text(
              p,
              style: const pw.TextStyle(fontSize: 11),
            ),
          );
        }),
      ],
    ),
  );
}

pw.Widget _sectionTitle(String text, PdfColor primary) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(vertical: 6),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 11,
        fontWeight: pw.FontWeight.bold,
        color: primary,
      ),
    ),
  );
}

Future<Uint8List> buildTeamSheetPdf(TeamSheetData data) async {
  final pdf = pw.Document();

  final primary = PdfColor.fromInt(data.primaryColor);
  // then just use a light grey background instead of opacity:
  final secondaryWash = PdfColors.grey200;

  final logo = data.logoBytes != null ? pw.MemoryImage(data.logoBytes!) : null;

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(24, 20, 24, 20),
      build: (context) {
        return [
          // Header band
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: secondaryWash,
              borderRadius: pw.BorderRadius.circular(12),
              border: pw.Border.all(color: primary, width: 1.2),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (logo != null)
                  pw.Container(
                    width: 48,
                    height: 48,
                    margin: const pw.EdgeInsets.only(right: 12),
                    child: pw.Image(logo, fit: pw.BoxFit.contain),
                  ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        data.clubName.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: primary,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        '${data.clubName}  v  ${data.opponentName}',
                        style: pw.TextStyle(fontSize: 12, color: primary),
                      ),
                      pw.SizedBox(height: 8),

                      // Badges row
                      pw.Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _badge(data.isHome ? 'HOME' : 'AWAY', secondaryWash, primary),
                          _badge(data.section.toUpperCase(), secondaryWash, primary),
                          _badge('${data.rinksRequired} RINKS', secondaryWash, primary),
                          _badge(
                            data.playersPerRink == 2
                                ? 'PAIRS'
                                : data.playersPerRink == 3
                                    ? 'TRIPLES'
                                    : 'RINKS',
                            secondaryWash,
                            primary,
                          ),
                          _badge('${_fmtDate(data.startAt)} - ${_fmtTime(data.startAt)}', secondaryWash, primary),
                          if ((data.captainName ?? '').isNotEmpty) _badge('CAPT: ${data.captainName}', secondaryWash, primary),
                          if ((data.viceName ?? '').isNotEmpty) _badge('VICE: ${data.viceName}', secondaryWash, primary),
                        ],
                      ),

                      pw.SizedBox(height: 8),

                      // Optional info line
                      pw.Text(
                        [
                          if (data.dress.trim().isNotEmpty) 'Dress: ${data.dress}',
                          if ((data.mealInfo ?? '').trim().isNotEmpty) 'Meal: ${data.mealInfo}',
                        ].join('   -   '),
                        style: pw.TextStyle(fontSize: 10, color: PdfColors.grey800),
                      ),

                      if ((data.notes ?? '').trim().isNotEmpty) ...[
                        pw.SizedBox(height: 6),
                        pw.Text(
                          data.notes!,
                          style: pw.TextStyle(fontSize: 10, color: PdfColors.grey800),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 14),

          // Rinks - 2 columns grid, up to 6
          _sectionTitle('TEAM', primary),
          pw.Wrap(
            spacing: 12,
            runSpacing: 12,
            children: List.generate(data.rinks.length, (i) {
              return pw.SizedBox(
                width: (PdfPageFormat.a4.availableWidth - 12) / 2,
                child: _rinkBox(
                  rink: data.rinks[i],
                  playersPerRink: data.playersPerRink,
                  primary: primary,
                  accent: secondaryWash,
                ),
              );
            }),
          ),

          pw.SizedBox(height: 14),

          // Reserves
          _sectionTitle('RESERVES', primary),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              borderRadius: pw.BorderRadius.circular(10),
              border: pw.Border.all(color: primary, width: 1),
            ),
            child: pw.Wrap(
              spacing: 10,
              runSpacing: 8,
              children: data.reserves.isEmpty
                  ? [pw.Text('None', style: const pw.TextStyle(fontSize: 11))]
                  : data.reserves.map((name) {
                      return pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.grey100,
                          borderRadius: pw.BorderRadius.circular(8),
                          border: pw.Border.all(color: PdfColors.grey300),
                        ),
                        child: pw.Text(name, style: const pw.TextStyle(fontSize: 11)),
                      );
                    }).toList(),
            ),
          ),

          pw.Spacer(),

          // Footer line (optional)
          pw.SizedBox(height: 10),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Generated by Bowls Club App',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          ),
        ];
      },
    ),
  );

  return pdf.save();
}

