import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/hex_color.dart';
import '../../core/utils/date_format.dart';
import 'fixture_details_page.dart';
import 'repeat_fixture_planner_page.dart';
import '../rinks/widgets/rink_availability_panel.dart';
import '../../core/widgets/club_member_picker_page.dart';

enum FixtureLocationType { home, away }
enum FixtureWorkflowType { rsvp, team }

class CreateFixturePage extends StatefulWidget {
  final String clubId;
  final String clubName;
  final bool memberBookingMode;

  const CreateFixturePage({
    super.key,
    required this.clubId,
    required this.clubName,
    this.memberBookingMode = false,
  });

  @override
  State<CreateFixturePage> createState() => _CreateFixturePageState();
}

class _CreateFixturePageState extends State<CreateFixturePage> {
  final _teamNameCtrl = TextEditingController();

  String? _currentMemberId;

  bool _isSuperuser = false;
  bool _isClubAdmin = false;
  bool _isSelector = false;
  bool _isFixtureCreator = false;
  bool _isFixtureCaptain = false;
  bool _isFixtureViceCaptain = false;

  bool _loadingPermissions = true;

  bool _loading = false;
  String? _error;

  bool _isHome = true;
  bool _isTeamFixture = false;
  bool _isPreselectFixture = false;

  DateTime? _startAtLocal;
  DateTime? _endAtLocal;

  FixtureLocationType _fixtureLocation = FixtureLocationType.home;
  FixtureWorkflowType _workflowType = FixtureWorkflowType.rsvp;

  // Venues
  List<Map<String, dynamic>> _homeVenues = [];
  List<Map<String, dynamic>> _opponentVenues = [];
  String? _homeVenueId;
  String? _opponentVenueId;

  // Players, Opponents, Markers
  List<Map<String, dynamic>> _clubMembers = [];
  final Map<String, String?> _playerSelections = {};
  final Map<String, String?> _opponentSelections = {};
  final Map<String, String?> _markerSelections = {};

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

    // Fixture types
  List<Map<String, dynamic>> _fixtureTypes = [];
  String? _fixtureTypeId;
  bool _workflowLockedByFixtureType = false;

  bool _loadingRinkAvailability = false;
  String? _rinkAvailabilityError;
  List<Map<String, dynamic>> _rinkAvailability = [];

  Map<String, dynamic>? _selectedBookedRink;

  final Set<String> _draftSelectedRinkLabels = {};

  bool _shownInsufficientRinksWarning = false;

  String? _opponentVenueName(String? opponentVenueId) {
    if (opponentVenueId == null || opponentVenueId.isEmpty) return null;

    for (final venue in _opponentVenues) {
      if (venue['id'].toString() == opponentVenueId) {
        return (venue['name'] ?? '').toString();
      }
    }

    return null;
  }  

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
      await _loadUserPermissions();
      await _loadFixtureTypes();
      await _loadTeams();
      // Only load greens once we have a home venue selected
      await _loadGreenAreas();
      await _loadClubMembers();

      _defaultBookerIntoFirstPlayerSlot();

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

