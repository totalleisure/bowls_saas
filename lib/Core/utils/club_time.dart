DateTime toClubTime(DateTime dt) {
  final utc = dt.toUtc();

  final year = utc.year;

  final marchLastSunday = DateTime(
    year,
    4,
    0,
  ).subtract(Duration(days: DateTime(year, 4, 0).weekday % 7));

  final octoberLastSunday = DateTime(
    year,
    11,
    0,
  ).subtract(Duration(days: DateTime(year, 11, 0).weekday % 7));

  final bstStart = DateTime.utc(year, 3, marchLastSunday.day, 1);

  final bstEnd = DateTime.utc(year, 10, octoberLastSunday.day, 1);

  final isBst = utc.isAfter(bstStart) && utc.isBefore(bstEnd);

  return utc.add(Duration(hours: isBst ? 1 : 0));
}
