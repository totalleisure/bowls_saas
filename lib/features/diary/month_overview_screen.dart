import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../fixtures/fixture_details_page.dart';

import 'rinks_day_view.dart';

enum DiaryViewMode { month, week, day, rinks }

class MonthOverviewScreen extends StatefulWidget {
  const MonthOverviewScreen({
    super.key,
    required this.clubId,
    required this.clubName,
    required this.initialDate,
  });

  final String clubId;
  final String clubName;
  final DateTime initialDate;

  @override
  State<MonthOverviewScreen> createState() => _MonthOverviewScreenState();
}

class _MonthOverviewScreenState extends State<MonthOverviewScreen> {
  final _client = Supabase.instance.client;

  late DateTime _visibleMonth;

  bool _isLoading = true;
  String? _loadError;

  List<_MonthDiaryItem> _items = [];

String? _myProfileId;

  @override
  void initState() {
    super.initState();
    _visibleMonth = DateTime(widget.initialDate.year, widget.initialDate.month);
    _loadMonth();
  }

  Future<void> _loadMonth() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final monthStart = DateTime(_visibleMonth.year, _visibleMonth.month);
      final monthEnd = DateTime(_visibleMonth.year, _visibleMonth.month + 1);

      final userId = _client.auth.currentUser?.id;

      if (userId != null) {
        final mp = await _client
            .from('member_profiles')
            .select('id')
            .eq('user_id', userId)
            .maybeSingle();

        _myProfileId = mp?['id']?.toString();
      } else {
        _myProfileId = null;
      }

      final res = await _client
          .from('fixtures')
          .select('''
            id,
            club_id,
            start_at,
            end_at,
            is_home,
            opponent_name,
            green_area_id,
            rinks_required,
            competition_types (
              id,
              name,
              is_internal,
              selection_mode,
              colour_scheme:fixture_colour_schemes (
                background_hex,
                foreground_hex
              )
            ),
            fixture_rinks (
              id,
              home_rink_label,
              fixture_rink_assignments (
                member_profile_id
              )
            )
          ''')
          .eq('club_id', widget.clubId)
          .gte('start_at', monthStart.toIso8601String())
          .lt('start_at', monthEnd.toIso8601String())
          .order('start_at');

      final rows = List<Map<String, dynamic>>.from(res);

