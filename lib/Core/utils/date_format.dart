import 'package:intl/intl.dart';

/// Formats an ISO-8601 UTC timestamp string into the local time zone.
/// Example output: "Saturday 21 February 2026, 7:30 p.m."
String formatWhenLocal(String isoUtc) {
  final dt = DateTime.parse(isoUtc).toLocal();
  return DateFormat("EEEE d MMMM yyyy, h:mm a")
      .format(dt)
      .replaceAll('AM', 'a.m.')
      .replaceAll('PM', 'p.m.');
}
