import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/hex_color.dart';
import '../../core/utils/date_format.dart';
import 'fixture_details_page.dart';

class MemberFixtureCreationPage extends StatefulWidget {
  final String clubId;
  final String clubName;

  const MemberFixtureCreationPage({
    super.key,
    required this.clubId,
    required this.clubName,
  });

  @override
  State<MemberFixtureCreationPage> createState() =>
      _MemberFixtureCreationPageState();
}

class _MemberFixtureCreationPageState
    extends State<MemberFixtureCreationPage> {
  final _teamNameCtrl = TextEditingController();

  bool _loading = false;
  String? _error;

  DateTime? _startAtLocal;
  DateTime? _endAtLocal;

  // Venues
  List<Map<String, dynamic>> _homeVenues = [];

  String? _homeVenueId;

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

    // Fixture types
  List<Map<String, dynamic>> _fixtureTypes = [];
  String? _fixtureTypeId;

  SupabaseClient get _client => Supabase.instance.client;

  String? _currentMemberProfileId;
  
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

  Future<void> _loadCurrentMemberProfileId() async {
    final userId = _client.auth.currentUser?.id;

    if (userId == null) {
      throw Exception('You must be signed in to book a fixture.');
    }

    final row = await _client
        .from('member_profiles')
        .select('id, club_memberships!inner(id)')
        .eq('user_id', userId)
        .eq('club_memberships.club_id', widget.clubId)
        .eq('club_memberships.is_active', true)
        .maybeSingle();

    if (row == null || row['id'] == null) {
      throw Exception('Your member profile could not be found for this club.');
    }

    _currentMemberProfileId = row['id'].toString();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _loadCurrentMemberProfileId();
      await _loadVenues();
      await _loadFixtureTypes();
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

  Future<void> _loadFixtureTypes() async {
    final rows = await _client
        .from('competition_types')
        .select('''
          id,
          name,
          is_internal,
          section,
          default_rinks_required,
          default_players_per_rink,
          team_selection_enabled,
          selection_mode,
          team_id,
          is_active,
          colour_scheme:fixture_colour_schemes(
            id,
            name,
            background_hex,
            foreground_hex
          )
        ''')
        .eq('club_id', widget.clubId)
        .eq('is_active', true)
        .order('name');

    _fixtureTypes = List<Map<String, dynamic>>.from(rows);
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

    // Defaults (first item), if not already selected
    _homeVenueId ??= _homeVenues.isNotEmpty ? _homeVenues.first['id'].toString() : null;

  }

  Future<String?> _pickVenue({
    required List<Map<String, dynamic>> Function() getVenues,
    required String title,
    required bool isHomeVenue,
  }) async {
    String search = '';
    List<Map<String, dynamic>> filtered = List.from(getVenues());

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setStateSheet) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  top: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.75,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              final newId = await _createVenueFromFixture(
                                isHomeVenue: isHomeVenue,
                              );
                              if (newId == null) return;

                              Navigator.pop(sheetContext, newId);
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('Add'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: const InputDecoration(
                          hintText: 'Search venues...',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          search = value.toLowerCase();
                          setStateSheet(() {
                            filtered = getVenues().where((v) {
                              final name = (v['name'] ?? '').toString().toLowerCase();
                              final town = (v['town_city'] ?? '').toString().toLowerCase();
                              final postcode = (v['postcode'] ?? '').toString().toLowerCase();
                              return name.contains(search) ||
                                  town.contains(search) ||
                                  postcode.contains(search);
                            }).toList();
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: filtered.isEmpty
                            ? const Center(child: Text('No venues match your search.'))
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (_, i) {
                                  final v = filtered[i];
                                  final name = (v['name'] ?? '').toString();
                                  final town = (v['town_city'] ?? '').toString().trim();
                                  final postcode = (v['postcode'] ?? '').toString().trim();

                                  return ListTile(
                                    title: Text(name),
                                    subtitle: Text([
                                      if (town.isNotEmpty) town,
                                      if (postcode.isNotEmpty) postcode,
                                    ].join(' • ')),
                                    onTap: () => Navigator.pop(
                                      sheetContext,
                                      v['id'].toString(),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _loadGreenAreas() async {
    debugPrint('GREEN LOAD: _homeVenueId=$_homeVenueId');
    if (_homeVenueId == null) {
      if (mounted) {
        setState(() {
          _greenAreas = [];
          _greenAreaId = null;
          _orientation = null;
        });
      }
      return;
    }

    final greens = await _client
        .from('green_areas')
        .select('id, name, venue_id, discipline, orientation_mode, allowed_orientations')
        .eq('venue_id', _homeVenueId!)
        .order('name');

    debugPrint('GREEN LOAD: found ${greens.length} greens for venue $_homeVenueId');
    debugPrint('GREEN LOAD: greens=$greens');

    final loadedGreens = List<Map<String, dynamic>>.from(greens);

    if (!mounted) return;

    setState(() {
      _greenAreas = loadedGreens;
      _greenAreaId = _greenAreas.isNotEmpty ? _greenAreas.first['id'].toString() : null;
      _syncOrientationToSelectedGreen();
    });
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

  void _applyFixtureType(String? fixtureTypeId) {
    if (fixtureTypeId == null) return;

    final row = _fixtureTypeById(fixtureTypeId);
    if (row == null) return;

    final name = (row['name'] ?? '').toString().trim();
    final section = (row['section'] ?? '').toString().trim();
    final defaultRinksRequired = row['default_rinks_required'] as int?;
    final defaultPlayersPerRink = row['default_players_per_rink'] as int?;

    setState(() {
      _fixtureTypeId = fixtureTypeId;
      _teamNameCtrl.text = name;

      if (section.isNotEmpty) {
        _section = section;
      }
      if (defaultPlayersPerRink != null) {
        _playersPerRink = defaultPlayersPerRink;
      }
      if (defaultRinksRequired != null) {
        _rinksRequired = defaultRinksRequired;
      }
    });
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

  Future<String?> _createVenueFromFixture({required bool isHomeVenue}) async {
    final nameCtrl = TextEditingController();
    final townCtrl = TextEditingController();
    final postcodeCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Add home venue'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Venue name'),
              ),
              TextField(
                controller: townCtrl,
                decoration: const InputDecoration(labelText: 'Town/City (optional)'),
              ),
              TextField(
                controller: postcodeCtrl,
                decoration: const InputDecoration(labelText: 'Postcode (optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (ok != true) return null;

    final venueName = nameCtrl.text.trim();
    if (venueName.isEmpty) return null;

    try {
      final inserted = await _client
          .from('venues')
          .insert({
            'club_id': widget.clubId,
            'name': venueName,
            'is_home_venue': isHomeVenue,
            'town_city': townCtrl.text.trim().isEmpty ? null : townCtrl.text.trim(),
            'postcode': postcodeCtrl.text.trim().isEmpty ? null : postcodeCtrl.text.trim(),
          })
          .select('id')
          .single();

      final newId = inserted['id']?.toString();

      await _loadVenues();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Venue created ✅')),
        );
      }

      return newId;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Create venue error: $e')),
        );
      }
      return null;
    }
  }

  Future<void> _pickEndDateTime() async {
    final now = DateTime.now();
    final initialDate =
        _endAtLocal ??
        _startAtLocal?.add(const Duration(hours: 2)) ??
        now.add(const Duration(hours: 2));

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
      _endAtLocal = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
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

      // Default end time to start + 2 hours if not set yet,
      // or if end is not after the new start.
      if (_endAtLocal == null || !_endAtLocal!.isAfter(_startAtLocal!)) {
        _endAtLocal = _startAtLocal!.add(const Duration(hours: 2));
      }
    });
  }

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

  String _friendlySaveError(PostgrestException e) {
    if (e.message.contains('Not enough rinks available')) {
      return 'Not enough rinks are available at that time. Please choose another time, date, or green.';
    }

    return e.message;
  }

  Future<void> _showSaveErrorDialog(String message) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Booking could not be saved'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_fixtureTypeId == null || _fixtureTypeId!.trim().isEmpty) {
        throw Exception('Please choose a Fixture Type.');
      }
      if (_startAtLocal == null || _endAtLocal == null) {
        throw Exception('Please select a start and end time.');
      }
      if (_homeVenueId == null) {
        throw Exception('Please select a home venue.');
      }
      if (_greenAreaId == null) {
        throw Exception('Please select a green.');
      }
      if (_currentMemberProfileId == null) {
        throw Exception('Your member profile could not be found.');
      }

      final fixtureLabel = _teamNameCtrl.text.trim();

      final insertedRows = await _client.from('fixtures').insert({
        'club_id': widget.clubId,
        'start_at': _startAtLocal!.toUtc().toIso8601String(),
        'end_at': _endAtLocal!.toUtc().toIso8601String(),
        'is_home': true,
        'section': _section,
        'rinks_required': _rinksRequired,
        'players_per_rink': _playersPerRink,
        'competition_type_id': _fixtureTypeId,
        'team_id': null,
        'team_name': fixtureLabel.isEmpty ? null : fixtureLabel,
        'requires_rsvp': false,
        'venue_id': _homeVenueId,
        'opponent_venue_id': null,
        'green_area_id': _greenAreaId,
        'orientation': (_isOutdoorSelectedGreen && _orientationEnabledForSelectedGreen)
            ? _orientation
            : null,
        'captain_member_profile_id': _currentMemberProfileId,
      }).select('id');

      final fixtureId = (insertedRows as List).first['id'].toString();

      final rinkRows = <Map<String, dynamic>>[];
      final formatCode = _formatCodeForRinks(_playersPerRink);

      for (var i = 1; i <= _rinksRequired; i++) {
        rinkRows.add({
          'fixture_id': fixtureId,
          'fixture_rink_no': i,
          'format': formatCode,
          'players_per_rink': _playersPerRink,
        });
      }

      if (rinkRows.isNotEmpty) {
        await _client.from('fixture_rinks').insert(rinkRows);
      }

      if (!mounted) return;

      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => FixtureDetailsPage(fixtureId: fixtureId),
        ),
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      final message = _friendlySaveError(e);

      if (mounted) {
        setState(() {
          _loading = false;
          _error = null;
        });
      }

      await _showSaveErrorDialog(message);
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');

      if (mounted) {
        setState(() {
          _loading = false;
          _error = null;
        });
      }

      await _showSaveErrorDialog(message);
    } finally {
      if (mounted && _loading) {
        setState(() => _loading = false);
      }
    }
  }

  Map<String, dynamic>? _fixtureTypeById(String? id) {
    if (id == null) return null;

    for (final ft in _fixtureTypes) {
      if (ft['id'].toString() == id) return ft;
    }
    return null;
  }

  Widget _fixtureTypeSwatch(Map<String, dynamic> ft) {
    final colourScheme = ft['colour_scheme'] as Map<String, dynamic>?;
    final hasColours = colourScheme != null;

    final bg = hasColours
        ? colorFromHex(
            colourScheme['background_hex']?.toString(),
            fallback: Colors.grey.shade200,
          )
        : Colors.grey.shade100;

    final fg = hasColours
        ? colorFromHex(
            colourScheme['foreground_hex']?.toString(),
            fallback: Colors.black87,
          )
        : Colors.black87;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: fg.withOpacity(0.20),
        ),
      ),
      child: Text(
        ft['name']?.toString() ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _selectedFixtureTypeField() {
    final selected = _fixtureTypeById(_fixtureTypeId);

    if (selected == null) {
      return InkWell(
        onTap: _pickFixtureType,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Fixture Type',
            border: OutlineInputBorder(),
          ),
          child: const Text('Select Fixture Type'),
        ),
      );
    }

    final colourScheme = selected['colour_scheme'] as Map<String, dynamic>?;
    final hasColours = colourScheme != null;

    final bg = hasColours
        ? colorFromHex(
            colourScheme['background_hex']?.toString(),
            fallback: Colors.grey.shade200,
          )
        : Colors.grey.shade100;

    final fg = hasColours
        ? colorFromHex(
            colourScheme['foreground_hex']?.toString(),
            fallback: Colors.black87,
          )
        : Colors.black87;

    return InkWell(
      onTap: _pickFixtureType,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Fixture Type',
          border: OutlineInputBorder(),
        ),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 56),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: fg.withOpacity(0.20),
            ),
          ),
          child: Text(
            selected['name']?.toString() ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w600,
              fontSize: 18,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _fixtureTypeSelectedSwatch(Map<String, dynamic> ft) {
    final colourScheme = ft['colour_scheme'] as Map<String, dynamic>?;
    final hasColours = colourScheme != null;

    final bg = hasColours
        ? colorFromHex(
            colourScheme['background_hex']?.toString(),
            fallback: Colors.grey.shade200,
          )
        : Colors.transparent;

    final fg = hasColours
        ? colorFromHex(
            colourScheme['foreground_hex']?.toString(),
            fallback: Colors.black87,
          )
        : Colors.black87;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: double.infinity,
          height: constraints.maxHeight,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: hasColours ? bg : null,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasColours ? fg.withOpacity(0.25) : Colors.black12,
            ),
          ),
          child: Text(
            ft['name']?.toString() ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w600,
              fontSize: 18,
              height: 1.2,
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickFixtureType() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.70,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Select Fixture Type',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _fixtureTypes.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final ft = _fixtureTypes[i];
                        final id = ft['id'].toString();

                        return InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.pop(sheetContext, id),
                          child: _fixtureTypeSwatch(ft),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (selected == null) return;
    _applyFixtureType(selected);
  }

  @override
  Widget build(BuildContext context) {
    final startLabel = _startAtLocal == null
        ? 'Select date & time'
        : formatWhenLocal(_startAtLocal!.toUtc().toIso8601String());
    
    final endLabel = _endAtLocal == null
        ? 'Select end date & time'
        : formatWhenLocal(_endAtLocal!.toUtc().toIso8601String());

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

                  const Text('Fixture Type', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _selectedFixtureTypeField(),
//                  const SizedBox(height: 12),

//                  const Text('Location', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),

                  if (_fixtureTypeById(_fixtureTypeId)?['is_internal'] == true) ...[
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Location',
                        border: OutlineInputBorder(),
                      ),
                      child: const Text('Home'),
                    ),
                  ],

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Start'),
                            const SizedBox(height: 6),
                            OutlinedButton(
                              onPressed: _pickDateTime,
                              child: Text(startLabel),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('End'),
                            const SizedBox(height: 6),
                            OutlinedButton(
                              onPressed: _pickEndDateTime,
                              child: Text(endLabel),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  TextField(
                    controller: _teamNameCtrl,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Pre-Selected fixture label',
                      hintText: 'Set from Fixture Type',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  InkWell(
                    onTap: () async {
                      final selected = await _pickVenue(
                        getVenues: () => _homeVenues,
                        title: 'Select home venue',
                        isHomeVenue: true,
                      );

                      if (selected != null) {
                        debugPrint('HOME VENUE PICKED: $selected');

                        setState(() {
                          _homeVenueId = selected;
                          _greenAreas = [];
                          _greenAreaId = null;
                          _orientation = null;
                        });

                        await _loadGreenAreas();
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Home venue',
                        border: OutlineInputBorder(),
                      ),
                      child: Text(
                        _homeVenues
                                .firstWhere(
                                  (v) => v['id'].toString() == _homeVenueId,
                                  orElse: () => {'name': 'Select venue'},
                                )['name']
                                ?.toString() ??
                            'Select venue',
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  if (_greenAreas.isEmpty) ...[
                    const InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Green area',
                        border: OutlineInputBorder(),
                      ),
                      child: Text('No greens available for this venue'),
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    DropdownButtonFormField<String>(
                      value: _greenAreaId,
                      decoration: const InputDecoration(
                        labelText: 'Green area',
                        border: OutlineInputBorder(),
                      ),
                      items: _greenAreas.map((g) {
                        return DropdownMenuItem(
                          value: g['id'].toString(),
                          child: Text(g['name'].toString()),
                        );
                      }).toList(),
                      onChanged: (v) {
                        setState(() {
                          _greenAreaId = v;
                          _syncOrientationToSelectedGreen();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                  ],

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

                  DropdownButtonFormField<String>(
                    value: _section.isEmpty ? null : _section,
                    decoration: const InputDecoration(
                      labelText: 'Section',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'mixed', child: Text('Mixed')),
                      DropdownMenuItem(value: 'mens', child: Text("Men's")),
                      DropdownMenuItem(value: 'ladies', child: Text("Ladies")),
                    ],
                    onChanged: _fixtureTypeId == null
                        ? (value) {
                            setState(() {
                              _section = value ?? '';
                            });
                          }
                        : null,
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