      setState(() {
        _items = rows.map(_mapFixture).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _loadError = e.toString();
        _isLoading = false;
      });
    }
  }

  _MonthDiaryItem _mapFixture(Map<String, dynamic> row) {
    final startAt = DateTime.parse(row['start_at'].toString()).toLocal();
    final endAt = row['end_at'] != null
        ? DateTime.parse(row['end_at'].toString()).toLocal()
        : startAt.add(const Duration(hours: 3));

    final type = row['competition_types'] as Map<String, dynamic>?;
    final colourScheme = type?['colour_scheme'] as Map<String, dynamic>?;

    final bg = _parseHexColor(
      colourScheme?['background_hex']?.toString(),
      const Color(0xFFDBEAFE),
    );

    final fg = _parseHexColor(
      colourScheme?['foreground_hex']?.toString(),
      const Color(0xFF1E3A8A),
    );

    final isInternal = type?['is_internal'] == true;
    final typeName = (type?['name'] ?? '').toString().trim();
    final opponentName = (row['opponent_name'] ?? '').toString().trim();

    final title = isInternal
        ? (typeName.isNotEmpty ? typeName : 'Internal Fixture')
        : (opponentName.isNotEmpty ? opponentName : typeName);

    final homeAway = row['is_home'] == true ? 'H' : 'A';

    return _MonthDiaryItem(
      fixtureId: row['id'].toString(),
      startAt: startAt,
      endAt: endAt,
      label: isInternal
          ? '${_timeLabel(startAt)} • $title'
          : '${_timeLabel(startAt)} $homeAway • $title',
      backgroundColor: bg,
      foregroundColor: fg,
      isMine: _fixtureContainsCurrentUser(row),
      rinksUsed: (row['fixture_rinks'] as List?)?.length ?? 0,
    );
  }

  bool _fixtureContainsCurrentUser(Map<String, dynamic> fixture) {
    if (_myProfileId == null) return false;

    final rinks = List<Map<String, dynamic>>.from(
      fixture['fixture_rinks'] ?? [],
    );

    for (final rink in rinks) {
      final assignments = List<Map<String, dynamic>>.from(
        rink['fixture_rink_assignments'] ?? [],
      );

      final found = assignments.any(
        (a) => a['member_profile_id']?.toString() == _myProfileId,
      );

      if (found) return true;
    }

    return false;
  }

  void _moveMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    });
    _loadMonth();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Monthly Overview')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_loadError!),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 44,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _MonthHeader(
              clubName: widget.clubName,
              visibleMonth: _visibleMonth,
              onPrevious: () => _moveMonth(-1),
              onNext: () => _moveMonth(1),
              onToday: () {
                setState(() {
                  final now = DateTime.now();
                  _visibleMonth = DateTime(now.year, now.month);
                });
                _loadMonth();
              },
            ),
            _ViewSwitcher(
              selected: DiaryViewMode.month,
              onSelected: (mode) {
                // Wire Week/Day/Rinks navigation later.
              },
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 980,
                  child: _MonthGrid(
                    month: _visibleMonth,
                    items: _items,
                    onFixtureTap: _openFixture,
                    onDayTap: _openDay,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFixture(String fixtureId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FixtureDetailsPage(fixtureId: fixtureId),
      ),
    );

    if (!mounted) return;
    await _loadMonth();
  }

  Future<void> _openDay(DateTime date) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RinkDayViewScreen(
          clubId: widget.clubId,
          clubName: widget.clubName,
          date: date,
        ),
      ),
    );

    if (!mounted) return;
    await _loadMonth();
  }

  Color _parseHexColor(String? hex, Color fallback) {
    if (hex == null || hex.trim().isEmpty) return fallback;
    var value = hex.trim().replaceFirst('#', '');
    if (value.length == 6) value = 'FF$value';
    final parsed = int.tryParse(value, radix: 16);
    if (parsed == null) return fallback;
    return Color(parsed);
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.clubName,
    required this.visibleMonth,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  final String clubName;
  final DateTime visibleMonth;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  clubName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF374151),
                  ),
                ),
                Text(
                  _monthLabel(visibleMonth),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF111827),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
          ),
          TextButton(
            onPressed: onToday,
            child: const Text('Today'),
          ),
        ],
      ),
    );
  }
}

class _ViewSwitcher extends StatelessWidget {
  const _ViewSwitcher({
    required this.selected,
    required this.onSelected,
  });

