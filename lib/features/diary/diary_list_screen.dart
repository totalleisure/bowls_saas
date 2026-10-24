import '../fixtures/next_fixture_reminder_button.dart';
import 'diary_involvement.dart';
import '../communications/club_options_button.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/date_format.dart';
import '../dashboard/dashboard_filter_screen.dart';
import '../../models/dashboard_fixture_filter.dart';
import '../fixtures/fixture_details_page.dart';
import '../fixtures/fixture_display.dart';
import 'diary_list_filter.dart';
import 'diary_list_repository.dart';
import 'diary_view_bar.dart';

class DiaryListScreen extends StatefulWidget {
  final String clubId;
  final String clubName;
  final DateTime initialDate;
  final bool showNextMatchOnOpen;
  // Injection points keep the date navigation and filtering testable offline.
  final Future<List<Map<String, dynamic>>> Function(DateTime, DateTime)?
  entriesLoader;
  final Future<List<Map<String, dynamic>>> Function()? typesLoader;
  final Future<List<Map<String, dynamic>>> Function()? teamsLoader;
  final Future<DiaryInvolvement> Function(DateTime, DateTime)?
  involvementLoader;
  final Future<Map<String, dynamic>?> Function()? nextMatchLoader;
  final String? userId;
  final DateTime Function()? now;
  const DiaryListScreen({
    super.key,
    required this.clubId,
    required this.clubName,
    required this.initialDate,
    this.showNextMatchOnOpen = false,
    this.entriesLoader,
    this.typesLoader,
    this.teamsLoader,
    this.userId,
    this.involvementLoader,
    this.nextMatchLoader,
    this.now,
  });
  @override
  State<DiaryListScreen> createState() => _DiaryListScreenState();
}

class _DiaryListScreenState extends State<DiaryListScreen> {
  bool _shownEntryReminder = false;
  final _scroll = ScrollController();
  final _search = TextEditingController();
  String _searchText = '';
  bool get _narrowed => _filter.isFiltered || _searchText.trim().isNotEmpty;
  final _pivotKey = GlobalKey();
  late DateTime _anchor;
  late DateTime _from;
  late DateTime _until;
  DiaryListFilter _filter = const DiaryListFilter();
  List<Map<String, dynamic>> _entries = [];
  List<Map<String, dynamic>> _teams = [];
  bool _busy = true;
  bool _ready = false;
  bool _awayFromToday = false;
  String? _error;
  String? _preferenceError;
  String? _involvementError;
  bool _findingNext = false;
  String? _jumpTargetId;
  late final DiaryInvolvementRepository _personal = DiaryInvolvementRepository(
    Supabase.instance.client,
    widget.clubId,
  );
  late String _storageKey;
  DiaryListRepository get _repository =>
      DiaryListRepository(Supabase.instance.client, widget.clubId);
  DateTime get _today {
    final now = widget.now?.call() ?? toClubTime(DateTime.now());
    return DateTime(now.year, now.month, now.day);
  }

  Future<List<Map<String, dynamic>>> _load(DateTime a, DateTime b) async {
    final entries = widget.entriesLoader?.call(a, b) ?? _repository.load(a, b);
    final involvement = (() async {
      try {
        final result =
            await (widget.involvementLoader?.call(a, b) ??
                (widget.entriesLoader != null
                    ? Future.value(const DiaryInvolvement())
                    : _personal.load(a, b)));
        if (mounted) setState(() => _involvementError = null);
        return result;
      } catch (_) {
        if (mounted) {
          setState(
            () => _involvementError =
                'Personal markers could not be loaded. Refresh to try again.',
          );
        }
        return const DiaryInvolvement();
      }
    })();
    final results = await Future.wait<dynamic>([entries, involvement]);
    final personal = results[1] as DiaryInvolvement;
    return [
      for (final row in results[0] as List<Map<String, dynamic>>)
        {...row, '_involvement': personal.badgesFor(row)},
    ];
  }

