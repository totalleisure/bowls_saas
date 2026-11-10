import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Compare Club calendar dates: the entire play-by day is permitted.
bool competitionBookingAfterDeadline(
  DateTime? scheduledClubTime,
  String? playBy,
) {
  final deadline = DateTime.tryParse(playBy ?? '');
  if (scheduledClubTime == null || deadline == null) return false;
  return DateTime.utc(
    scheduledClubTime.year,
    scheduledClubTime.month,
    scheduledClubTime.day,
  ).isAfter(DateTime.utc(deadline.year, deadline.month, deadline.day));
}

class CompetitionDeadlineWarning extends StatelessWidget {
  const CompetitionDeadlineWarning({
    super.key,
    required this.scheduledClubTime,
    required this.playBy,
  });
  final DateTime? scheduledClubTime;
  final String? playBy;
  @override
  Widget build(BuildContext context) {
    if (!competitionBookingAfterDeadline(scheduledClubTime, playBy)) {
      return const SizedBox.shrink();
    }
    final d = DateTime.parse(playBy!);
    final suffix = d.day % 100 >= 11 && d.day % 100 <= 13
        ? 'th'
        : switch (d.day % 10) {
            1 => 'st',
            2 => 'nd',
            3 => 'rd',
            _ => 'th',
          };
    return Card(
      color: const Color(0xfffff1ad),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xffb58b16)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xff5a4300)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Warning : This match should be played by ${d.day}$suffix ${DateFormat('MMM yyyy').format(d)}',
                style: const TextStyle(
                  color: Color(0xff3e3100),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
