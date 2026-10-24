import '../fixtures/next_fixture_reminder_button.dart';
import '../communications/club_options_button.dart';
import 'diary_view_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'month_calendar.dart';
import 'month_diary_repository.dart';

import '../../core/utils/date_format.dart';

import 'diary_day_screen.dart';

class MonthOverviewScreen extends StatefulWidget {
  const MonthOverviewScreen({
    super.key,
    required this.clubId,
    required this.clubName,
    required this.initialDate,
    this.showNextMatchOnOpen = false,
  });

  final String clubId;
  final String clubName;
  final DateTime initialDate;
  final bool showNextMatchOnOpen;

  @override
  State<MonthOverviewScreen> createState() => _MonthOverviewScreenState();
}

class _MonthOverviewScreenState extends State<MonthOverviewScreen> {
  static const _windowTitle = MethodChannel('bowls/window_title');
  Future<void> _updateWindowTitle({bool reset = false}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
    try {
      await _windowTitle.invokeMethod<void>(
        reset ? 'reset' : 'set',
        reset ? null : _monthLabel(_visibleMonth),
      );
    } on MissingPluginException {
      // Other hosts and widget tests do not provide the Windows title channel.
    }
  }

  @override
  void dispose() {
    _updateWindowTitle(reset: true);
    super.dispose();
  }

  bool _shownEntryReminder = false;
  final _client = Supabase.instance.client;

  late DateTime _visibleMonth;
  late DateTime _selectedDate;

  bool _isLoading = true;
  String? _loadError;

  double _monthZoom = 1.0;

  List<MonthDiaryItem> _items = [];

  String? _myProfileId;

  void _setMonthZoom(double nextZoom) {
    if (nextZoom == _monthZoom) return;

    setState(() {
      _monthZoom = nextZoom;
    });
  }

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
      widget.initialDate.day,
    );

    _visibleMonth = DateTime(widget.initialDate.year, widget.initialDate.month);
    _updateWindowTitle();
    _loadMonth();
  }

  Future<void> _loadMonth() async {
    _updateWindowTitle();
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
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

      final rows = await MonthDiaryRepository(
        _client,
        widget.clubId,
      ).load(_visibleMonth);
      if (!mounted) return;

      setState(() {
        _items = rows.map(_mapFixture).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _isLoading = false;
      });
    }
  }

  MonthDiaryItem _mapFixture(Map<String, dynamic> row) {
    final startAt = parseClubTime(row['start_at'].toString());

    final endAt = row['end_at'] != null
        ? parseClubTime(row['end_at'].toString())
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

    final venueName = ((row['venue'] as Map?)?['name'] ?? '').toString().trim();
    final title = row['is_home'] == false
        ? (venueName.isNotEmpty ? venueName : 'Venue to be confirmed')
        : isInternal
        ? (typeName.isNotEmpty ? typeName : 'Internal Fixture')
        : (opponentName.isNotEmpty ? opponentName : typeName);

    final homeAway = row['is_home'] == true ? 'H' : 'A';

    final isCancelled = row['cancelled_at'] != null;

    return MonthDiaryItem(
      fixtureId: row['id'].toString(),
      startAt: startAt,
      endAt: endAt,
      label: isInternal && row['is_home'] != false
          ? '${_timeLabel(startAt)} • $title'
          : '${_timeLabel(startAt)} $homeAway • $title',
      backgroundColor: bg,
      foregroundColor: fg,
      isMine: _fixtureContainsCurrentUser(row),
      rinksUsed: (row['fixture_rinks'] as List?)?.length ?? 0,
      isCancelled: isCancelled,
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

  Future<void> _goToToday() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    setState(() {
      _selectedDate = today;
      _visibleMonth = DateTime(today.year, today.month);
    });

    await _loadMonth();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Monthly Diary'),
          actions: [
            NextFixtureReminderButton(
              clubId: widget.clubId,
              clubName: widget.clubName,
              showOnOpen: widget.showNextMatchOnOpen && !_shownEntryReminder,
              onAutomaticOpen: () => _shownEntryReminder = true,
            ),
            ClubOptionsButton(clubId: widget.clubId, clubName: widget.clubName),
          ],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Monthly Diary'),
          actions: [
            NextFixtureReminderButton(
              clubId: widget.clubId,
              clubName: widget.clubName,
              showOnOpen: widget.showNextMatchOnOpen && !_shownEntryReminder,
              onAutomaticOpen: () => _shownEntryReminder = true,
            ),
            ClubOptionsButton(clubId: widget.clubId, clubName: widget.clubName),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_loadError!),
        ),
      );
    }

    final toolbar = AppBar(
      primary: true,
      toolbarHeight: 44,
      title: Text(
        _monthLabel(_visibleMonth),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      actions: [
        NextFixtureReminderButton(
          clubId: widget.clubId,
          clubName: widget.clubName,
          showOnOpen: widget.showNextMatchOnOpen && !_shownEntryReminder,
          onAutomaticOpen: () => _shownEntryReminder = true,
        ),
        ClubOptionsButton(clubId: widget.clubId, clubName: widget.clubName),
      ],
      bottom: DiaryViewBar(
        selected: DiaryView.month,
        clubId: widget.clubId,
        clubName: widget.clubName,
        date: _selectedDate,
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
    return Scaffold(
      appBar: toolbar,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Material(
        key: const ValueKey('month-floating-navigation'),
        elevation: 4,
        color: Theme.of(context).colorScheme.surface,
        shape: StadiumBorder(
          side: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () => _moveMonth(-1),
              icon: const Icon(Icons.chevron_left),
              label: const Text('Previous'),
            ),
            Container(
              width: 1,
              height: 22,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
              iconAlignment: IconAlignment.end,
              onPressed: () => _moveMonth(1),
              icon: const Icon(Icons.chevron_right),
              label: const Text('Next'),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: MonthCalendar(
          month: _visibleMonth,
          selectedDate: _selectedDate,
          items: _items,
          onDayTap: _openDay,
          zoom: _monthZoom,
          onZoomChanged: _setMonthZoom,
          showZoomControls: false,
          header: Column(
            children: [
              _MonthHeader(
                clubName: widget.clubName,
                selectedDate: _selectedDate,
                onToday: _goToToday,
                zoom: _monthZoom,
                onZoomChanged: _setMonthZoom,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDay(DateTime date) async {
    final selected = DateTime(date.year, date.month, date.day);

    setState(() {
      _selectedDate = selected;
      _visibleMonth = DateTime(selected.year, selected.month);
    });

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DiaryDayScreen(
          clubId: widget.clubId,
          clubName: widget.clubName,
          date: selected,
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
    required this.selectedDate,
    required this.onToday,
    required this.zoom,
    required this.onZoomChanged,
  });

  final String clubName;
  final DateTime selectedDate;
  final VoidCallback onToday;
  final double zoom;
  final ValueChanged<double> onZoomChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedDateText = Text(
      'Selected Day: ${_prettyDate(selectedDate)}',
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        color: Color(0xFF4B5563),
      ),
    );

    final actionRow = Row(
      children: [
        FilledButton.icon(
          onPressed: onToday,
          icon: const Icon(Icons.today),
          label: const Text('Today'),
        ),
        const Spacer(),
        MonthCalendarZoomControls(zoom: zoom, onChanged: onZoomChanged),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
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
          const SizedBox(height: 8),
          const SizedBox(height: 10),
          actionRow,
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: Center(child: selectedDateText),
          ),
        ],
      ),
    );
  }
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
