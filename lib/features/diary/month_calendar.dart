import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MonthDiaryItem {
  const MonthDiaryItem({
    required this.fixtureId,
    required this.startAt,
    required this.endAt,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.isMine,
    required this.rinksUsed,
    required this.isCancelled,
  });
  final String fixtureId, label;
  final DateTime startAt, endAt;
  final Color backgroundColor, foregroundColor;
  final bool isMine, isCancelled;
  final int rinksUsed;
}

/// Busy weekdays widen together, preserving the month grid's alignment.
class MonthCalendar extends StatefulWidget {
  const MonthCalendar({
    super.key,
    required this.month,
    required this.selectedDate,
    required this.items,
    required this.onDayTap,
    required this.zoom,
    required this.onZoomChanged,
    this.header,
    this.showZoomControls = true,
  });
  final DateTime month, selectedDate;
  final List<MonthDiaryItem> items;
  final ValueChanged<DateTime> onDayTap;
  final double zoom;
  final ValueChanged<double> onZoomChanged;
  final Widget? header;
  final bool showZoomControls;
  @override
  State<MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<MonthCalendar> {
  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final first = DateTime(widget.month.year, widget.month.month);
      final offset = first.weekday - 1;
      final start = DateTime(first.year, first.month, 1 - offset);
      final weeks =
          (offset + DateUtils.getDaysInMonth(first.year, first.month) + 6) ~/ 7;
      final byDay = <DateTime, List<MonthDiaryItem>>{};
      for (final item in widget.items) {
        (byDay[DateUtils.dateOnly(item.startAt)] ??= []).add(item);
      }
      for (final items in byDay.values) {
        items.sort((a, b) {
          final t = a.startAt.compareTo(b.startAt);
          return t != 0 ? t : a.label.compareTo(b.label);
        });
      }
      final weights = List.generate(
        7,
        (d) =>
            byDay.entries.any(
              (e) => e.key.weekday == d + 1 && e.value.length >= 10,
            )
            ? 2
            : 1,
      );
      final total = weights.reduce((a, b) => a + b);
      final unit = math.max(constraints.maxWidth / total, 140 * widget.zoom);
      final width = unit * total;
      final sideways = width > constraints.maxWidth;
      return SingleChildScrollView(
        controller: _vertical,
        key: PageStorageKey('month-weeks-${first.year}-${first.month}'),
        child: Column(
          children: [
            if (widget.header != null) widget.header!,
            if (widget.showZoomControls)
              Align(
                alignment: Alignment.centerRight,
                child: MonthCalendarZoomControls(
                  zoom: widget.zoom,
                  onChanged: widget.onZoomChanged,
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Text(
                    sideways
                        ? 'Tap a day for Day View · Scroll left/right for whole week'
                        : 'Tap a day for Day View',
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ),
            Scrollbar(
              controller: _horizontal,
              thumbVisibility: sideways,
              notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                key: const PageStorageKey('month-calendar-horizontal'),
                controller: _horizontal,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          for (var d = 0; d < 7; d++)
                            SizedBox(
                              width: unit * weights[d],
                              child: Container(
                                color: const Color(0xfff1f5f9),
                                padding: const EdgeInsets.all(9),
                                alignment: Alignment.center,
                                child: Text(
                                  const [
                                    'Mon',
                                    'Tue',
                                    'Wed',
                                    'Thu',
                                    'Fri',
                                    'Sat',
                                    'Sun',
                                  ][d],
                                ),
                              ),
                            ),
                        ],
                      ),
                      for (var w = 0; w < weeks; w++)
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var d = 0; d < 7; d++)
                                SizedBox(
                                  width: unit * weights[d],
                                  child: _day(
                                    DateTime(
                                      start.year,
                                      start.month,
                                      start.day + w * 7 + d,
                                    ),
                                    byDay,
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
            const SizedBox(height: 88),
          ],
        ),
      );
    },
  );
  Widget _day(DateTime date, Map<DateTime, List<MonthDiaryItem>> byDay) {
    final items = byDay[date] ?? [];
    final selected = DateUtils.isSameDay(date, widget.selectedDate);
    final today = DateUtils.isSameDay(date, DateTime.now());
    final current = date.month == widget.month.month;
    final used = items
        .where((i) => !i.isCancelled)
        .fold<int>(0, (sum, i) => sum + i.rinksUsed);
    return Semantics(
      button: true,
      label:
          '${DateFormat('EEEE d MMMM yyyy').format(date)}. ${items.length} fixtures. Open Day View.',
      child: Material(
        color: selected
            ? const Color(0xffeff6ff)
            : current
            ? Colors.white
            : const Color(0xfff3f4f6),
        child: InkWell(
          key: ValueKey('month-day-${date.toIso8601String()}'),
          onTap: () => widget.onDayTap(date),
          child: Container(
            constraints: BoxConstraints(minHeight: 112 * widget.zoom),
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              border: Border.all(
                color: selected || today
                    ? const Color(0xff2563eb)
                    : const Color(0xffdbe2ea),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        DateFormat('dd-MMM-yy').format(date),
                        style: TextStyle(
                          fontSize: 12 * widget.zoom,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (today) const Icon(Icons.today, size: 14),
                    const SizedBox(width: 4),
                    if (items.isNotEmpty)
                      Text(
                        '${items.length}',
                        style: const TextStyle(fontSize: 11),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (items.length >= 10)
                  for (var i = 0; i < items.length; i += 2)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _label(items[i])),
                        const SizedBox(width: 6),
                        Expanded(
                          child: i + 1 < items.length
                              ? _label(items[i + 1])
                              : const SizedBox(),
                        ),
                      ],
                    )
                else
                  for (final item in items) _label(item),
                const Spacer(),
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Open day',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xff475569),
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 14),
                  ],
                ),
                const SizedBox(height: 3),
                Container(
                  height: 4,
                  color: used == 0
                      ? const Color(0xffe5e7eb)
                      : used <= 2
                      ? const Color(0xff22c55e)
                      : used <= 5
                      ? const Color(0xfff59e0b)
                      : const Color(0xffdc2626),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(MonthDiaryItem item) {
    final foreground = item.isCancelled
        ? Colors.grey.shade800
        : item.foregroundColor;
    return Container(
      key: ValueKey('month-fixture-${item.fixtureId}'),
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: item.isCancelled ? Colors.grey.shade300 : item.backgroundColor,
        borderRadius: BorderRadius.circular(5),
        border: item.isMine ? Border.all(color: foreground, width: 1.4) : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              '${item.isCancelled ? 'Cancelled · ' : ''}${item.label}',
              softWrap: true,
              style: TextStyle(
                fontSize: 13 * widget.zoom,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ),
          if (item.isMine)
            Icon(Icons.person, size: 13 * widget.zoom, color: foreground),
        ],
      ),
    );
  }
}

class MonthCalendarZoomControls extends StatelessWidget {
  const MonthCalendarZoomControls({
    super.key,
    required this.zoom,
    required this.onChanged,
  });
  final double zoom;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: 'Smaller calendar',
        onPressed: zoom <= .8
            ? null
            : () => onChanged((zoom - .1).clamp(.8, 1.6)),
        icon: const Icon(Icons.zoom_out),
      ),
      Text('${(zoom * 100).round()}%'),
      IconButton(
        tooltip: 'Larger calendar',
        onPressed: zoom >= 1.6
            ? null
            : () => onChanged((zoom + .1).clamp(.8, 1.6)),
        icon: const Icon(Icons.zoom_in),
      ),
    ],
  );
}
