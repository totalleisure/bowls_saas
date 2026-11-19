import 'package:intl/intl.dart';

DateTime parseClubTime(String isoUtc) {
  final utc = DateTime.parse(isoUtc).toUtc();
  final year = utc.year;

  final marchLastSunday = DateTime.utc(
    year,
    4,
    0,
  ).subtract(Duration(days: DateTime.utc(year, 4, 0).weekday % 7));

  final octoberLastSunday = DateTime.utc(
    year,
    11,
    0,
  ).subtract(Duration(days: DateTime.utc(year, 11, 0).weekday % 7));

  final bstStart = DateTime.utc(year, 3, marchLastSunday.day, 1);
  final bstEnd = DateTime.utc(year, 10, octoberLastSunday.day, 1);

  final isBst = !utc.isBefore(bstStart) && utc.isBefore(bstEnd);

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

/// Formats the time at which a journal action occurred in natural UK wording.
String formatAuditTimestamp(String isoUtc) {
  final dt = parseClubTime(isoUtc);

  return DateFormat(
    "EEEE d MMMM yyyy 'at' h:mm a",
  ).format(dt).replaceAll('AM', 'a.m.').replaceAll('PM', 'p.m.');
}

/// Replaces a raw Postgres timestamp at the end of an audit record label.
String formatAuditRecordLabel(String label) {
  final timestamp = RegExp(
    r'(\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}(?::?\d{2})?))$',
  ).firstMatch(label);
  if (timestamp == null) return label;

  try {
    return label.replaceRange(
      timestamp.start,
      timestamp.end,
      formatAuditTimestamp(timestamp.group(1)!),
    );
  } on FormatException {
    return label;
  }
}

DateTime clubTimeToUtc(DateTime clubTime) {
  final year = clubTime.year;

  final marchLastSunday = DateTime.utc(
    year,
    4,
    0,
  ).subtract(Duration(days: DateTime.utc(year, 4, 0).weekday % 7));

  final octoberLastSunday = DateTime.utc(
    year,
    11,
    0,
  ).subtract(Duration(days: DateTime.utc(year, 11, 0).weekday % 7));

  final bstStartLocal = DateTime.utc(year, 3, marchLastSunday.day, 2);
  final bstEndLocal = DateTime.utc(year, 10, octoberLastSunday.day, 2);

  final wallTime = DateTime.utc(
    clubTime.year,
    clubTime.month,
    clubTime.day,
    clubTime.hour,
    clubTime.minute,
    clubTime.second,
    clubTime.millisecond,
    clubTime.microsecond,
  );
  final isBst =
      !wallTime.isBefore(bstStartLocal) && wallTime.isBefore(bstEndLocal);

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
