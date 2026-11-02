import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowls_saas/features/competitions/competition_repository.dart';
import 'package:bowls_saas/features/competitions/competition_arrangement_repository.dart';
import 'package:bowls_saas/features/competitions/competition_fixture_management_repository.dart';
import 'package:bowls_saas/features/competitions/screens/competition_fixture_management_screen.dart';

class FakeManagement extends CompetitionFixtureManagementRepository {
  FakeManagement()
    : super(
        SupabaseClient(
          'https://example.invalid',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
        'fixture',
      );
  int changes = 0, markers = 0;
  bool locked = false, conflict = false;
  Map<String, dynamic> fixture = {
    'id': 'fixture',
    'club_id': 'club',
    'name': 'Mixed Pairs',
    'round': 'Final 1',
    'start_at': '2030-07-02T10:00:00Z',
    'end_at': '2030-07-02T12:30:00Z',
    'green_area_id': 'g',
    'rinks_required': 1,
  };
  Map<String, dynamic> rink = {
    'id': 'rink',
    'number': 1,
    'home_rink_label': 'R1',
    'marker_required': true,
    'marker_member_id': null,
    'marker_name': null,
  };
  CompetitionRow? expected;
  @override
  Future<CompetitionRow> load() async {
    if (locked) throw Exception('Competition fixture is locked');
    return {
      'fixture': Map<String, dynamic>.from(fixture),
      'rinks': [Map<String, dynamic>.from(rink)],
      'assigned_member_ids': ['player1', 'player2'],
    };
  }

  @override
  Future<List<CompetitionRow>> greens(String clubId) async => [
    {'id': 'g', 'name': 'Indoor Green', 'orientation_mode': 'not_applicable'},
  ];
  @override
  Future<List<CompetitionRow>> availability(
    String id,
    DateTime start,
    DateTime end,
  ) async => [
    {'rink_label': 'R1', 'is_booked': false, 'free_capacity_rinks': 1},
  ];
  @override
  Future<void> changeBooking(
    CompetitionBookingChoice choice,
    CompetitionRow previous,
    List<String?> labels,
  ) async {
    changes++;
    expected = previous;
    if (conflict) throw Exception('Booking has changed. Refresh.');
    fixture['start_at'] = '2030-07-03T13:00:00Z';
  }

  @override
  Future<void> setMarker(
    CompetitionRow previous,
    bool required,
    String? member,
  ) async {
    markers++;
    rink['marker_required'] = required;
    rink['marker_member_id'] = member;
    rink['marker_name'] = member == null ? null : 'Test Marker';
  }
}

Future<void> open(WidgetTester t, FakeManagement repo) async {
  t.view.physicalSize = const Size(1000, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      home: CompetitionFixtureManagementScreen(
        fixtureId: 'fixture',
        repository: repo,
        windowPicker: (context, start, end) async => (
          start: DateTime(2030, 7, 3, 13),
          end: DateTime(2030, 7, 3, 15, 30),
        ),
        markerPicker: (context, excluded) async {
          expect(excluded, contains('player1'));
          return 'marker';
        },
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> pick(WidgetTester t) async {
  await t.tap(find.text('Change date, time, green or rink'));
  await t.pumpAndSettle();
  await t.tap(find.text('Use selected rinks'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'Shared booking edits require confirmation and retain the expected snapshot',
    (t) async {
      final repo = FakeManagement();
      await open(t, repo);
      expect(find.text('Add Team/Rink'), findsNothing);
      expect(find.text('Cancel fixture'), findsNothing);
      await pick(t);
      await t.tap(find.text('Keep current booking'));
      await t.pumpAndSettle();
      expect(repo.changes, 0);
      await pick(t);
      await t.tap(find.text('Save booking'));
      await t.pumpAndSettle();
      expect(repo.changes, 1);
      expect(repo.expected?['start_at'], '2030-07-02T10:00:00Z');
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('Shared marker controls can assign and clear a marker', (
    t,
  ) async {
    final repo = FakeManagement();
    await open(t, repo);
    await t.tap(find.text('Choose marker'));
    await t.pumpAndSettle();
    expect(repo.markers, 1);
    expect(find.text('Test Marker'), findsOneWidget);
    await t.tap(find.text('Clear marker'));
    await t.pumpAndSettle();
    expect(repo.markers, 2);
    expect(find.text('No marker assigned'), findsOneWidget);
    await t.tap(find.byType(SwitchListTile));
    await t.pumpAndSettle();
    expect(repo.rink['marker_required'], false);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'Conflicts are shown and locked fixtures expose no editing controls',
    (t) async {
      final repo = FakeManagement()..conflict = true;
      await open(t, repo);
      await pick(t);
      await t.tap(find.text('Save booking'));
      await t.pumpAndSettle();
      expect(find.textContaining('Booking has changed'), findsOneWidget);
      repo.locked = true;
      await t.tap(find.byTooltip('Refresh'));
      await t.pumpAndSettle();
      expect(find.text('Change date, time, green or rink'), findsNothing);
      expect(find.text('Choose marker'), findsNothing);
      expect(find.textContaining('locked'), findsOneWidget);
    },
  );
}
