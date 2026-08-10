import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/date_format.dart';

import '../fixtures/create_fixture_page.dart';
import '../fixtures/fixture_details_page.dart';

/// Primary operational Rinks Day view.
///
/// Rows = physical rinks
/// Columns = time from 09:00 to 22:00
///
/// This file is a UI scaffold with mock data so layout and behaviour can be
/// refined before wiring to Supabase.

const int kDayStartHour = 9;
const int kDayEndHour = 22;
const int kDayMinutes = (kDayEndHour - kDayStartHour) * 60;
const double kRinkLabelWidth = 54;
const double kTimelineMinWidth = 1040;
const double kRowHeight = 72;
const double kHeaderHeight = 44;
const double kHourWidth = 80;

enum RinkBlockStatus { confirmed, provisional, blocked }

enum RinksTimelineDensity { fit, compact, detailed }

class RinkDayViewScreen extends StatefulWidget {
  const RinkDayViewScreen({
    super.key,
    required this.clubId,
    required this.clubName,
    required this.date,
    this.fixtureId,
  });

  final String clubId;
  final String clubName;
  final DateTime date;
  final String? fixtureId;

  @override
  State<RinkDayViewScreen> createState() => _RinkDayViewScreenState();
}

class _RinkDayViewScreenState extends State<RinkDayViewScreen> {
  late DateTime _selectedDate;

  final _client = Supabase.instance.client;

  double _horizontalOffset = 0;

  bool _isLoading = true;
  String? _loadError;

  String? _myProfileId;
  String? _membershipRole;

  bool _hasClubMembership = false;
  bool _isSuperuser = false;
  bool _isClubAdmin = false;
  bool _isGuest = false;

  bool get _canBookFixtureFromRinks {
    if (_isSuperuser) return true;
    if (!_hasClubMembership) return false;
    if (_isGuest) return false;

    return true;
  }

  bool get _canBookMaintenanceFromRinks {
    return _isSuperuser || _isClubAdmin;
  }

  RinksTimelineDensity _density = RinksTimelineDensity.detailed;

  List<RinkLane> _rinks = [];
  List<RinkAssignmentBlock> _assignments = [];
  List<UnassignedRinkNeed> _unassigned = [];

  Map<String, dynamic>? _selectedGreen;
  SunsetBookingWindow? _sunsetWindow;

  final ScrollController _horizontalHeaderController = ScrollController();
  final ScrollController _horizontalBodyController = ScrollController();
  final ScrollController _verticalBodyController = ScrollController();
  final ScrollController _verticalLabelController = ScrollController();

  bool _syncingVerticalLabelScroll = false;

  SunsetBookingWindow? _calculateSunsetWindowForGreen(
    Map<String, dynamic> green,
    DateTime date,
  ) {
    final isOutdoor = green['is_outdoor'] == true;
    final usesSunsetCutoff = green['uses_sunset_cutoff'] == true;

    if (!isOutdoor || !usesSunsetCutoff) {
      return null;
    }

    final lat = _asDouble(green['venue_latitude']);
    final lng = _asDouble(green['venue_longitude']);

    if (lat == null || lng == null) {
      debugPrint(
        'Sunset cutoff enabled but venue latitude/longitude is missing.',
      );
      return null;
    }

    final offsetMinutes =
        int.tryParse(
          (green['sunset_booking_offset_minutes'] ?? 30).toString(),
        ) ??
        30;

    return calculateSunsetBookingWindow(
      date: date,
      latitude: lat,
      longitude: lng,
      offsetMinutes: offsetMinutes,
    );
  }

  double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime(
      widget.date.year,
      widget.date.month,
      widget.date.day,
    );

    _horizontalBodyController.addListener(_syncHorizontalFromBody);
    _horizontalHeaderController.addListener(_syncHorizontalFromHeader);
    _verticalBodyController.addListener(_syncVerticalLabelsToBody);

