import 'package:intl/intl.dart';

DateTime parseClubTime(String isoUtc) {
  final utc = DateTime.parse(isoUtc).toUtc();
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

DateTime toClubTime(DateTime dt) {
  return parseClubTime(dt.toUtc().toIso8601String());
}

/// Formats an ISO-8601 UTC timestamp string into club time.
/// For now this assumes UK club time.
String formatWhenLocal(String isoUtc) {
  final dt = parseClubTime(isoUtc);

  return DateFormat(
    "EEEE d MMMM yyyy, h:mm a",
  ).format(dt).replaceAll('AM', 'a.m.').replaceAll('PM', 'p.m.');
}

DateTime clubTimeToUtc(DateTime clubTime) {
  final year = clubTime.year;

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

  final bstStartLocal = DateTime(year, 3, marchLastSunday.day, 2);
  final bstEndLocal = DateTime(year, 10, octoberLastSunday.day, 2);

  final isBst =
      clubTime.isAfter(bstStartLocal) && clubTime.isBefore(bstEndLocal);

  return DateTime.utc(
    clubTime.year,
    clubTime.month,
    clubTime.day,
    clubTime.hour - (isBst ? 1 : 0),
    clubTime.minute,
    clubTime.second,
    clubTime.millisecond,
    clubTime.microsecond,
  );
}

String formatClubDateTime(DateTime clubTime) {
  return DateFormat(
    "EEEE d MMMM yyyy, h:mm a",
  ).format(clubTime).replaceAll('AM', 'a.m.').replaceAll('PM', 'p.m.');
}
