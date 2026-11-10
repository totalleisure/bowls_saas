import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/scorecards/scorecard.dart';
import 'package:bowls_saas/features/scorecards/scorecard_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final title in ['', '   ']) {
    test(
      'Legacy blank title exports a paper card and audit pages, length=${title.length}',
      () async {
        final c = Scorecard.create()
          ..title = title
          ..sideA = 'South Hill'
          ..sideB = 'Lewisham and Crystal Palace'
          ..handicapA = -2
          ..handicapB = 2;
        final start = DateTime.utc(2026, 11, 3, 10);
        c.startMatch(start);
        for (var i = 0; i < 21; i++) {
          c.startEnd(start.add(Duration(minutes: i)));
          c.recordEnd(i, i.isEven ? 2 : 0, i.isOdd ? 1 : 0);
        }
        c.finish(start.add(const Duration(hours: 2)));
        final before = jsonEncode(c.toJson());
        for (final audit in [false, true]) {
          final pdf = await scorecardPdf(c, includeAudit: audit);
          expect(ascii.decode(pdf.take(4).toList()), '%PDF');
        }
        expect(jsonEncode(c.toJson()), before);
      },
    );
  }
  test('Exact saved card PDF export for local visual verification', () async {
    if (!const bool.fromEnvironment('EXISTING_SCORECARD_QA')) return;
    final c = Scorecard.fromJson(
      jsonDecode(
            await File('tmp/scorecard-existing-pdf-repro.json').readAsString(),
          )
          as Map<String, dynamic>,
    );
    final pdf = await scorecardPdf(c);
    await Directory('output/pdf').create(recursive: true);
    await File('output/pdf/recovered-scorecard.pdf').writeAsBytes(pdf);
  });
}