    _loadDay();
  }

  @override
  void dispose() {
    _horizontalBodyController.removeListener(_syncHorizontalFromBody);
    _horizontalHeaderController.removeListener(_syncHorizontalFromHeader);
    _verticalBodyController.removeListener(_syncVerticalLabelsToBody);

    _horizontalHeaderController.dispose();
    _horizontalBodyController.dispose();
    _verticalBodyController.dispose();
    _verticalLabelController.dispose();

    super.dispose();
  }

  void _syncHorizontalFromBody() {
    if (mounted) {
      setState(() {
        _horizontalOffset = _horizontalBodyController.hasClients
            ? _horizontalBodyController.offset
            : 0;
      });
    }

    if (!_horizontalHeaderController.hasClients) return;
    if ((_horizontalHeaderController.offset - _horizontalBodyController.offset)
            .abs() <
        1) {
      return;
    }
    _horizontalHeaderController.jumpTo(_horizontalBodyController.offset);
  }

  void _syncHorizontalFromHeader() {
    if (!_horizontalBodyController.hasClients) return;
    if ((_horizontalBodyController.offset - _horizontalHeaderController.offset)
            .abs() <
        1)
      return;
    _horizontalBodyController.jumpTo(_horizontalHeaderController.offset);
  }

  void _syncVerticalLabelsToBody() {
    if (_syncingVerticalLabelScroll) return;

    if (!_verticalBodyController.hasClients ||
        !_verticalLabelController.hasClients) {
      return;
    }

    _syncingVerticalLabelScroll = true;

    try {
      final targetOffset = _verticalBodyController.offset.clamp(
        0.0,
        _verticalLabelController.position.maxScrollExtent,
      );

      if ((_verticalLabelController.offset - targetOffset).abs() > 0.5) {
        _verticalLabelController.jumpTo(targetOffset);
      }
    } finally {
      _syncingVerticalLabelScroll = false;
    }
  }

  void _moveDay(int delta) {
    setState(() {
      _selectedDate = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day + delta,
      );
    });
    _loadDay();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(_selectedDate.year - 3),
      lastDate: DateTime(_selectedDate.year + 3),
      helpText: 'Choose rinks date',
    );

    if (picked == null) return;
    if (!mounted) return;

    setState(() {
      _selectedDate = DateTime(picked.year, picked.month, picked.day);
    });

    await _loadDay();
  }

  int _maxConcurrentAssignments(
    List<RinkAssignmentBlock> assignments,
    RinkBlockStatus status,
  ) {
    final events = <MapEntry<DateTime, int>>[];

    for (final a in assignments.where((x) => x.status == status)) {
      events.add(MapEntry(a.startAt, 1));
      events.add(MapEntry(a.endAt, -1));
    }

    events.sort((a, b) {
      final t = a.key.compareTo(b.key);
      if (t != 0) return t;

      // End before start so 10:00-12:00 and 12:00-14:00 don't overlap.
      return a.value.compareTo(b.value);
    });

    var current = 0;
    var maxCount = 0;

    for (final e in events) {
      current += e.value;
      if (current > maxCount) maxCount = current;
    }

    return maxCount;
  }

  Future<void> _loadUserPermissionsForRinks() async {
    _myProfileId = null;
    _membershipRole = null;
    _hasClubMembership = false;
    _isSuperuser = false;
    _isClubAdmin = false;
    _isGuest = false;

    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      final profileIdResult = await _client.rpc('my_member_profile_id');
      final profileId = profileIdResult?.toString();

      if (profileId == null || profileId.isEmpty || profileId == 'null') {
        return;
      }

      _myProfileId = profileId;

      try {
        final superuserRow = await _client
            .from('app_superusers')
            .select('user_id')
            .eq('user_id', user.id)
            .maybeSingle();

        _isSuperuser = superuserRow != null;
      } catch (_) {
        _isSuperuser = false;
      }

      final membership = await _client
          .from('club_memberships')
          .select('id, role')
          .eq('member_profile_id', profileId)
          .eq('club_id', widget.clubId)
          .maybeSingle();

      if (membership == null) return;

      _hasClubMembership = true;

      final role = (membership['role'] ?? '').toString().trim().toLowerCase();

      _membershipRole = role;
      _isClubAdmin =
          role == 'admin' || role == 'club_admin' || role == 'club admin';

      _isGuest = role == 'guest';
    } catch (e) {
      debugPrint('Could not load rinks permissions: $e');
    }
  }

  Future<void> _loadDay() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final dayStart = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        0,
        0,
        0,
      );

      await _loadUserPermissionsForRinks();

      final dayEnd = dayStart.add(const Duration(days: 1));

      final green = await _loadHomeGreen();
      final rinks = _buildRinksFromGreen(green);
      final sunsetWindow = _calculateSunsetWindowForGreen(green, dayStart);

      final greenAreaId = green['id']?.toString();

      if (greenAreaId == null || greenAreaId.isEmpty) {
        throw Exception('Green area is missing its ID');
      }

      final fixtures = await _loadHomeFixturesForDay(dayStart, dayEnd);

      final maintenanceRows = await _loadMaintenanceForDay(
        dayStart,
        dayEnd,
        greenAreaId,
      );

      final assignments = <RinkAssignmentBlock>[
        ..._mapAssignments(fixtures),
        ..._mapMaintenance(maintenanceRows, rinks),
      ];

      final unassigned = _mapUnassigned(fixtures);

      if (!mounted) return;

      setState(() {
        _selectedGreen = green;
        _sunsetWindow = sunsetWindow;
        _rinks = rinks;
        _assignments = assignments;
        _unassigned = unassigned;
        _isLoading = false;
      });

      _scrollToFirstActivity(assignments: assignments, unassigned: unassigned);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadError = e.toString();
        _isLoading = false;
      });
    }
  }

  double _leftForTime(DateTime startAt, double hourWidth) {
    final startMinutes = ((startAt.hour - kDayStartHour) * 60) + startAt.minute;

    final clamped = startMinutes.clamp(0, kDayMinutes);

    return (clamped / 60.0) * hourWidth;
  }

  void _scrollToFirstActivity({
    required List<RinkAssignmentBlock> assignments,
    required List<UnassignedRinkNeed> unassigned,
  }) {
    DateTime? earliest;

    for (final block in assignments) {
      if (earliest == null || block.startAt.isBefore(earliest)) {
        earliest = block.startAt;
      }
    }

    for (final item in unassigned) {
      if (earliest == null || item.startAt.isBefore(earliest)) {
        earliest = item.startAt;
      }
    }

    if (earliest == null) return;

    final availableTimelineWidth =
        (MediaQuery.of(context).size.width - kRinkLabelWidth).clamp(
          260.0,
          double.infinity,
        );

    final hourWidth = _hourWidthForAvailableWidth(availableTimelineWidth);
    final timelineWidth = _timelineWidthForAvailableWidth(
      availableTimelineWidth,
    );

    final targetOffset = (_leftForTime(earliest, hourWidth) - 24).clamp(
      0.0,
      timelineWidth,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_horizontalBodyController.hasClients) return;

      final maxOffset = _horizontalBodyController.position.maxScrollExtent;

      _horizontalBodyController.jumpTo(targetOffset.clamp(0.0, maxOffset));
    });
  }

  Future<Map<String, dynamic>> _loadHomeGreen() async {
    final venue = await _client
        .from('venues')
        .select('id, name, latitude, longitude')
        .eq('club_id', widget.clubId)
        .eq('is_home_venue', true)
        .maybeSingle();

    if (venue == null) {
      throw Exception('No home venue found for this club');
    }

    final green = await _client
        .from('green_areas')
        .select(
          'id, name, rink_count, scheme_type, custom_labels, scheme_prefix, scheme_padding, '
          'is_outdoor, uses_sunset_cutoff, sunset_booking_offset_minutes',
        )
        .eq('venue_id', venue['id'])
        .limit(1)
        .maybeSingle();

    if (green == null) {
      throw Exception('No green area found for the home venue');
    }

    final result = Map<String, dynamic>.from(green);
    result['venue_latitude'] = venue['latitude'];
    result['venue_longitude'] = venue['longitude'];
    result['venue_name'] = venue['name'];

    return result;
  }

  List<RinkLane> _buildRinksFromGreen(Map<String, dynamic> green) {
    final rinkCount = (green['rink_count'] ?? 0) as int;
    final schemeType = (green['scheme_type'] ?? 'numeric').toString();

    final custom = green['custom_labels'];

    if (schemeType == 'custom_list' && custom is List && custom.isNotEmpty) {
      return custom
          .take(rinkCount)
          .toList()
          .asMap()
          .entries
          .map((e) => RinkLane(id: '${e.key + 1}', label: e.value.toString()))
          .toList();
    }

    final rawPrefix = green['scheme_prefix']?.toString();
    final prefix = rawPrefix == null || rawPrefix.trim().isEmpty
        ? 'R'
        : rawPrefix.trim();

    final padding = (green['scheme_padding'] ?? 0) as int;

    return List.generate(rinkCount, (i) {
      final n = i + 1;

      final label = schemeType == 'alpha'
          ? '$prefix${String.fromCharCode(64 + n)}'
          : '$prefix${padding > 0 ? n.toString().padLeft(padding, '0') : n.toString()}';

      return RinkLane(id: '$n', label: label);
    });
  }

  Future<List<Map<String, dynamic>>> _loadHomeFixturesForDay(
    DateTime dayStart,
    DateTime dayEnd,
  ) async {
    final res = await _client
        .from('fixtures')
        .select('''
          id,
          club_id,
          start_at,
          end_at,
          is_home,
          rinks_required,
          green_area_id,
          opponent_name,

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
            fixture_rink_no,
            home_rink_label,
            fixture_rink_assignments (
              member_profile_id
            )
          )
        ''')
        .eq('club_id', widget.clubId)
        .eq('is_home', true)
        .gte('start_at', clubTimeToUtc(dayStart).toIso8601String())
        .lt('start_at', clubTimeToUtc(dayEnd).toIso8601String())
        .order('start_at');

    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> _loadMaintenanceForDay(
    DateTime dayStart,
    DateTime dayEnd,
    String greenAreaId,
  ) async {
    final res = await _client
        .from('green_rink_maintenance')
        .select('''
          id,
          green_area_id,
          rink_number,
          start_at,
          end_at,
          reason,
          notes,
          status
        ''')
        .eq('green_area_id', greenAreaId)
        .eq('status', 'active')
        .lt('start_at', clubTimeToUtc(dayEnd).toIso8601String())
        .gt('end_at', clubTimeToUtc(dayStart).toIso8601String())
        .order('start_at');

    return List<Map<String, dynamic>>.from(res);
  }

  List<RinkAssignmentBlock> _mapMaintenance(
    List<Map<String, dynamic>> rows,
    List<RinkLane> rinks,
  ) {
    final blocks = <RinkAssignmentBlock>[];

    final rinksByNumber = <String, RinkLane>{
      for (final rink in rinks) rink.id: rink,
    };

    for (final row in rows) {
      final rinkNumber = row['rink_number']?.toString();
      if (rinkNumber == null || rinkNumber.isEmpty) continue;

      final rink = rinksByNumber[rinkNumber];
      if (rink == null) continue;

      final startValue = row['start_at']?.toString();
      final endValue = row['end_at']?.toString();

      if (startValue == null ||
          startValue.isEmpty ||
          endValue == null ||
          endValue.isEmpty) {
        continue;
      }

      final startAt = parseClubTime(startValue);
      final endAt = parseClubTime(endValue);

      final rawReason = (row['reason'] ?? '').toString().trim();
      final reason = rawReason.isEmpty ? 'Maintenance' : rawReason;

      blocks.add(
        RinkAssignmentBlock(
          fixtureId: '',
          rinkLabel: rink.label,
          title: reason,
          startAt: startAt,
          endAt: endAt,
          status: RinkBlockStatus.blocked,
          color: const Color(0xFFFEE2E2),
          textColor: const Color(0xFF991B1B),
          isMine: false,
        ),
      );
    }

    return blocks;
  }

  String _fixtureBlockTitle(Map<String, dynamic> fixture) {
    final competitionType =
        fixture['competition_types'] as Map<String, dynamic>?;

    final isInternal = competitionType?['is_internal'] == true;
    final typeName = (competitionType?['name'] ?? '').toString().trim();

    // ✅ INTERNAL → always show fixture type
    if (isInternal) {
      return typeName.isNotEmpty ? typeName : 'Internal Fixture';
    }

    // ✅ NON-INTERNAL → show opponent
    final opponentName = (fixture['opponent_name'] ?? '').toString().trim();

    if (opponentName.isNotEmpty) {
      return opponentName;
    }

    // fallback
    return typeName.isNotEmpty ? typeName : 'Fixture';
  }

  Color _parseHexColor(String? hex, Color fallback) {
    if (hex == null || hex.trim().isEmpty) return fallback;

    var value = hex.trim().replaceFirst('#', '');
    if (value.length == 6) value = 'FF$value';

    final parsed = int.tryParse(value, radix: 16);
    if (parsed == null) return fallback;

    return Color(parsed);
  }

  List<RinkAssignmentBlock> _mapAssignments(
    List<Map<String, dynamic>> fixtures,
  ) {
    final blocks = <RinkAssignmentBlock>[];

    for (final fixture in fixtures) {
      final startAt = parseClubTime(fixture['start_at'].toString());

      final endAt = fixture['end_at'] != null
          ? parseClubTime(fixture['end_at'].toString())
          : startAt.add(const Duration(hours: 3));

      final competitionType =
          fixture['competition_types'] as Map<String, dynamic>?;
      final colourScheme =
          competitionType?['colour_scheme'] as Map<String, dynamic>?;

      final bg = _parseHexColor(
        colourScheme?['background_hex']?.toString(),
        const Color(0xFFDBEAFE),
      );
      final fg = _parseHexColor(
        colourScheme?['foreground_hex']?.toString(),
        const Color(0xFF1E3A8A),
      );

      final title = _fixtureBlockTitle(fixture);

      final rinks = List<Map<String, dynamic>>.from(
        fixture['fixture_rinks'] ?? [],
      );

      for (final rink in rinks) {
        final rinkAssignments = List<Map<String, dynamic>>.from(
          rink['fixture_rink_assignments'] ?? [],
        );

        final isMine =
            _myProfileId != null &&
            rinkAssignments.any(
              (a) => a['member_profile_id']?.toString() == _myProfileId,
            );

        final rinkLabel = (rink['home_rink_label'] ?? '').toString().trim();

        final fixtureId = fixture['id']?.toString() ?? '';

        if (rinkLabel.isEmpty) continue;

        blocks.add(
          RinkAssignmentBlock(
            fixtureId: fixtureId,
            rinkLabel: rinkLabel,
            title: title,
            startAt: startAt,
            endAt: endAt,
            status: RinkBlockStatus.confirmed,
            color: bg,
            textColor: fg,
            isMine: isMine,
          ),
        );
      }
    }

    return blocks;
  }

  List<UnassignedRinkNeed> _mapUnassigned(List<Map<String, dynamic>> fixtures) {
    final items = <UnassignedRinkNeed>[];

    for (final fixture in fixtures) {
      final rinks = List<Map<String, dynamic>>.from(
        fixture['fixture_rinks'] ?? [],
      );
      final rinksRequired = (fixture['rinks_required'] ?? 0) as int;

      if (rinks.isNotEmpty || rinksRequired <= 0) continue;

      final startAt = parseClubTime(fixture['start_at'].toString());

      final endAt = fixture['end_at'] != null
          ? parseClubTime(fixture['end_at'].toString())
          : startAt.add(const Duration(hours: 3));
      final competitionType =
          fixture['competition_types'] as Map<String, dynamic>?;
      final colourScheme =
          competitionType?['colour_scheme'] as Map<String, dynamic>?;

      final bg = _parseHexColor(
        colourScheme?['background_hex']?.toString(),
        const Color(0xFFDCFCE7),
      );

      items.add(
        UnassignedRinkNeed(
          id: fixture['id'].toString(),
          title: _fixtureBlockTitle(fixture),
          subtitle:
              '$rinksRequired rink${rinksRequired == 1 ? '' : 's'} needed',
          startAt: startAt,
          endAt: endAt,
          rinksRequired: rinksRequired,
          color: bg,
        ),
      );
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rinks = _rinks;
    final assignments = _assignments;
    final unassigned = _unassigned;
    final isWide = MediaQuery.of(context).size.width >= 900;
    final isEmptyDay = assignments.isEmpty && unassigned.isEmpty;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_loadError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_loadError!),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 0,
        elevation: 0,
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;

          if (velocity < -300) {
            _moveDay(1);
          } else if (velocity > 300) {
            _moveDay(-1);
          }
        },
        child: Column(
          children: [
            _RinksHeader(
              clubName: widget.clubName,
              date: _selectedDate,
              sunsetWindow: _sunsetWindow,
              onPrevious: () => _moveDay(-1),
              onNext: () => _moveDay(1),
              onPickDate: _pickDate,
              density: _density,
              onDensityChanged: (value) {
                setState(() => _density = value);
              },
            ),
            _SummaryBar(
              totalRinks: rinks.length,
              assignedCount: _maxConcurrentAssignments(
                assignments,
                RinkBlockStatus.confirmed,
              ),
              provisionalCount:
                  _maxConcurrentAssignments(
                    assignments,
                    RinkBlockStatus.provisional,
                  ) +
                  unassigned.length,
              conflictCount: 0,
            ),

            if (isEmptyDay)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: Color(0xFF15803D)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No rink bookings yet today. Tap an empty rink slot to create a booking.',
                        style: TextStyle(
                          color: Color(0xFF166534),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            Expanded(
              child: isWide
                  ? _buildDesktopLayout(context, rinks, assignments, unassigned)
                  : _buildMobileLayout(context, rinks, assignments, unassigned),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    List<RinkLane> rinks,
    List<RinkAssignmentBlock> assignments,
    List<UnassignedRinkNeed> unassigned,
  ) {
    final availableTimelineWidth =
        (MediaQuery.of(context).size.width - kRinkLabelWidth).clamp(
          260.0,
          double.infinity,
        );

    final hourWidth = _hourWidthForAvailableWidth(availableTimelineWidth);
    final timelineWidth = _timelineWidthForAvailableWidth(
      availableTimelineWidth,
    );

    return Column(
      children: [
        _buildTimeHeader(
          context,
          assignments,
          rinks.length,
          hourWidth,
          timelineWidth,
        ),
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: kRinkLabelWidth,
                child: ListView.builder(
                  controller: _verticalLabelController,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: rinks.length,
                  itemBuilder: (context, index) {
                    final rink = rinks[index];

                    return SizedBox(
                      height: kRowHeight,
                      child: _RinkLabelCell(label: rink.label),
                    );
                  },
                ),
              ),
              Expanded(
                child: Scrollbar(
                  controller: _horizontalBodyController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _horizontalBodyController,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: timelineWidth,
                      child: Scrollbar(
                        controller: _verticalBodyController,
                        thumbVisibility: true,
                        child: ListView.builder(
                          controller: _verticalBodyController,
                          itemCount: rinks.length,
                          itemBuilder: (context, index) {
                            final rink = rinks[index];
                            final blocks = assignments
                                .where((a) => a.rinkLabel == rink.label)
                                .toList();
                            return LayoutBuilder(
                              builder: (context, constraints) =>
                                  _RinkTimelineRow(
                                    rink: rink,
                                    blocks: blocks,
                                    timelineWidth: timelineWidth,
                                    hourWidth: hourWidth,
                                    date: _selectedDate,
                                    sunsetWindow: _sunsetWindow,
                                    onBlockTap: _openBlock,
                                    onEmptySlotTap: _openEmptySlot,
                                    onAfterBookableCutoffTap:
                                        _showSunsetCutoffMessage,
                                    isAlternate: index.isOdd,
                                    horizontalOffset: _horizontalOffset,
                                    viewportWidth: constraints.maxWidth,
                                    hasFutureActivity:
                                        assignments.isNotEmpty ||
                                        unassigned.isNotEmpty,
                                  ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (unassigned.isNotEmpty)
          _UnassignedNeedsPanel(items: unassigned, onTap: (item) {}),
      ],
    );
  }

  Widget _buildMobileLayout(
    BuildContext context,
    List<RinkLane> rinks,
    List<RinkAssignmentBlock> assignments,
    List<UnassignedRinkNeed> unassigned,
  ) {
    final hasFutureActivity = assignments.isNotEmpty || unassigned.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableTimelineWidth = (constraints.maxWidth - kRinkLabelWidth)
            .clamp(260.0, double.infinity);

        final hourWidth = _hourWidthForAvailableWidth(availableTimelineWidth);
        final timelineWidth = _timelineWidthForAvailableWidth(
          availableTimelineWidth,
        );

        return Column(
          children: [
            _buildTimeHeader(
              context,
              assignments,
              rinks.length,
              hourWidth,
              timelineWidth,
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _horizontalBodyController,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: kRinkLabelWidth + timelineWidth,
                  child: ListView(
                    children: [
                      for (final rink in rinks)
                        Row(
                          children: [
                            SizedBox(
                              width: kRinkLabelWidth,
                              height: kRowHeight,
                              child: _RinkLabelCell(label: rink.label),
                            ),
                            SizedBox(
                              width: timelineWidth,
                              child: _RinkTimelineRow(
                                rink: rink,
                                blocks: assignments
                                    .where((a) => a.rinkLabel == rink.label)
                                    .toList(),
                                timelineWidth: timelineWidth,
                                hourWidth: hourWidth,
                                date: _selectedDate,
                                sunsetWindow: _sunsetWindow,
                                onBlockTap: _openBlock,
                                onEmptySlotTap: _openEmptySlot,
                                onAfterBookableCutoffTap:
                                    _showSunsetCutoffMessage,
                                isAlternate: rinks.indexOf(rink).isOdd,
                                horizontalOffset: _horizontalOffset,
                                viewportWidth:
                                    MediaQuery.of(context).size.width -
                                    kRinkLabelWidth,
                                hasFutureActivity: hasFutureActivity,
                              ),
                            ),
                          ],
                        ),
                      if (unassigned.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
                          child: _UnassignedNeedsPanel(
                            items: unassigned,
                            onTap: (item) {},
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

  List<int> _buildRinkUsagePerHour(List<RinkAssignmentBlock> assignments) {
    final usage = List<int>.filled(kDayEndHour - kDayStartHour + 1, 0);

    for (final block in assignments) {
      final startMinutes =
          ((block.startAt.hour - kDayStartHour) * 60) + block.startAt.minute;
      final endMinutes =
          ((block.endAt.hour - kDayStartHour) * 60) + block.endAt.minute;

      final visibleStart = startMinutes.clamp(0, kDayMinutes);
      final visibleEnd = endMinutes.clamp(0, kDayMinutes);

      for (int hour = kDayStartHour; hour <= kDayEndHour; hour++) {
        final hourStart = (hour - kDayStartHour) * 60;
        final hourEnd = hourStart + 60;

        final overlapsHour = visibleStart < hourEnd && visibleEnd > hourStart;

        if (overlapsHour) {
          final index = hour - kDayStartHour;
          if (index >= 0 && index < usage.length) {
            usage[index]++;
          }
        }
      }
    }

    return usage;
  }

  Widget _buildTimeHeader(
    BuildContext context,
    List<RinkAssignmentBlock> assignments,
    int rinkCount,
    double hourWidth,
    double timelineWidth,
  ) {
    final textStyle = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700);

    final usage = _buildRinkUsagePerHour(assignments);

    return Row(
      children: [
        const SizedBox(
          width: kRinkLabelWidth,
          height: kHeaderHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: Color(0xFFDDDDDD)),
                bottom: BorderSide(color: Color(0xFFDDDDDD)),
              ),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: _horizontalHeaderController,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: SizedBox(
              width: timelineWidth,
              height: kHeaderHeight + 24,
              child: Column(
                children: [
                  Row(
                    children: [
                      for (int i = 0; i < usage.length; i++)
                        Container(
                          width: hourWidth,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            border: Border(
                              left: BorderSide(color: Color(0xFFEEEEEE)),
                            ),
                          ),
                          child: Text(
                            usage[i] == 0 ? '' : usage[i].toString(),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: usage[i] >= rinkCount
                                      ? const Color(0xFFB91C1C)
                                      : const Color(0xFF374151),
                                ),
                          ),
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      for (
                        int hour = kDayStartHour;
                        hour <= kDayEndHour;
                        hour++
                      )
                        Container(
                          width: hourWidth,
                          height: kHeaderHeight,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.only(left: 6),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF8FAFC),
                            border: Border(
                              left: BorderSide(color: Color(0xFFEEEEEE)),
                              bottom: BorderSide(color: Color(0xFFDDDDDD)),
                            ),
                          ),
                          child: Text(_hourLabel(hour), style: textStyle),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  double _hourWidthForAvailableWidth(double availableTimelineWidth) {
    final hourCount = kDayEndHour - kDayStartHour + 1;

    switch (_density) {
      case RinksTimelineDensity.fit:
        return (availableTimelineWidth / hourCount).clamp(28.0, 80.0);
      case RinksTimelineDensity.compact:
        return 52.0;
      case RinksTimelineDensity.detailed:
        return 80.0;
    }
  }

  double _timelineWidthForAvailableWidth(double availableTimelineWidth) {
    final hourCount = kDayEndHour - kDayStartHour + 1;
    return hourCount * _hourWidthForAvailableWidth(availableTimelineWidth);
  }

  Future<void> _openBlock(RinkAssignmentBlock block) async {
    final fixtureId = block.fixtureId;

    if (fixtureId.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(block.title)));
      return;
    }

    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FixtureDetailsPage(fixtureId: fixtureId),
      ),
    );

    if (!mounted) return;

    if (changed == true) {
      _loadDay();
    }
  }

  void _bookFixtureFromSlot(RinkEmptySlot slot) {
    final green = _selectedGreen;

    if (green == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cannot book from this slot because the green has not loaded.',
          ),
        ),
      );
      return;
    }

    final greenAreaId = green['id']?.toString();
    final greenName = (green['name'] ?? 'Green').toString();

    if (greenAreaId == null || greenAreaId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cannot book from this slot because the green is missing an ID.',
          ),
        ),
      );
      return;
    }

    debugPrint(
      'BOOK FROM SLOT: '
      'gap=${_timeLabel(slot.startAt)}-${_timeLabel(slot.endAt)} '
      'suggested=${_timeLabel(slot.suggestedStartAt)}-${_timeLabel(slot.suggestedEndAt)}',
    );

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => CreateFixturePage(
              clubId: widget.clubId,
              clubName: widget.clubName,
              memberBookingMode: true,
              initialRinkBooking: InitialRinkBookingContext(
                greenAreaId: greenAreaId,
                greenName: greenName,
                rinkLabel: slot.rinkLabel,
                startAt: slot.suggestedStartAt,
                latestEndAt: slot.endAt,
                suggestedEndAt: slot.suggestedEndAt,
              ),
            ),
          ),
        )
        .then((_) {
          if (mounted) {
            _loadDay();
          }
        });
  }

  Future<void> _bookMaintenanceFromSlot(RinkEmptySlot slot) async {
    final green = _selectedGreen;

    if (green == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cannot create maintenance because the green has not loaded.',
          ),
        ),
      );
      return;
    }

    final greenAreaId = green['id']?.toString();

    if (greenAreaId == null || greenAreaId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cannot create maintenance because the green is missing its ID.',
          ),
        ),
      );
      return;
    }

    RinkLane? selectedRink;

    for (final rink in _rinks) {
      if (rink.label == slot.rinkLabel) {
        selectedRink = rink;
        break;
      }
    }

    if (selectedRink == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not identify physical rink ${slot.rinkLabel}.'),
        ),
      );
      return;
    }

    final rinkNumber = int.tryParse(selectedRink.id);

    if (rinkNumber == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not identify the rink number for ${slot.rinkLabel}.',
          ),
        ),
      );
      return;
    }

    //
    // IMPORTANT:
    // Maintenance defaults to the WHOLE AVAILABLE GAP,
    // not the suggested two-hour fixture period.
    //
    DateTime startAt = slot.startAt;
    DateTime endAt = slot.endAt;

    final reasonController = TextEditingController(text: 'Maintenance');
    final notesController = TextEditingController();

    var impacts = <Map<String, dynamic>>[];
    String? errorText;
    var saving = false;
    var saved = false;

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              Future<void> chooseStartTime() async {
                final picked = await showTimePicker(
                  context: sheetContext,
                  initialTime: TimeOfDay(
                    hour: startAt.hour,
                    minute: startAt.minute,
                  ),
                  helpText: 'Maintenance start time',
                );

                if (picked == null || !sheetContext.mounted) return;

                setSheetState(() {
                  startAt = DateTime(
                    _selectedDate.year,
                    _selectedDate.month,
                    _selectedDate.day,
                    picked.hour,
                    picked.minute,
                  );

                  impacts = [];
                  errorText = null;
                });
              }

              Future<void> chooseEndTime() async {
                final picked = await showTimePicker(
                  context: sheetContext,
                  initialTime: TimeOfDay(
                    hour: endAt.hour,
                    minute: endAt.minute,
                  ),
                  helpText: 'Maintenance end time',
                );

                if (picked == null || !sheetContext.mounted) return;

                setSheetState(() {
                  endAt = DateTime(
                    _selectedDate.year,
                    _selectedDate.month,
                    _selectedDate.day,
                    picked.hour,
                    picked.minute,
                  );

                  impacts = [];
                  errorText = null;
                });
              }

              Future<void> saveMaintenance() async {
                if (saving) return;

                if (!endAt.isAfter(startAt)) {
                  setSheetState(() {
                    errorText =
                        'The maintenance end time must be after the start time.';
                    impacts = [];
                  });
                  return;
                }

                setSheetState(() {
                  saving = true;
                  errorText = null;
                  impacts = [];
                });

                try {
                  final startUtc = clubTimeToUtc(startAt);
                  final endUtc = clubTimeToUtc(endAt);

                  //
                  // First show the administrator any consequences.
                  //
                  final result = await _client.rpc(
                    'get_green_maintenance_impacts',
                    params: {
                      'p_green_area_id': greenAreaId,
                      'p_rink_labels': [slot.rinkLabel],
                      'p_start_at': startUtc.toIso8601String(),
                      'p_end_at': endUtc.toIso8601String(),
                    },
                  );

                  final rawRows = result is List ? result : const [];

                  final foundImpacts = rawRows
                      .map((row) => Map<String, dynamic>.from(row as Map))
                      .toList();

                  if (!sheetContext.mounted) return;

                  if (foundImpacts.isNotEmpty) {
                    setSheetState(() {
                      impacts = foundImpacts;
                      saving = false;
                    });
                    return;
                  }

                  //
                  // No impacts found.
                  // The SAFE RPC performs the same check again on the server
                  // immediately before inserting.
                  //
                  final reason = reasonController.text.trim();
                  final notes = notesController.text.trim();

                  await _client.rpc(
                    'create_green_rink_maintenance_safe',
                    params: {
                      'p_green_area_id': greenAreaId,
                      'p_rink_number': rinkNumber,
                      'p_start_at': startUtc.toIso8601String(),
                      'p_end_at': endUtc.toIso8601String(),
                      'p_reason': reason.isEmpty ? 'Maintenance' : reason,
                      'p_notes': notes.isEmpty ? null : notes,
                    },
                  );

                  saved = true;

                  if (sheetContext.mounted) {
                    Navigator.of(sheetContext).pop();
                  }
                } catch (e) {
                  if (!sheetContext.mounted) return;

                  final rawError = e.toString();

                  setSheetState(() {
                    saving = false;

                    if (rawError.contains('MAINTENANCE_IMPACT')) {
                      errorText =
                          'The rink situation changed while saving. '
                          'Please check the maintenance period again.';
                    } else {
                      errorText = 'Could not save maintenance: $rawError';
                    }
                  });
                }
              }

              final maintenanceDuration = endAt.difference(startAt);

              return SafeArea(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    16 + MediaQuery.of(sheetContext).viewInsets.bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.construction,
                            color: Color(0xFF991B1B),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Rink Maintenance — ${slot.rinkLabel}',
                              style: Theme.of(sheetContext).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 4),

                      Text(
                        _prettyDate(_selectedDate),
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 14),

                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFD1D5DB)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Available gap',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_timeLabel(slot.startAt)} – '
                              '${_timeLabel(slot.endAt)}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'The maintenance period has been defaulted '
                              'to this whole available gap.',
                              style: TextStyle(color: Color(0xFF6B7280)),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: saving ? null : chooseStartTime,
                              icon: const Icon(Icons.schedule),
                              label: Text('From ${_timeLabel(startAt)}'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: saving ? null : chooseEndTime,
                              icon: const Icon(Icons.schedule),
                              label: Text('Until ${_timeLabel(endAt)}'),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 6),

                      Text(
                        endAt.isAfter(startAt)
                            ? 'Duration: ${_durationLabel(maintenanceDuration)}'
                            : 'Invalid maintenance period',
                        style: TextStyle(
                          color: endAt.isAfter(startAt)
                              ? const Color(0xFF374151)
                              : const Color(0xFFB91C1C),
                          fontWeight: FontWeight.w700,
                        ),
                      ),

                      const SizedBox(height: 14),

                      TextField(
                        controller: reasonController,
                        enabled: !saving,
                        decoration: const InputDecoration(
                          labelText: 'Reason',
                          hintText: 'Maintenance',
                          border: OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 12),

                      TextField(
                        controller: notesController,
                        enabled: !saving,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),

                      if (impacts.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7ED),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFF59E0B)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.warning_amber,
                                    color: Color(0xFFB45309),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'This maintenance period affects '
                                      '${impacts.length} existing '
                                      'rink commitment'
                                      '${impacts.length == 1 ? '' : 's'}.',
                                      style: const TextStyle(
                                        color: Color(0xFF92400E),
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              for (final impact in impacts.take(4))
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Text(
                                    '• ${(impact['title'] ?? 'Booking').toString()}'
                                    '${(impact['impact_reason'] ?? '').toString().trim().isEmpty ? '' : '\n  ${(impact['impact_reason']).toString()}'}',
                                    style: const TextStyle(
                                      color: Color(0xFF78350F),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),

                              if (impacts.length > 4)
                                Text(
                                  '…and ${impacts.length - 4} more.',
                                  style: const TextStyle(
                                    color: Color(0xFF78350F),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),

                              const SizedBox(height: 6),

                              const Text(
                                'Adjust the times to remove the conflict. '
                                'More complex cases will be handled by '
                                'Green Maintenance.',
                                style: TextStyle(color: Color(0xFF92400E)),
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (errorText != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          errorText!,
                          style: const TextStyle(
                            color: Color(0xFFB91C1C),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],

                      const SizedBox(height: 18),

                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: saving
                                  ? null
                                  : () => Navigator.of(sheetContext).pop(),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: saving ? null : saveMaintenance,
                              icon: saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.construction),
                              label: Text(
                                saving ? 'Checking...' : 'Book Maintenance',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      reasonController.dispose();
      notesController.dispose();
    }

    if (!mounted || !saved) return;

    await _loadDay();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Maintenance booked: ${slot.rinkLabel} '
          '${_timeLabel(startAt)}–${_timeLabel(endAt)}.',
        ),
      ),
    );
  }

  void _showSunsetCutoffMessage() {
    final window = _sunsetWindow;
    if (window == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Bookings close at ${_timeLabel(window.bookableUntil)} because this outdoor green uses a sunset booking limit.',
        ),
      ),
    );
  }

  void _openEmptySlot(RinkEmptySlot slot) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final duration = slot.suggestedDuration;
        final durationText = _durationLabel(duration);
        final shortSlot = duration < const Duration(hours: 2);

        final canBookFixture = _canBookFixtureFromRinks;
        final canBookMaintenance = _canBookMaintenanceFromRinks;
        final hasBookingActions = canBookFixture || canBookMaintenance;

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.event_available,
                        color: Color(0xFF2563EB),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Available Slot',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF1E3A8A),
                                  ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${slot.rinkLabel} • ${_timeLabel(slot.suggestedStartAt)}–${_timeLabel(slot.suggestedEndAt)} • $durationText',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E40AF),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Available gap: ${_timeLabel(slot.startAt)}–${_timeLabel(slot.endAt)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                if (shortSlot) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber, color: Color(0xFFB45309)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This slot is shorter than the recommended 2 hour minimum.',
                            style: TextStyle(
                              color: Color(0xFF92400E),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                Text(
                  hasBookingActions
                      ? 'Options Available'
                      : 'Booking Not Available',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),

                const SizedBox(height: 8),

                if (!hasBookingActions) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFD1D5DB)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.lock_outline,
                          color: Color(0xFF6B7280),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _isGuest
                                ? 'Guests can view rink availability, but cannot make bookings.'
                                : 'You do not currently have permission to book from this view.',
                            style: const TextStyle(
                              color: Color(0xFF374151),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                if (hasBookingActions)
                  Row(
                    children: [
                      if (canBookFixture)
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.add_circle_outline),
                            label: const Text('Book Fixture'),
                            onPressed: () {
                              Navigator.pop(context);

                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) return;
                                _bookFixtureFromSlot(slot);
                              });
                            },
                          ),
                        ),

                      if (canBookFixture && canBookMaintenance)
                        const SizedBox(width: 8),

                      if (canBookMaintenance)
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.construction),
                            label: const Text('Maintenance'),
                            onPressed: () {
                              Navigator.pop(context);

                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) return;
                                _bookMaintenanceFromSlot(slot);
                              });
                            },
                          ),
                        ),
                    ],
                  ),

                const SizedBox(height: 8),

                TextButton.icon(
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel'),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /*  
  List<RinkLane> _mockRinks() => const [
    RinkLane(id: '1', label: 'R1'),
    RinkLane(id: '2', label: 'R2'),
    RinkLane(id: '3', label: 'R3'),
    RinkLane(id: '4', label: 'R4'),
    RinkLane(id: '5', label: 'R5'),
    RinkLane(id: '6', label: 'R6'),
  ];

  List<RinkAssignmentBlock> _mockAssignments(DateTime day) {
    DateTime at(int h, int m) => DateTime(day.year, day.month, day.day, h, m);

    return [
      RinkAssignmentBlock(
        
        rinkLabel: 'R1',
        title: 'Bromley ✓',
        subtitle: 'League Match',
        startAt: at(10, 0),
        endAt: at(13, 0),
        status: RinkBlockStatus.confirmed,
        color: const Color(0xFFDBEAFE),
        textColor: const Color(0xFF1E3A8A),
      ),
      RinkAssignmentBlock(
        id: 'a2',
        rinkLabel: 'R2',
        title: 'Bromley',
        subtitle: 'League Match',
        startAt: at(10, 0),
        endAt: at(13, 0),
        status: RinkBlockStatus.confirmed,
        color: const Color(0xFFDBEAFE),
        textColor: const Color(0xFF1E3A8A),
      ),
      RinkAssignmentBlock(
        id: 'a3',
        rinkLabel: 'R3',
        title: 'Roll-Up',
        subtitle: 'No Players',
        startAt: at(14, 0),
        endAt: at(17, 0),
        status: RinkBlockStatus.provisional,
        color: const Color(0xFFEDE9FE),
        textColor: const Color(0xFF5B21B6),
      ),
      RinkAssignmentBlock(
        id: 'a4',
        rinkLabel: 'R4',
        title: 'Roll-Up',
        subtitle: 'No Players',
        startAt: at(14, 0),
        endAt: at(17, 0),
        status: RinkBlockStatus.provisional,
        color: const Color(0xFFEDE9FE),
        textColor: const Color(0xFF5B21B6),
      ),
      RinkAssignmentBlock(
        id: 'a5',
        rinkLabel: 'R5',
        title: 'Maintenance',
        subtitle: 'Greens Team',
        startAt: at(18, 0),
        endAt: at(20, 0),
        status: RinkBlockStatus.confirmed,
        color: const Color(0xFFFEE2E2),
        textColor: const Color(0xFF991B1B),
      ),
    ];
  }

*/

  List<UnassignedRinkNeed> _mockUnassigned(DateTime day) {
    DateTime at(int h, int m) => DateTime(day.year, day.month, day.day, h, m);

    return [
      UnassignedRinkNeed(
        id: 'u1',
        title: 'Drive',
        subtitle: '2 rinks needed',
        startAt: at(19, 0),
        endAt: at(21, 0),
        rinksRequired: 2,
        color: const Color(0xFFDCFCE7),
      ),
    ];
  }
}