  final DiaryViewMode selected;
  final ValueChanged<DiaryViewMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: SegmentedButton<DiaryViewMode>(
        segments: const [
          ButtonSegment(value: DiaryViewMode.month, label: Text('Month')),
          ButtonSegment(value: DiaryViewMode.week, label: Text('Week')),
          ButtonSegment(value: DiaryViewMode.day, label: Text('Day')),
          ButtonSegment(value: DiaryViewMode.rinks, label: Text('Rinks')),
        ],
        selected: {selected},
        onSelectionChanged: (values) => onSelected(values.first),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.items,
    required this.onFixtureTap,
    required this.onDayTap,
  });

  final DateTime month;
  final List<_MonthDiaryItem> items;
  final ValueChanged<String> onFixtureTap;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(month.year, month.month);
    final startOffset = firstOfMonth.weekday - DateTime.monday;
    final gridStart = firstOfMonth.subtract(Duration(days: startOffset));

    return Column(
      children: [
        Row(
          children: const [
            _WeekdayHeader('Mon'),
            _WeekdayHeader('Tue'),
            _WeekdayHeader('Wed'),
            _WeekdayHeader('Thu'),
            _WeekdayHeader('Fri'),
            _WeekdayHeader('Sat'),
            _WeekdayHeader('Sun'),
          ],
        ),
        Expanded(
          child: GridView.builder(
            physics: const ClampingScrollPhysics(),
            itemCount: 42,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.05,
            ),
            itemBuilder: (context, index) {
              final date = gridStart.add(Duration(days: index));
              final dayItems = items
                  .where((i) =>
                      i.startAt.year == date.year &&
                      i.startAt.month == date.month &&
                      i.startAt.day == date.day)
                  .toList()
                ..sort((a, b) {
                  final timeCompare = a.startAt.compareTo(b.startAt);
                  if (timeCompare != 0) return timeCompare;
                  return a.label.compareTo(b.label);
                });

              return _MonthDayCell(
                date: date,
                isCurrentMonth: date.month == month.month,
                items: dayItems,
                onFixtureTap: onFixtureTap,
                onDayTap: onDayTap,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 34,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAFC),
          border: Border(
            top: BorderSide(color: Color(0xFFE5E7EB)),
            bottom: BorderSide(color: Color(0xFFE5E7EB)),
            right: BorderSide(color: Color(0xFFE5E7EB)),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _MonthDayCell extends StatelessWidget {
  const _MonthDayCell({
    required this.date,
    required this.isCurrentMonth,
    required this.items,
    required this.onFixtureTap,
    required this.onDayTap,
  });

  final DateTime date;
  final bool isCurrentMonth;
  final List<_MonthDiaryItem> items;
  final ValueChanged<String> onFixtureTap;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final isToday =
        date.year == today.year && date.month == today.month && date.day == today.day;

    final visibleItems = items.take(4).toList();
    final hiddenCount = items.length - visibleItems.length;

    return InkWell(
      onTap: () => onDayTap(date),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: isCurrentMonth ? Colors.white : const Color(0xFFF3F4F6),
          border: Border.all(
            color: isToday ? const Color(0xFF2563EB) : const Color(0xFFE5E7EB),
            width: isToday ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Text(
                '${date.day}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: isCurrentMonth ? const Color(0xFF111827) : const Color(0xFF9CA3AF),
                ),
              ),
            ),
            const SizedBox(height: 3),
            for (final item in visibleItems)
              _MonthFixtureChip(
                item: item,
                onTap: () => onFixtureTap(item.fixtureId),
              ),
            if (hiddenCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '+$hiddenCount more',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
            const Spacer(),
            _RinkUsageLine(items: items),
          ],
        ),
      ),
    );
  }
}

class _MonthFixtureChip extends StatelessWidget {
  const _MonthFixtureChip({
    required this.item,
    required this.onTap,
  });

  final _MonthDiaryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: item.backgroundColor,
            borderRadius: BorderRadius.circular(4),
            border: item.isMine
                ? Border.all(color: item.foregroundColor, width: 1.4)
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.05,
                    fontWeight: FontWeight.w700,
                    color: item.foregroundColor,
                  ),
                ),
              ),
              if (item.isMine) ...[
                const SizedBox(width: 2),
                Icon(
                  Icons.person,
                  size: 11,
                  color: item.foregroundColor,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RinkUsageLine extends StatelessWidget {
  const _RinkUsageLine({required this.items});

  final List<_MonthDiaryItem> items;

  @override
  Widget build(BuildContext context) {
    final rinksUsed = items.fold<int>(0, (sum, item) => sum + item.rinksUsed);

    Color color;
    if (rinksUsed == 0) {
      color = const Color(0xFFE5E7EB);
    } else if (rinksUsed <= 2) {
      color = const Color(0xFF22C55E);
    } else if (rinksUsed <= 5) {
      color = const Color(0xFFF59E0B);
    } else {
      color = const Color(0xFFDC2626);
    }

    return Container(
      height: 4,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _MonthDiaryItem {
  const _MonthDiaryItem({
    required this.fixtureId,
    required this.startAt,
    required this.endAt,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.isMine,
    required this.rinksUsed,
  });

  final String fixtureId;
  final DateTime startAt;
  final DateTime endAt;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final bool isMine;
  final int rinksUsed;
}

String _monthLabel(DateTime date) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  return '${months[date.month - 1]} ${date.year}';
}

String _timeLabel(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

String _prettyDate(DateTime dt) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
}