  Future<void> _loadRinkAvailability() async {
    debugPrint(
      'RINK AVAILABILITY CHECK: '
      'green=$_greenAreaId '
      'start=$_startAtLocal '
      'end=$_endAtLocal',
    );

    if (_greenAreaId == null || _startAtLocal == null || _endAtLocal == null) {
      setState(() {
        _rinkAvailability = [];
        _rinkAvailabilityError = null;
        _loadingRinkAvailability = false;
      });
      return;
    }

    setState(() {
      _loadingRinkAvailability = true;
      _rinkAvailabilityError = null;
    });

    try {
      final rows = await _client.rpc(
        'get_green_rink_availability',
        params: {
          'p_green_area_id': _greenAreaId,
          'p_start_at': _startAtLocal!.toUtc().toIso8601String(),
          'p_end_at': _endAtLocal!.toUtc().toIso8601String(),
        },
      );

      debugPrint('RINK AVAILABILITY RPC rows=$rows');
      debugPrint('RINK AVAILABILITY RPC type=${rows.runtimeType}');

      if (!mounted) return;

      setState(() {
        _rinkAvailability = List<Map<String, dynamic>>.from(rows);
      });

      if (_isHome &&
          _greenAreaId != null &&
          _rinksRequired > 0 &&
          !_hasEnoughRinkCapacity &&
          !_shownInsufficientRinksWarning) {
        _shownInsufficientRinksWarning = true;
        await _showInsufficientRinksDialog();
      }

      if (_hasEnoughRinkCapacity) {
        _shownInsufficientRinksWarning = false;
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _rinkAvailabilityError = e.toString();
        _rinkAvailability = [];
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingRinkAvailability = false;
        });
      }
    }
  }

  Future<void> _loadUserPermissions() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      throw Exception('No logged-in user');
    }

    final myProfileId = (await supabase.rpc('my_member_profile_id')).toString();

    // 1) Global superuser
    final superuserRow = await supabase
        .from('app_superusers')
        .select('user_id')
        .eq('user_id', user.id)
        .maybeSingle();

    _isSuperuser = superuserRow != null;

    // 2) Club membership for this club, using member_profile_id
    final membership = await supabase
        .from('club_memberships')
        .select('id, club_id, member_profile_id, role')
        .eq('member_profile_id', myProfileId)
        .eq('club_id', widget.clubId)
        .maybeSingle();

    debugPrint('AUTH user.id       = ${user.id}');
    debugPrint('PROFILE myProfileId = $myProfileId');
    debugPrint('MEMBERSHIP row      = $membership');

    if (membership != null) {
      _currentMemberId = myProfileId;

      final role = (membership['role'] ?? '').toString().trim().toLowerCase();

      debugPrint('MEMBERSHIP role raw = ${membership['role']}');
      debugPrint('MEMBERSHIP role norm= $role');

      _isClubAdmin = role == 'admin';
      _isSelector = role == 'selector';

      _isFixtureCreator = _isSuperuser || _isClubAdmin || _isSelector;
    } else {
      _currentMemberId = myProfileId;
      _isClubAdmin = false;
      _isSelector = false;
      _isFixtureCreator = _isSuperuser;
    }

    debugPrint(
      'Dashboard perms: super=$_isSuperuser '
      'admin=$_isClubAdmin '
      'selector=$_isSelector '
      'fixtureCreator=$_isFixtureCreator '
      'memberId=$_currentMemberId',
    );

    if (mounted) {
      setState(() {
        _loadingPermissions = false;
      });
    }
  }

  Future<bool> _confirmCreateRepeatFixtures(
    List<RepeatFixtureDate> dates,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Create ${dates.length} fixtures?'),
          content: SizedBox(
            width: 520,
            child: ListView(
              shrinkWrap: true,
              children: dates.map((d) {
                final dateText =
                    MaterialLocalizations.of(context).formatFullDate(d.date);

                final opponentName = _opponentVenueName(d.opponentVenueId);

                return ListTile(
                  title: Text(dateText),
                  subtitle: Text(
                    opponentName == null
                        ? 'Internal fixture'
                        : '${d.isHome ? 'Home' : 'Away'} against $opponentName',
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Back'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create fixtures'),
            ),
          ],
        );
      },
    );

    return confirmed == true;
  }

  Future<void> _openRepeatPlanner() async {
    if (_startAtLocal == null) return;

    final selectionMode = _selectedFixtureSelectionMode.trim().toLowerCase();

    final requiresOpponent = selectionMode != 'preselect' &&
        selectionMode != 'open' &&
        selectionMode != 'opensession' &&
        selectionMode != 'open_session' &&
        selectionMode != 'open-session';

    final result = await Navigator.of(context).push<List<RepeatFixtureDate>>(
      MaterialPageRoute(
        builder: (_) => RepeatFixturePlannerPage(
          startDateTime: _startAtLocal!,
          requiresOpponent: requiresOpponent,
          opponentVenues: requiresOpponent ? _opponentVenues : const [],
        ),
      ),
    );

    if (result == null) return;

    final selectedDates = result.where((d) => d.enabled).toList();

    if (selectedDates.isEmpty) {
      await _showSaveErrorDialog('No repeat dates were selected.');
      return;
    }

    final confirmed = await _confirmCreateRepeatFixtures(selectedDates);

    if (!confirmed) return;

    await _createRepeatFixtures(selectedDates);    

    debugPrint('Repeat count: ${result.where((d) => d.enabled).length}');
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
          uses_rinks,
          bookable_by_members,
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

    rows.sort((a, b) {
      final nameA = (a['name'] ?? '').toString().toLowerCase();
      final nameB = (b['name'] ?? '').toString().toLowerCase();
      return nameA.compareTo(nameB);
    });

    final loaded = List<Map<String, dynamic>>.from(rows);

    _fixtureTypes = _canSeeAllFixtureTypes
        ? loaded
        : loaded.where((t) => t['bookable_by_members'] == true).toList();
  }

  DateTime _combineRepeatDateWithOriginalTime(DateTime repeatDate) {
    return DateTime(
      repeatDate.year,
      repeatDate.month,
      repeatDate.day,
      _startAtLocal!.hour,
      _startAtLocal!.minute,
    );
  }

  Future<String> _createSingleRepeatFixture(RepeatFixtureDate repeatDate) async {
    if (_fixtureTypeId == null || _fixtureTypeId!.trim().isEmpty) {
      throw Exception('Please choose a Fixture Type.');
    }

    if (_section.trim().isEmpty) {
      throw Exception('Section is missing for the selected Fixture Type.');
    }

    if (_startAtLocal == null || _endAtLocal == null) {
      throw Exception('Please select a start and end time.');
    }

    if (_homeVenueId == null) {
      throw Exception('Please select a home venue.');
    }

    final selectedFixtureType = _fixtureTypeById(_fixtureTypeId);
    final isInternalFixtureType = selectedFixtureType?['is_internal'] == true;

    if (!isInternalFixtureType &&
        (repeatDate.opponentVenueId == null ||
            repeatDate.opponentVenueId!.trim().isEmpty)) {
      throw Exception('Please select an opponent venue.');
    }

    final startAt = _combineRepeatDateWithOriginalTime(repeatDate.date);
    final duration = _endAtLocal!.difference(_startAtLocal!);
    final endAt = startAt.add(duration);

    final isHome = isInternalFixtureType ? true : repeatDate.isHome;

    if (isHome && _greenAreaId == null) {
      throw Exception('Please select a green area.');
    }

    final String venueId = isHome
        ? _homeVenueId!
        : repeatDate.opponentVenueId!;

    final String? opponentVenueId = isInternalFixtureType
        ? null
        : (isHome ? repeatDate.opponentVenueId! : _homeVenueId!);

    final fixtureLabel = _teamNameCtrl.text.trim();

    if (_isTeamFixture && _teamId == null) {
      throw Exception('Please select a team.');
    }

    final availabilityRows = await _client.rpc(
      'get_green_rink_availability',
      params: {
        'p_green_area_id': isHome ? _greenAreaId : null,
        'p_start_at': startAt.toUtc().toIso8601String(),
        'p_end_at': endAt.toUtc().toIso8601String(),
      },
    );

    if (isHome) {
      final availability = List<Map<String, dynamic>>.from(availabilityRows);

      int asInt(dynamic v, int fallback) {
        if (v is int) return v;
        return int.tryParse((v ?? '').toString()) ?? fallback;
      }

      if (availability.isEmpty) {
        throw Exception('No rink availability returned for this green.');
      }

      final first = availability.first;
      final totalRinks = asInt(first['total_rinks'], availability.length);
      final freeRinks = asInt(first['free_capacity_rinks'], totalRinks);

      if (freeRinks < _rinksRequired) {
        throw Exception(
          'Not enough rinks available: $freeRinks free, $_rinksRequired required.',
        );
      }
    }

    final insertedRows = await _client.from('fixtures').insert({
      'club_id': widget.clubId,
      'start_at': startAt.toUtc().toIso8601String(),
      'end_at': endAt.toUtc().toIso8601String(),
      'is_home': isHome,
      'section': _section,
      'rinks_required': _rinksRequired,
      'players_per_rink': _playersPerRink,
      'competition_type_id': _fixtureTypeId,
      'team_id': _isTeamFixture ? _teamId : null,
      'team_name': fixtureLabel.isEmpty ? null : fixtureLabel,
      'requires_rsvp': (!_isTeamFixture && !_isPreselectFixture),
      'venue_id': venueId,
      'opponent_venue_id': opponentVenueId,
      'green_area_id': isHome ? _greenAreaId : null,
      'orientation': (isHome &&
              _isOutdoorSelectedGreen &&
              _orientationEnabledForSelectedGreen)
          ? _orientation
          : null,
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

    return fixtureId;
  }  

  Future<void> _createRepeatFixtures(List<RepeatFixtureDate> dates) async {
    final results = <RepeatFixtureCreationResult>[];

    setState(() => _loading = true);

    try {
      for (final d in dates) {
        try {
          // Temporary first pass.
          // Next step: replace this with the real fixture insert.
          final fixtureId = await _createSingleRepeatFixture(d);

          results.add(
            RepeatFixtureCreationResult(
              date: d.date,
              success: true,
              message: 'Created successfully',
              fixtureId: fixtureId,
            ),
          );
        } catch (e) {
          results.add(
            RepeatFixtureCreationResult(
              date: d.date,
              success: false,
              message: e.toString(),
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }

    await _showRepeatCreationResults(results);
  }

  Future<void> _showInsufficientRinksDialog() async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Not enough rinks'),
          content: const Text(
            'There are not enough free rinks for this fixture.\n\n'
            'Please change the green, time, date, or reduce the number of rinks required.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
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
    debugPrint('GREEN LOAD: _isHome=$_isHome, _homeVenueId=$_homeVenueId');

    // Green areas are only relevant for HOME fixtures
    if (!_isHome) {
      if (mounted) {
        setState(() {
          _greenAreas = [];
          _greenAreaId = null;
          _orientation = null;
        });
      }
      return;
    }

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

  Future<void> _moveBookedRinkToFreeRink(
    Map<String, dynamic> booked,
    String newRinkLabel,
  ) async {
    final oldLabel =
        (booked['rink_label'] ?? booked['label'] ?? booked['name'] ?? '')
            .toString();

    final fixtureRinkId = booked['fixture_rink_id']?.toString();

    if (fixtureRinkId == null || fixtureRinkId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot move this booking yet. Missing fixture rink id.'),
        ),
      );
      return;
    }

    await Supabase.instance.client
        .from('fixture_rinks')
        .update({
          'home_rink_label': newRinkLabel,
        })
        .eq('id', fixtureRinkId);

    setState(() {
      _selectedBookedRink = null;
    });

    await _loadRinkAvailability();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Moved $oldLabel to $newRinkLabel')),
    );
  }

  Future<void> _swapBookedRinks(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) async {
    final aId = a['fixture_rink_id']?.toString();
    final bId = b['fixture_rink_id']?.toString();

    final aLabel =
        (a['rink_label'] ?? a['label'] ?? a['name'] ?? '').toString();
    final bLabel =
        (b['rink_label'] ?? b['label'] ?? b['name'] ?? '').toString();

    if (aId == null || aId.isEmpty || bId == null || bId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot swap. Missing fixture rink id.'),
        ),
      );
      return;
    }

    try {
      await Supabase.instance.client.rpc(
        'swap_fixture_rink_labels',
        params: {
          'p_a_fixture_rink_id': aId,
          'p_b_fixture_rink_id': bId,
        },
      );

      setState(() {
        _selectedBookedRink = null;
      });

      await _loadRinkAvailability();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Swapped $aLabel with $bLabel')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Swap failed: $e')),
      );
    }
  }
  
  Future<void> _handleRinkTap(Map<String, dynamic> rink) async {  

    if (!_hasEnoughRinkCapacity) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'There are not enough free rinks for this fixture. Change the green, time, date, or reduce the rinks required.',
          ),
        ),
      );
      return;
    }

    final rinkLabel =
        (rink['rink_label'] ?? rink['label'] ?? rink['name'] ?? '').toString();

    final isBooked = rink['is_booked'] == true;

    debugPrint(
      'RINK TAP label=$rinkLabel isBooked=$isBooked '
      'canAdmin=$_canEditAdminFixtureDetails '
      'selectedBooked=${_selectedBookedRink != null}',
    );

    if (rinkLabel.isEmpty) return;

    if (isBooked) {
      if (!_canEditAdminFixtureDetails) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This rink is already booked.')),
        );
        return;
      }

      final currentSelectedLabel =
          (_selectedBookedRink?['rink_label'] ??
                  _selectedBookedRink?['label'] ??
                  _selectedBookedRink?['name'] ??
                  '')
              .toString();

      if (currentSelectedLabel == rinkLabel) {
        setState(() {
          _selectedBookedRink = null;
        });
        return;
      }

      if (_selectedBookedRink != null) {
        _swapBookedRinks(_selectedBookedRink!, rink);
        return;
      }

      setState(() {
        _selectedBookedRink = rink;
      });
      return;
    }

    if (_selectedBookedRink != null) {
      _moveBookedRinkToFreeRink(_selectedBookedRink!, rinkLabel);
      return;
    }

    _toggleHomeRinkSelection(rinkLabel);
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

    final row = _fixtureTypes.cast<Map<String, dynamic>?>().firstWhere(
      (r) => r?['id']?.toString() == fixtureTypeId,
      orElse: () => null,
    );

    if (row == null) return;

    final selectionMode = (row['selection_mode'] ?? '').toString();
    final name = (row['name'] ?? '').toString().trim();
    final section = (row['section'] ?? '').toString().trim();
    final isInternal = row['is_internal'] == true;
    final defaultRinksRequired = row['default_rinks_required'] as int?;
    final defaultPlayersPerRink = row['default_players_per_rink'] as int?;
    final linkedTeamId = row['team_id']?.toString();

    final selectionModeLower = selectionMode.toLowerCase();

    final usesSimpleBookingWorkflow =
        isInternal && selectionModeLower == 'preselect';
        
    setState(() {
      _fixtureTypeId = fixtureTypeId;
      _workflowLockedByFixtureType = true;

      if (isInternal) {
        _isHome = true;
        _fixtureLocation = FixtureLocationType.home;
        _opponentVenueId = null;
      }

      if (selectionMode == 'team') {
        _workflowType = FixtureWorkflowType.team;
        _isTeamFixture = true;
        _isPreselectFixture = false;

        _teamNameCtrl.text = name;

        if (linkedTeamId != null && linkedTeamId.isNotEmpty) {
          _teamId = linkedTeamId;
        } else {
          _teamId ??= _teams.isNotEmpty ? _teams.first['id'].toString() : null;
        }
      } else if (selectionMode == 'preselect') {
        _isTeamFixture = false;
        _isPreselectFixture = true;
        _teamId = null;

        _teamNameCtrl.text = name;
      } else if (selectionMode == 'opensession') {
//        _workflowType = FixtureWorkflowType.rsvp; // neutral existing workflow
        _isTeamFixture = false;
        _isPreselectFixture = false;
        _teamId = null;

        _teamNameCtrl.text = name;
      } else {
        // rsvp / practice
        _workflowType = FixtureWorkflowType.rsvp;
        _isTeamFixture = false;
        _isPreselectFixture = false;
        _teamId = null;

        _teamNameCtrl.text = name;
      }

      if (section.isNotEmpty) {
        _section = section;
      }
      if (defaultPlayersPerRink != null) {
        _playersPerRink = defaultPlayersPerRink;
      }
      if (defaultRinksRequired != null) {
        _rinksRequired = defaultRinksRequired;
      }
      if (usesSimpleBookingWorkflow) {
        _fixtureLocation = FixtureLocationType.home;
        _isHome = true;

        _workflowType = FixtureWorkflowType.rsvp; // hidden anyway
        _isTeamFixture = false;
        _isPreselectFixture = true;

        _teamId = null;
        _opponentVenueId = null;

        _teamNameCtrl.text = name;
      }      
    });

    _loadGreenAreas();
    _loadRinkAvailability();
  }

  String _memberLabel(Map<String, dynamic> m) {
    final first = (m['first_name'] ?? '').toString().trim();
    final last = (m['last_name'] ?? '').toString().trim();
    final display = (m['display_name'] ?? '').toString().trim();

    if (last.isNotEmpty && first.isNotEmpty) return '$last, $first';
    if (display.isNotEmpty) return display;
    return 'Unnamed member';
  }

  String _selectedMemberLabel(String? memberProfileId) {
    if (memberProfileId == null) return 'Select player';

    final match = _clubMembers.where((m) => m['id'].toString() == memberProfileId);
    if (match.isEmpty) return 'Select player';

    return _memberLabel(match.first);
  }

  String? get _selectedGreenName {
    if (_greenAreaId == null) return null;

    for (final g in _greenAreas) {
      if (g['id'].toString() == _greenAreaId) {
        return g['name']?.toString();
      }
    }

    return null;
  }

  Color get _selectedFixtureBgColor {
    final ft = _fixtureTypeById(_fixtureTypeId);
    final hex = ft?['colour_scheme']?['background_hex']?.toString();

    if (hex == null || hex.isEmpty) {
      return Colors.blue.shade50;
    }

    return _colourFromHex(hex);
  }

  Color get _selectedFixtureFgColor {
    final ft = _fixtureTypeById(_fixtureTypeId);
    final hex = ft?['colour_scheme']?['foreground_hex']?.toString();

    if (hex == null || hex.isEmpty) {
      return Colors.blue.shade900;
    }

    return _colourFromHex(hex);
  }

  Map<String, dynamic>? get _selectedGreenArea {
    if (_greenAreaId == null) return null;
    for (final g in _greenAreas) {
      if (g['id'].toString() == _greenAreaId) return g;
    }
    return null;
  }

  final Map<int, String> _selectedHomeRinkByTeam = {};

  int? _teamNoForSelectedRink(String rinkLabel) {
    for (final entry in _selectedHomeRinkByTeam.entries) {
      if (entry.value == rinkLabel) {
        return entry.key;
      }
    }
    return null;
  }

  void _toggleHomeRinkSelection(String rinkLabel) {
    final existingTeamNo = _teamNoForSelectedRink(rinkLabel);

    setState(() {
      // Click again = unbook/unselect
      if (existingTeamNo != null) {
        _selectedHomeRinkByTeam.remove(existingTeamNo);
        return;
      }

      // Otherwise assign to first team without a rink
      for (var teamNo = 1; teamNo <= _rinksRequired; teamNo++) {
        if (!_selectedHomeRinkByTeam.containsKey(teamNo)) {
          _selectedHomeRinkByTeam[teamNo] = rinkLabel;
          return;
        }
      }
    });
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

  String _backgroundImageForWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (width >= 1000) {
      return 'assets/images/auth_bg_desktop.png';
    }
    if (width >= 600) {
      return 'assets/images/auth_bg_tablet.png';
    }
    return 'assets/images/auth_bg_phone.png';
  }  

  bool get _canEditAdminFixtureDetails =>
      _isSuperuser ||
      _isClubAdmin ||
      _isSelector ||
      _isFixtureCreator;

  bool get _canEditFixtureOperationalDetails =>
      _canEditAdminFixtureDetails ||
      _isFixtureCaptain ||
      _isFixtureViceCaptain;
      
  Map<String, dynamic>? get _selectedFixtureType =>
      _fixtureTypeById(_fixtureTypeId);

  String get _selectedFixtureSelectionMode =>
      (_selectedFixtureType?['selection_mode'] ?? '')
          .toString()
          .trim()
          .toLowerCase();

  bool get _selectedFixtureIsInternal =>
      _selectedFixtureType?['is_internal'] == true;

  bool get _selectedFixtureIsBookableByMembers =>
      _selectedFixtureType?['bookable_by_members'] == true;

  /// WORKFLOW:
  /// Controls which create-screen process/UI is used.
  bool get _simpleBookingMode =>
      _selectedFixtureIsInternal &&
      _selectedFixtureSelectionMode == 'preselect';

  bool get _shouldShowRinksSection {
    return _isHome &&
        _greenAreaId != null &&
        (_rinksRequired > 0);
  }

  bool get _isOpenSessionFixture =>
      _selectedFixtureSelectionMode == 'opensession' ||
      _selectedFixtureSelectionMode == 'open_session' ||
      _selectedFixtureSelectionMode == 'open-session';  

  /// ACCESS:
  /// Controls whether the logged-in user may create/use this fixture type.
  bool get _canUseSelectedFixtureType {
    if (_selectedFixtureType == null) return false;
    if (_canEditAdminFixtureDetails) return true;

    return _selectedFixtureIsBookableByMembers;
  }
      
  bool get _canSeeAllFixtureTypes =>
      _isSuperuser || _isClubAdmin || _isSelector;

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

  bool get _canUseRepeat {
    return _isClubAdmin || _isSelector || _isSuperuser;
  }

  bool get _hasEnoughRinkCapacity {
    if (_rinkAvailability.isEmpty) return true;

    int asInt(dynamic v, int fallback) {
      if (v is int) return v;
      return int.tryParse((v ?? '').toString()) ?? fallback;
    }

    final first = _rinkAvailability.first;
    final totalRinks = asInt(first['total_rinks'], _rinkAvailability.length);
    final freeRinks = asInt(first['free_capacity_rinks'], totalRinks);

    return freeRinks >= _rinksRequired;
  }

  bool _memberAlreadySelectedElsewhere({
    required String memberProfileId,
    required String targetBucket,
    required String targetKey,
  }) {
    bool foundIn(Map<String, String?> map, String bucket) {
      for (final entry in map.entries) {
        if (bucket == targetBucket && entry.key == targetKey) {
          continue;
        }

        if (entry.value == memberProfileId) {
          return true;
        }
      }

      return false;
    }

    return foundIn(_playerSelections, 'player') ||
        foundIn(_opponentSelections, 'opponent') ||
        foundIn(_markerSelections, 'marker');
  }

  Color _colourFromHex(String hex) {
    final clean = hex.replaceAll('#', '').trim();
    if (clean.length != 6) return Colors.grey.shade100;
    return Color(int.parse('FF$clean', radix: 16));
  }

  Future<String?> _createVenueFromFixture({required bool isHomeVenue}) async {
    final nameCtrl = TextEditingController();
    final townCtrl = TextEditingController();
    final postcodeCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isHomeVenue ? 'Add home venue' : 'Add opponent venue'),
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

  Future<void> _loadClubMembers() async {
    final rows = await _client
        .from('club_memberships')
        .select('''
          member_profile:member_profiles(
            id,
            first_name,
            last_name,
            display_name,
            email_address
          )
        ''')
        .eq('club_id', widget.clubId)
        .eq('is_active', true);

    final members = <Map<String, dynamic>>[];

    for (final row in rows) {
      final profile = row['member_profile'];
      if (profile is Map<String, dynamic>) {
        members.add(profile);
      }
    }

    members.sort((a, b) => _memberLabel(a).compareTo(_memberLabel(b)));

    _clubMembers = members;

debugPrint('CLUB MEMBERS LOADED: ${_clubMembers.length}');
for (final m in _clubMembers) {
  debugPrint('MEMBER: ${m['id']} ${_memberLabel(m)}');
}

  }

  void _defaultBookerIntoFirstPlayerSlot() {
    if (_currentMemberId == null) return;

    final key = _slotKey(1, 1);

    if (_playerSelections[key] == null) {
      setState(() {
        _playerSelections[key] = _currentMemberId;
      });
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
    _loadRinkAvailability();
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
    _loadRinkAvailability();
  }

  String _formatForDisplay(int ppr) {
    switch (ppr) {
      case 1:
        return 'Singles (1)';
      case 2:
        return 'Pairs (2)';
      case 3:
        return 'Triples (3)';
      case 4:
        return 'Rinks (4)';
      default:
        return '$ppr per rink';
    }
  }

  String _formatCodeForRinks(int playersPerRink) {
    switch (playersPerRink) {
      case 1:
        return 'singles';
      case 2:
        return 'pairs';
      case 3:
        return 'triples';
      case 4:
        return 'rinks';
      default:
        throw ArgumentError('Invalid playersPerRink: $playersPerRink');
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

  String _slotKey(int teamNo, int slotNo) => '$teamNo:$slotNo';

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
    if (_loading) {
      debugPrint('SAVE: ignored because already loading');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_fixtureTypeId == null || _fixtureTypeId!.trim().isEmpty) {
        throw Exception('Please choose a Fixture Type.');
      }
      if (_section.trim().isEmpty) {
        throw Exception('Section is missing for the selected Fixture Type.');
      }      
      if (_startAtLocal == null) {
        throw Exception('Please select a start date/time.');
      }
      if (_homeVenueId == null) {
        throw Exception('Please select a home venue.');
      }
      final selectedFixtureType = _fixtureTypeById(_fixtureTypeId);
      final isInternalFixtureType = selectedFixtureType?['is_internal'] == true;

      if (!isInternalFixtureType && _opponentVenueId == null) {
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
      final String? opponentVenueId = isInternalFixtureType
          ? null
          : (_isHome ? _opponentVenueId! : _homeVenueId!);

      final fixtureLabel = _teamNameCtrl.text.trim();

      if (_isTeamFixture && _teamId == null) {
        throw Exception('Please select a team.');
      }

      final captainMemberProfileId =
          _simpleBookingMode ? _currentMemberId : null;

debugPrint('CREATE FIXTURE captainMemberProfileId=$captainMemberProfileId');
debugPrint('CREATE FIXTURE currentMemberId=$_currentMemberId');
debugPrint('CREATE FIXTURE canSeeAll=$_canSeeAllFixtureTypes');


      final insertedRows = await _client.from('fixtures').insert({
        'club_id': widget.clubId,
        'start_at': _startAtLocal!.toUtc().toIso8601String(),
        'end_at': _endAtLocal!.toUtc().toIso8601String(),
        'is_home': _isHome,
        'section': _section,
        'rinks_required': _rinksRequired,
        'players_per_rink': _playersPerRink,
        'competition_type_id': _fixtureTypeId,
        'team_id': _isTeamFixture ? _teamId : null,
        'team_name': fixtureLabel.isEmpty ? null : fixtureLabel,

        // ✅ IMPORTANT: override DB default TRUE
        // RSVP => true
        // Team / Preselect => false
        'requires_rsvp': (!_isTeamFixture && !_isPreselectFixture), // team fixture => false, friendly/internal => true

        'venue_id': venueId,
        'opponent_venue_id': opponentVenueId,

        // Greens/orientation only relevant for HOME fixtures
        'green_area_id': _isHome ? _greenAreaId : null,
        'orientation': (_isHome && _isOutdoorSelectedGreen && _orientationEnabledForSelectedGreen)
            ? _orientation
            : null,
        'captain_member_profile_id': captainMemberProfileId,            
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
          'fixture_rink_no': i,
          'format': formatCode,
          'players_per_rink': _playersPerRink,
          'home_rink_label': _selectedHomeRinkByTeam[i],
        });
      }
      if (rinkRows.isNotEmpty) {
        await _client.from('fixture_rinks').insert(rinkRows);
      }
      debugPrint('SAVE: pop');
      
      if (!mounted) return;
      
      debugPrint('create_fixture_page: created fixtureId=$fixtureId, opening details...');

      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => FixtureDetailsPage(fixtureId: fixtureId),
        ),
      );

      debugPrint('create_fixture_page: details returned changed=$changed');

      if (!context.mounted) return;

      // return to fixtures_screen
      Navigator.pop(context, true);

    } on PostgrestException catch (e) {
      final message = e.message.contains('Not enough rinks available')
          ? 'Not enough rinks are available at that time. Please choose another time, date, or green.'
          : (e.message.isNotEmpty ? e.message : 'Database error');

      if (mounted) {
        setState(() {
          _loading = false;
          _error = null;
        });
      }

      await _showSaveErrorDialog(message);      
    } catch (e) {
      final message = e.toString();

      if (mounted) {
        setState(() {
          _loading = false;
          _error = null;
        });
      }

      await _showSaveErrorDialog(message);
    }
  }

  Map<String, dynamic>? _fixtureTypeById(String? id) {
    if (id == null) return null;

    for (final ft in _fixtureTypes) {
      if (ft['id'].toString() == id) return ft;
    }
    return null;
  }

  Widget _buildMemberBookingInlineSection() {
    final playersPerSide = _playersPerRink;

    return Card(
      margin: const EdgeInsets.only(top: 8, bottom: 20),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Players, opponents and rinks',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 12),

            for (var teamNo = 1; teamNo <= _rinksRequired; teamNo++) ...[
              Text(
                'Team $teamNo',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),

              for (var playerNo = 1; playerNo <= playersPerSide; playerNo++) ...[
                Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text('Player $playerNo'),
                    ),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final key = _slotKey(teamNo, playerNo);
                          final current = _playerSelections[key];

                          final selectedList = await Navigator.of(context).push<List<String>?>(
                            MaterialPageRoute(
                              builder: (_) => ClubMemberPickerPage(
                                clubId: widget.clubId,
                                title: 'Select Player $playerNo',
                                fixtureId: null,
                                useFixtureSection: true,
                                allowMultiple: false,
                                initialSelectedIds: {
                                  if (current != null && current.isNotEmpty) current,
                                },
                              ),
                            ),
                          );

                          if (!mounted) return;
                          if (selectedList == null) return;

                          final selected = selectedList.isEmpty ? '' : selectedList.first;
                          if (selected != null && mounted) {
                            if (selected.isNotEmpty &&
                                _memberAlreadySelectedElsewhere(
                                  memberProfileId: selected,
                                  targetBucket: 'player',
                                  targetKey: key,
                                )) {
                              await _showSaveErrorDialog(
                                'This member has already been selected elsewhere in this fixture.',
                              );
                              return;
                            }

                            setState(() {
                              _playerSelections[key] = selected.isEmpty ? null : selected;
                            });
                          }
                        },
                        child: Text(
                          _selectedMemberLabel(_playerSelections[_slotKey(teamNo, playerNo)]),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 90,
                      child: Text('Opponent $playerNo'),
                    ),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final key = _slotKey(teamNo, playerNo);
                          final current = _opponentSelections[key];

                          final selectedList = await Navigator.of(context).push<List<String>?>(
                            MaterialPageRoute(
                              builder: (_) => ClubMemberPickerPage(
                                clubId: widget.clubId,
                                title: 'Select Opponent $playerNo',
                                fixtureId: null,
                                useFixtureSection: true,
                                allowMultiple: false,
                                initialSelectedIds: {
                                  if (current != null && current.isNotEmpty) current,
                                },
                              ),
                            ),
                          );

                          if (!mounted) return;
                          if (selectedList == null) return;

                          final selected = selectedList.isEmpty ? '' : selectedList.first;

                          if (selected != null && mounted) {
                            if (selected.isNotEmpty &&
                                _memberAlreadySelectedElsewhere(
                                  memberProfileId: selected,
                                  targetBucket: 'opponent',
                                  targetKey: key,
                                )) {
                              await _showSaveErrorDialog(
                                'This member has already been selected elsewhere in this fixture.',
                              );
                              return;
                            }

                            setState(() {
                              _opponentSelections[key] = selected.isEmpty ? null : selected;
                            });
                          }
                        },
                        child: Text(
                          _selectedMemberLabel(_opponentSelections[_slotKey(teamNo, playerNo)]),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],

              Row(
                children: [
                  const SizedBox(
                    width: 80,
                    child: Text('Marker'),
                  ),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final key = _slotKey(teamNo, 1);
                        final current = _markerSelections[key];

                        final selectedList = await Navigator.of(context).push<List<String>?>(
                          MaterialPageRoute(
                            builder: (_) => ClubMemberPickerPage(
                              clubId: widget.clubId,
                              title: 'Select Marker',
                              fixtureId: null,
                              useFixtureSection: false,
                              initialSectionFilter: MemberPickerSectionFilter.open,
                              allowMultiple: false,
                              initialSelectedIds: {
                                if (current != null && current.isNotEmpty) current,
                              },
                            ),
                          ),
                        );

                        if (!mounted) return;
                        if (selectedList == null) return;

                        final selected = selectedList.isEmpty ? '' : selectedList.first;

                        if (selected != null && mounted) {
                          if (selected.isNotEmpty &&
                              _memberAlreadySelectedElsewhere(
                                memberProfileId: selected,
                                targetBucket: 'marker',
                                targetKey: key,
                              )) {
                            await _showSaveErrorDialog(
                              'This member has already been selected elsewhere in this fixture.',
                            );
                            return;
                          }

                          setState(() {
                            _markerSelections[key] = selected.isEmpty ? null : selected;
                          });
                        }
                      },
                      child: Text(
                        _selectedMemberLabel(_markerSelections[_slotKey(teamNo, 1)]),
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 28),
            ],

            _buildGreenAndRinkAvailabilityBlock(),          
          ],
        ),
      ),
    );
  }

  Widget _buildGreenAndRinkAvailabilityBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _selectedGreenName?.isNotEmpty == true
              ? 'Rinks — $_selectedGreenName'
              : 'Rinks',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        _buildRinkAvailabilitySection(),
      ],
    );
  }

  Widget _buildRinkAvailabilitySection() {
    if (_greenAreaId == null || _startAtLocal == null || _endAtLocal == null) {
      return const Text(
        'Choose green, start time and end time to see rink availability.',
        textAlign: TextAlign.center,
      );
    }

    if (_loadingRinkAvailability) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_rinkAvailabilityError != null) {
      return Text(
        'Could not load rink availability: $_rinkAvailabilityError',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.red),
      );
    }

    if (_rinkAvailability.isEmpty) {
      return const Text(
        'No physical rinks found for this green.',
        textAlign: TextAlign.center,
      );
    }

    int asInt(dynamic v, int fallback) {
      if (v is int) return v;
      return int.tryParse((v ?? '').toString()) ?? fallback;
    }

    final first = _rinkAvailability.first;

    final totalRinks = asInt(first['total_rinks'], _rinkAvailability.length);
    final freeRinks = asInt(first['free_capacity_rinks'], totalRinks);
    final enoughRinks = freeRinks >= _rinksRequired;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: enoughRinks ? Colors.green.shade50 : Colors.red.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: enoughRinks ? Colors.green.shade300 : Colors.red.shade300,
            ),
          ),
          child: Text(
            '$freeRinks of $totalRinks rinks free',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: enoughRinks ? Colors.green.shade900 : Colors.red.shade900,
            ),
          ),
        ),

        Column(
          children: _rinkAvailability.map((r) {
            final rinkLabel =
                (r['rink_label'] ?? r['label'] ?? r['name'] ?? '').toString();
            final isBooked = r['is_booked'] == true;
            final bookedText = (r['booked_text'] ?? '').toString();

            final selectedTeamNo = _teamNoForSelectedRink(rinkLabel);
            final isSelected = selectedTeamNo != null;            

            final bgHex = (r['background_hex'] ?? '#FEE2E2').toString();
            final fgHex = (r['foreground_hex'] ?? '#991B1B').toString();

            final bookedBgColor = _colourFromHex(bgHex);
            final bookedFgColor = _colourFromHex(fgHex);

            final selectedBookedLabel =
                (_selectedBookedRink?['rink_label'] ??
                        _selectedBookedRink?['label'] ??
                        _selectedBookedRink?['name'] ??
                        '')
                    .toString();

            final isSelectedBooked = isBooked && selectedBookedLabel == rinkLabel;

            return InkWell(
              onTap: () => _handleRinkTap(r),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isSelectedBooked
                      ? Colors.amber.shade100
                      : isBooked
                          ? bookedBgColor
                          : isSelected
                              ? _selectedFixtureBgColor
                              : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    width: (isSelected || isSelectedBooked) ? 2 : 1,
                    color: isSelectedBooked
                        ? Colors.orange.shade700
                        : isBooked
                            ? bookedFgColor.withOpacity(0.35)
                            : isSelected
                                ? _selectedFixtureBgColor
                                : Colors.green.shade300,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            rinkLabel.isEmpty ? 'Rink' : rinkLabel,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: isSelectedBooked
                                  ? Colors.orange.shade900
                                  : isBooked
                                      ? bookedFgColor
                                      : isSelected
                                          ? _selectedFixtureFgColor
                                          : Colors.green.shade900,
                            ),
                          ),
                        ),
                        if (isSelectedBooked)
                          Icon(
                            Icons.swap_horiz,
                            size: 18,
                            color: Colors.orange.shade900,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isBooked
                          ? isSelectedBooked
                              ? 'Selected booking — tap a free rink to move it, or another booked rink to swap'
                              : bookedText
                          : isSelected
                              ? 'Selected for Team $selectedTeamNo'
                              : _selectedBookedRink != null
                                  ? 'Free — tap to move selected booking here'
                                  : 'Free',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                      color: isSelectedBooked
                          ? Colors.orange.shade900
                          : isBooked
                              ? bookedFgColor
                              : isSelected
                                  ? _selectedFixtureFgColor
                                  : Colors.green.shade900,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
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

   Future<void> _showRepeatCreationResults(
    List<RepeatFixtureCreationResult> results,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Repeat fixture results'),
          content: SizedBox(
            width: 520,
            child: ListView(
              shrinkWrap: true,
              children: results.map((r) {
                final dateText =
                    MaterialLocalizations.of(context).formatFullDate(r.date);

                return ListTile(
                  leading: Icon(
                    r.success ? Icons.check_circle : Icons.error,
                    color: r.success ? Colors.green : Colors.red,
                  ),
                  title: Text(dateText),
                  subtitle: Text(r.message),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
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
        selectedGreen == null ? <String>[] : _allowedOrientationsFor(selectedGreen);

    return Scaffold(
      appBar: AppBar(
        title: Text(_simpleBookingMode ? 'Book Fixture' : 'Create Fixture'),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.16,
              child: Image.asset(
                _backgroundImageForWidth(context),
                fit: BoxFit.cover,
              ),
            ),
          ),
          _loading
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

                      const Text(
                        'Fixture Type',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      _selectedFixtureTypeField(),
                      const SizedBox(height: 12),

                      if (!_simpleBookingMode) ...[
                        const Text(
                          'Location',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),

                        if (_fixtureTypeById(_fixtureTypeId)?['is_internal'] == true) ...[
                          InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Location',
                              border: OutlineInputBorder(),
                            ),
                            child: const Text('Home'),
                          ),
                        ] else ...[
                          SegmentedButton<FixtureLocationType>(
                            segments: const [
                              ButtonSegment(
                                value: FixtureLocationType.home,
                                label: Text('Home'),
                                icon: Icon(Icons.home),
                              ),
                              ButtonSegment(
                                value: FixtureLocationType.away,
                                label: Text('Away'),
                                icon: Icon(Icons.directions_bus),
                              ),
                            ],
                            selected: {_fixtureLocation},
                            onSelectionChanged: (newSelection) async {
                              final v = newSelection.first;
                              setState(() {
                                _fixtureLocation = v;
                                _isHome = v == FixtureLocationType.home;
                                _greenAreas = [];
                                _greenAreaId = null;
                                _orientation = null;
                              });
                              await _loadGreenAreas();
                            },
                          ),
                        ],
                        const SizedBox(height: 12),
                      ],

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

                      const SizedBox(height: 12),

                      if (!_simpleBookingMode) ...[
                        const Text(
                          'Fixture workflow',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),

                        if (_isPreselectFixture) ...[
                          InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Pre-Selection mode',
                              border: OutlineInputBorder(),
                            ),
                            child: const Text('Pre-Select'),
                          ),
                        ] else ...[
                          SegmentedButton<FixtureWorkflowType>(
                            segments: const [
                              ButtonSegment(
                                value: FixtureWorkflowType.rsvp,
                                label: Text('RSVP'),
                                icon: Icon(Icons.how_to_reg),
                              ),
                              ButtonSegment(
                                value: FixtureWorkflowType.team,
                                label: Text('Team'),
                                icon: Icon(Icons.groups),
                              ),
                            ],
                            selected: {_workflowType},
                            onSelectionChanged: _workflowLockedByFixtureType
                                ? null
                                : (newSelection) {
                                    final v = newSelection.first;
                                    setState(() {
                                      _workflowType = v;
                                      _isTeamFixture =
                                          v == FixtureWorkflowType.team;
                                      _isPreselectFixture = false;

                                      if (_isTeamFixture) {
                                        _teamId ??= _teams.isNotEmpty
                                            ? _teams.first['id'].toString()
                                            : null;
                                      } else {
                                        _teamId = null;
                                      }
                                    });
                                  },
                          ),
                        ],

                        const SizedBox(height: 8),
                      ],

                      if (!_isTeamFixture && !_simpleBookingMode) ...[
                        TextField(
                          controller: _teamNameCtrl,
                          readOnly: _isPreselectFixture,
                          decoration: InputDecoration(
                            labelText: _isPreselectFixture
                                ? 'Pre-Selected fixture label'
                                : 'Fixture label (optional)',
                            hintText: _isPreselectFixture
                                ? 'Set from Fixture Type'
                                : 'e.g. Mid-week National Team Selection',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      if (!_simpleBookingMode || _homeVenues.length > 1) ...[
                        InkWell(
                          onTap: () async {
                            final selected = await _pickVenue(
                              getVenues: () => _homeVenues,
                              title: 'Select home venue',
                              isHomeVenue: true,
                            );

                            if (selected != null) {
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
                      ],
                      
                      if (!_simpleBookingMode &&
                          _fixtureTypeById(_fixtureTypeId)?['is_internal'] != true) ...[
                        InkWell(
                          onTap: () async {
                            final selected = await _pickVenue(
                              getVenues: () => _opponentVenues,
                              title: 'Select Opponent Club',
                              isHomeVenue: false,
                            );
                            if (selected != null) {
                              setState(() => _opponentVenueId = selected);
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Opponent Club',
                              border: OutlineInputBorder(),
                            ),
                            child: Text(
                              _opponentVenues
                                      .firstWhere(
                                        (v) =>
                                            v['id'].toString() == _opponentVenueId,
                                        orElse: () => {'name': 'Select Club'},
                                      )['name']
                                      ?.toString() ??
                                  'Select Club',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      if (_isHome &&
                          (!_simpleBookingMode || _greenAreas.length > 1)) ...[
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
                              _loadRinkAvailability();
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],

                      if (_isHome &&
                          _isOutdoorSelectedGreen &&
                          _orientationEnabledForSelectedGreen &&
                          allowedOrients.isNotEmpty) ...[
                        DropdownButtonFormField<String>(
                          value: _orientation,
                          decoration:
                              const InputDecoration(labelText: 'Orientation'),
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

                      if (!_simpleBookingMode) ...[
                        DropdownButtonFormField<String>(
                          value: _section.isEmpty ? null : _section,
                          decoration: const InputDecoration(
                            labelText: 'Section',
                          ),
                          items: const [
                            DropdownMenuItem(value: 'open', child: Text('Open')),
                            DropdownMenuItem(value: 'mixed', child: Text('Mixed')),
                            DropdownMenuItem(value: 'mens', child: Text("Men's")),
                            DropdownMenuItem(
                                value: 'ladies', child: Text("Ladies")),
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
                          items: const [4, 3, 2, 1].map((ppr) {
                            return DropdownMenuItem(
                              value: ppr,
                              child: Text(
                                ppr == 4
                                    ? 'Fours (4)'
                                    : ppr == 3
                                        ? 'Triples (3)'
                                        : ppr == 2
                                            ? 'Pairs (2)'
                                            : 'Singles (1)',
                              ),
                            );
                          }).toList(),
                          onChanged: (v) =>
                              setState(() => _playersPerRink = v ?? 4),
                        ),

                        const SizedBox(height: 12),
                      ],

                      DropdownButtonFormField<int>(
                        value: _rinksRequired,
                        decoration:
                            const InputDecoration(labelText: 'Rinks required'),
                        items: List.generate(12, (i) => i + 1).map((n) {
                          return DropdownMenuItem(
                            value: n,
                            child: Text(n.toString()),
                          );
                        }).toList(),
                        onChanged: (v) {
                          setState(() => _rinksRequired = v ?? 1);
                          _loadRinkAvailability();
                        },
                      ),

                      const SizedBox(height: 20),

                      if (_simpleBookingMode) ...[
                        _buildMemberBookingInlineSection(),
                      ] else if (_shouldShowRinksSection) ...[
                        _buildGreenAndRinkAvailabilityBlock(),
                      ],

                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _loading ? null : _save,
                              icon: const Icon(Icons.save),
                              label: const Text('Save'),
                            ),
                          ),
                          if (_canUseRepeat) ...[
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed: _loading ? null : _openRepeatPlanner,
                              icon: const Icon(Icons.repeat),
                              label: const Text('Repeat'),
                            ),
                          ],
                        ],
                      )
                    ],
                  ),
                ),
        ],
      ),
    );
  }
}

class RepeatFixtureCreationResult {
  RepeatFixtureCreationResult({
    required this.date,
    required this.success,
    required this.message,
    this.fixtureId,
  });

  final DateTime date;
  final bool success;
  final String message;
  final String? fixtureId;
}