class RinkLane {
  const RinkLane({required this.id, required this.label});

  final String id;
  final String label;
}

class RinkAssignmentBlock {
  const RinkAssignmentBlock({
    required this.fixtureId,
    required this.rinkLabel,
    required this.title,
    required this.startAt,
    required this.endAt,
    required this.status,
    required this.color,
    required this.textColor,
    required this.isMine,
  });

  final String fixtureId;
  final String rinkLabel;
  final String title;
  final DateTime startAt;
  final DateTime endAt;
  final RinkBlockStatus status;
  final Color color;
  final Color textColor;
  final bool isMine;
}

class UnassignedRinkNeed {
  const UnassignedRinkNeed({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.startAt,
    required this.endAt,
    required this.rinksRequired,
    required this.color,
  });

  final String id;
  final String title;
  final String subtitle;
  final DateTime startAt;
  final DateTime endAt;
  final int rinksRequired;
  final Color color;
}

class _RinksHeader extends StatelessWidget {
  const _RinksHeader({
    required this.clubName,
    required this.date,
    required this.sunsetWindow,
    required this.onPrevious,
    required this.onNext,
    required this.onPickDate,
    required this.density,
    required this.onDensityChanged,
  });

  final String clubName;
  final DateTime date;
  final SunsetBookingWindow? sunsetWindow;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPickDate;
  final RinksTimelineDensity density;
  final ValueChanged<RinksTimelineDensity> onDensityChanged;

