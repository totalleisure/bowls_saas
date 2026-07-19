import 'package:flutter/material.dart';

class RepeatFixtureDate {
  RepeatFixtureDate({
    required this.date,
    this.enabled = true,
    this.isHome = true,
    this.opponentVenueId,
    this.warning,
  });

  final DateTime date;
  bool enabled;
  bool isHome;
  String? opponentVenueId;
  String? warning;
}

class RepeatFixturePlannerPage extends StatefulWidget {
  const RepeatFixturePlannerPage({
    super.key,
    required this.startDateTime,
    required this.requiresOpponent,
    required this.opponentVenues,
  });

  final DateTime startDateTime;
  final bool requiresOpponent;
  final List<Map<String, dynamic>> opponentVenues;

  @override
  State<RepeatFixturePlannerPage> createState() =>
      _RepeatFixturePlannerPageState();
}

class _RepeatFixturePlannerPageState extends State<RepeatFixturePlannerPage> {
  final Color _setupCardColor = Colors.blue.shade50;
  final Color _repeatOnCardColor = Colors.purple.shade50;
  final Color _addDateCardColor = Colors.orange.shade50;
  final Color _dateCardColor = Colors.green.shade50;
  final Color _selectedToggleColor = Colors.green.shade700;

  DateTime? _fromDate;
  DateTime? _toDate;

  final Set<int> _weekdays = {};
  final List<RepeatFixtureDate> _dates = [];
  final List<RepeatFixtureDate> _manualDates = [];

  int get _enabledCount => _allDates.where((d) => d.enabled).length;

  List<RepeatFixtureDate> get _allDates {
    final byKey = <String, RepeatFixtureDate>{};

    for (final d in [..._dates, ..._manualDates]) {
      byKey[_dateKey(d.date)] = d;
    }

    final result = byKey.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    return result;
  }

  @override
  void initState() {
    super.initState();
    _fromDate = DateTime(
      widget.startDateTime.year,
      widget.startDateTime.month,
      widget.startDateTime.day,
    );
    _weekdays.add(widget.startDateTime.weekday);
  }

