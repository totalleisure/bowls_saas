import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../core/utils/date_format.dart';

/// Simple DTOs you can build from Supabase rows
class TeamSheetRink {
  final int rinkNumber;
  final List<String> players;
  final List<String> opponents;
  final String? marker;
  final String? homeRinkLabel;

  TeamSheetRink({
    required this.rinkNumber,
    required this.players,
    this.opponents = const [],
    this.marker,
    this.homeRinkLabel,
  });
}

class TeamSheetData {
  final String clubName;
  final String opponentName;
  final DateTime startAt;
  final bool isHome;
  final String section;
  final int rinksRequired;
  final int playersPerRink;
  final String dress;
  final String? mealInfo;
  final String? notes;

  final String? captainName;
  final String? captainEmail;
  final String? captainPhone;

  final String? viceName;
  final String? viceEmail;
  final String? vicePhone;

  final List<TeamSheetRink> rinks;
  final List<String> reserves;

  // branding
  final int primaryColor;
  final int secondaryColor;
  final Uint8List? logoBytes;

  // NEW
  final String? fixtureTypeName;
  final int? fixtureTypeBgColor;
  final int? fixtureTypeFgColor;

  final bool? isInternal;
  final String? selectionMode;

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
    this.captainEmail,
    this.captainPhone,
    this.viceName,
    this.viceEmail,
    this.vicePhone,

    // NEW
    this.fixtureTypeName,
    this.fixtureTypeBgColor,
    this.fixtureTypeFgColor,
    this.isInternal,
    this.selectionMode,
  });
}

String _two(int n) => n.toString().padLeft(2, '0');

String _fmtDate(DateTime dt) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  final d = toClubTime(dt);

  final dow = days[d.weekday - 1];
  final mon = months[d.month - 1];

  return '$dow ${_two(d.day)} $mon ${d.year}';
}

String _fmtTime(DateTime dt) {
  final d = toClubTime(dt);
  return '${_two(d.hour)}:${_two(d.minute)}';
}

String _matchTitle(TeamSheetData data) {
  if (data.isHome) {
    return '${data.clubName} v ${data.opponentName}';
  }
  return 'Away at ${data.opponentName} v ${data.clubName}';
}

String? _internalLabel(bool? isInternal) {
  if (isInternal == null) return null;
  return isInternal ? 'INTERNAL' : 'EXTERNAL';
}

String? _selectionModeLabel(String? mode) {
  final m = (mode ?? '').trim().toLowerCase();

  switch (m) {
    case 'preselect':
    case 'pre_select':
    case 'pre-selected':
    case 'preselected':
      return 'PRE-SELECTED';

    case 'rsvp':
      return 'RSVP';

    case 'selection':
      return 'SELECTED';

    case 'open':
      return 'OPEN SELECTION';

    default:
      return m.isEmpty ? null : m.toUpperCase();
  }
}

String _positionLabel(int position, int playersPerRink) {
  if (position == 1) return 'Lead';
  if (position == playersPerRink) return 'Skip';

  if (playersPerRink == 4) {
    return position == 2 ? '2' : '3';
  }
  if (playersPerRink == 3) {
    return '2';
  }
  return position.toString();
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
      style: pw.TextStyle(
        fontSize: 9,
        color: fg,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  );
}

pw.Widget _fixtureTypeBand(
  TeamSheetData data,
  PdfColor fallbackBg,
  PdfColor fallbackFg,
) {
  final isInternal = data.isInternal == true;
  final rawName = (data.fixtureTypeName ?? '').trim();

  final displayName = isInternal ? 'Internal Fixture' : rawName;

  if (displayName.isEmpty) return pw.SizedBox();

  final bg = data.fixtureTypeBgColor != null
      ? PdfColor.fromInt(data.fixtureTypeBgColor!)
      : fallbackBg;

  final fg = data.fixtureTypeFgColor != null
      ? PdfColor.fromInt(data.fixtureTypeFgColor!)
      : fallbackFg;

  final dateTimeText = '${_fmtDate(data.startAt)}  ${_fmtTime(data.startAt)}';

  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: pw.BoxDecoration(
      color: bg,
      borderRadius: pw.BorderRadius.circular(6),
      border: pw.Border.all(color: fg, width: 0.8),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Top row: Fixture Type + Date/Time
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                displayName.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: fg,
                ),
              ),
            ),
            pw.Text(
              dateTimeText,
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: fg,
              ),
            ),
          ],
        ),

        // 👇 NEW: Arrival message
        pw.SizedBox(height: 4),
        pw.Text(
          'Please arrive at least 15 minutes before the start of the fixture',
          style: pw.TextStyle(fontSize: 10, color: fg),
        ),
      ],
    ),
  );
}