  String get _densityLabel {
    switch (density) {
      case RinksTimelineDensity.fit:
        return 'Fit';
      case RinksTimelineDensity.compact:
        return 'Compact';
      case RinksTimelineDensity.detailed:
        return 'Detailed';
    }
  }

  IconData get _densityIcon {
    switch (density) {
      case RinksTimelineDensity.fit:
        return Icons.fit_screen;
      case RinksTimelineDensity.compact:
        return Icons.view_week;
      case RinksTimelineDensity.detailed:
        return Icons.zoom_out_map;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final narrow = MediaQuery.of(context).size.width < 650;

    final densityButton = PopupMenuButton<RinksTimelineDensity>(
      tooltip: 'Timeline density',
      initialValue: density,
      onSelected: onDensityChanged,
      itemBuilder: (_) => const [
        PopupMenuItem(value: RinksTimelineDensity.fit, child: Text('Fit day')),
        PopupMenuItem(
          value: RinksTimelineDensity.compact,
          child: Text('Compact'),
        ),
        PopupMenuItem(
          value: RinksTimelineDensity.detailed,
          child: Text('Detailed'),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFD1D5DB)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_densityIcon, size: 18, color: const Color(0xFF374151)),
            if (!narrow) ...[
              const SizedBox(width: 6),
              Text(
                _densityLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF374151),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    final sunsetChip = sunsetWindow == null
        ? null
        : _SunsetBookingChip(window: sunsetWindow!);

    final dateLine = Row(
      children: [
        Expanded(
          child: Text(
            _prettyDate(date),
            maxLines: narrow ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style:
                (narrow
                        ? theme.textTheme.headlineSmall
                        : theme.textTheme.headlineMedium)
                    ?.copyWith(
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                      color: const Color(0xFF111827),
                    ),
          ),
        ),
        const SizedBox(width: 8),
        densityButton,
        if (sunsetChip != null && !narrow) ...[
          const SizedBox(width: 8),
          sunsetChip,
        ],
      ],
    );

    final navButtons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous day',
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Next day',
        ),
        IconButton(
          onPressed: onPickDate,
          icon: const Icon(Icons.calendar_month),
          tooltip: 'Pick date',
        ),
      ],
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back',
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        clubName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF374151),
                        ),
                      ),
                    ),
                    navButtons,
                  ],
                ),
                const SizedBox(height: 6),
                dateLine,
                if (sunsetChip != null) ...[
                  const SizedBox(height: 8),
                  sunsetChip,
                ],
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back',
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clubName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF374151),
                        ),
                      ),
                      const SizedBox(height: 4),
                      dateLine,
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                navButtons,
              ],
            ),
    );
  }
}

