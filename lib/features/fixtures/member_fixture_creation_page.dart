import 'fixture_type_booking_policy.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/hex_color.dart';
import '../diary/rinks_day_view.dart' show calculateSunsetBookingWindow;
import 'fixture_details_page.dart';
import 'create_fixture_page.dart';
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
  bool _adminBooking = false;
  bool _homeBookingChosen = false;
  int? _rinkCountOverride;
  final List<String> _selectedLabels = [];
  int get _requiredRinks =>
      ((!_adminBooking && _type?['lock_rinks'] == true
                  ? null
                  : _rinkCountOverride) ??
              (_type?['default_rinks_required'] as num?)?.toInt() ??
              1)
          .clamp(1, 99);
  bool get _continueToDetails => _adminBooking || _requiredRinks > 1;

  void _changeRinkCount(int count) {
    if (!_adminBooking && _type?['lock_rinks'] == true) return;
    setState(() {
      _rinkCountOverride = count;
      if (_selectedLabels.length > count)
        _selectedLabels.removeRange(count, _selectedLabels.length);
      _label = _selectedLabels.firstOrNull;
      _error = null;
    });
  }

  Widget _rinkCountControl() {
    final locked = !_adminBooking && _type?['lock_rinks'] == true;
    final free = _start == null
        ? null
        : _day!.availableRinks(_start!, _labels, duration: _duration);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 4,
          children: [
            const Text(
              'Rinks needed',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                border: Border.all(color: Colors.blue.shade800),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const Key('fewer-rinks'),
                    tooltip: 'Fewer rinks',
                    icon: const Icon(Icons.chevron_left),
                    color: Colors.blue.shade900,
                    onPressed: locked || _checking || _requiredRinks <= 1
                        ? null
                        : () => _changeRinkCount(_requiredRinks - 1),
                  ),
                  Text(
                    '$_requiredRinks ${_requiredRinks == 1 ? 'rink' : 'rinks'}',
                    style: TextStyle(
                      color: Colors.blue.shade900,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    key: const Key('more-rinks'),
                    tooltip: 'More rinks',
                    icon: const Icon(Icons.chevron_right),
                    color: Colors.blue.shade900,
                    onPressed:
                        locked || _checking || _requiredRinks >= _labels.length
                        ? null
                        : () => _changeRinkCount(_requiredRinks + 1),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (locked)
          const Text(
            'Rink count is set by this Fixture Type.',
            style: TextStyle(fontSize: 12),
          ),
        if (_adminBooking &&
            _type?['lock_rinks'] == true &&
            _requiredRinks !=
                ((_type?['default_rinks_required'] as num?)?.toInt() ?? 1))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Admin override: this Fixture Type normally allows ${(_type?['default_rinks_required'] as num?)?.toInt() ?? 1} ${_type?['default_rinks_required'] == 1 ? 'rink' : 'rinks'} for member bookings.',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (free != null)
          Text(
            free < _requiredRinks
                ? 'Only $free of ${_labels.length} rinks are free for this whole time. Reduce the rink count or choose another time.'
                : '$free of ${_labels.length} rinks free for this whole time.',
            style: TextStyle(
              color: free < _requiredRinks
                  ? Colors.red.shade800
                  : Colors.green.shade900,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }

  final _bookingGridKey = GlobalKey();
  final _formScroll = ScrollController();

  @override
  void dispose() {
    _formScroll.dispose();
    super.dispose();
  }

  Future<void> _showBookingGrid() async {
    if (_bookingGridKey.currentContext == null && _formScroll.hasClients) {
      await _formScroll.animateTo(
        _formScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
    if (!mounted) return;
    final gridContext = _bookingGridKey.currentContext;
    if (gridContext != null) {
      await Scrollable.ensureVisible(
        gridContext,
        duration: const Duration(milliseconds: 300),
        alignment: 0,
        curve: Curves.easeInOut,
      );
    }
  }

  int? _durationOverride;
  Duration get _duration => Duration(
    minutes:
        _durationOverride ??
        (_type?['default_duration_minutes'] as num?)?.toInt() ??
        150,
  );
  List<Map<String, dynamic>> get _windows =>
      (_type?['booking_windows'] as List? ?? [])
          .map((w) => Map<String, dynamic>.from(w as Map))
          .toList();
  int _venueMinute(String field, int fallback) {
    final parts = '${_venue?[field]}'.split(':');
    return parts.length < 2
        ? fallback
        : int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  int get _opens => _venueMinute('club_start_time', 540);
  int get _closes => _venueMinute('club_end_time', 1320);
  bool _allowedStart(DateTime start) =>
      fixtureTypeTimingError(
        _type,
        _windows,
        start,
        start.add(_duration),
        privileged: _adminBooking,
      ) ==
      null;

  @override
  void initState() {
    super.initState();
    final now = toClubTime(DateTime.now());
    final initial = widget.initialDate ?? now;
    _date = DateTime(initial.year, initial.month, initial.day);
    _load();
  }

  String _message(Object e) => bookingErrorMessage(e);
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _member = await _repo.memberId(widget.clubId);
      _adminBooking = await _repo.canManageFixtures(widget.clubId);
      final results = await Future.wait([
        _adminBooking
            ? _repo.adminFixtureTypes(widget.clubId)
            : _repo.fixtureTypes(widget.clubId),
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
      _selectedLabels.clear();
      _error = null;
      _checking = false;
    });
    if (green == null) return;
    try {
      final day = await _repo.day(widget.clubId, green['id'].toString(), _date);
      if (mounted && request == _request) {
        setState(() => _day = day);
        await _applyInitialSlot();
      }
    } catch (e) {
      if (mounted && request == _request) setState(() => _error = _message(e));
    }
  }

  Future<void> _applyInitialSlot() async {
    if (_initialApplied ||
        _type == null ||
        _day == null ||
        widget.initialDate == null ||
        widget.initialRinkLabel == null)
      return;
    _initialApplied = true;
    final start = widget.initialDate!;
    final label = widget.initialRinkLabel!;
    final timingError = fixtureTypeTimingError(
      _type,
      _windows,
      start,
      start.add(_duration),
      privileged: _adminBooking,
    );
    final timeline = MemberBookingTimeline(
      date: _date,
      labels: _labels,
      day: _day!,
      density: _density,
      latestEnd: _latestEnd,
      onSelect: _select,
      duration: _duration,
      opens: _opens,
      closes: _closes,
      allowedStart: _allowedStart,
      rinksRequired: _requiredRinks,
    );
    if (!_labels.contains(label) || !timeline.available(label, start)) {
      setState(() {
        _start = start;
        _label = label;
        _error =
            timingError ??
            'The selected rink and time are not available for this duration. Choose another slot.';
      });
      return;
    }
    await _select(label, start);
  }

  void _chooseType(Map<String, dynamic> type) {
    setState(() {
      _type = type;
      _homeBookingChosen = false;
      _rinkCountOverride = null;
      _durationOverride = null;
      _start = null;
      _label = null;
      _selectedLabels.clear();
      _error = null;
    });
    _applyInitialSlot();
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
    final sameTime =
        _start != null &&
        memberBookingWallTime(_start!) == memberBookingWallTime(start);
    if (sameTime && _selectedLabels.contains(label)) {
      setState(() {
        _selectedLabels.remove(label);
        _label = _selectedLabels.firstOrNull;
        if (_selectedLabels.isEmpty) _start = null;
      });
      return;
    }
    if (sameTime && _selectedLabels.length >= _requiredRinks) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unselect a rink first to choose a different one.'),
        ),
      );
      return;
    }
    final request = _request;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      if (!_allowedStart(start))
        throw StateError(
          fixtureTypeTimingError(
            _type,
            _windows,
            start,
            start.add(_duration),
            privileged: _adminBooking,
          )!,
        );
      if (!_day!.canBook(
        label,
        start,
        _labels,
        duration: _duration,
        rinksRequired: _requiredRinks,
      )) {
        throw StateError(
          'There is not enough free space for $_requiredRinks rinks at this time. Choose another time or date.',
        );
      }
      await _repo.checkSlotWindow(
        _green!['id'].toString(),
        label,
        start,
        _duration,
      );
      if (mounted && request == _request) {
        setState(() {
          if (!sameTime) _selectedLabels.clear();
          _selectedLabels.add(label);
          _label = _selectedLabels.first;
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
    if (_saving ||
        _error != null ||
        _type == null ||
        _start == null ||
        _label == null)
      return;
    if (_selectedLabels.length != _requiredRinks) return;
    if (_continueToDetails) {
      setState(() => _checking = true);
      try {
        // Recheck the whole selection before handing it to the existing form.
        final day = await _repo.day(
          widget.clubId,
          _green!['id'].toString(),
          _date,
        );
        for (final label in _selectedLabels) {
          if (!day.canBook(
            label,
            _start!,
            _labels,
            duration: _duration,
            rinksRequired: _requiredRinks,
          )) {
            throw StateError(
              'Your selected rinks are no longer all available. Please choose again.',
            );
          }
          await _repo.checkSlotWindow(
            _green!['id'].toString(),
            label,
            _start!,
            _duration,
          );
        }
        if (!mounted) return;
        final result = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => CreateFixturePage(
              clubId: widget.clubId,
              clubName: widget.clubName,
              initialFixtureTypeId: _type!['id'].toString(),
              initialRinkBooking: InitialRinkBookingContext(
                greenAreaId: _green!['id'].toString(),
                greenName: _green!['name'].toString(),
                rinkLabel: _selectedLabels.first,
                rinkLabels: List.of(_selectedLabels),
                startAt: _start!,
                suggestedEndAt: _start!.add(_duration),
                latestEndAt:
                    _latestEnd ??
                    DateTime(
                      _date.year,
                      _date.month,
                      _date.day,
                      _closes ~/ 60,
                      _closes % 60,
                    ),
              ),
            ),
          ),
        );
        if (mounted && result == true) Navigator.pop(context, true);
      } catch (e) {
        if (mounted) setState(() => _error = _message(e));
      } finally {
        if (mounted) setState(() => _checking = false);
      }
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      _createdFixtureId ??= await _repo.bookWindow(
        clubId: widget.clubId,
        memberId: _member!,
        type: _type!,
        venueId: _venue!['id'].toString(),
        green: _green!,
        label: _label!,
        start: _start!,
        duration: _duration,
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
    // Internal types and bookings begun on a club diary slot are already home.
    if (!_loading &&
        _adminBooking &&
        _type != null &&
        _type!['is_internal'] != true &&
        !_homeBookingChosen &&
        widget.initialGreenId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Where will the fixture be played?')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '${_type!['name']} — choose Home or Away so we can guide you through the right booking process.',
            ),
            const SizedBox(height: 16),
            Card(
              color: const Color(0xffe7f1fc),
              child: ListTile(
                key: const Key('start-home-fixture'),
                leading: const Icon(Icons.home, color: Color(0xff23496b)),
                title: const Text(
                  'Home',
                  style: TextStyle(
                    color: Color(0xff23496b),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  'Choose the date, time and available club rinks.',
                  style: TextStyle(color: Color(0xff23496b)),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  setState(() => _homeBookingChosen = true);
                },
              ),
            ),
            Card(
              color: const Color(0xffe6f3e9),
              child: ListTile(
                key: const Key('start-away-fixture'),
                leading: const Icon(Icons.directions, color: Color(0xff235735)),
                title: const Text(
                  'Away',
                  style: TextStyle(
                    color: Color(0xff235735),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  'Choose the opponent and match details. Your club rinks will not be reserved.',
                  style: TextStyle(color: Color(0xff235735)),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final created = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => CreateFixturePage(
                        clubId: widget.clubId,
                        clubName: widget.clubName,
                        initialLocation: FixtureLocationType.away,
                        initialDate: _date,
                        initialFixtureTypeId: _type!['id'].toString(),
                      ),
                    ),
                  );
                  if (mounted && created == true) Navigator.pop(context, true);
                },
              ),
            ),
          ],
        ),
      );
    }
    if (!_loading && _type == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            _adminBooking
                ? 'Choose Home Fixture Type'
                : 'Choose Member Fixture Type',
          ),
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
                        onTap: () => _chooseType(type),
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
    final window = MediaQuery.sizeOf(context);
    final smallWindow = window.width < 600 || window.height < 650;
    final needsSlot = _start == null || _error != null;
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
                              : _requiredRinks == 1
                              ? 'Selected, not booked: $_label · ${DateFormat.Hm().format(_start!)}–${DateFormat.Hm().format(_start!.add(_duration))}'
                              : '${_selectedLabels.length} of $_requiredRinks rinks selected · ${DateFormat.Hm().format(_start!)}–${DateFormat.Hm().format(_start!.add(_duration))}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (smallWindow && needsSlot)
                          FilledButton.icon(
                            key: const Key('booking-grid-bottom-action'),
                            onPressed: _day == null || _checking
                                ? null
                                : _showBookingGrid,
                            icon: const Icon(Icons.arrow_downward),
                            label: const Text('Choose a rink and time'),
                          )
                        else
                          FilledButton(
                            onPressed:
                                _start != null &&
                                    _selectedLabels.length == _requiredRinks &&
                                    _error == null &&
                                    !_saving &&
                                    !_checking
                                ? _book
                                : null,
                            child: Text(
                              _saving
                                  ? 'Booking…'
                                  : _continueToDetails
                                  ? 'Continue to fixture details'
                                  : 'Book rink',
                            ),
                          ),
                        if (smallWindow)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Scroll up to change your duration from ${_duration.inMinutes} minutes.',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
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
                  controller: _formScroll,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
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
                      onChanged: (id) => setState(() {
                        _homeBookingChosen = false;
                        _durationOverride = null;
                        _rinkCountOverride = null;
                        _type = _types.firstWhere(
                          (t) => t['id'].toString() == id,
                        );
                        _start = null;
                        _label = null;
                        _selectedLabels.clear();
                      }),
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
                    FixtureBookingRulesHint(
                      type: _type,
                      windows: _windows,
                      privileged: _adminBooking,
                    ),
                    if (smallWindow && _day != null) ...[
                      FilledButton.icon(
                        onPressed: _showBookingGrid,
                        icon: const Icon(Icons.arrow_downward),
                        label: const Text('Choose a rink and time'),
                      ),
                      const Text(
                        'Scroll down to see available rinks and select your start time.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                    TextButton.icon(
                      icon: const Icon(Icons.access_time),
                      label: const Text('Choose an exact start time'),
                      onPressed: _day == null
                          ? null
                          : () async {
                              final time = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay(
                                  hour: _opens ~/ 60,
                                  minute: _opens % 60,
                                ),
                              );
                              if (time == null || !mounted) return;
                              final start = DateTime(
                                _date.year,
                                _date.month,
                                _date.day,
                                time.hour,
                                time.minute,
                              );
                              final timeline = MemberBookingTimeline(
                                date: _date,
                                labels: _labels,
                                day: _day!,
                                density: _density,
                                onSelect: _select,
                                duration: _duration,
                                opens: _opens,
                                closes: _closes,
                                allowedStart: _allowedStart,
                                rinksRequired: _requiredRinks,
                              );
                              final label = _labels
                                  .where(
                                    (label) => timeline.available(label, start),
                                  )
                                  .firstOrNull;
                              if (label == null) {
                                setState(
                                  () => _error =
                                      'No rink is available at that time under the booking rules.',
                                );
                                return;
                              }
                              await _select(label, start);
                            },
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
                              '${_green?['name']} · ${_labels.length} rinks',
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
                        const Text(
                          'Home fixture · nothing is booked until you save.',
                        ),
                        const SizedBox(height: 10),
                        _rinkCountControl(),
                        Padding(
                          key: _bookingGridKey,
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: const Text(
                            'Tap a green half-hour box to start your booking. Grey boxes cannot be selected for the chosen duration. A red outline shows your selection.',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        DropdownButtonFormField<int>(
                          key: ValueKey(
                            'duration_${_type?['id']}_$_durationOverride',
                          ),
                          initialValue: _duration.inMinutes,
                          decoration: _decoration('Duration (minutes)'),
                          items:
                              {
                                    for (
                                      var m = 30;
                                      m <=
                                          (_type?['lock_duration'] == true
                                              ? ((_type?['default_duration_minutes']
                                                            as num?)
                                                        ?.toInt() ??
                                                    150)
                                              : (_closes - _opens));
                                      m += 30
                                    )
                                      m,
                                    _duration.inMinutes,
                                  }
                                  .map(
                                    (m) => DropdownMenuItem(
                                      value: m,
                                      child: Text('$m minutes'),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) {
                            if (v != null)
                              setState(() {
                                _durationOverride = v;
                                _start = null;
                                _label = null;
                              });
                          },
                        ),
                        if (_requiredRinks > 1 && _start != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Choose $_requiredRinks rinks for this home fixture. All rinks use the same start and finish time.',
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final label in _labels)
                                FilterChip(
                                  key: ValueKey('choose-rink-$label'),
                                  label: Text('Rink $label'),
                                  selected: _selectedLabels.contains(label),
                                  onSelected:
                                      _checking ||
                                          !_day!.canBook(
                                            label,
                                            _start!,
                                            _labels,
                                            duration: _duration,
                                            rinksRequired: _requiredRinks,
                                          )
                                      ? null
                                      : (_) => _select(label, _start!),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],
                        MemberBookingTimeline(
                          date: _date,
                          labels: _labels,
                          day: _day!,
                          density: _density,
                          selectedLabel: _label,
                          selectedLabels: _selectedLabels,
                          selectedStart: _start,
                          latestEnd: _latestEnd,
                          enabled: !_saving && !_checking,
                          onSelect: _select,
                          duration: _duration,
                          opens: _opens,
                          closes: _closes,
                          allowedStart: _allowedStart,
                          rinksRequired: _requiredRinks,
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
      duration: _duration,
      opens: _opens,
      closes: _closes,
      allowedStart: _allowedStart,
      rinksRequired: _requiredRinks,
    );
    final choices = <({String label, DateTime start})>[];
    for (
      var minute = _opens;
      minute + _duration.inMinutes <= _closes;
      minute += 30
    ) {
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
        Text(
          _duration.inMinutes == 150
              ? 'No rink is free for 2½ hours on this date.'
              : 'No rink is free for ${_duration.inMinutes} minutes on this date.',
        ),
        TextButton(
          onPressed: () => _changeDate(_date.add(const Duration(days: 1))),
          child: const Text('Try next day →'),
        ),
      ];
    }
    return [];
  }
}
