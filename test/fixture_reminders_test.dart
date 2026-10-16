import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/core/utils/fixture_reminders.dart';

void main() {
  final now = DateTime.utc(2026, 10, 10, 12);
  Map<String, dynamic> match(String id, int days, String status) => {
    'id': id,
    'start_at': now.add(Duration(days: days)).toIso8601String(),
    '_reminderAcceptance': status,
  };
  test(
    'accepted and urgent pending fixtures are ordered by date, not reason',
    () {
      expect(
        fixtureReminders([
          match('pending-later', 3, 'pending'),
          match('accepted', 1, 'accepted'),
          match('pending-first', 0, 'pending'),
          match('later', 10, 'pending'),
        ], now: now).map((f) => f['id']),
        ['pending-first', 'accepted', 'pending-later'],
      );
    },
  );
  test('seven-day boundary, past, cancelled and declined fixtures', () {
    expect(
      fixtureReminders([
        match('seven', 7, 'pending'),
        match('eight', 8, 'pending'),
        match('past', -1, 'accepted'),
        match('declined', 1, 'declined'),
        {...match('cancelled', 1, 'pending'), 'cancelled_at': '2026-10-09'},
      ], now: now).map((f) => f['id']),
      ['seven'],
    );
  });
  test('all urgent responses survive the nearest-two accepted limit', () {
    expect(
      fixtureReminders([
        for (var i = 1; i <= 4; i++) match('accepted-$i', i, 'accepted'),
        match('pending', 5, 'pending'),
        match('pending', 5, 'pending'),
      ], now: now).map((f) => f['id']),
      ['accepted-1', 'accepted-2', 'pending'],
    );
  });
  test('duplicate pending response takes precedence over accepted row', () {
    for (final reverse in [false, true]) {
      final rows = [match('same', 1, 'accepted'), match('same', 1, 'pending')];
      expect(
        fixtureReminders(
          reverse ? rows.reversed : rows,
          now: now,
        ).single['_reminderAcceptance'],
        'pending',
      );
    }
  });
}
