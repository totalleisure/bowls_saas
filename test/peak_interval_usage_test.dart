import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/core/utils/peak_interval_usage.dart';

void main() {
  DateTime at(int h, [int m = 0]) => DateTime(2026, 9, 25, h, m);
  final bookings = [
    for (var i = 0; i < 3; i++) (start: at(9), end: at(11, 10)),
    for (var i = 0; i < 5; i++) (start: at(11, 10), end: at(13, 40)),
    for (var i = 0; i < 6; i++) (start: at(13, 45), end: at(16, 15)),
    for (var i = 0; i < 6; i++) (start: at(16, 20), end: at(18, 40)),
  ];
  test(
    'screenshot transitions show peak occupancy, not all touching bookings',
    () {
      expect(peakIntervalUsage(bookings, at(11), at(12)), 5);
      expect(peakIntervalUsage(bookings, at(13), at(14)), 6);
      expect(peakIntervalUsage(bookings, at(16), at(17)), 6);
      expect(peakIntervalUsage(bookings, at(10), at(13)), 5);
    },
  );
  test('member booking spanning successive sessions peaks at six', () {
    final withMember = [...bookings, (start: at(9, 30), end: at(12, 30))];
    expect(peakIntervalUsage(withMember, at(9, 30), at(12, 30)), 6);
    expect(peakIntervalUsage(withMember, at(11), at(12)), 6);
    expect(peakIntervalUsage(withMember, at(13), at(14)), 6);
  });
  test('genuine overlaps are counted without clamping to rink count', () {
    expect(
      peakIntervalUsage(
        [...bookings, (start: at(16, 25), end: at(17))],
        at(16),
        at(17),
      ),
      7,
    );
  });
  test('boundary, empty and previous-day intervals', () {
    expect(peakIntervalUsage(bookings, at(18, 40), at(19)), 0);
    expect(peakIntervalUsage(bookings, at(11), at(11)), 0);
    expect(
      peakIntervalUsage(
        [(start: at(0).subtract(const Duration(hours: 2)), end: at(10))],
        at(9),
        at(10),
      ),
      1,
    );
  });
}
