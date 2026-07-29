import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'venue_maintain_screen.dart';

// Stable venue UI baseline: Phase 2D.3, 2026-07-28.
const String venuesScreenRevision = '20260728-phase2d3-stable';

class VenuesScreen extends StatefulWidget {
  final String clubId;
  final String clubName;

  const VenuesScreen({
    super.key,
    required this.clubId,
    required this.clubName,
  });

  @override
  State<VenuesScreen> createState() => _VenuesScreenState();
}

class _VenuesScreenState extends State<VenuesScreen> {
  bool _loadingPermissions = true;
  bool _isSuperuser = false;
  bool _isClubAdmin = false;
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _venues = [];
  List<Map<String, dynamic>> _allVenues = [];
  String _searchText = '';

  bool get _canManage => _isSuperuser || _isClubAdmin;

  String _s(dynamic value) => (value ?? '').toString().trim();

  @override
  void initState() {
    super.initState();
    _initScreen();
  }

  Future<void> _initScreen() async {
    try {
      await _loadUserPermissions();
      await _load();
    } catch (error, stackTrace) {
      debugPrint('Venues init failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;
      setState(() {
        _loadingPermissions = false;
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadUserPermissions() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) throw Exception('No logged-in user');

    final myProfileId = (await supabase.rpc('my_member_profile_id')).toString();

    final superuserRow = await supabase
        .from('app_superusers')
        .select('user_id')
        .eq('user_id', user.id)
        .maybeSingle();

    _isSuperuser = superuserRow != null;

    final membership = await supabase
        .from('club_memberships')
        .select('role')
        .eq('member_profile_id', myProfileId)
        .eq('club_id', widget.clubId)
        .maybeSingle();

    final role = _s(membership?['role']).toLowerCase();
    _isClubAdmin = role == 'admin';

    if (!mounted) return;
    setState(() => _loadingPermissions = false);
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final rows = await Supabase.instance.client
          .from('venues')
          .select(
            'id, club_id, name, is_home_venue, '
            'contact_name, contact_phone, contact_email, '
            'address_line1, address_line2, town_city, postcode, directions_url, '
            'website_url, google_maps_url, google_place_id, latitude, longitude, '
            'venue_master_id, club_officers',
          )
          .eq('club_id', widget.clubId)
          .order('name');

      _allVenues = List<Map<String, dynamic>>.from(rows)
        ..sort(
          (a, b) => _s(a['name'])
              .toLowerCase()
              .compareTo(_s(b['name']).toLowerCase()),
        );
      _applyFilter(updateState: false);
    } catch (error) {
      _error = error.toString();
      _allVenues = [];
      _venues = [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter({bool updateState = true}) {
    void apply() {
      final query = _searchText.trim().toLowerCase();

      if (query.isEmpty) {
        _venues = List<Map<String, dynamic>>.from(_allVenues);
        return;
      }

      _venues = _allVenues.where((venue) {
        return _s(venue['name']).toLowerCase().contains(query) ||
            _s(venue['town_city']).toLowerCase().contains(query) ||
            _s(venue['postcode']).toLowerCase().contains(query);
      }).toList();
    }

    if (updateState) {
      setState(apply);
    } else {
      apply();
    }
  }

  Future<void> _openVenue(Map<String, dynamic> venue) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => VenueMaintainScreen(
          clubId: widget.clubId,
          venue: venue,
          canEdit: _canManage,
        ),
      ),
    );

    if (changed == true && mounted) await _load();
  }

  Future<void> _createVenue() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => VenueMaintainScreen(
          clubId: widget.clubId,
          canEdit: true,
          startInEditMode: true,
        ),
      ),
    );

    if (changed == true && mounted) await _load();
  }

  Future<void> _deleteVenue(Map<String, dynamic> venue) async {
    final id = _s(venue['id']);
    final name = _s(venue['name']);
    if (id.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete venue'),
        content: Text(
          'Are you sure you want to delete "$name"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final fixtureLinks = await Supabase.instance.client
          .from('fixtures')
          .select('id')
          .or('venue_id.eq.$id,opponent_venue_id.eq.$id')
          .limit(1);

      if ((fixtureLinks as List).isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'This venue cannot be deleted because it is linked to existing fixtures.',
              ),
            ),
          );
        }
        return;
      }

      await Supabase.instance.client.from('venues').delete().eq('id', id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Venue deleted.')),
        );
      }
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete venue error: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Venues — ${widget.clubName}'),
        actions: [
          IconButton(
            tooltip: 'Refresh venues',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton(
              tooltip: 'Add venue',
              onPressed: _createVenue,
              child: const Icon(Icons.add),
            )
          : null,
      body: (_loading || _loadingPermissions)
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _allVenues.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _canManage
                              ? 'No venues yet.\nTap + to add one.'
                              : 'No venues available.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'Search venues…',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _searchText.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Clear search',
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        _searchText = '';
                                        _applyFilter();
                                      },
                                    ),
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (value) {
                              _searchText = value;
                              _applyFilter();
                            },
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _venues.length,
                            itemBuilder: (_, index) {
                              final venue = _venues[index];
                              final isHome =
                                  venue['is_home_venue'] == true;
                              final town = _s(venue['town_city']);
                              final postcode = _s(venue['postcode']);

                              return ListTile(
                                onTap: () => _openVenue(venue),
                                tileColor: isHome
                                    ? Colors.green.withValues(alpha: 0.08)
                                    : Colors.orange.withValues(alpha: 0.08),
                                title: Text(_s(venue['name'])),
                                subtitle: Text(
                                  [
                                    isHome
                                        ? 'Home venue'
                                        : 'Opponent venue',
                                    if (town.isNotEmpty) town,
                                    if (postcode.isNotEmpty) postcode,
                                  ].join(' • '),
                                ),
                                trailing: _canManage
                                    ? Wrap(
                                        spacing: 0,
                                        children: [
                                          const Icon(Icons.chevron_right),
                                          IconButton(
                                            tooltip: 'Delete venue',
                                            icon: const Icon(
                                              Icons.delete_outline,
                                            ),
                                            onPressed: () =>
                                                _deleteVenue(venue),
                                          ),
                                        ],
                                      )
                                    : const Icon(Icons.chevron_right),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
    );
  }
}
