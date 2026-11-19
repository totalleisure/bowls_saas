import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String bookingErrorMessage(Object error) {
  if (error is PostgrestException) {
    if (error.code == '42501')
      return 'You do not have permission to change these settings. Please contact a Club Admin.';
    return error.message;
  }
  return error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Exception: ', '');
}

String ruleTime(int m) =>
    '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

String? fixtureTypeTimingError(
  Map<String, dynamic>? type,
  List<Map<String, dynamic>> windows,
  DateTime start,
  DateTime end, {
  required bool privileged,
  bool home = true,
}) {
  if (privileged || type == null) return null;
  final maximum = (type['default_duration_minutes'] as num?)?.toInt();
  if (type['lock_duration'] == true &&
      maximum != null &&
      end.difference(start).inSeconds > maximum * 60)
    return 'This Fixture Type allows a maximum of $maximum minutes. Choose an earlier end time.';
  if (!home ||
      type['bookable_by_members'] != true ||
      type['booking_start_times_enabled'] != true)
    return null;
  if (start.weekday < DateTime.saturday) return null;
  final minute = start.hour * 60 + start.minute + start.second / 60;
  for (final w in windows) {
    if (minute >= (w['from'] as num) && minute < (w['until'] as num)) {
      final starts = List<int>.from(w['starts'] as List);
      if (!starts.contains(minute))
        return 'On Saturdays and Sundays, between ${ruleTime(w['from'] as int)} and ${ruleTime(w['until'] as int)}, start at ${starts.map(ruleTime).join(' or ')}.';
    }
  }
  return null;
}

Future<List<Map<String, dynamic>>> loadBookingWindows(
  SupabaseClient client,
  String clubId,
) async {
  final row = await client
      .from('fixture_booking_start_rules')
      .select('windows')
      .eq('club_id', clubId)
      .maybeSingle();
  return (row?['windows'] as List? ?? [])
      .map((w) => Map<String, dynamic>.from(w as Map))
      .toList();
}

class FixtureBookingRulesHint extends StatelessWidget {
  const FixtureBookingRulesHint({
    super.key,
    required this.type,
    required this.windows,
    required this.privileged,
  });
  final Map<String, dynamic>? type;
  final List<Map<String, dynamic>> windows;
  final bool privileged;
  @override
  Widget build(BuildContext context) {
    final timed =
        type?['booking_start_times_enabled'] == true &&
        type?['bookable_by_members'] == true;
    final maximum = type?['lock_duration'] == true
        ? (type?['default_duration_minutes'])
        : null;
    if (!timed && maximum == null) return const SizedBox.shrink();
    return Card(
      color: Colors.teal.shade50,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: DefaultTextStyle.merge(
          style: const TextStyle(fontSize: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.schedule, color: Colors.teal, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Fixture booking rules',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              if (maximum != null)
                Text(
                  'Maximum duration: $maximum minutes. Shorter bookings are welcome.',
                ),
              if (timed) ...[
                for (final w in windows)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${ruleTime(w['from'] as int)}–${ruleTime(w['until'] as int)}:',
                        ),
                        for (final s in w['starts'] as List)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            padding: EdgeInsets.zero,
                            labelPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                            ),
                            label: Text(
                              ruleTime(s as int),
                              style: const TextStyle(fontSize: 12),
                            ),
                            avatar: const Icon(Icons.play_arrow, size: 12),
                          ),
                      ],
                    ),
                  ),
                const Text(
                  'Saturday and Sunday only. On weekdays, or outside these windows, choose any start within Club opening hours.',
                ),
              ],
              if (privileged)
                const Text(
                  'Admin / superuser override available.',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
