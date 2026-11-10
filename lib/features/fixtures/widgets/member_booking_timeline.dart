import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/utils/hex_color.dart';
import '../member_booking_repository.dart';
import '../rink_fixture_card_title.dart';

enum MemberTimelineDensity { fit, compact, detailed }

class MemberBookingTimeline extends StatelessWidget {
  const MemberBookingTimeline({
    super.key,
    required this.date,
    required this.labels,
    required this.day,
    required this.density,
    required this.onSelect,
    this.selectedLabel,
    this.selectedStart,
    this.latestEnd,
    this.enabled = true,
  });
  final DateTime date;
  final List<String> labels;
  final MemberBookingDay day;
  final MemberTimelineDensity density;
  final String? selectedLabel;
  final DateTime? selectedStart;
  final DateTime? latestEnd;
  final bool enabled;
  final void Function(String label, DateTime start) onSelect;

  bool available(String label, DateTime start) =>
      clubTimeToUtc(start).isAfter(DateTime.now().toUtc()) &&
      start.hour * 60 + start.minute + 150 <= 22 * 60 &&
      (latestEnd == null ||
          !memberBookingWallTime(
            start.add(memberBookingDuration),
          ).isAfter(memberBookingWallTime(latestEnd!))) &&
      day.canBook(label, start, labels);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const labelWidth = 46.0, rowHeight = 48.0;
      final viewport = math.max(1.0, constraints.maxWidth - labelWidth);
      final hourWidth = switch (density) {
        MemberTimelineDensity.fit => (viewport / 14).clamp(28.0, 80.0),
        MemberTimelineDensity.compact => 52.0,
        MemberTimelineDensity.detailed => 80.0,
      };
      final width = hourWidth * 14;
      final theme = Theme.of(context);
      final border = theme.dividerColor.withValues(alpha: .3);
      final dateStart = DateTime.utc(date.year, date.month, date.day, 9);
      double left(DateTime at) => math.max(
        0,
        memberBookingWallTime(at).difference(dateStart).inMinutes /
            60 *
            hourWidth,
      );
      Widget block(Map<String, dynamic> row, String title, Color bg, Color fg) {
        final start = parseClubTime(row['start_at'].toString());
        final end = parseClubTime(row['end_at'].toString());
        final x = left(start), right = math.min(13 * hourWidth, left(end));
        if (right <= x) return const SizedBox.shrink();
        return Positioned(
          left: x + 2,
          top: 4,
          width: math.max(0, right - x - 4),
          height: 40,
          child: Tooltip(
            message:
                '$title · ${DateFormat.Hm().format(start)}–${DateFormat.Hm().format(end)}',
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: title.contains('\n') ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontSize: title.contains('\n') ? 11 : 12,
                        height: 1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${DateFormat.Hm().format(start)}–${DateFormat.Hm().format(end)}',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(color: fg, fontSize: 10, height: 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            child: Column(
              children: [
                const SizedBox(
                  height: 32,
                  child: Center(
                    child: Text('Rink', style: TextStyle(fontSize: 12)),
                  ),
                ),
                for (final label in labels)
                  Container(
                    height: rowHeight,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: border)),
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                child: Column(
                  children: [
                    SizedBox(
                      height: 32,
                      child: Row(
                        children: [
                          for (var hour = 9; hour <= 22; hour++)
                            Container(
                              width: hourWidth,
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 3),
                              child: Text(
                                '${hour.toString().padLeft(2, '0')}:00',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                        ],
                      ),
                    ),
                    for (var i = 0; i < labels.length; i++)
                      Container(
                        height: rowHeight,
                        decoration: BoxDecoration(
                          color: i.isEven
                              ? theme.colorScheme.surface
                              : theme.colorScheme.surfaceContainerLow,
                          border: Border(top: BorderSide(color: border)),
                        ),
                        child: Stack(
                          children: [
                            for (var slot = 0; slot < 26; slot++)
                              Builder(
                                builder: (context) {
                                  final start = dateStart.add(
                                    Duration(minutes: slot * 30),
                                  );
                                  final free = available(labels[i], start);
                                  return Positioned(
                                    left: slot * hourWidth / 2,
                                    top: 0,
                                    bottom: 0,
                                    width: hourWidth / 2,
                                    child: Semantics(
                                      button: true,
                                      label:
                                          '${labels[i]}, ${DateFormat.Hm().format(start)}, ${free ? 'available' : 'unavailable'}',
                                      child: InkWell(
                                        onTap: enabled && free
                                            ? () => onSelect(labels[i], start)
                                            : null,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: free
                                                ? theme.colorScheme.primary
                                                      .withValues(alpha: .05)
                                                : theme.disabledColor
                                                      .withValues(alpha: .08),
                                            border: Border(
                                              left: BorderSide(
                                                color: border,
                                                width: slot.isEven ? 1 : .4,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            for (final fixture in day.fixtures)
                              if ((fixture['fixture_rinks'] as List? ?? []).any(
                                (r) => r['home_rink_label'] == labels[i],
                              ))
                                Builder(
                                  builder: (context) {
                                    final type =
                                        fixture['competition_types']
                                            as Map<String, dynamic>?;
                                    final colours =
                                        type?['colour_scheme']
                                            as Map<String, dynamic>?;
                                    return block(
                                      fixture,
                                      rinkFixtureCardTitle(fixture),
                                      colorFromHex(
                                        colours?['background_hex']?.toString(),
                                        fallback: const Color(0xffdbeafe),
                                      ),
                                      colorFromHex(
                                        colours?['foreground_hex']?.toString(),
                                        fallback: const Color(0xff1e3a8a),
                                      ),
                                    );
                                  },
                                ),
                            for (final maintenance in day.maintenance)
                              if (maintenance['rink_number'] == i + 1)
                                block(
                                  maintenance,
                                  maintenance['reason']?.toString() ??
                                      'Maintenance',
                                  theme.colorScheme.errorContainer,
                                  theme.colorScheme.onErrorContainer,
                                ),
                            if (selectedLabel == labels[i] &&
                                selectedStart != null)
                              Positioned(
                                left: left(selectedStart!) + 2,
                                top: 4,
                                width: hourWidth * 2.5 - 4,
                                height: 40,
                                child: IgnorePointer(
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      'Selected slot\n${DateFormat.Hm().format(selectedStart!)}–${DateFormat.Hm().format(selectedStart!.add(memberBookingDuration))}',
                                      maxLines: 2,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: theme.colorScheme.onPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
