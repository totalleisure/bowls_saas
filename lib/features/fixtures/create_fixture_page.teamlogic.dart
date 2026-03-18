import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/date_format.dart';
import 'fixture_details_page.dart';

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
  final _teamNameCtrl = TextEditingController();

  bool _loading = false;
  String? _error;

  bool _isHome = true;
  bool _isTeamFixture = false;

  DateTime? _startAtLocal;

  // Venues
  List<Map<String, dynamic>> _homeVenues = [];
  List<Map<String, dynamic>> _opponentVenues = [];
  String? _homeVenueId;
  String? _opponentVenueId;

    // Teams (for team fixtures)
  List<Map<String, dynamic>> _teams = [];
  String? _teamId;

// Greens (green_areas) - belong to a venue
  List<Map<String, dynamic>> _greenAreas = [];
  String? _greenAreaId;

  // Orientation (stored lowercase, e.g. north_south / east_west)
  String? _orientation;

  // Fixture meta
  String _section = 'mixed';

  // Defaults requested
  int _rinksRequired = 6;
  int _playersPerRink = 4; // 4 = rinks, 3 = triples, 2 = pairs

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _teamNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _loadVenues();
      await _loadTeams();
      // Only load greens once we have a home venue selected
      await _loadGreenAreas();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadVenues() async {
    final homeVenues = await _client
        .from('venues')
        .select('id, name')
        .eq('club_id', widget.clubId)
        .eq('is_home_venue', true)
        .order('name');

    final opponentVenues = await _client
        .from('venues')
        .select('id, name')
        .eq('club_id', widget.clubId)
        .eq('is_home_venue', false)
        .order('name');

    _homeVenues = List<Map<String, dynamic>>.from(homeVenues);
    _opponentVenues = List<Map<String, dynamic>>.from(opponentVenues);

    // Defaults (first item), if not already selected
    _homeVenueId ??= _homeVenues.isNotEmpty ? _homeVenues.first['id'].toString() : null;
    _opponentVenueId ??=
        _opponentVenues.isNotEmpty ? _opponentVenues.first['id'].toString() : null;
  }


  Future<void> _loadTeams() async {
    final rows = await _client
        .from('teams')
        .select('id, name, is_active')
        .eq('club_id', widget.clubId)
        .eq('is_active', true)
        .order('name');

    _teams = List<Map<String, dynamic>>.from(rows);
    _teamId ??= _teams.isNotEmpty ? _teams.first['id'].toString() : null;
  }

  Future<void> _loadGreenAreas() async {
    // Green areas are only relevant for HOME fixtures (you pick an actual green)
    if (!_isHome) {
      _greenAreas = [];
      _greenAreaId = null;
      _orientation = null;
      return;
    }

    if (_homeVenueId == null) {
      _greenAreas = [];
      _greenAreaId = null;
      _orientation = null;
      return;
    }

    final greens = await _client
        .from('green_areas')
        .select('id, name, venue_id, discipline, orientation_mode, allowed_orientations')
        .eq('venue_id', _homeVenueId!)
        .order('name');

    _greenAreas = List<Map<String, dynamic>>.from(greens);

    // Default green
    _greenAreaId ??= _greenAreas.isNotEmpty ? _greenAreas.first['id'].toString() : null;

    // Ensure orientation is valid for the selected green
    _syncOrientationToSelectedGreen();
  }

  void _syncOrientationToSelectedGreen() {
    final g = _selectedGreenArea;
    if (g == null) {
      _orientation = null;
      return;
    }

    final allowed = _allowedOrientationsFor(g);
    if (allowed.isEmpty) {
      _orientation = null;
      return;
    }

    if (_orientation == null || !allowed.contains(_orientation)) {
      _orientation = allowed.first;
    }
  }

  Map<String, dynamic>? get _selectedGreenArea {
    if (_greenAreaId == null) return null;
    for (final g in _greenAreas) {
      if (g['id'].toString() == _greenAreaId) return g;
    }
    return null;
  }

  List<String> _allowedOrientationsFor(Map<String, dynamic> greenAreaRow) {
    final raw = greenAreaRow['allowed_orientations'];
    if (raw is! List) return [];

    // Stored as lowercase: ["north_south","east_west"]
    final vals = raw
        .map((e) => e.toString().trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    // Stable ordering preference
    vals.sort((a, b) {
      const pref = {'north_south': 0, 'east_west': 1};
      return (pref[a] ?? 99).compareTo(pref[b] ?? 99);
    });

    return vals;
  }

  bool get _isOutdoorSelectedGreen {
    final g = _selectedGreenArea;
    if (g == null) return false;
    final discipline = (g['discipline'] ?? '').toString().toLowerCase();
    return discipline.contains('outdoor');
  }

  bool get _orientationEnabledForSelectedGreen {
    final g = _selectedGreenArea;
    if (g == null) return false;
    final mode = (g['orientation_mode'] ?? '').toString().toLowerCase();
    return mode != 'off';
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final initialDate = _startAtLocal ?? now;

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );
    if (time == null) return;

    setState(() {
      _startAtLocal = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

/*   Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete fixture?'),
        content: const Text(
          'This will permanently delete the fixture and all related data '
          '(RSVPs, team selections, rinks, assignments).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _deleteFixture();
    }
  }
 */

/*   Future<void> _deleteFixture() async {
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client.rpc(
        'delete_fixture',
        params: {'p_fixture_id': widget.fixtureId},
      );

      if (res == true && mounted) {
        Navigator.pop(context, true); // tell previous screen to refresh
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
 */
  String _formatForDisplay(int ppr) {
    switch (ppr) {
      case 2:
        return 'Pairs (2)';
      case 3:
        return 'Triples (3)';
      case 4:
      default:
        return 'Rinks (4)';
    }
  }

  String _formatCodeForRinks(int ppr) {
    switch (ppr) {
      case 2:
        return 'pairs';
      case 3:
        return 'triples';
      case 4:
      default:
        return 'rinks';
    }
  }

  String _prettyOrientation(String v) {
    // north_south -> north_South
    final t = v.replaceAll('_', ' ');
    return t[0].toUpperCase() + t.substring(1);
  }

  Future<void> _save() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_startAtLocal == null) {
        throw Exception('Please select a start date/time.');
      }
      if (_homeVenueId == null) {
        throw Exception('Please select a home venue.');
      }
      if (_opponentVenueId == null) {
        throw Exception('Please select an opponent venue.');
      }

      // For HOME fixtures, you must choose a green area (because DB enforces green belongs to venue)
      if (_isHome && _greenAreaId == null) {
        throw Exception('Please select a green area.');
      }

      // Decide what goes into fixtures.venue_id and fixtures.opponent_venue_id.
      //
      // IMPORTANT (to satisfy your DB check "Green area does not belong to venue"):
      // - For HOME fixtures, venue_id must be the HOME venue (so green_area.venue_id matches fixtures.venue_id).
      // - For AWAY fixtures, venue_id should be the OPPONENT venue (the venue you travel to).
      //
      final String venueId = _isHome ? _homeVenueId! : _opponentVenueId!;
      final String opponentVenueId = _isHome ? _opponentVenueId! : _homeVenueId!;

      final fixtureLabel = _teamNameCtrl.text.trim();

      if (_isTeamFixture && _teamId == null) {
        throw Exception('Please select a team.');
      }

      final insertedRows = await _client.from('fixtures').insert({
        'club_id': widget.clubId,
        'start_at': _startAtLocal!.toUtc().toIso8601String(),
        'is_home': _isHome,
        'section': _section,
        'rinks_required': _rinksRequired,
        'players_per_rink': _playersPerRink,
        'team_id': _isTeamFixture ? _teamId : null,
        'team_name': _isTeamFixture ? null : (fixtureLabel.isEmpty ? null : fixtureLabel),
        'venue_id': venueId,
        'opponent_venue_id': opponentVenueId,

        // Greens/orientation only relevant for HOME fixtures
        'green_area_id': _isHome ? _greenAreaId : null,
        'orientation': (_isHome && _isOutdoorSelectedGreen && _orientationEnabledForSelectedGreen)
            ? _orientation
            : null,
      }).select('id');

      debugPrint('SAVE: read fixture id');
      final fixtureId = (insertedRows as List).first['id'].toString();
      debugPrint('SAVE: insert rinks');
      // Create default rink placeholders (can be edited/deleted later)
      final rinkRows = <Map<String, dynamic>>[];
      final formatCode = _formatCodeForRinks(_playersPerRink);
      for (var i = 1; i <= _rinksRequired; i++) {
        rinkRows.add({
          'fixture_id': fixtureId,
          'fixture_rink_no': i, // you renamed rink_order -> fixture_rink_no
          'format': formatCode,
          'players_per_rink': _playersPerRink,
        });
      }
      if (rinkRows.isNotEmpty) {
        await _client.from('fixture_rinks').insert(rinkRows);
      }
      debugPrint('SAVE: pop');
//      if (mounted) Navigator.pop(context, fixtureId);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => FixtureDetailsPage(fixtureId: fixtureId),
        ),
      );    
    } catch (e) {
      debugPrint('SAVE ERROR: $e');
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final startLabel = _startAtLocal == null
        ? 'Select date & time'
        : formatWhenLocal(_startAtLocal!.toUtc().toIso8601String());

    final selectedGreen = _selectedGreenArea;
    final allowedOrients =
        (selectedGreen == null) ? <String>[] : _allowedOrientationsFor(selectedGreen);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Fixture'),
//        actions: [
//          IconButton(
//            icon: const Icon(Icons.delete),
//            onPressed: _loading ? null : _confirmDelete,
//          ),
//        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 12),
                  ],

                  SwitchListTile(
                    title: const Text('Home fixture'),
                    value: _isHome,
                    onChanged: (v) async {
                      setState(() {
                        _isHome = v;
                        // reset green selection when toggling
                        _greenAreas = [];
                        _greenAreaId = null;
                        _orientation = null;
                      });
                      await _loadGreenAreas();
                      setState(() {});
                    },
                  ),

                  const SizedBox(height: 8),

                  OutlinedButton(
                    onPressed: _pickDateTime,
                    child: Text(startLabel),
                  ),

                  const SizedBox(height: 12),

                  

