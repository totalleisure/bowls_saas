import '../../fixtures/fixture_type_booking_policy.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String bookingClock(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

/// Shared Club timetable. Fixture Types opt in individually.
class FixtureBookingStartTimesScreen extends StatefulWidget {
  const FixtureBookingStartTimesScreen({
    super.key,
    required this.clubId,
    this.readOnly = false,
  });
  final String clubId;
  final bool readOnly;
  @override
  State<FixtureBookingStartTimesScreen> createState() =>
      _FixtureBookingStartTimesScreenState();
}

class _FixtureBookingStartTimesScreenState
    extends State<FixtureBookingStartTimesScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _windows = [];
  String? _revision, _error;
  bool _loading = true, _saving = false, _dirty = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final row = await _client
          .from('fixture_booking_start_rules')
          .select()
          .eq('club_id', widget.clubId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _revision = row?['updated_at']?.toString();
        _windows = (row?['windows'] as List? ?? [])
            .map((w) => Map<String, dynamic>.from(w as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = bookingErrorMessage(e);
          _loading = false;
        });
    }
  }

  Future<int?> _time(int value) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: value ~/ 60, minute: value % 60),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    return t == null ? null : t.hour * 60 + t.minute;
  }

  Future<void> _edit([int? index]) async {
    int from = index == null ? 840 : (_windows[index]['from'] as num).toInt();
    int until = index == null
        ? 1200
        : (_windows[index]['until'] as num).toInt();
    final starts = index == null
        ? <int>[]
        : List<int>.from(_windows[index]['starts'] as List);
    String? error;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            index == null ? 'Add booking window' : 'Edit booking window',
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'On Saturdays and Sundays, members must use the listed start times within this window. The end boundary belongs to the next window.',
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.wb_sunny_outlined),
                        label: Text('From ${bookingClock(from)}'),
                        onPressed: () async {
                          final v = await _time(from);
                          if (v != null) update(() => from = v);
                        },
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.nights_stay_outlined),
                        label: Text('Until ${bookingClock(until)}'),
                        onPressed: () async {
                          final v = await _time(until);
                          if (v != null) update(() => until = v);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Allowed start times',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final s in starts..sort())
                        InputChip(
                          label: Text(bookingClock(s)),
                          avatar: const Icon(Icons.schedule, size: 18),
                          onDeleted: () => update(() => starts.remove(s)),
                        ),
                    ],
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.add_alarm),
                    label: const Text('Add start time'),
                    onPressed: () async {
                      final v = await _time(from);
                      if (v != null && !starts.contains(v))
                        update(() => starts.add(v));
                    },
                  ),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (from >= until ||
                    starts.isEmpty ||
                    starts.any((s) => s < from || s >= until)) {
                  update(
                    () => error =
                        'Choose an end after the start and at least one start time inside this window.',
                  );
                  return;
                }
                for (var i = 0; i < _windows.length; i++) {
                  if (i != index &&
                      from < (_windows[i]['until'] as int) &&
                      until > (_windows[i]['from'] as int)) {
                    update(
                      () => error = 'This overlaps another booking window.',
                    );
                    return;
                  }
                }
                Navigator.pop(dialogContext, {
                  'from': from,
                  'until': until,
                  'starts': starts..sort(),
                });
              },
              child: const Text('Use window'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        _windows.add(result);
      } else {
        _windows[index] = result;
      }
      _windows.sort((a, b) => (a['from'] as int).compareTo(b['from'] as int));
      _dirty = true;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_revision == null) {
        await _client.from('fixture_booking_start_rules').insert({
          'club_id': widget.clubId,
          'windows': _windows,
        });
      } else {
        final rows = await _client
            .from('fixture_booking_start_rules')
            .update({'windows': _windows})
            .eq('club_id', widget.clubId)
            .eq('updated_at', _revision!)
            .select('club_id');
        if (rows.isEmpty)
          throw Exception(
            'The timetable changed while you were editing. Reopen it before saving.',
          );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        setState(() {
          _error = bookingErrorMessage(e);
          _saving = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(title: const Text('Fixture Booking Start Times')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xff1746c9), Color(0xff6b40ae)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.access_time_filled,
                        color: Colors.white,
                        size: 36,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Weekend booking timetable',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Saturday and Sunday only. On weekdays, and outside these windows, members can choose any start within Club opening hours. Admins and superusers may override this timetable.',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                for (var i = 0; i < _windows.length; i++) _card(i),
                if (_windows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No restricted windows. Add a window to choose fixed start times.',
                    ),
                  ),
                if (!widget.readOnly) ...[
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => _edit(),
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Add booking window'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _saving || !_dirty ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save timetable'),
                  ),
                ],
              ],
            ),
    ),
  );
  Widget _card(int i) {
    final w = _windows[i],
        color = [
          Colors.teal,
          Colors.deepPurple,
          Colors.orange,
          Colors.blue,
        ][i % 4];
    return Card(
      color: color.shade50,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timeline, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${bookingClock(w['from'] as int)} – ${bookingClock(w['until'] as int)}',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: color.shade900,
                    ),
                  ),
                ),
                if (!widget.readOnly) ...[
                  IconButton(
                    tooltip: 'Edit window',
                    onPressed: _saving ? null : () => _edit(i),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Remove window',
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _windows.removeAt(i);
                            _dirty = true;
                          }),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ],
            ),
            const Divider(),
            const Text('Members may start at'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in w['starts'] as List)
                  Chip(
                    avatar: Icon(Icons.play_circle_fill, color: color),
                    label: Text(
                      bookingClock(s as int),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