pw.Widget _rinkBox({
  required TeamSheetRink rink,
  required int playersPerRink,
  required PdfColor primary,
  required PdfColor accent,
}) {
  final playerLines = List<String>.from(rink.players);
  while (playerLines.length < playersPerRink) {
    playerLines.add('');
  }
  if (playerLines.length > playersPerRink) {
    playerLines.removeRange(playersPerRink, playerLines.length);
  }

  final opponentLines = List<String>.from(rink.opponents);
  while (opponentLines.length < playersPerRink) {
    opponentLines.add('');
  }
  if (opponentLines.length > playersPerRink) {
    opponentLines.removeRange(playersPerRink, opponentLines.length);
  }

  final showMatchups =
      opponentLines.any((o) => o.trim().isNotEmpty) ||
      ((rink.marker ?? '').trim().isNotEmpty);

  final label = (rink.homeRinkLabel ?? '').trim();
  final title = label.isNotEmpty
      ? 'TEAM ${rink.rinkNumber}  -  HOME RINK: $label'
      : 'TEAM ${rink.rinkNumber}';

  pw.Widget standardLine(int index, String player) {
    final posLabel = _positionLabel(index + 1, playersPerRink);

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.8),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 42,
            child: pw.Text(
              posLabel,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: primary,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(player, style: const pw.TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  pw.Widget matchupLine(int index, String player, String opponent) {
    final posLabel = _positionLabel(index + 1, playersPerRink);

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.8),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 42,
            child: pw.Text(
              posLabel,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: primary,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(player, style: const pw.TextStyle(fontSize: 11)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6),
            child: pw.Text(
              'v',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: primary,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(opponent, style: const pw.TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

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

        if (showMatchups) ...[
          for (int i = 0; i < playersPerRink; i++)
            matchupLine(i, playerLines[i], opponentLines[i]),
          if ((rink.marker ?? '').trim().isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text(
              'Marker: ${rink.marker!}',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: primary,
              ),
            ),
          ],
        ] else ...[
          for (int i = 0; i < playersPerRink; i++)
            standardLine(i, playerLines[i]),
        ],
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

pw.Widget _captainContactsBox(TeamSheetData data, PdfColor primary) {
  String safe(String? v) {
    final s = (v ?? '').trim();
    return s.isEmpty ? '-' : s;
  }

  pw.Widget personBlock({
    required String title,
    required String name,
    required String email,
    required String phone,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Text(name, style: const pw.TextStyle(fontSize: 13)),
        pw.SizedBox(height: 6),
        pw.Text(
          '   ${safe(email)}',
          style: pw.TextStyle(
            fontSize: 12,
            color: PdfColors.blueGrey700,
            decoration: pw.TextDecoration.underline,
          ),
        ),

        pw.SizedBox(height: 6),

        pw.Text('   ${safe(phone)}', style: const pw.TextStyle(fontSize: 12)),
      ],
    );
  }

  final hasCaptainInfo =
      safe(data.captainName) != '-' ||
      safe(data.captainEmail) != '-' ||
      safe(data.captainPhone) != '-';

  final hasViceInfo =
      safe(data.viceName) != '-' ||
      safe(data.viceEmail) != '-' ||
      safe(data.vicePhone) != '-';

  if (!hasCaptainInfo && !hasViceInfo) {
    return pw.SizedBox();
  }

  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: primary, width: 1.4),
      borderRadius: pw.BorderRadius.circular(20),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: personBlock(
            title: 'Team Captain',
            name: safe(data.captainName),
            email: safe(data.captainEmail),
            phone: safe(data.captainPhone),
          ),
        ),
        pw.SizedBox(width: 40),
        pw.Expanded(
          child: personBlock(
            title: 'Vice Captain',
            name: safe(data.viceName),
            email: safe(data.viceEmail),
            phone: safe(data.vicePhone),
          ),
        ),
      ],
    ),
  );
}

