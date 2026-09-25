/// Maximum simultaneous intervals in [start, end), with touching intervals
/// treated as successive bookings. Counts overlapping assignments separately
/// so genuine double bookings remain visible.
int peakIntervalUsage(
  Iterable<({DateTime start, DateTime end})> intervals,
  DateTime start,
  DateTime end,
) {
  if (!start.isBefore(end)) return 0;
  final changes = <DateTime, int>{};
  for (final interval in intervals) {
    final from = interval.start.isBefore(start) ? start : interval.start;
    final until = interval.end.isAfter(end) ? end : interval.end;
    if (!from.isBefore(until)) continue;
    changes.update(from, (value) => value + 1, ifAbsent: () => 1);
    changes.update(until, (value) => value - 1, ifAbsent: () => -1);
  }
  var current = 0;
  var peak = 0;
  for (final point in changes.keys.toList()..sort()) {
    current += changes[point]!;
    if (current > peak) peak = current;
  }
  return peak;
}
