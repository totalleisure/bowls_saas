import '../../core/utils/date_format.dart';

bool fixtureScoringDayReached(
  Map<String, dynamic> snapshot, {
  DateTime? nowUtc,
}) {
  final start = DateTime.tryParse('${snapshot['startAt'] ?? ''}');
  if (start == null) return false;
  final scheduled = toClubTime(start);
  final today = toClubTime(nowUtc ?? DateTime.now().toUtc());
  return !DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).isBefore(DateTime.utc(scheduled.year, scheduled.month, scheduled.day));
}