  void _generateDates() {
    if (_fromDate == null || _toDate == null || _weekdays.isEmpty) {
      setState(() => _dates.clear());
      return;
    }

    final result = <RepeatFixtureDate>[];

    var cursor = _fromDate!;
    while (!cursor.isAfter(_toDate!)) {
      if (_weekdays.contains(cursor.weekday)) {
        result.add(RepeatFixtureDate(date: cursor));
      }
      cursor = cursor.add(const Duration(days: 1));
    }

    setState(() {
      _dates
        ..clear()
        ..addAll(result);
    });
  }

  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _fromDate = picked);
      _generateDates();
    }
  }

  Future<void> _pickToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? _fromDate ?? DateTime.now(),
      firstDate: _fromDate ?? DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _toDate = picked);
      _generateDates();
    }
  }

  Widget _weekdayChip(String label, int weekday) {
    return FilterChip(
      label: Text(label),
      selected: _weekdays.contains(weekday),
      onSelected: (selected) {
        setState(() {
          if (selected) {
            _weekdays.add(weekday);
          } else {
            _weekdays.remove(weekday);
          }
        });
        _generateDates();
      },
    );
  }

  String _dateLabel(DateTime date) {
    return MaterialLocalizations.of(context).formatFullDate(date);
  }

  String _dateKey(DateTime date) {
    return '${date.year}-${date.month}-${date.day}';
  }

  String _shortDateLabel(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  Future<void> _pickSingleDateToAdd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? widget.startDateTime,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked == null) return;

    final normalised = DateTime(picked.year, picked.month, picked.day);

    final exists = _manualDates.any(
      (d) =>
          d.date.year == normalised.year &&
          d.date.month == normalised.month &&
          d.date.day == normalised.day,
    );

    if (!exists) {
      setState(() {
        _manualDates.add(RepeatFixtureDate(date: normalised));
        _manualDates.sort((a, b) => a.date.compareTo(b.date));
      });
    }
  }

  Widget _buildManualDateButton(RepeatFixtureDate item) {
    return FilterChip(
      label: Text(_shortDateLabel(item.date)),
      selected: item.enabled,
      onSelected: (selected) {
        setState(() {
          item.enabled = selected;
        });
      },
      onDeleted: () {
        setState(() {
          _manualDates.remove(item);
        });
      },
    );
  }

  Widget _buildGenerationCard() {
    return Card(
      color: _setupCardColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Repeat setup',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _pickFromDate,
                    child: Text(
                      _fromDate == null
                          ? 'From date'
                          : MaterialLocalizations.of(
                              context,
                            ).formatMediumDate(_fromDate!),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _pickToDate,
                    child: Text(
                      _toDate == null
                          ? 'To date'
                          : MaterialLocalizations.of(
                              context,
                            ).formatMediumDate(_toDate!),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _repeatOnCardColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Repeat on',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _weekdayChip('Mon', DateTime.monday),
                      _weekdayChip('Tue', DateTime.tuesday),
                      _weekdayChip('Wed', DateTime.wednesday),
                      _weekdayChip('Thu', DateTime.thursday),
                      _weekdayChip('Fri', DateTime.friday),
                      _weekdayChip('Sat', DateTime.saturday),
                      _weekdayChip('Sun', DateTime.sunday),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _addDateCardColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickSingleDateToAdd,
                        icon: const Icon(Icons.calendar_month),
                        label: const Text('Add date'),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '$_enabledCount fixture${_enabledCount == 1 ? '' : 's'} selected',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  if (_manualDates.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _manualDates
                          .map(_buildManualDateButton)
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selected fixture dates',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),

            Text(
              _allDates.isEmpty
                  ? 'No dates selected yet'
                  : '$_enabledCount fixture${_enabledCount == 1 ? '' : 's'} will be created',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 4),

            if (_allDates.isEmpty)
              const Text(
                'Choose a date range and days above, or add specific dates.',
              )
            else
              ..._allDates.map(_buildDateTile),
          ],
        ),
      ),
    );
  }

  Widget _buildDateTile(RepeatFixtureDate item) {
    final isNarrow = MediaQuery.of(context).size.width < 600;

    Widget dateAndToggleRow() {
      return Row(
        children: [
          Checkbox(
            value: item.enabled,
            onChanged: (value) {
              setState(() => item.enabled = value ?? false);
            },
          ),
          Expanded(
            child: Text(
              _dateLabel(item.date),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (widget.requiresOpponent) ...[
            const SizedBox(width: 8),
            ToggleButtons(
              isSelected: [item.isHome, !item.isHome],
              color: Colors.grey,
              selectedColor: Colors.white,
              fillColor: Colors.green.shade700,
              selectedBorderColor: Colors.green.shade700,
              borderColor: Colors.green.shade300,
              borderRadius: BorderRadius.circular(8),
              constraints: const BoxConstraints(minHeight: 32, minWidth: 42),
              onPressed: item.enabled
                  ? (index) {
                      setState(() {
                        item.isHome = index == 0;
                      });
                    }
                  : null,
              children: const [Text('H'), Text('A')],
            ),
          ],
        ],
      );
    }

    Widget opponentDropdown() {
      return DropdownButtonFormField<String>(
        value: item.opponentVenueId,
        decoration: const InputDecoration(
          labelText: 'Opponent',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: widget.opponentVenues.map((venue) {
          return DropdownMenuItem<String>(
            value: venue['id'].toString(),
            child: Text(
              (venue['name'] ?? '').toString(),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
        onChanged: item.enabled
            ? (value) {
                setState(() {
                  item.opponentVenueId = value;
                });
              }
            : null,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Card(
        color: Colors.green.shade50,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Colors.green.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: widget.requiresOpponent
              ? isNarrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          dateAndToggleRow(),
                          const SizedBox(height: 8),
                          opponentDropdown(),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(flex: 2, child: dateAndToggleRow()),
                          const SizedBox(width: 8),
                          Expanded(flex: 3, child: opponentDropdown()),
                        ],
                      )
              : dateAndToggleRow(),
        ),
      ),
    );
  }

  Future<void> _handleCancel() async {
    final hasOpponentInfo = _allDates.any(
      (d) => d.opponentVenueId != null && d.opponentVenueId!.isNotEmpty,
    );

    if (!hasOpponentInfo) {
      Navigator.pop(context);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cancel repeat fixture setup?'),
          content: const Text(
            'All selected opponent fixture information will be lost.\n\n'
            'Do you want to cancel?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Repeat Fixture Planner'),
        actions: [
          TextButton(
            onPressed: _handleCancel,
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: _enabledCount == 0
                ? null
                : () => Navigator.pop(context, _allDates),
            child: const Text(
              'Proceed',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildGenerationCard(),
          const SizedBox(height: 8),
          _buildDatesCard(),
        ],
      ),
    );
  }
}
