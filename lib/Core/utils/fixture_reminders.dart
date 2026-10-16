/// Pending responses within seven days and accepted matches share date order.
/// The nearest two accepted matches are retained alongside every urgent response.
List<Map<String, dynamic>> fixtureReminders(
  Iterable<Map<String, dynamic>> candidates, {
  required DateTime now,
}) {
  final unique = <String, Map<String, dynamic>>{};
  final instant = now.toUtc();
  for (final fixture in candidates) {
    final start = DateTime.tryParse('${fixture['start_at']}')?.toUtc();
    if (start == null ||
        start.isBefore(instant) ||
        fixture['cancelled_at'] != null) {
      continue;
    }
    final status = fixture['_reminderAcceptance'] ?? 'accepted';
    if (status != 'accepted' && status != 'pending') continue;
    if (status == 'pending' &&
        start.difference(instant) > const Duration(days: 7)) {
      continue;
    }
    final id = '${fixture['id']}';
    // An outstanding response must not be hidden by a duplicate accepted row.
    if (unique[id]?['_reminderAcceptance'] == 'pending') continue;
    unique[id] = fixture;
  }
  final ordered = unique.values.toList()
    ..sort((a, b) {
      final order = DateTime.parse(
        '${a['start_at']}',
      ).compareTo(DateTime.parse('${b['start_at']}'));
      return order == 0 ? '${a['id']}'.compareTo('${b['id']}') : order;
    });
  var accepted = 0;
  return ordered
      .where((f) => f['_reminderAcceptance'] == 'pending' || ++accepted <= 2)
      .toList();
}
