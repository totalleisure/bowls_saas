import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/hex_color.dart';
import '../diary/rinks_day_view.dart' show calculateSunsetBookingWindow;
import 'fixture_details_page.dart';
import 'member_booking_repository.dart';
import 'widgets/member_booking_timeline.dart';

class MemberFixtureCreationPage extends StatefulWidget {
  const MemberFixtureCreationPage({
    super.key,
    required this.clubId,
    required this.clubName,
    this.repository,
    this.initialDate,
    this.initialGreenId,
    this.initialRinkLabel,
  });
  final String clubId, clubName;
  final MemberBookingRepository? repository;
  final DateTime? initialDate;
  final String? initialGreenId, initialRinkLabel;
  @override
  State<MemberFixtureCreationPage> createState() =>
      _MemberFixtureCreationPageState();
}

class _MemberFixtureCreationPageState extends State<MemberFixtureCreationPage> {
  late final _repo = widget.repository ?? MemberBookingRepository();
  late DateTime _date;
  List<Map<String, dynamic>> _types = [], _venues = [], _greens = [];
  Map<String, dynamic>? _type, _venue, _green;
  String? _member, _label, _error, _createdFixtureId;
  DateTime? _start;
  MemberBookingDay? _day;
  bool _loading = true, _saving = false, _checking = false;
  var _density = MemberTimelineDensity.compact;
  int _request = 0;
  bool _initialApplied = false;

  @override
  void initState() {
    super.initState();
    final now = toClubTime(DateTime.now());
    final initial = widget.initialDate ?? now;
    _date = DateTime(initial.year, initial.month, initial.day);
    _load();
  }

  String _message(Object e) => e
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Exception: ', '');
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _member = await _repo.memberId(widget.clubId);
      final results = await Future.wait([
        _repo.fixtureTypes(widget.clubId),
        _repo.venues(widget.clubId),
      ]);
      if (!mounted) return;
      _types = results[0];
      _venues = results[1];
      _venue = _venues.length == 1 ? _venues.single : null;
      if (widget.initialGreenId != null) {
        final id = await _repo.venueForGreen(widget.initialGreenId!);
        if (!mounted) return;
        _venue = _venues.where((v) => v['id'].toString() == id).firstOrNull;
      }
      _error = null;
      if (_venue != null) await _loadGreens();
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadGreens() async {
    final greens = await _repo.greens(_venue!['id'].toString());
    if (!mounted) return;
    _greens = greens;
    _green = greens.length == 1 ? greens.single : null;
    _green =
        greens
            .where((g) => g['id'].toString() == widget.initialGreenId)
            .firstOrNull ??
        _green;
    if (_green != null) await _loadDay();
  }

  Future<void> _loadDay() async {
    final request = ++_request, green = _green;
    setState(() {
      _day = null;
      _start = null;
      _label = null;
      _error = null;
      _checking = false;
    });
    if (green == null) return;
    try {
      final day = await _repo.day(widget.clubId, green['id'].toString(), _date);
      if (mounted && request == _request) {
        setState(() => _day = day);
        if (!_initialApplied &&
            widget.initialDate != null &&
            widget.initialRinkLabel != null) {
          _initialApplied = true;
          final timeline = MemberBookingTimeline(
            date: _date,
            labels: _labels,
            day: day,
            density: _density,
            latestEnd: _latestEnd,
            onSelect: _select,
          );
          if (timeline.available(
            widget.initialRinkLabel!,
            widget.initialDate!,
          )) {
            await _select(widget.initialRinkLabel!, widget.initialDate!);
          }
        }
      }
    } catch (e) {
      if (mounted && request == _request) setState(() => _error = _message(e));
    }
  }

  List<String> get _labels =>
      _green == null ? [] : memberBookingRinkLabels(_green!);
  DateTime? get _latestEnd {
    if (_green?['is_outdoor'] != true ||
        _green?['uses_sunset_cutoff'] != true) {
      return null;
    }
    final lat = double.tryParse('${_venue?['latitude']}'),
        lng = double.tryParse('${_venue?['longitude']}');
    if (lat == null || lng == null) return null;
    return calculateSunsetBookingWindow(
      date: _date,
      latitude: lat,
      longitude: lng,
      offsetMinutes:
          (_green?['sunset_booking_offset_minutes'] as num?)?.toInt() ?? 30,
    )?.bookableUntil;
  }

  void _changeDate(DateTime date) {
    setState(() => _date = DateTime(date.year, date.month, date.day));
    _loadDay();
  }

