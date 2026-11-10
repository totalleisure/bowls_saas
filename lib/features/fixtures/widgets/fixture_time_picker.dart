import 'package:flutter/material.dart';
import '../../../core/utils/date_format.dart';

typedef FixtureTimeWindow = ({DateTime start, DateTime end});

// Values are Club wall times. Compare components independently of device zone.
DateTime _wall(DateTime value) => DateTime.utc(
  value.year,
  value.month,
  value.day,
  value.hour,
  value.minute,
  value.second,
);

String? fixtureTimingError(
  DateTime start,
  DateTime end, {
  DateTime? now,
  bool requireFuture = true,
}) {
  if (requireFuture &&
      !_wall(start).isAfter(_wall(now ?? toClubTime(DateTime.now())))) {
    return 'Choose a start date and time in the future.';
  }
  if (!DateUtils.isSameDay(start, end)) {
    return 'The fixture must finish on the start date. Choose an earlier start or a shorter duration.';
  }
  if (!_wall(end).isAfter(_wall(start))) {
    return 'End time must be after the start time.';
  }
  return null;
}

FixtureTimeWindow moveFixtureStart(
  DateTime newStart, {
  DateTime? start,
  DateTime? end,
  DateTime? latestEnd,
  Duration defaultDuration = const Duration(hours: 2),
}) {
  final duration =
      start != null && end != null && _wall(end).isAfter(_wall(start))
      ? _wall(end).difference(_wall(start))
      : defaultDuration;
  final shifted = _wall(newStart).add(duration);
  var dayEnd = DateTime.utc(
    newStart.year,
    newStart.month,
    newStart.day,
    23,
    59,
  );
  if (latestEnd != null &&
      DateUtils.isSameDay(newStart, latestEnd) &&
      _wall(latestEnd).isBefore(dayEnd)) {
    dayEnd = _wall(latestEnd);
  }
  final finish = shifted.isAfter(dayEnd) ? dayEnd : shifted;
  return (
    start: newStart,
    end: DateTime(
      finish.year,
      finish.month,
      finish.day,
      finish.hour,
      finish.minute,
    ),
  );
}

void _showError(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));

Future<FixtureTimeWindow?> pickFixtureStart(
  BuildContext context, {
  DateTime? start,
  DateTime? end,
  DateTime? now,
  DateTime? latestEnd,
  Duration defaultDuration = const Duration(hours: 2),
}) async {
  final current = now ?? toClubTime(DateTime.now());
  final today = DateTime(current.year, current.month, current.day);
  final initial = start ?? current.add(const Duration(hours: 1));
  final initialDay = DateTime(initial.year, initial.month, initial.day);
  final date = await showDatePicker(
    context: context,
    initialDate: initialDay.isBefore(today) ? today : initialDay,
    firstDate: today,
    lastDate: DateTime(
      (initial.year > current.year ? initial.year : current.year) + 10,
      12,
      31,
    ),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
    helpText: 'Fixture start time',
  );
  if (time == null || !context.mounted) return null;
  final window = moveFixtureStart(
    DateTime(date.year, date.month, date.day, time.hour, time.minute),
    start: start,
    end: end,
    latestEnd: latestEnd,
    defaultDuration: defaultDuration,
  );
  final error = fixtureTimingError(window.start, window.end, now: now);
  if (error != null) {
    _showError(context, error);
    return null;
  }
  final intendedDuration =
      start != null && end != null && _wall(end).isAfter(_wall(start))
      ? _wall(end).difference(_wall(start))
      : defaultDuration;
  if (_wall(window.end).difference(_wall(window.start)) < intendedDuration) {
    final minutes = _wall(window.end).difference(_wall(window.start)).inMinutes;
    final finish =
        '${window.end.hour.toString().padLeft(2, '0')}:${window.end.minute.toString().padLeft(2, '0')}';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            'This fixture is shorter than a normal session. '
            'It will finish at $finish on the start date (${minutes ~/ 60} hr ${minutes % 60} min).',
          ),
        ),
      );
  }
  return window;
}

Future<DateTime?> pickFixtureEndTime(
  BuildContext context, {
  required DateTime start,
  DateTime? end,
}) async {
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(
      end ?? start.add(const Duration(hours: 2)),
    ),
    helpText: 'Fixture end time',
  );
  if (time == null || !context.mounted) return null;
  final finish = DateTime(
    start.year,
    start.month,
    start.day,
    time.hour,
    time.minute,
  );
  final error = fixtureTimingError(start, finish, requireFuture: false);
  if (error != null) {
    _showError(context, error);
    return null;
  }
  return finish;
}
