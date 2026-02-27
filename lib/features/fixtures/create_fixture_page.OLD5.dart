import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/date_format.dart';

class CreateFixturePage extends StatefulWidget {
  final String clubId;
  final String clubName;

  const CreateFixturePage({
    super.key,
    required this.clubId,
    required this.clubName,
  });

  @override
  State<CreateFixturePage> createState() => _CreateFixturePageState();
}


class _CreateFixturePageState extends State<CreateFixturePage> {
  bool _saving = false;
  String? _error;

  DateTime _startAt = DateTime.now().add(const Duration(days: 1));
  bool _isHome = true;

  String _section = 'mixed';
  int _playersPerRink = 4;
  int _rinksRequired = 6;

  String? _venueId;
  String? _greenAreaId;
  String? _orientation;

  List<Map<String, dynamic>> _venues = [];
  List<Map<String, dynamic>> _greens = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = Supabase.instance.client;

    final venues = await client
        .from('venues')
        .select('id, name, is_home_venue')
        .eq('club_id', widget.clubId)
        .eq('is_home_venue', _isHome) // <-- key line
        .order('name');

    setState(() {
      _venues = List<Map<String, dynamic>>.from(venues);
      if (_venues.isNotEmpty) {
        _venueId = _venues.first['id'];
      }
    });

    await _loadGreens();
  }

  Future<void> _loadGreens() async {
    if (_venueId == null) return;
    if (!_isHome) {
      setState(() {
        _greens = [];
        _greenAreaId = null;
        _orientation = null;
      });
      return;
    }

    final rows = await Supabase.instance.client
        .from('green_areas')
        .select('id, name, discipline, orientation_mode, allowed_orientations')
        .eq('club_id', widget.clubId)   // <-- key line
        .eq('venue_id', _venueId!);     // <-- key line

    setState(() {
      _greens = List<Map<String, dynamic>>.from(rows);
      _greenAreaId = _greens.isNotEmpty ? _greens.first['id'] : null;
      _orientation = null;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await Supabase.instance.client.from('fixtures').insert({
        'club_id': widget.clubId,
        'start_at': _startAt.toUtc().toIso8601String(),
        'is_home': _isHome,
        'venue_id': _venueId,
        'green_area_id': _isHome ? _greenAreaId : null,
        'section': _section,
        'players_per_rink': _playersPerRink,
        'rinks_required': _rinksRequired,
        'orientation': _isHome ? _orientation : null,
      });

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine orientation options for the selected green area (home fixtures only)
    Map<String, dynamic>? selectedGreen;
    if (_isHome && _greenAreaId != null) {
      for (final g in _greens) {
        if (g['id'].toString() == _greenAreaId.toString()) {
          selectedGreen = g;
          break;
        }
      }
    }

    final discipline = (selectedGreen?['discipline'] ?? '').toString().toLowerCase();
    final isOutdoor = discipline.contains('outdoor');
    final orientationMode = (selectedGreen?['orientation_mode'] ?? '').toString().toLowerCase();

    final rawAllowed = selectedGreen?['allowed_orientations'];
    final allowedOrients = <String>[];
    if (rawAllowed is List) {
      for (final v in rawAllowed) {
        final s = v.toString().trim();
        if (s.isNotEmpty) allowedOrients.add(s.toLowerCase());
      }
    }

    // Ensure current _orientation is valid, otherwise pick the first allowed value.
    if (_isHome && isOutdoor && allowedOrients.isNotEmpty) {
      if (_orientation == null || !allowedOrients.contains(_orientation!.toLowerCase())) {
        _orientation = allowedOrients.first;
      } else {
        _orientation = _orientation!.toLowerCase();
      }
    } else {
      // Indoor greens or no allowed orientations -> clear selection
      _orientation = null;
    }

    final showOrientation = _isHome && isOutdoor && allowedOrients.isNotEmpty && orientationMode != 'off';

    return Scaffold(
      appBar: AppBar(title: const Text('Create fixture')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ListTile(
              title: const Text('Start time'),
              subtitle: Text(formatWhenLocal(_startAt.toUtc().toIso8601String())),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _startAt,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (date == null) return;

                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(_startAt),
                );
                if (time == null) return;

                setState(() {
                  _startAt = DateTime(
                    date.year,
                    date.month,
                    date.day,
                    time.hour,
                    time.minute,
                  );
                });
              },
            ),

            SwitchListTile(
              title: const Text('Home fixture'),
              value: _isHome,
              onChanged: (v) async {
                setState(() {
                  _isHome = v;
                  // Clear stale selections when switching mode
                  _venueId = null;
                  _greens = [];
                  _greenAreaId = null;
                  _orientation = null;
                });
                await _load();
              },
            ),

            DropdownButtonFormField<String>(
              value: _venueId,
              decoration: const InputDecoration(labelText: 'Venue'),
              items: _venues
                  .map<DropdownMenuItem<String>>(
                    (v) => DropdownMenuItem<String>(
                      value: v['id'] as String,
                      child: Text(v['name'] as String),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                setState(() => _venueId = v);
                _loadGreens();
              },
            ),

            if (_isHome)
              DropdownButtonFormField<String>(
                value: _greenAreaId,
                decoration: const InputDecoration(labelText: 'Green area'),
                items: _greens
                    .map<DropdownMenuItem<String>>(
                      (g) => DropdownMenuItem<String>(
                        value: g['id'] as String,
                        child: Text(g['name'] as String),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _greenAreaId = v;
                    _orientation = null; // force re-pick based on new green
                  });
                },
              ),

            if (showOrientation)
              DropdownButtonFormField<String>(
                value: _orientation,
                decoration: const InputDecoration(labelText: 'Orientation'),
                items: allowedOrients
                    .map((o) => DropdownMenuItem<String>(
                          value: o,
                          child: Text(o.replaceAll('_', ' ').toUpperCase()),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _orientation = v),
              ),

            DropdownButtonFormField<String>(
              value: _section,
              decoration: const InputDecoration(labelText: 'Section'),
              items: const [
                DropdownMenuItem(value: 'mixed', child: Text('Mixed')),
                DropdownMenuItem(value: 'mens', child: Text('Men')),
                DropdownMenuItem(value: 'ladies', child: Text('Ladies')),
              ],
              onChanged: (v) => setState(() => _section = v!),
            ),

            DropdownButtonFormField<int>(
              value: _playersPerRink,
              decoration: const InputDecoration(labelText: 'Players per rink'),
              items: const [
                DropdownMenuItem(value: 2, child: Text('Pairs')),
                DropdownMenuItem(value: 3, child: Text('Triples')),
                DropdownMenuItem(value: 4, child: Text('Rinks')),
              ],
              onChanged: (v) => setState(() => _playersPerRink = v!),
            ),

            TextFormField(
              initialValue: _rinksRequired.toString(),
              decoration: const InputDecoration(labelText: 'Rinks required'),
              keyboardType: TextInputType.number,
              onChanged: (v) => _rinksRequired = int.tryParse(v) ?? _rinksRequired,
            ),

            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving ? const CircularProgressIndicator() : const Text('Create fixture'),
            ),
          ],
        ),
      ),
    );
  }
}