if (!_isTeamFixture) ...[
                    TextField(
                      controller: _teamNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Fixture label (optional)',
                        hintText: 'e.g. Mid-week National Team Selection',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (_isTeamFixture) ...[
                    DropdownButtonFormField<String>(
                      value: _teamId,
                      decoration: const InputDecoration(
                        labelText: 'Team',
                        border: OutlineInputBorder(),
                      ),
                      items: _teams.map((t) {
                        return DropdownMenuItem(
                          value: t['id'].toString(),
                          child: Text(t['name'].toString()),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _teamId = v),
                    ),
                    const SizedBox(height: 12),
                  ],

                  SwitchListTile(
                    title: const Text('Team fixture'),
                    subtitle: const Text('If on, this fixture uses team workflows (selection, pools, etc.)'),
                    value: _isTeamFixture,
                    onChanged: (v) {
                      setState(() {
                        _isTeamFixture = v;
                        if (_isTeamFixture) {
                          _teamId ??= _teams.isNotEmpty ? _teams.first['id'].toString() : null;
                        } else {
                          _teamId = null;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 8),

                  const SizedBox(height: 12),

                  DropdownButtonFormField<String>(
                    value: _homeVenueId,
                    decoration: const InputDecoration(labelText: 'Home venue'),
                    items: _homeVenues.map((v) {
                      return DropdownMenuItem(
                        value: v['id'].toString(),
                        child: Text(v['name'].toString()),
                      );
                    }).toList(),
                    onChanged: (v) async {
                      setState(() {
                        _homeVenueId = v;
                        _greenAreas = [];
                        _greenAreaId = null;
                        _orientation = null;
                      });
                      await _loadGreenAreas();
                      setState(() {});
                    },
                  ),

                  const SizedBox(height: 12),

                  DropdownButtonFormField<String>(
                    value: _opponentVenueId,
                    decoration: const InputDecoration(labelText: 'Opponent venue'),
                    items: _opponentVenues.map((v) {
                      return DropdownMenuItem(
                        value: v['id'].toString(),
                        child: Text(v['name'].toString()),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _opponentVenueId = v),
                  ),

                  const SizedBox(height: 12),

                  if (_isHome) ...[
                    DropdownButtonFormField<String>(
                      value: _greenAreaId,
                      decoration: const InputDecoration(labelText: 'Green area'),
                      items: _greenAreas.map((g) {
                        return DropdownMenuItem(
                          value: g['id'].toString(),
                          child: Text(g['name'].toString()),
                        );
                      }).toList(),
                      onChanged: (v) {
                        setState(() {
                          _greenAreaId = v;
                        });
                        setState(() => _syncOrientationToSelectedGreen());
                      },
                    ),
                    const SizedBox(height: 12),

                    if (_isOutdoorSelectedGreen &&
                        _orientationEnabledForSelectedGreen &&
                        allowedOrients.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        value: _orientation,
                        decoration: const InputDecoration(labelText: 'Orientation'),
                        items: allowedOrients.map((o) {
                          return DropdownMenuItem(
                            value: o,
                            child: Text(_prettyOrientation(o)),
                          );
                        }).toList(),
                        onChanged: (v) => setState(() => _orientation = v),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],

                  DropdownButtonFormField<String>(
                    value: _section,
                    decoration: const InputDecoration(labelText: 'Section'),
                    items: const [
                      DropdownMenuItem(value: 'mixed', child: Text('Mixed')),
                      DropdownMenuItem(value: 'mens', child: Text('Mens')),
                      DropdownMenuItem(value: 'ladies', child: Text('Ladies')),
                    ],
                    onChanged: (v) => setState(() => _section = v ?? 'mixed'),
                  ),

                  const SizedBox(height: 12),

                  DropdownButtonFormField<int>(
                    value: _playersPerRink,
                    decoration: const InputDecoration(labelText: 'Format'),
                    items: const [4, 3, 2].map((ppr) {
                      return DropdownMenuItem(
                        value: ppr,
                        child: Text(ppr == 4 ? 'Rinks (4)' : ppr == 3 ? 'Triples (3)' : 'Pairs (2)'),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _playersPerRink = v ?? 4),
                  ),

                  const SizedBox(height: 12),

                  DropdownButtonFormField<int>(
                    value: _rinksRequired,
                    decoration: const InputDecoration(labelText: 'Rinks required'),
                    items: List.generate(12, (i) => i + 1).map((n) {
                      return DropdownMenuItem(value: n, child: Text(n.toString()));
                    }).toList(),
                    onChanged: (v) => setState(() => _rinksRequired = v ?? 6),
                  ),

                  const SizedBox(height: 20),

                  ElevatedButton(
                    onPressed: _loading ? null : _save,
                    child: const Text('Create fixture'),
                  ),
                ],
              ),
            ),
    );
  }
}