  Future<List<Map<String, dynamic>>> _types() =>
      widget.typesLoader?.call() ?? _repository.loadTypes();
  @override
  void initState() {
    super.initState();
    _anchor = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
      widget.initialDate.day,
    );
    _from = _anchor;
    _until = DateTime(_anchor.year, _anchor.month + 1, _anchor.day);
    _scroll.addListener(_trackPosition);
    _initialise();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _trackPosition() {
    final away = _anchor != _today || _scroll.offset.abs() > 100;
    if (_awayFromToday != away && mounted) {
      setState(() => _awayFromToday = away);
    }
  }

  Future<void> _initialise() async {
    try {
      final userId =
          widget.userId ?? Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw StateError('Please sign in to view the diary.');
      _storageKey = DiaryListFilter.storageKey(userId, widget.clubId);
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_storageKey);
      if (saved != null) {
        _filter = DiaryListFilter.fromJson(
          jsonDecode(saved) as Map<String, dynamic>,
        );
      }
      _teams = await (widget.teamsLoader?.call() ?? _repository.loadTeams());
      if (!mounted) return;
      _ready = true;
      if (_filter.fixtures.period != 'all') {
        final start = _filter.fixtures.periodStart(_today);
        _anchor = DateTime(start.year, start.month, start.day);
        _from = _anchor;
        _until = DateTime(_anchor.year, _anchor.month + 1, _anchor.day);
      }
      await _reload();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _busy = false;
        });
      }
    }
  }

  Future<void> _reload() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rows = await _load(_from, _until);
      if (mounted) setState(() => _entries = rows);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _extend(bool earlier, {bool reveal = false}) async {
    if (_busy || !_ready) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final first = earlier
        ? DateTime(_from.year, _from.month - 1, _from.day)
        : _until;
    final last = earlier
        ? _from
        : DateTime(_until.year, _until.month + 1, _until.day);
    try {
      final added = await _load(first, last);
      if (!mounted) return;
      setState(() {
        final byId = {
          for (final row in [..._entries, ...added])
            '${row['_maintenance'] == true ? 'm' : 'f'}:${row['id']}': row,
        };
        _entries = byId.values.toList();
        if (earlier) {
          _from = first;
        } else {
          _until = last;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && reveal && earlier && _error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.minScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _saveFilter(DiaryListFilter next) async {
    setState(() {
      _filter = next;
      _preferenceError = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(_storageKey, jsonEncode(next.toJson()))) {
        throw StateError('Save failed');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _preferenceError =
              'These filters could not be saved for your next visit.',
        );
      }
    }
  }

  Future<void> _filters() async {
    final result = await Navigator.of(context).push<DashboardFixtureFilter>(
      MaterialPageRoute(
        builder: (_) => DashboardFilterScreen(
          initialFilter: _filter.fixtures,
          clubId: widget.clubId,
          diaryMode: true,
          fixtureTypesLoader: _types,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final oldPeriod = _filter.fixtures.period;
    await _saveFilter(_filter.copyWith(fixtures: result));
    if (mounted && result.period != 'all' && oldPeriod != result.period) {
      final start = result.periodStart(_today);
      await _goTo(DateTime(start.year, start.month, start.day));
    }
  }

  Future<void> _goTo(DateTime day, {String? targetId}) async {
    if (_busy) return;
    setState(() {
      _jumpTargetId = targetId;
      _anchor = targetId == null ? DateTime(day.year, day.month, day.day) : day;
      _from = DateTime(day.year, day.month, day.day);
      _until = DateTime(day.year, day.month + 1, day.day);
      _entries = [];
      _awayFromToday = _anchor != _today;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await _reload();
  }

  bool _beforeAnchor(Map<String, dynamic> row) {
    final date = _displayStart(row);
    return date.isBefore(_anchor) ||
        (_jumpTargetId != null &&
            date == _anchor &&
            row['id'].toString().compareTo(_jumpTargetId!) < 0);
  }

  Future<void> _nextMatch() async {
    if (_busy || _findingNext) return;
    setState(() => _findingNext = true);
    try {
      final next =
          await (widget.nextMatchLoader?.call() ??
              _personal.nextAccepted(
                widget.now == null
                    ? DateTime.now().toUtc()
                    : clubTimeToUtc(widget.now!()),
              ));
      if (!mounted) return;
      if (next == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You have no upcoming accepted fixtures.'),
          ),
        );
        return;
      }
      if (!_filter.matches(next, _today) ||
          !diaryEntryMatchesSearch(next, _searchText)) {
        final open = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Your next match is hidden'),
            content: Text(
              'Your current filters or search hide ${fixtureTitleUnified(next, myClubName: widget.clubName)}. You can open its details without changing your filters.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep browsing'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Open details'),
              ),
            ],
          ),
        );
        if (open == true && mounted) await _open(next);
        return;
      }
      await _goTo(
        parseClubTime(next['start_at'] as String),
        targetId: next['id'].toString(),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not find your next match. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _findingNext = false);
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _anchor,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null && mounted) await _goTo(date);
  }

  DateTime _displayStart(Map<String, dynamic> row) {
    final start = parseClubTime(row['start_at'] as String);
    // Ongoing maintenance remains visible at the start of the loaded span.
    return row['_maintenance'] == true && start.isBefore(_from) ? _from : start;
  }

  Future<void> _open(Map<String, dynamic> row) async {
    if (row['_maintenance'] == true) {
      final start = parseClubTime(row['start_at'] as String);
      final end = parseClubTime(row['end_at'] as String);
      final green = (row['green_areas'] as Map?)?['name'] ?? 'Green';
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(row['reason']?.toString() ?? 'Green maintenance'),
          content: SingleChildScrollView(
            child: Text(
              [
                '$green · Rink ${row['rink_number']}',
                'From ${DateFormat('EEEE d MMM yyyy, HH:mm').format(start)}',
                'Until ${DateFormat('EEEE d MMM yyyy, HH:mm').format(end)}',
                if ((row['notes']?.toString() ?? '').isNotEmpty)
                  row['notes'].toString(),
              ].join('\n\n'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FixtureDetailsPage(fixtureId: row['id'] as String),
      ),
    );
    if (mounted) await _reload();
  }

  List<Widget> _datedCards(List<Map<String, dynamic>> rows) {
    final children = <Widget>[];
    String? lastDay;
    for (final row in rows) {
      final day = DateFormat('EEEE d MMMM yyyy').format(_displayStart(row));
      if (day != lastDay) {
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
            child: Text(
              day,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        );
        lastDay = day;
      }
      children.add(
        DiaryEntryCard(
          entry: row,
          clubName: widget.clubName,
          onTap: () => _open(row),
        ),
      );
    }
    return children;
  }

  @override
  Widget build(BuildContext context) {
    final visible =
        _entries
            .where(
              (e) =>
                  _filter.matches(e, _today) &&
                  diaryEntryMatchesSearch(e, _searchText),
            )
            .toList()
          ..sort((a, b) {
            final dateOrder = _displayStart(a).compareTo(_displayStart(b));
            return dateOrder != 0
                ? dateOrder
                : a['id'].toString().compareTo(b['id'].toString());
          });
    final before = _datedCards(visible.where((e) => _beforeAnchor(e)).toList());
    final after = _datedCards(visible.where((e) => !_beforeAnchor(e)).toList());
    final hidden = _entries.length - visible.length;
    final teamIds = _teams.map((e) => e['id'].toString()).toSet();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diary · List'),
        actions: [
          IconButton(
            tooltip: 'Choose date',
            onPressed: _busy ? null : _pickDate,
            icon: const Icon(Icons.calendar_today),
          ),
          IconButton(
            tooltip: 'Refresh diary',
            onPressed: _busy ? null : (_ready ? _reload : _initialise),
            icon: const Icon(Icons.refresh),
          ),
          NextFixtureReminderButton(
            clubId: widget.clubId, clubName: widget.clubName,
            showOnOpen: widget.showNextMatchOnOpen && !_shownEntryReminder,
            onAutomaticOpen: () => _shownEntryReminder = true),
          ClubOptionsButton(clubId: widget.clubId, clubName: widget.clubName),
        ],
        bottom: DiaryViewBar(
          selected: DiaryView.list,
          clubId: widget.clubId,
          clubName: widget.clubName,
          date: _anchor,
        ),
      ),
      floatingActionButton: _awayFromToday
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : () => _goTo(_today),
              icon: const Icon(Icons.today),
              label: const Text('Today'),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.clubName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search events, fixtures or opponents',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchText.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _search.clear();
                                setState(() => _searchText = '');
                              },
                            ),
                    ),
                    onChanged: (value) => setState(() => _searchText = value),
                  ),
                  Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: _busy || _findingNext ? null : _nextMatch,
                        icon: const Icon(Icons.skip_next),
                        label: Text(
                          _findingNext ? 'Finding match…' : 'Next match',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: !_ready || _busy ? null : _filters,
                        icon: const Icon(Icons.filter_list),
                        label: Text(
                          _filter.isFiltered
                              ? 'Filters active'
                              : 'All activity',
                        ),
                      ),
                      DropdownButton<String>(
                        value: _filter.location,
                        items: const [
                          DropdownMenuItem(
                            value: 'all',
                            child: Text('Home & away'),
                          ),
                          DropdownMenuItem(value: 'home', child: Text('Home')),
                          DropdownMenuItem(value: 'away', child: Text('Away')),
                        ],
                        onChanged: !_ready || _busy
                            ? null
                            : (v) => _saveFilter(_filter.copyWith(location: v)),
                      ),
                      DropdownButton<String>(
                        value: _filter.team,
                        items: [
                          const DropdownMenuItem(
                            value: 'all',
                            child: Text('All teams'),
                          ),
                          const DropdownMenuItem(
                            value: 'unassigned',
                            child: Text('No team'),
                          ),
                          if (_filter.team != 'all' &&
                              _filter.team != 'unassigned' &&
                              !teamIds.contains(_filter.team))
                            DropdownMenuItem(
                              value: _filter.team,
                              child: const Text('Previously selected team'),
                            ),
                          for (final team in _teams)
                            DropdownMenuItem(
                              value: team['id'].toString(),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 180,
                                ),
                                child: Text(
                                  team['name']?.toString() ?? 'Team',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                        ],
                        onChanged: !_ready || _busy
                            ? null
                            : (v) => _saveFilter(_filter.copyWith(team: v)),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Showing ${visible.length} of ${_entries.length} diary entries · $hidden filtered out',
                      ),
                      if (_narrowed)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  _search.clear();
                                  setState(() => _searchText = '');
                                  _saveFilter(const DiaryListFilter());
                                },
                          child: const Text('Clear filters'),
                        ),
                    ],
                  ),
                  Text(
                    'Loaded dates: ${DateFormat('d MMM yyyy').format(_from)} – ${DateFormat('d MMM yyyy').format(_until.subtract(const Duration(days: 1)))}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (_involvementError != null)
                    Text(
                      _involvementError!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (_preferenceError != null)
                    Text(
                      _preferenceError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    const Text(
                      'The diary could not be fully loaded. Please retry.',
                    ),
                    Text(_error!, style: Theme.of(context).textTheme.bodySmall),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : (_ready ? _reload : _initialise),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            if (!_busy && _error == null && visible.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _narrowed
                      ? 'No entries match your filters or search in these dates.'
                      : 'No diary entries in these dates.',
                ),
              ),
            Expanded(
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: (notification) {
                  // Only extend in response to a user's movement, never an empty-layout loop.
                  if ((notification.dragDetails != null ||
                          _scroll.position.userScrollDirection !=
                              ScrollDirection.idle) &&
                      !_busy &&
                      _error == null) {
                    if (notification.metrics.extentBefore < 160 &&
                        (notification.scrollDelta ?? 0) < 0) {
                      _extend(true);
                    } else if (notification.metrics.extentAfter < 160 &&
                        (notification.scrollDelta ?? 0) > 0) {
                      _extend(false);
                    }
                  }
                  return false;
                },
                child: CustomScrollView(
                  controller: _scroll,
                  center: _pivotKey,
                  slivers: [
                    SliverList(
                      delegate: SliverChildListDelegate([
                        ...before.reversed,
                        if (before.isNotEmpty)
                          Center(
                            child: TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _extend(true, reveal: true),
                              child: const Text('Earlier dates'),
                            ),
                          ),
                      ]),
                    ),
                    SliverList(
                      key: _pivotKey,
                      delegate: SliverChildListDelegate([
                        if (before.isEmpty)
                          Center(
                            child: TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _extend(true, reveal: true),
                              child: const Text('Earlier dates'),
                            ),
                          ),
                        ...after,
                        Center(
                          child: TextButton(
                            onPressed: _busy ? null : () => _extend(false),
                            child: const Text('Later dates'),
                          ),
                        ),
                        const SizedBox(height: 80),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DiaryEntryCard extends StatelessWidget {
  final Map<String, dynamic> entry;
  final String clubName;
  final VoidCallback onTap;
  const DiaryEntryCard({
    super.key,
    required this.entry,
    required this.clubName,
    required this.onTap,
  });
  Color _colour(dynamic hex, Color fallback) {
    final raw = hex?.toString().replaceAll('#', '') ?? '';
    final value = int.tryParse(raw.length == 6 ? 'FF$raw' : raw, radix: 16);
    return value == null ? fallback : Color(value);
  }

  @override
  Widget build(BuildContext context) {
    final type = entry['competition_type'] as Map? ?? {};
    final scheme = type['colour_scheme'] as Map? ?? {};
    final isCancelled = entry['cancelled_at'] != null;
    final maintenance = entry['_maintenance'] == true;
    final usesRinks = type['uses_rinks'] != false;
    final start = parseClubTime(entry['start_at'] as String);
    final end = entry['end_at'] == null
        ? null
        : parseClubTime(entry['end_at'] as String);
    final title = maintenance
        ? (entry['reason']?.toString() ?? 'Green maintenance')
        : fixtureTitleUnified(entry, myClubName: clubName);
    final venue = (entry['venue'] as Map?)?['name']?.toString();
    final green = (entry['green_areas'] as Map?)?['name']?.toString();
    final rinks = entry['rinks_required'];
    final details = <String>[
      if (type['name'] != null && type['name'] != title)
        type['name'].toString(),
      if (!maintenance &&
          usesRinks &&
          type['is_internal'] != true &&
          type['selection_mode'] != 'open')
        entry['is_home'] == true ? 'Home' : 'Away',
      if (venue != null && venue.isNotEmpty) venue,
      if (usesRinks && green != null && green.isNotEmpty) green,
      if (maintenance) 'Rink ${entry['rink_number']}',
      if (!maintenance && usesRinks && rinks is num && rinks > 0)
        '$rinks ${rinks == 1 ? 'rink' : 'rinks'}',
      if (maintenance) 'From ${DateFormat('d MMM, HH:mm').format(start)}',
      if (maintenance && end != null)
        'Until ${DateFormat('d MMM, HH:mm').format(end)}',
    ];
    final foreground = isCancelled ? Colors.grey.shade800 : _colour(
      scheme['foreground_hex'],
      Theme.of(context).colorScheme.onSurface,
    );
    return Card(
      color: isCancelled ? Colors.grey.shade300 : _colour(
        scheme['background_hex'],
        Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 54,
                child: Text(
                  DateFormat('HH:mm').format(start),
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isCancelled)
                      Text(
                        'Cancelled',
                        style: TextStyle(
                          color: foreground,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    Text(
                      title,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if ((entry['_involvement'] as List? ?? []).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 2),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final label in entry['_involvement'] as List)
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(color: foreground),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  child: Text(
                                    label.toString(),
                                    style: TextStyle(
                                      color: foreground,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (details.isNotEmpty)
                      Text(
                        details.join(' · '),
                        style: TextStyle(color: foreground),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}
