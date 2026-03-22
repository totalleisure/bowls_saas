import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
//import 'package:flutter/services.dart';
//import 'package:intl/intl.dart';
//import 'package:share_plus/share_plus.dart';
//import '../../core/utils/date_format.dart';

//import '../../Core/permissions/club_role_resolver.dart';
//import '../../Core/permissions/dashboard_permissions.dart';
//import '../../Core/permissions/fixture_permissions.dart';
//import '../../Core/permissions/fixture_role_resolver.dart';
//import '../../Core/permissions/permission_models.dart';

class VenuesScreen extends StatefulWidget {
  final String clubId;
  final String clubName;

  const VenuesScreen({super.key, required this.clubId, required this.clubName});

  @override
  State<VenuesScreen> createState() => _VenuesScreenState();
}

class _VenuesScreenState extends State<VenuesScreen> {

  bool _loadingPermissions = true;
  bool _isSuperuser = false;
  bool _isClubAdmin = false;
  String? _currentMemberId;

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _venues = [];

  List<Map<String, dynamic>> _allVenues = [];
  String _searchText = '';

  bool get _canManage => _isSuperuser || _isClubAdmin;

  void _applyFilter() {
    final q = _searchText.trim().toLowerCase();

    setState(() {
      if (q.isEmpty) {
        _venues = List<Map<String, dynamic>>.from(_allVenues);
        return;
      }

      _venues = _allVenues.where((v) {
        final name = (v['name'] ?? '').toString().toLowerCase();
        final town = (v['town_city'] ?? '').toString().toLowerCase();
        final postcode = (v['postcode'] ?? '').toString().toLowerCase();

        return name.contains(q) || town.contains(q) || postcode.contains(q);
      }).toList();
    });
  }

  Future<void> _initScreen() async {
    try {
      await _loadUserPermissions();
      await _load();
    } catch (e, st) {
      debugPrint('Venues init failed: $e');
      debugPrintStack(stackTrace: st);

      if (mounted) {
        setState(() {
          _loadingPermissions = false;
          _loading = false;
          _error = e.toString();
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

    final superuserRow = await supabase
        .from('app_superusers')
        .select('user_id')
        .eq('user_id', user.id)
        .maybeSingle();

    _isSuperuser = superuserRow != null;

    final membership = await supabase
        .from('club_memberships')
        .select('id, club_id, member_profile_id, role')
        .eq('member_profile_id', myProfileId)
        .eq('club_id', widget.clubId)
        .maybeSingle();

    debugPrint('VENUES user.id       = ${user.id}');
    debugPrint('VENUES myProfileId   = $myProfileId');
    debugPrint('VENUES membership    = $membership');

    _currentMemberId = myProfileId;

    if (membership != null) {
      final role = (membership['role'] ?? '').toString().trim().toLowerCase();
      _isClubAdmin = role == 'admin';
    } else {
      _isClubAdmin = false;
    }

    debugPrint(
      'Venues perms: super=$_isSuperuser '
      'admin=$_isClubAdmin '
      'memberId=$_currentMemberId',
    );

    if (mounted) {
      setState(() {
        _loadingPermissions = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
      _initScreen();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await Supabase.instance.client
          .from('venues')
          .select('id, name, is_home_venue, town_city, postcode')
          .eq('club_id', widget.clubId)
          .order('name');

      _allVenues = List<Map<String, dynamic>>.from(rows);
      _applyFilter();
    } catch (e) {
      _error = '$e';
      _allVenues = [];
      _venues = [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createVenue() async {
    final name = TextEditingController();
    final town = TextEditingController();
    final postcode = TextEditingController();
    bool isHome = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Create venue'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Venue name'),
                ),
                TextField(
                  controller: town,
                  decoration: const InputDecoration(labelText: 'Town/City (optional)'),
                ),
                TextField(
                  controller: postcode,
                  decoration: const InputDecoration(labelText: 'Postcode (optional)'),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: isHome,
                  onChanged: (v) => setStateDialog(() => isHome = v),
                  title: const Text('Home venue'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
          ],
        ),
      ),
    );

    if (ok != true) return;
    final venueName = name.text.trim();
    if (venueName.isEmpty) return;

    try {
      await Supabase.instance.client.from('venues').insert({
        'club_id': widget.clubId,
        'name': venueName,
        'is_home_venue': isHome,
        'town_city': town.text.trim().isEmpty ? null : town.text.trim(),
        'postcode': postcode.text.trim().isEmpty ? null : postcode.text.trim(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Venue created ✅')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Create venue error: $e')));
      }
    }
  }

  Future<void> _editVenue(Map<String, dynamic> venue) async {
    final id = venue['id']?.toString();
    if (id == null || id.isEmpty) return;

    final name = TextEditingController(text: (venue['name'] ?? '').toString());
    final town = TextEditingController(text: (venue['town_city'] ?? '').toString());
    final postcode = TextEditingController(text: (venue['postcode'] ?? '').toString());
    bool isHome = venue['is_home_venue'] == true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Edit venue'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Venue name'),
                ),
                TextField(
                  controller: town,
                  decoration: const InputDecoration(labelText: 'Town/City (optional)'),
                ),
                TextField(
                  controller: postcode,
                  decoration: const InputDecoration(labelText: 'Postcode (optional)'),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isHome,
                  onChanged: (v) => setStateDialog(() => isHome = v),
                  title: const Text('Home venue'),
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
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    final venueName = name.text.trim();
    if (venueName.isEmpty) return;

    try {
      await Supabase.instance.client
          .from('venues')
          .update({
            'name': venueName,
            'is_home_venue': isHome,
            'town_city': town.text.trim().isEmpty ? null : town.text.trim(),
            'postcode': postcode.text.trim().isEmpty ? null : postcode.text.trim(),
          })
          .eq('id', id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Venue updated ✅')),
        );
      }

      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Edit venue error: $e')),
        );
      }
    }
  }

  Future<void> _deleteVenue(Map<String, dynamic> venue) async {
    final id = venue['id']?.toString();
    final name = (venue['name'] ?? '').toString();

    if (id == null || id.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete venue'),
        content: Text(
          'Are you sure you want to delete "$name"? This cannot be undone.',
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

      await Supabase.instance.client
          .from('venues')
          .delete()
          .eq('id', id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Venue deleted ✅')),
        );
      }

      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete venue error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Venues — ${widget.clubName}'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton(
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
                            hintText: 'Search venues...',
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
                          itemBuilder: (_, i) {
                            final v = _venues[i];
                            final name = (v['name'] ?? '').toString();
                            final isHome = v['is_home_venue'] == true;
                            final town = (v['town_city'] ?? '').toString().trim();
                            final pc = (v['postcode'] ?? '').toString().trim();

                            return ListTile(
                              tileColor: isHome
                                  ? Colors.green.withOpacity(0.08)
                                  : Colors.orange.withOpacity(0.08),
                              title: Text(name),
                              subtitle: Text([
                                if (isHome) 'Home venue' else 'Opponent venue',
                                if (town.isNotEmpty) town,
                                if (pc.isNotEmpty) pc,
                              ].join(' • ')),
                              trailing: _canManage
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Edit venue',
                                          icon: const Icon(Icons.edit_outlined),
                                          onPressed: () => _editVenue(v),
                                        ),
                                        IconButton(
                                          tooltip: 'Delete venue',
                                          icon: const Icon(Icons.delete_outline),
                                          onPressed: () => _deleteVenue(v),
                                        ),
                                      ],
                                    )
                                  : null,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
    );
  }
}


