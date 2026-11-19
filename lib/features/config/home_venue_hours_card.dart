import '../fixtures/fixture_type_booking_policy.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomeVenueHoursCard extends StatefulWidget {
  const HomeVenueHoursCard({
    super.key,
    required this.venueId,
    required this.editable,
  });
  final String venueId;
  final bool editable;
  @override
  State<HomeVenueHoursCard> createState() => _HomeVenueHoursCardState();
}

class _HomeVenueHoursCardState extends State<HomeVenueHoursCard> {
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0),
      _end = const TimeOfDay(hour: 22, minute: 0);
  bool _loading = true, _saving = false, _dirty = false;
  String? _error;
  String _clock(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final row = await Supabase.instance.client
          .from('venues')
          .select('club_start_time,club_end_time')
          .eq('id', widget.venueId)
          .single();
      TimeOfDay parse(dynamic value, TimeOfDay fallback) {
        final p = '$value'.split(':');
        return p.length < 2
            ? fallback
            : TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
      }

      if (mounted)
        setState(() {
          _start = parse(row['club_start_time'], _start);
          _end = parse(row['club_end_time'], _end);
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

  Future<void> _pick(bool start) async {
    final value = await showTimePicker(
      context: context,
      initialTime: start ? _start : _end,
    );
    if (value != null && mounted)
      setState(() {
        if (start) {
          _start = value;
        } else {
          _end = value;
        }
        _dirty = true;
      });
  }

  Future<void> _save() async {
    if (_start.hour * 60 + _start.minute >= _end.hour * 60 + _end.minute) {
      setState(() => _error = 'Club End Time must be after Club Start Time.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc(
        'set_home_venue_club_hours',
        params: {
          'p_venue_id': widget.venueId,
          'p_start': _clock(_start),
          'p_end': _clock(_end),
        },
      );
      if (mounted) {
        setState(() => _dirty = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Club opening hours saved.')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = bookingErrorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.amber.shade50,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: _loading
          ? const LinearProgressIndicator()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.storefront, color: Colors.deepOrange),
                    SizedBox(width: 10),
                    Text(
                      'Club opening hours',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Home rink bookings must fit inside these hours, on the same day (UK time). This applies to all app versions, including Admin bookings.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: widget.editable && !_saving
                          ? () => _pick(true)
                          : null,
                      icon: const Icon(Icons.wb_sunny_outlined),
                      label: Text('Club Start Time: ${_clock(_start)}'),
                    ),
                    OutlinedButton.icon(
                      onPressed: widget.editable && !_saving
                          ? () => _pick(false)
                          : null,
                      icon: const Icon(Icons.nights_stay_outlined),
                      label: Text('Club End Time: ${_clock(_end)}'),
                    ),
                  ],
                ),
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                if (widget.editable)
                  FilledButton.icon(
                    onPressed: _dirty && !_saving ? _save : null,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save Club hours'),
                  ),
              ],
            ),
    ),
  );
}