Future<Uint8List> buildTeamSheetPdf(TeamSheetData data) async {
  final pdf = pw.Document();

  final primary = PdfColor.fromInt(data.primaryColor);
  final clubBg = PdfColor.fromInt(data.primaryColor);
  final clubFg = PdfColor.fromInt(data.secondaryColor);
  final secondaryWash = PdfColors.grey200;

  final fixtureTypeBg = data.fixtureTypeBgColor != null
      ? PdfColor.fromInt(data.fixtureTypeBgColor!)
      : PdfColors.grey300;

  final fixtureTypeFg = data.fixtureTypeFgColor != null
      ? PdfColor.fromInt(data.fixtureTypeFgColor!)
      : PdfColors.black;

  final logo = data.logoBytes != null ? pw.MemoryImage(data.logoBytes!) : null;

  final internalLabel = _internalLabel(data.isInternal);
  final selectionModeLabel = _selectionModeLabel(data.selectionMode);

  final showOpponentsAndMarker =
      (data.selectionMode ?? '').trim().toLowerCase() == 'preselect' &&
      data.isInternal == true;

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
              color: clubBg,
              borderRadius: pw.BorderRadius.circular(12),
              border: pw.Border.all(color: clubFg, width: 1.2),
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
                          color: clubFg,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(() {
                        final opp = (data.opponentName ?? '').trim();

                        if (opp.isEmpty) {
                          return data.isHome ? data.clubName : 'Away fixture';
                        }

                        return data.isHome
                            ? '${data.clubName}  v  $opp'
                            : 'Away at $opp  v  ${data.clubName}';
                      }(), style: pw.TextStyle(fontSize: 12, color: clubFg)),

                      //                      if ((data.fixtureTypeName ?? '').trim().isNotEmpty) ...[
                      //                        pw.SizedBox(height: 8),
                      //                        _fixtureTypeBand(data, secondaryWash, primary),
                      //                      ],
                      pw.SizedBox(height: 8),

                      pw.Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if ((internalLabel ?? '').isNotEmpty)
                            _badge(internalLabel!, secondaryWash, primary),

                          if ((selectionModeLabel ?? '').isNotEmpty)
                            _badge(selectionModeLabel!, secondaryWash, primary),

                          _badge(
                            data.isHome ? 'HOME' : 'AWAY',
                            secondaryWash,
                            primary,
                          ),
                          _badge(
                            data.section.toUpperCase(),
                            secondaryWash,
                            primary,
                          ),
                          _badge(
                            '${data.rinksRequired} TEAMS',
                            secondaryWash,
                            primary,
                          ),
                          _badge(
                            data.playersPerRink == 2
                                ? 'PAIRS'
                                : data.playersPerRink == 3
                                ? 'TRIPLES'
                                : 'RINKS',
                            secondaryWash,
                            primary,
                          ),
                          _badge(
                            '${_fmtDate(data.startAt)} - ${_fmtTime(data.startAt)}',
                            secondaryWash,
                            primary,
                          ),
                        ],
                      ),

                      pw.SizedBox(height: 8),

                      pw.Text(
                        [
                          if (data.dress.trim().isNotEmpty)
                            'Dress: ${data.dress}',
                          if ((data.mealInfo ?? '').trim().isNotEmpty)
                            'Meal: ${data.mealInfo}',
                        ].join('   -   '),
                        style: pw.TextStyle(fontSize: 10, color: clubFg),
                      ),

                      if ((data.notes ?? '').trim().isNotEmpty) ...[
                        pw.SizedBox(height: 6),
                        pw.Text(
                          data.notes!,
                          style: pw.TextStyle(fontSize: 10, color: clubFg),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 👇 NEW — fixture type strip OUTSIDE header
          if ((data.fixtureTypeName ?? '').trim().isNotEmpty ||
              data.isInternal == true) ...[
            pw.SizedBox(height: 6),
            _fixtureTypeBand(data, secondaryWash, primary),
          ],

          pw.SizedBox(height: 12),
          _captainContactsBox(data, primary),
          pw.SizedBox(height: 14),

          // Teams - 2 columns grid, centred row-by-row
          _sectionTitle('TEAMS', primary),
          pw.Column(
            children: List.generate((data.rinks.length / 2).ceil(), (rowIndex) {
              final leftIndex = rowIndex * 2;
              final rightIndex = leftIndex + 1;

              final leftRink = data.rinks[leftIndex];
              final TeamSheetRink? rightRink = rightIndex < data.rinks.length
                  ? data.rinks[rightIndex]
                  : null;

              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 12),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.SizedBox(
                      width: 230,
                      child: _rinkBox(
                        rink: leftRink,
                        playersPerRink: data.playersPerRink,
                        primary: primary,
                        accent: secondaryWash,
                      ),
                    ),
                    pw.SizedBox(width: 12),
                    pw.SizedBox(
                      width: 230,
                      child: rightRink == null
                          ? pw.SizedBox()
                          : _rinkBox(
                              rink: rightRink,
                              playersPerRink: data.playersPerRink,
                              primary: primary,
                              accent: secondaryWash,
                            ),
                    ),
                  ],
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
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.grey100,
                          borderRadius: pw.BorderRadius.circular(8),
                          border: pw.Border.all(color: PdfColors.grey300),
                        ),
                        child: pw.Text(
                          name,
                          style: const pw.TextStyle(fontSize: 11),
                        ),
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