class _SunsetBookingChip extends StatelessWidget {
  const _SunsetBookingChip({required this.window});

  final SunsetBookingWindow window;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF7ED), Color(0xFFFEE2E2)],
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFF97316)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF97316).withOpacity(0.14),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wb_twilight, size: 18, color: Color(0xFFC2410C)),
          const SizedBox(width: 8),
          Text(
            'Sunset ${_timeLabel(window.sunsetAt)}',
            style: const TextStyle(
              color: Color(0xFF9A3412),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 1,
            height: 16,
            color: const Color(0xFFF97316).withOpacity(0.45),
          ),
          const SizedBox(width: 8),
          Text(
            'Bookable until ${_timeLabel(window.bookableUntil)}',
            style: const TextStyle(
              color: Color(0xFF7F1D1D),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({
    required this.totalRinks,
    required this.assignedCount,
    required this.provisionalCount,
    required this.conflictCount,
  });

  final int totalRinks;
  final int assignedCount;
  final int provisionalCount;
  final int conflictCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          _pill(
            '${totalRinks} rinks',
            bg: const Color(0xFFF3F4F6),
            fg: const Color(0xFF111827),
          ),
          _pill(
            '$assignedCount assigned',
            bg: const Color(0xFFDBEAFE),
            fg: const Color(0xFF1D4ED8),
          ),
          _pill(
            '$provisionalCount provisional',
            bg: const Color(0xFFEDE9FE),
            fg: const Color(0xFF6D28D9),
          ),
          if (conflictCount > 0)
            _pill(
              '$conflictCount conflict${conflictCount == 1 ? '' : 's'}',
              bg: const Color(0xFFFEE2E2),
              fg: const Color(0xFFB91C1C),
            ),
        ],
      ),
    );
  }

  Widget _pill(String text, {required Color bg, required Color fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.08)),
      ),
      child: Text(
        text,
        style: TextStyle(color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _RinkLabelCell extends StatelessWidget {
  const _RinkLabelCell({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kRowHeight,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(
          right: BorderSide(color: Color(0xFFE5E7EB)),
          bottom: BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: const Color(0xFF111827),
        ),
      ),
    );
  }
}

class _RinkTimelineRow extends StatelessWidget {
  const _RinkTimelineRow({
    required this.rink,
    required this.blocks,
    required this.timelineWidth,
    required this.hourWidth,
    required this.date,
    required this.sunsetWindow,
    required this.onAfterBookableCutoffTap,
    required this.onBlockTap,
    required this.onEmptySlotTap,
    required this.horizontalOffset,
    required this.viewportWidth,
    required this.hasFutureActivity,
    this.isAlternate = false,
  });

  final RinkLane rink;
  final List<RinkAssignmentBlock> blocks;
  final double timelineWidth;
  final double hourWidth;
  final DateTime date;
  final SunsetBookingWindow? sunsetWindow;
  final VoidCallback onAfterBookableCutoffTap;
  final ValueChanged<RinkAssignmentBlock> onBlockTap;
  final ValueChanged<RinkEmptySlot> onEmptySlotTap;
  final double horizontalOffset;
  final double viewportWidth;
  final bool hasFutureActivity;
  final bool isAlternate;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        if (_isAfterBookableCutoff(details.localPosition.dx)) {
          onAfterBookableCutoffTap();
          return;
        }

        final slot = _slotForTap(details.localPosition.dx);

        if (slot != null) {
          onEmptySlotTap(slot);
        }
      },
      child: SizedBox(
        height: kRowHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: isAlternate ? const Color(0xFFF9FAFB) : Colors.white,
              ),
            ),
            _HourGridBackground(width: timelineWidth, hourWidth: hourWidth),
            if (sunsetWindow != null)
              _SunsetCutoffOverlay(
                timelineWidth: timelineWidth,
                hourWidth: hourWidth,
                sunsetAt: sunsetWindow!.sunsetAt,
                bookableUntil: sunsetWindow!.bookableUntil,
              ),
            for (final block in blocks)
              Positioned(
                left: _leftFor(block.startAt),
                top: 6,
                width: _widthFor(block.startAt, block.endAt),
                height: kRowHeight - 12,
                child: _TimelineBlock(
                  block: block,
                  onTap: () => onBlockTap(block),
                ),
              ),
            if (_hasHiddenLeft)
              const Positioned(
                left: 6,
                top: 0,
                bottom: 0,
                child: _HiddenBookingsChevron(isLeft: true),
              ),
            if (_hasHiddenRight)
              const Positioned(
                right: 6,
                top: 0,
                bottom: 0,
                child: _HiddenBookingsChevron(isLeft: false),
              ),
          ],
        ),
      ),
    );
  }

  double _leftFor(DateTime startAt) {
    final startMinutes = ((startAt.hour - kDayStartHour) * 60) + startAt.minute;
    final clamped = startMinutes.clamp(0, kDayMinutes);
    return (clamped / 60.0) * hourWidth;
  }

  double _widthFor(DateTime startAt, DateTime endAt) {
    final startMinutes = ((startAt.hour - kDayStartHour) * 60) + startAt.minute;
    final endMinutes = ((endAt.hour - kDayStartHour) * 60) + endAt.minute;
    final visibleStart = startMinutes.clamp(0, kDayMinutes);
    final visibleEnd = endMinutes.clamp(0, kDayMinutes);
    final durationMinutes = (visibleEnd - visibleStart).clamp(20, kDayMinutes);
    return (durationMinutes / 60.0) * hourWidth;
  }

  RinkEmptySlot? _slotForTap(double x) {
    final tapMinutes = _minutesForX(x);
    final effectiveEndMinutes = _effectiveBookableEndMinutes;

    if (tapMinutes >= effectiveEndMinutes) {
      return null;
    }

    final intervals =
        blocks
            .map((block) {
              final start = _clampMinute(
                _minutesFromDayStart(block.startAt),
                effectiveEndMinutes,
              );

              final end = _clampMinute(
                _minutesFromDayStart(block.endAt),
                effectiveEndMinutes,
              );

              return (start: start, end: end);
            })
            .where((interval) => interval.end > interval.start)
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));

    var gapStartMinutes = 0;

    for (final interval in intervals) {
      if (tapMinutes >= gapStartMinutes && tapMinutes < interval.start) {
        return _slotFromMinutes(
          tapMinutes: tapMinutes,
          startMinutes: gapStartMinutes,
          endMinutes: interval.start,
        );
      }

      if (tapMinutes >= interval.start && tapMinutes < interval.end) {
        return null;
      }

      if (interval.end > gapStartMinutes) {
        gapStartMinutes = interval.end;
      }
    }

    if (tapMinutes >= gapStartMinutes && tapMinutes < effectiveEndMinutes) {
      return _slotFromMinutes(
        tapMinutes: tapMinutes,
        startMinutes: gapStartMinutes,
        endMinutes: effectiveEndMinutes,
      );
    }

    return null;
  }

  int get _effectiveBookableEndMinutes {
    final window = sunsetWindow;
    if (window == null) return kDayMinutes;

    return _clampMinute(
      _minutesFromDayStart(window.bookableUntil),
      kDayMinutes,
    );
  }

  bool _isAfterBookableCutoff(double x) {
    if (sunsetWindow == null) return false;
    return _minutesForX(x) >= _effectiveBookableEndMinutes;
  }

  int _minutesForX(double x) {
    return ((x / hourWidth) * 60).round().clamp(0, kDayMinutes).toInt();
  }

  int _minutesFromDayStart(DateTime value) {
    return ((value.hour - kDayStartHour) * 60) + value.minute;
  }

  int _clampMinute(int value, int max) {
    if (value < 0) return 0;
    if (value > max) return max;
    return value;
  }

  RinkEmptySlot _slotFromMinutes({
    required int tapMinutes,
    required int startMinutes,
    required int endMinutes,
  }) {
    final dayStart = DateTime(date.year, date.month, date.day, kDayStartHour);

    final suggestedStartMinutes = _suggestedStartMinutes(
      tapMinutes: tapMinutes,
      gapStartMinutes: startMinutes,
      gapEndMinutes: endMinutes,
    );

    final suggestedEndMinutes = _suggestedEndMinutes(
      suggestedStartMinutes: suggestedStartMinutes,
      gapEndMinutes: endMinutes,
    );

    return RinkEmptySlot(
      rinkLabel: rink.label,
      tapAt: dayStart.add(Duration(minutes: tapMinutes)),
      startAt: dayStart.add(Duration(minutes: startMinutes)),
      endAt: dayStart.add(Duration(minutes: endMinutes)),
      suggestedStartAt: dayStart.add(Duration(minutes: suggestedStartMinutes)),
      suggestedEndAt: dayStart.add(Duration(minutes: suggestedEndMinutes)),
    );
  }

  int _suggestedStartMinutes({
    required int tapMinutes,
    required int gapStartMinutes,
    required int gapEndMinutes,
  }) {
    const normalFixtureMinutes = 120;

    final latestPossibleStart = gapEndMinutes - normalFixtureMinutes;

    if (latestPossibleStart < gapStartMinutes) {
      return gapStartMinutes;
    }

    final firstWholeHourStart = _ceilToHour(gapStartMinutes);
    final lastWholeHourStart = _floorToHour(latestPossibleStart);

    if (firstWholeHourStart > lastWholeHourStart) {
      return gapStartMinutes;
    }

    var bestStart = firstWholeHourStart;
    var bestDistance = (firstWholeHourStart - tapMinutes).abs();

    for (
      var candidate = firstWholeHourStart;
      candidate <= lastWholeHourStart;
      candidate += 60
    ) {
      final distance = (candidate - tapMinutes).abs();

      if (distance < bestDistance) {
        bestDistance = distance;
        bestStart = candidate;
      }
    }

    return bestStart;
  }

  int _suggestedEndMinutes({
    required int suggestedStartMinutes,
    required int gapEndMinutes,
  }) {
    const normalFixtureMinutes = 120;

    final suggestedEnd = suggestedStartMinutes + normalFixtureMinutes;

    if (suggestedEnd > gapEndMinutes) {
      return gapEndMinutes;
    }

    return suggestedEnd;
  }

  int _ceilToHour(int minutes) {
    if (minutes % 60 == 0) return minutes;
    return ((minutes ~/ 60) + 1) * 60;
  }

  int _floorToHour(int minutes) {
    return (minutes ~/ 60) * 60;
  }

  bool get _hasHiddenLeft {
    if (horizontalOffset <= 4) return false;

    return blocks.any(
      (block) => _leftFor(block.startAt) < horizontalOffset - 2,
    );
  }

  bool get _hasHiddenRight {
    final visibleRight = horizontalOffset + viewportWidth;

    final hasHiddenAssigned = blocks.any(
      (block) =>
          _leftFor(block.startAt) + _widthFor(block.startAt, block.endAt) >
          visibleRight + 2,
    );

    if (blocks.isEmpty && hasFutureActivity) {
      return true;
    }

    return hasHiddenAssigned;
  }
}

