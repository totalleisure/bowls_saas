import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowls_saas/features/competitions/screens/fixture_booking_start_times_screen.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.invalid',
      anonKey: 'test',
      httpClient: MockClient(
        (r) async => http.Response(
          jsonEncode([{
            'club_id': 'club',
            'updated_at': '2026-11-18T00:00:00Z',
            'windows': [
              {
                'from': 540,
                'until': 840,
                'starts': [540, 690],
              },
            ],
          }]),
          200,
          headers: {'content-type': 'application/json'}, request: r,
        ),
      ),
    );
  });
  testWidgets(
    'colourful timetable renders on a narrow screen and allows another window',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const RepaintBoundary(key: ValueKey('preview'), child: MaterialApp(home: FixtureBookingStartTimesScreen(clubId: 'club'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('09:00'), findsOneWidget);
      expect(find.text('11:30'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final boundary=tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('preview')));
      await tester.runAsync(() async { final image=await boundary.toImage(pixelRatio:1); final bytes=await image.toByteData(format:ui.ImageByteFormat.png); await File('tmp/fixture-booking-timetable-preview.png').writeAsBytes(bytes!.buffer.asUint8List()); image.dispose(); });
      await tester.ensureVisible(find.text('Add booking window'));
      await tester.tap(find.text('Add booking window'));
      await tester.pumpAndSettle();
      expect(find.text('Allowed start times'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Use window'));
      await tester.pump();
      expect(find.textContaining('at least one start time'), findsOneWidget);
    },
  );
}