  Future<void> _pickDate() async {
    final now = toClubTime(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (picked != null && mounted) _changeDate(picked);
  }

  Future<void> _select(String label, DateTime start) async {
    if (_saving || _checking) return;
    final request = _request;
    setState(() {
      _checking = true;
      _start = null;
      _label = null;
      _error = null;
    });
    try {
      await _repo.checkSlot(_green!['id'].toString(), label, start);
      if (mounted && request == _request) {
        setState(() {
          _label = label;
          _start = start;
        });
      }
    } catch (e) {
      if (mounted && request == _request) {
        await _loadDay();
        if (mounted) setState(() => _error = _message(e));
      }
    } finally {
      if (mounted && request == _request) setState(() => _checking = false);
    }
  }

  Future<void> _book() async {
    if (_saving || _type == null || _start == null || _label == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      _createdFixtureId ??= await _repo.book(
        clubId: widget.clubId,
        memberId: _member!,
        type: _type!,
        venueId: _venue!['id'].toString(),
        green: _green!,
        label: _label!,
        start: _start!,
      );
      if (!mounted) return;
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => FixtureDetailsPage(fixtureId: _createdFixtureId!),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        await _loadDay();
        if (mounted) setState(() => _error = _message(e));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _decoration(String label, {Color? fill}) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(fontWeight: FontWeight.bold),
    floatingLabelBehavior: FloatingLabelBehavior.always,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    border: const OutlineInputBorder(),
    filled: fill != null,
    fillColor: fill,
  );

  @override
  Widget build(BuildContext context) {
    if (!_loading && _type == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Choose Member Fixture Type'),
          toolbarHeight: 44,
        ),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (_error != null) ...[
              Text(_error!),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
            if (_types.isEmpty && _error == null)
              const Text(
                'No Member Fixture Types are available for this club.',
              ),
            for (final type in _types)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Builder(
                  builder: (context) {
                    final colors =
                        type['colour_scheme'] as Map<String, dynamic>?;
                    final scheme = Theme.of(context).colorScheme;
                    return Material(
                      color: colorFromHex(
                        colors?['background_hex']?.toString(),
                        fallback: scheme.surfaceContainerLow,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      child: ListTile(
                        key: ValueKey('member-type-${type['id']}'),
                        title: Text(
                          type['name'].toString(),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: colorFromHex(
                              colors?['foreground_hex']?.toString(),
                              fallback: scheme.onSurface,
                            ),
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => setState(() => _type = type),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final colors = _type?['colour_scheme'] as Map<String, dynamic>?;
    final bg = colors == null
        ? null
        : colorFromHex(
            colors['background_hex']?.toString(),
            fallback: scheme.surface,
          );
    final fg = colors == null
        ? scheme.onSurface
        : colorFromHex(
            colors['foreground_hex']?.toString(),
            fallback: scheme.onSurface,
          );
    final today = DateUtils.dateOnly(toClubTime(DateTime.now()));
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Book a rink'), toolbarHeight: 44),
        bottomNavigationBar: !_loading && _type != null
            ? SafeArea(
                top: false,
                child: Material(
                  elevation: 8,
                  color: scheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_checking) const LinearProgressIndicator(),
                        Text(
                          _start == null
                              ? 'Select a free rink and start time.'
                              : 'Selected, not booked: $_label · ${DateFormat.Hm().format(_start!)}–${DateFormat.Hm().format(_start!.add(memberBookingDuration))}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        FilledButton(
                          onPressed: _start != null && !_saving && !_checking
                              ? _book
                              : null,
                          child: Text(_saving ? 'Booking…' : 'Book rink'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : null,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : AbsorbPointer(
                absorbing: _saving,
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    DropdownButtonFormField<String>(
                      key: const Key('member-fixture-type'),
                      initialValue: _type?['id']?.toString(),
                      isExpanded: true,
                      decoration: _decoration('Fixture Type', fill: bg),
                      style: TextStyle(color: fg, fontSize: 14),
                      hint: const Text('Choose a Member Fixture Type'),
                      selectedItemBuilder: (context) => _types
                          .map(
                            (t) => Text(
                              t['name'].toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: fg),
                            ),
                          )
                          .toList(),
                      items: _types
                          .map(
                            (t) => DropdownMenuItem(
                              value: t['id'].toString(),
                              child: Text(
                                t['name'].toString(),
                                style: TextStyle(color: scheme.onSurface),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (id) => setState(
                        () => _type = _types.firstWhere(
                          (t) => t['id'].toString() == id,
                        ),
                      ),
                    ),
                    if (_types.isEmpty)
                      const Text(
                        'No Member Fixture Types are available for this club.',
                      ),
                    const SizedBox(height: 12),
                    InputDecorator(
                      decoration: _decoration('Booking Date'),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Previous day',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.chevron_left,
                              size: 32,
                              weight: 700,
                            ),
                            onPressed: _date.isAfter(today)
                                ? () => _changeDate(
                                    _date.subtract(const Duration(days: 1)),
                                  )
                                : null,
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: _pickDate,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 5,
                                ),
                                child: Text(
                                  DateFormat('EEEE, d MMM yyyy').format(_date),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Choose booking date',
                            visualDensity: VisualDensity.compact,
                            onPressed: _pickDate,
                            icon: const Icon(Icons.calendar_month, size: 20),
                          ),
                          IconButton(
                            tooltip: 'Next day',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.chevron_right,
                              size: 32,
                              weight: 700,
                            ),
                            onPressed: () =>
                                _changeDate(_date.add(const Duration(days: 1))),
                          ),
                        ],
                      ),
                    ),
                    if (_venues.length > 1) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _venue?['id'].toString(),
                        decoration: _decoration('Home venue'),
                        isExpanded: true,
                        items: _venues
                            .map(
                              (v) => DropdownMenuItem(
                                value: v['id'].toString(),
                                child: Text(v['name'].toString()),
                              ),
                            )
                            .toList(),
                        onChanged: (id) async {
                          setState(() {
                            _venue = _venues.firstWhere(
                              (v) => v['id'].toString() == id,
                            );
                            _green = null;
                            _day = null;
                            _start = null;
                            _label = null;
                            _loading = true;
                            ++_request;
                          });
                          try {
                            await _loadGreens();
                          } catch (e) {
                            if (mounted) setState(() => _error = _message(e));
                          } finally {
                            if (mounted) setState(() => _loading = false);
                          }
                        },
                      ),
                    ],
                    if (_greens.length > 1) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _green?['id'].toString(),
                        decoration: _decoration('Green'),
                        isExpanded: true,
                        items: _greens
                            .map(
                              (g) => DropdownMenuItem(
                                value: g['id'].toString(),
                                child: Text(g['name'].toString()),
                              ),
                            )
                            .toList(),
                        onChanged: (id) {
                          setState(
                            () => _green = _greens.firstWhere(
                              (g) => g['id'].toString() == id,
                            ),
                          );
                          _loadDay();
                        },
                      ),
                    ],
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _error!,
                              style: TextStyle(color: scheme.error),
                            ),
                            TextButton(
                              onPressed: _green != null ? _loadDay : _load,
                              child: const Text('Refresh availability'),
                            ),
                          ],
                        ),
                      ),
                    if (_venue == null && _venues.isEmpty)
                      const Text('No home venue is configured.'),
                    if (_venue != null && _greens.isEmpty)
                      const Text('No green is configured for this venue.'),
                    if (_green != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_venue?['name']} · ${_green?['name']} · ${_labels.length} rinks',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          PopupMenuButton<MemberTimelineDensity>(
                            tooltip: 'Timeline density',
                            initialValue: _density,
                            onSelected: (v) => setState(() => _density = v),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: MemberTimelineDensity.fit,
                                child: Text('Fit Day'),
                              ),
                              PopupMenuItem(
                                value: MemberTimelineDensity.compact,
                                child: Text('Compact'),
                              ),
                              PopupMenuItem(
                                value: MemberTimelineDensity.detailed,
                                child: Text('Detailed'),
                              ),
                            ],
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text(
                                switch (_density) {
                                  MemberTimelineDensity.fit => 'Fit Day',
                                  MemberTimelineDensity.compact => 'Compact',
                                  MemberTimelineDensity.detailed => 'Detailed',
                                },
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_latestEnd != null)
                        Text(
                          'Bookings finish by ${DateFormat.Hm().format(_latestEnd!)} (sunset limit)',
                          style: const TextStyle(fontSize: 12),
                        ),
                      if (_day == null && _error == null)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      if (_day != null) ...[
                        MemberBookingTimeline(
                          date: _date,
                          labels: _labels,
                          day: _day!,
                          density: _density,
                          selectedLabel: _label,
                          selectedStart: _start,
                          latestEnd: _latestEnd,
                          enabled: !_saving && !_checking,
                          onSelect: _select,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Tap free space · swipe left or right for times',
                          style: TextStyle(fontSize: 12),
                        ),
                        if (_day!.fixtures.any(
                          (f) =>
                              (f['rinks_required'] as num? ?? 0) >
                              (f['fixture_rinks'] as List? ?? [])
                                  .where((r) => r['home_rink_label'] != null)
                                  .length,
                        ))
                          const Text(
                            'Availability includes bookings awaiting physical rink allocation.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ..._suggestions(),
                      ],
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  List<Widget> _suggestions() {
    final timeline = MemberBookingTimeline(
      date: _date,
      labels: _labels,
      day: _day!,
      density: _density,
      latestEnd: _latestEnd,
      onSelect: _select,
    );
    final choices = <({String label, DateTime start})>[];
    for (var minute = 9 * 60; minute + 150 <= 22 * 60; minute += 30) {
      final start = DateTime(
        _date.year,
        _date.month,
        _date.day,
        minute ~/ 60,
        minute % 60,
      );
      final labels = _labels.where((label) => timeline.available(label, start));
      if (labels.isNotEmpty) choices.add((label: labels.first, start: start));
      if (choices.length == 2) break;
    }
    if (choices.isEmpty) {
      return [
        const Text('No rink is free for 2½ hours on this date.'),
        TextButton(
          onPressed: () => _changeDate(_date.add(const Duration(days: 1))),
          child: const Text('Try next day →'),
        ),
      ];
    }
    return [
      for (final c in choices)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _checking ? null : () => _select(c.label, c.start),
            child: Text(
              '${DateFormat.Hm().format(c.start)}–${DateFormat.Hm().format(c.start.add(memberBookingDuration))} · ${c.label}',
            ),
          ),
        ),
    ];
  }
}