class _SunsetCutoffOverlay extends StatelessWidget {
  const _SunsetCutoffOverlay({
    required this.timelineWidth,
    required this.hourWidth,
    required this.sunsetAt,
    required this.bookableUntil,
  });

  final double timelineWidth;
  final double hourWidth;
  final DateTime sunsetAt;
  final DateTime bookableUntil;

  double _leftFor(DateTime value) {
    final minutes = (((value.hour - kDayStartHour) * 60) + value.minute)
        .clamp(0, kDayMinutes)
        .toDouble();

    return ((minutes / 60.0) * hourWidth).clamp(0.0, timelineWidth);
  }

  @override
  Widget build(BuildContext context) {
    final sunsetLeft = _leftFor(sunsetAt);
    final cutoffLeft = _leftFor(bookableUntil);

    return IgnorePointer(
      child: SizedBox(
        width: timelineWidth,
        height: kRowHeight,
        child: Stack(
          children: [
            if (cutoffLeft < timelineWidth - 1)
              Positioned(
                left: cutoffLeft,
                top: 0,
                bottom: 0,
                width: timelineWidth - cutoffLeft,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2).withOpacity(0.45),
                    border: const Border(
                      left: BorderSide(color: Color(0xFFDC2626), width: 2),
                    ),
                  ),
                ),
              ),
            if (sunsetLeft >= 0 && sunsetLeft <= timelineWidth)
              Positioned(
                left: sunsetLeft - 1,
                top: 0,
                bottom: 0,
                width: 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF97316),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF97316).withOpacity(0.45),
                        blurRadius: 6,
                        spreadRadius: 1,
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

class _HourGridBackground extends StatelessWidget {
  const _HourGridBackground({required this.width, required this.hourWidth});

  final double width;
  final double hourWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: kRowHeight,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          for (int hour = kDayStartHour; hour < kDayEndHour; hour++)
            Container(
              width: hourWidth,
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: Color(0xFFF3F4F6))),
              ),
            ),
        ],
      ),
    );
  }
}

