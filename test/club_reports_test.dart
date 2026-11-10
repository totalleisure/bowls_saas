import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:bowls_saas/features/reports/club_report.dart';
import 'package:bowls_saas/features/reports/club_reports_screen.dart';
import 'package:bowls_saas/features/reports/report_excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ClubReport sample() => ClubReport(
  {
    'club_name': 'Test Club',
    'from': '2026-10-01',
    'to': '2026-10-26',
    'generated_at': '2026-10-26T12:00:00Z',
    'recording_started_at': '2026-10-26T00:00:00Z',
    'summary': {
      'active_members': 1,
      'inactive_members': 0,
      'ever_signed_in': 1,
      'last_sign_in_in_period': 1,
      'no_recorded_sign_in': 0,
      'without_email': 0,
      'without_phone': 0,
      'bookings_created': 2,
      'recorded_logins': 1,
      'app_visits': 1,
      'screen_views': 2,
      'active_app_users': 1,
    },
    'bookings': [
      {
        'fixture_type': 'Open Fixture',
        'fixtures': 2,
        'cancelled': 1,
        'archived': 0,
        'current_fixtures': 1,
      },
    ],
    'screens': [
      {'screen': 'Month View', 'platform': 'iOS', 'views': 2, 'members': 1},
    ],
  },
  [
    {
      'surname': '=2+2 <Test>',
      'forename': 'Anne',
      'email': 'a@example.invalid',
      'mobile': '02001234567',
      'member_type': 'member',
      'active': true,
      'last_sign_in': '2026-10-26T10:00:00Z',
      'recorded_logins': 1,
    },
  ],
);

void main() {
  test('Top Users ranks measured usage and keeps Guest members separate', () {
    final r = sample();
    final members = <Map<String, dynamic>>[
      {
        ...r.members.first,
        'surname': 'Recent',
        'recorded_logins': 2,
        'last_sign_in': '2026-10-26T10:00:00Z',
      },
      {
        ...r.members.first,
        'surname': 'Frequent',
        'screen_views': 8,
        'member_type': 'guest',
        'last_sign_in': '2026-10-20T10:00:00Z',
      },
      {
        ...r.members.first,
        'surname': 'Never',
        'recorded_logins': 0,
        'last_sign_in': null,
      },
    ];
    final report = ClubReport(r.data, members);
    expect(report.topUsers.map((m) => m['surname']), ['Frequent', 'Recent']);
    expect(report.guestMembers.single['surname'], 'Frequent');
    expect(report.hasRecordedUsage, isTrue);
  });
  test(
    'Excel preserves contact text, typed counts and dates and never turns a name into a formula',
    () {
      final bytes = buildReportExcel(sample());
      final archive = ZipDecoder().decodeBytes(bytes);
      final sheet = utf8.decode(
        archive.findFile('xl/worksheets/sheet2.xml')!.content as List<int>,
      );
      expect(sheet, contains('=2+2 &lt;Test&gt;'));
      expect(sheet, contains('02001234567'));
      expect(sheet, isNot(contains('<f>')));
      expect(sheet, contains('t="inlineStr"'));
      expect(sheet, contains('s="2"><v>'));
      expect(sheet, contains('<autoFilter ref="A1:W2"'));
      expect(sheet, contains('xSplit="2"'));
      Directory('tmp').createSync(recursive: true);
      File('tmp/reports-sample.xlsx').writeAsBytesSync(bytes);
    },
  );
  for (final width in [320.0, 768.0, 1200.0]) {
    testWidgets(
      'Reports usable at width $width with tabs, all members and usage explanation',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: ClubReportsScreen(
              clubId: 'test',
              loader: (_, _) async => sample(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Club reports'), findsOneWidget);
        expect(find.byTooltip('Download Excel report'), findsOneWidget);
        await tester.tap(find.text('App Usage'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.textContaining('Earlier login counts'),
          200,
          scrollable: find
              .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.textContaining('Earlier login counts'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Bookings'));
        await tester.pumpAndSettle();
        expect(find.text('Open Fixture'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
