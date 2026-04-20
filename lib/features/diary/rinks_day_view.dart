import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
const double kRinkLabelWidth = 84;
const double kTimelineMinWidth = 1040;
const double kRowHeight = 72;
const double kHeaderHeight = 44;
const double kHourWidth = 80;

enum RinkBlockStatus { confirmed, provisional, blocked }

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
  double _horizontalOffset = 0;
  late DateTime _selectedDate;

  final _client = Supabase.instance.client;

  bool _isLoading = true;
  String? _loadError;

  String? _myProfileId;

  List<RinkLane> _rinks = [];
  List<RinkAssignmentBlock> _assignments = [];
  List<UnassignedRinkNeed> _unassigned = [];

  final ScrollController _horizontalHeaderController = ScrollController();
  final ScrollController _horizontalBodyController = ScrollController();
  final ScrollController _verticalBodyController = ScrollController();

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime(widget.date.year, widget.date.month, widget.date.day);

    _horizontalBodyController.addListener(_syncHorizontalFromBody);
    _horizontalHeaderController.addListener(_syncHorizontalFromHeader);

    _loadDay();
  }

  @override
  void dispose() {
    _horizontalBodyController.removeListener(_syncHorizontalFromBody);
    _horizontalHeaderController.removeListener(_syncHorizontalFromHeader);
    _horizontalHeaderController.dispose();
    _horizontalBodyController.dispose();
    _verticalBodyController.dispose();
    super.dispose();
  }

  void _syncHorizontalFromBody() {
    if (mounted) {
      setState(() {
        _horizontalOffset =
            _horizontalBodyController.hasClients ? _horizontalBodyController.offset : 0;
      });
    }

    if (!_horizontalHeaderController.hasClients) return;
    if ((_horizontalHeaderController.offset - _horizontalBodyController.offset).abs() < 1) {
      return;
    }
    _horizontalHeaderController.jumpTo(_horizontalBodyController.offset);
  }

  void _syncHorizontalFromHeader() {
    if (!_horizontalBodyController.hasClients) return;
    if ((_horizontalBodyController.offset - _horizontalHeaderController.offset).abs() < 1) return;
    _horizontalBodyController.jumpTo(_horizontalHeaderController.offset);
  }

  void _moveDay(int delta) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: delta));
    });
    _loadDay();
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

      final dayEnd = dayStart.add(const Duration(days: 1));

      final green = await _loadHomeGreen();
      final rinks = _buildRinksFromGreen(green);

      final fixtures = await _loadHomeFixturesForDay(dayStart, dayEnd);

      final assignments = _mapAssignments(fixtures);
      final unassigned = _mapUnassigned(fixtures);

      if (!mounted) return;

      setState(() {
        _rinks = rinks;
        _assignments = assignments;
        _unassigned = unassigned;
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

  Future<Map<String, dynamic>> _loadHomeGreen() async {
    final venue = await _client
        .from('venues')
        .select('id, name')
        .eq('club_id', widget.clubId)
        .eq('is_home_venue', true)
        .maybeSingle();

    if (venue == null) {
      throw Exception('No home venue found for this club');
    }

    final green = await _client
        .from('green_areas')
        .select('id, name, rink_count')
        .eq('venue_id', venue['id'])
        .limit(1)
        .maybeSingle();

    if (green == null) {
      throw Exception('No green area found for the home venue');
    }

    return Map<String, dynamic>.from(green);
  }

  List<RinkLane> _buildRinksFromGreen(Map<String, dynamic> green) {
    final rinkCount = (green['rink_count'] ?? 0) as int;

    final custom = green['custom_labels'];

    if (custom is List && custom.isNotEmpty) {
      return custom
          .map((e) => e.toString())
          .toList()
          .asMap()
          .entries
          .map((e) => RinkLane(id: '${e.key + 1}', label: e.value))
          .toList();
    }

    final prefix = (green['scheme_prefix'] ?? 'R').toString();
    final padding = (green['scheme_padding'] ?? 0) as int;

    return List.generate(rinkCount, (i) {
      final num = (i + 1).toString().padLeft(padding, '0');
      return RinkLane(
        id: '${i + 1}',
        label: '$prefix$num',
      );
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
        .gte('start_at', dayStart.toIso8601String())
        .lt('start_at', dayEnd.toIso8601String())
        .order('start_at');

    return List<Map<String, dynamic>>.from(res);
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
    final opponentName =
        (fixture['opponent_name'] ?? '').toString().trim();

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
      final startAt =
          DateTime.parse(fixture['start_at'].toString()).toLocal();
      final endAt = fixture['end_at'] != null
          ? DateTime.parse(fixture['end_at'].toString()).toLocal()
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

      final rinks =
          List<Map<String, dynamic>>.from(fixture['fixture_rinks'] ?? []);

      for (final rink in rinks) {
        final rinkAssignments = List<Map<String, dynamic>>.from(
          rink['fixture_rink_assignments'] ?? [],
        );

        final isMine = _myProfileId != null &&
            rinkAssignments.any(
              (a) => a['member_profile_id']?.toString() == _myProfileId,
            );

        final rinkLabel =
            (rink['home_rink_label'] ?? '').toString().trim();

        if (rinkLabel.isEmpty) continue;

        blocks.add(
          RinkAssignmentBlock(
            id: '${fixture['id']}-${rink['id']}',
            rinkLabel: rinkLabel,
            title: title,
            subtitle: '',
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

  List<UnassignedRinkNeed> _mapUnassigned(
    List<Map<String, dynamic>> fixtures,
  ) {
    final items = <UnassignedRinkNeed>[];

    for (final fixture in fixtures) {
      final rinks =
          List<Map<String, dynamic>>.from(fixture['fixture_rinks'] ?? []);
      final rinksRequired = (fixture['rinks_required'] ?? 0) as int;

      if (rinks.isNotEmpty || rinksRequired <= 0) continue;

      final startAt =
          DateTime.parse(fixture['start_at'].toString()).toLocal();

      final endAt = fixture['end_at'] != null
          ? DateTime.parse(fixture['end_at'].toString()).toLocal()
          : startAt.add(const Duration(hours: 3));

      final competitionType = fixture['competition_types'] as Map<String, dynamic>?;
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
          subtitle: '$rinksRequired rink${rinksRequired == 1 ? '' : 's'} needed',
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

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
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
      body: Column(
        children: [
          _RinksHeader(
            clubName: widget.clubName,
            date: _selectedDate,
            onPrevious: () => _moveDay(-1),
            onNext: () => _moveDay(1),
          ),
          _SummaryBar(
            totalRinks: rinks.length,
            assignedCount: assignments.where((a) => a.status == RinkBlockStatus.confirmed).length,
            provisionalCount: assignments.where((a) => a.status == RinkBlockStatus.provisional).length + unassigned.length,
            conflictCount: 0,
          ),
          Expanded(
            child: isWide
                ? _buildDesktopLayout(context, rinks, assignments, unassigned)
                : _buildMobileLayout(context, rinks, assignments, unassigned),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    List<RinkLane> rinks,
    List<RinkAssignmentBlock> assignments,
    List<UnassignedRinkNeed> unassigned,
  ) {
    return Column(
      children: [        
        _buildTimeHeader(context, assignments, rinks.length),
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: kRinkLabelWidth,
                child: Column(
                  children: [
                    for (final rink in rinks)
                      _RinkLabelCell(label: rink.label),
                  ],
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
                      width: _timelineWidth,
                      child: Scrollbar(
                        controller: _verticalBodyController,
                        thumbVisibility: true,
                        child: ListView.builder(
                          controller: _verticalBodyController,
                          itemCount: rinks.length,
                          itemBuilder: (context, index) {
                            final rink = rinks[index];
                            final blocks = assignments.where((a) => a.rinkLabel == rink.label).toList();
                            return LayoutBuilder(
                              builder: (context, constraints) => _RinkTimelineRow(
                                rink: rink,
                                blocks: blocks,
                                timelineWidth: _timelineWidth,
                                onBlockTap: _openBlock,
                                isAlternate: index.isOdd,
                                horizontalOffset: _horizontalOffset,
                                viewportWidth: constraints.maxWidth,
                                hasFutureActivity: assignments.isNotEmpty || unassigned.isNotEmpty,
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
          _UnassignedNeedsPanel(
            items: unassigned,
            onTap: (item) {},
          ),
      ],
    );
  }

  Widget _buildMobileLayout(
    BuildContext context,
    List<RinkLane> rinks,
    List<RinkAssignmentBlock> assignments,
    List<UnassignedRinkNeed> unassigned,
  ) {
    final hasFutureActivity =
        assignments.isNotEmpty || unassigned.isNotEmpty;

    return Column(
      children: [
        _buildTimeHeader(context, assignments, rinks.length),
        Expanded(
          child: SingleChildScrollView(
            controller: _horizontalBodyController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: kRinkLabelWidth + _timelineWidth,
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
                          width: _timelineWidth,
                          child: _RinkTimelineRow(
                            rink: rink,
                            blocks: assignments
                                .where((a) => a.rinkLabel == rink.label)
                                .toList(),
                            timelineWidth: _timelineWidth,
                            onBlockTap: _openBlock,
                            isAlternate: rinks.indexOf(rink).isOdd,
                            horizontalOffset: _horizontalOffset,
                            viewportWidth:
                                MediaQuery.of(context).size.width - kRinkLabelWidth,
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
  }

  List<int> _buildRinkUsagePerHour(
    List<RinkAssignmentBlock> assignments,
  ) {
    final usage = List<int>.filled(
      kDayEndHour - kDayStartHour + 1,
      0,
    );

    for (final block in assignments) {
      final startHour = block.startAt.hour;
      final endHour = block.endAt.hour;

      for (int hour = startHour; hour <= endHour; hour++) {
        final index = hour - kDayStartHour;
        if (index >= 0 && index < usage.length) {
          usage[index]++;
        }
      }
    }

    return usage;
  }

  Widget _buildTimeHeader(
    BuildContext context,
    List<RinkAssignmentBlock> assignments,
    int rinkCount,
  ) {
    final textStyle = Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700);
    
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
              width: _timelineWidth,
              height: kHeaderHeight + 24,
              child: Column(
                children: [
                  Row(
                    children: [
                      for (int i = 0; i < usage.length; i++)
                        Container(
                          width: kHourWidth,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            border: Border(
                              left: BorderSide(color: Color(0xFFEEEEEE)),
                            ),
                          ),
                          child: Text(
                            usage[i] == 0 ? '' : usage[i].toString(),
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
                      for (int hour = kDayStartHour; hour <= kDayEndHour; hour++)
                        Container(
                          width: kHourWidth,
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

  double get _timelineWidth => (kDayEndHour - kDayStartHour + 1) * kHourWidth;

  void _openBlock(RinkAssignmentBlock block) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(block.title)),
    );
  }

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
        id: 'a1',
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
    required this.id,
    required this.rinkLabel,
    required this.title,
    required this.subtitle,
    required this.startAt,
    required this.endAt,
    required this.status,
    required this.color,
    required this.textColor,
    this.isMine = false,
  });

  final String id;
  final String rinkLabel;
  final String title;
  final String subtitle;
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
    required this.onPrevious,
    required this.onNext,
  });

  final String clubName;
  final DateTime date;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final narrow = MediaQuery.of(context).size.width < 430;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
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
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF374151),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _prettyDate(date),
                  maxLines: narrow ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                    color: const Color(0xFF111827),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
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
                onPressed: () {},
                icon: const Icon(Icons.calendar_view_month),
                tooltip: 'Change view',
              ),
            ],
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
          _pill('${totalRinks} rinks', bg: const Color(0xFFF3F4F6), fg: const Color(0xFF111827)),
          _pill('$assignedCount assigned', bg: const Color(0xFFDBEAFE), fg: const Color(0xFF1D4ED8)),
          _pill('$provisionalCount provisional', bg: const Color(0xFFEDE9FE), fg: const Color(0xFF6D28D9)),
          if (conflictCount > 0)
            _pill('$conflictCount conflict${conflictCount == 1 ? '' : 's'}', bg: const Color(0xFFFEE2E2), fg: const Color(0xFFB91C1C)),
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
    required this.onBlockTap,
    required this.horizontalOffset,
    required this.viewportWidth,
    required this.hasFutureActivity,
    this.isAlternate = false,
  });

  final RinkLane rink;
  final List<RinkAssignmentBlock> blocks;
  final double timelineWidth;
  final ValueChanged<RinkAssignmentBlock> onBlockTap;
  final double horizontalOffset;
  final double viewportWidth;
  final bool hasFutureActivity;
  final bool isAlternate;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kRowHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: isAlternate ? const Color(0xFFF9FAFB) : Colors.white,
            ),
          ),
          _HourGridBackground(width: timelineWidth),
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
    );
  }

  double _leftFor(DateTime startAt) {
    final startMinutes = ((startAt.hour - kDayStartHour) * 60) + startAt.minute;
    final clamped = startMinutes.clamp(0, kDayMinutes);
    return (clamped / 60.0) * kHourWidth;
  }

  double _widthFor(DateTime startAt, DateTime endAt) {
    final startMinutes = ((startAt.hour - kDayStartHour) * 60) + startAt.minute;
    final endMinutes = ((endAt.hour - kDayStartHour) * 60) + endAt.minute;
    final visibleStart = startMinutes.clamp(0, kDayMinutes);
    final visibleEnd = endMinutes.clamp(0, kDayMinutes);
    final durationMinutes = (visibleEnd - visibleStart).clamp(20, kDayMinutes);
    return (durationMinutes / 60.0) * kHourWidth;
  }

  bool get _hasHiddenLeft {
    if (horizontalOffset <= 4) return false;
    return blocks.any((block) => _leftFor(block.startAt) < horizontalOffset - 2);
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

class _HourGridBackground extends StatelessWidget {
  const _HourGridBackground({required this.width});

  final double width;

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
              width: kHourWidth,
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
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
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
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: block.textColor,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '${_timeLabel(block.startAt)}–${_timeLabel(block.endAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
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
                            Text(item.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text('${item.subtitle} • ${_timeLabel(item.startAt)}–${_timeLabel(item.endAt)}'),
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

String _hourLabel(int hour) {
  final h = hour.toString().padLeft(2, '0');
  return '$h:00';
}

String _timeLabel(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

String _prettyDate(DateTime dt) {
  const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
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
 