class _HiddenBookingsChevron extends StatelessWidget {
  const _HiddenBookingsChevron({required this.isLeft});

  final bool isLeft;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.88),
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Icon(
          isLeft ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: const Color(0xFF6B7280),
        ),
      ),
    );
  }
}

class _TimelineBlock extends StatelessWidget {
  const _TimelineBlock({required this.block, required this.onTap});

  final RinkAssignmentBlock block;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isProvisional = block.status == RinkBlockStatus.provisional;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isProvisional ? block.color.withOpacity(0.58) : block.color,
          borderRadius: BorderRadius.circular(14),
          boxShadow: isProvisional
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x11000000),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
          border: Border.all(
            color: block.textColor.withOpacity(isProvisional ? 0.55 : 0.15),
            width: 1.2,
          ),
        ),
        child: Stack(
          children: [
            if (block.isMine)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person,
                    size: 12,
                    color: block.textColor.withOpacity(0.95),
                  ),
                ),
              ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 120;

                    if (compact) {
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          block.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: block.textColor,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          block.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: block.textColor,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '${_timeLabel(block.startAt)}–${_timeLabel(block.endAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: block.textColor.withOpacity(0.85),
                                fontWeight: FontWeight.w600,
                                height: 1.0,
                              ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnassignedNeedsPanel extends StatelessWidget {
  const _UnassignedNeedsPanel({required this.items, required this.onTap});

  final List<UnassignedRinkNeed> items;
  final ValueChanged<UnassignedRinkNeed> onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Awaiting rink assignment',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            for (final item in items)
              InkWell(
                onTap: () => onTap(item),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: item.color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${item.subtitle} • ${_timeLabel(item.startAt)}–${_timeLabel(item.endAt)}',
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
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

class SunsetBookingWindow {
  const SunsetBookingWindow({
    required this.sunsetAt,
    required this.bookableUntil,
    required this.offsetMinutes,
  });

  final DateTime sunsetAt;
  final DateTime bookableUntil;
  final int offsetMinutes;
}

SunsetBookingWindow? calculateSunsetBookingWindow({
  required DateTime date,
  required double latitude,
  required double longitude,
  required int offsetMinutes,
}) {
  // NOAA-style sunrise/sunset calculation.
  // Good enough for booking cutoffs; normally within a minute or two.
  final dayOfYear =
      DateTime(
        date.year,
        date.month,
        date.day,
      ).difference(DateTime(date.year, 1, 1)).inDays +
      1;

  const zenith = 90.833; // official sunset
  final lngHour = longitude / 15.0;

  // Approximate time for sunset.
  final t = dayOfYear + ((18.0 - lngHour) / 24.0);

  final m = (0.9856 * t) - 3.289;

  var l = m + (1.916 * _sinDeg(m)) + (0.020 * _sinDeg(2 * m)) + 282.634;

  l = _normaliseDegrees(l);

  var ra = _atanDeg(0.91764 * _tanDeg(l));
  ra = _normaliseDegrees(ra);

  final lQuadrant = (l / 90.0).floor() * 90.0;
  final raQuadrant = (ra / 90.0).floor() * 90.0;
  ra = ra + (lQuadrant - raQuadrant);
  ra = ra / 15.0;

  final sinDec = 0.39782 * _sinDeg(l);
  final cosDec = _cosDeg(_asinDeg(sinDec));

  final cosH =
      (_cosDeg(zenith) - (sinDec * _sinDeg(latitude))) /
      (cosDec * _cosDeg(latitude));

  if (cosH > 1 || cosH < -1) {
    // Polar day/night edge case. Not expected for UK bowls clubs,
    // but return null rather than making nonsense.
    return null;
  }

  // Sunset uses acos(cosH).
  final h = _acosDeg(cosH) / 15.0;

  final localMeanTime = h + ra - (0.06571 * t) - 6.622;

  var utcHour = localMeanTime - lngHour;
  while (utcHour < 0) {
    utcHour += 24;
  }
  while (utcHour >= 24) {
    utcHour -= 24;
  }

  final utcMinutes = (utcHour * 60).round();

  final sunsetUtc = DateTime.utc(
    date.year,
    date.month,
    date.day,
  ).add(Duration(minutes: utcMinutes));

  final sunsetClubTime = parseClubTime(sunsetUtc.toIso8601String());

  return SunsetBookingWindow(
    sunsetAt: sunsetClubTime,
    bookableUntil: sunsetClubTime.add(Duration(minutes: offsetMinutes)),
    offsetMinutes: offsetMinutes,
  );
}

double _normaliseDegrees(double value) {
  var result = value % 360.0;
  if (result < 0) result += 360.0;
  return result;
}

double _degToRad(double degrees) => degrees * 3.141592653589793 / 180.0;
double _radToDeg(double radians) => radians * 180.0 / 3.141592653589793;

double _sinDeg(double degrees) => math.sin(_degToRad(degrees));
double _cosDeg(double degrees) => math.cos(_degToRad(degrees));
double _tanDeg(double degrees) => math.tan(_degToRad(degrees));
double _asinDeg(double value) => _radToDeg(math.asin(value));
double _acosDeg(double value) => _radToDeg(math.acos(value));
double _atanDeg(double value) => _radToDeg(math.atan(value));

class RinkEmptySlot {
  const RinkEmptySlot({
    required this.rinkLabel,
    required this.tapAt,
    required this.startAt,
    required this.endAt,
    required this.suggestedStartAt,
    required this.suggestedEndAt,
  });

  final String rinkLabel;

  /// The actual time represented by the mouse/tap position.
  final DateTime tapAt;

  /// Start of the whole available gap.
  final DateTime startAt;

  /// End of the whole available gap / latest possible finish.
  final DateTime endAt;

  /// Suggested booking start time, rounded from the tap position.
  final DateTime suggestedStartAt;

  /// Suggested booking end time, normally suggestedStartAt + 2 hours,
  /// but clipped to the available gap/sunset cutoff.
  final DateTime suggestedEndAt;

  Duration get duration => endAt.difference(startAt);

  Duration get suggestedDuration => suggestedEndAt.difference(suggestedStartAt);
}

String _hourLabel(int hour) {
  final h = hour.toString().padLeft(2, '0');
  return '$h:00';
}

String _timeLabel(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

String _durationLabel(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);

  if (hours > 0 && minutes > 0) {
    return '$hours hr ${minutes} mins';
  }

  if (hours > 0) {
    return hours == 1 ? '1 hr' : '$hours hrs';
  }

  return '$minutes mins';
}

String _prettyDate(DateTime dt) {
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
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
  return '${weekdays[dt.weekday - 1]} ${dt.day} ${months[dt.month - 1]} ${dt.year}';
}
