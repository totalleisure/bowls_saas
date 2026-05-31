import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'club_home_screen.dart';
import 'club_dashboard_screen.dart';
import '../../core/utils/date_format.dart';

class MyClubsScreen extends StatefulWidget {
  const MyClubsScreen({super.key});
  @override
  State<MyClubsScreen> createState() => _MyClubsScreenState();
}

class _MyClubsScreenState extends State<MyClubsScreen> {
  bool _loading = true;
  String? _error;
  String? _displayName;
  List<Map<String, dynamic>> _clubs = [];

  bool _isSuperuser = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser!;

      try {
        final superuserRow = await client
            .from('app_superusers')
            .select('user_id')
            .eq('user_id', user.id)
            .maybeSingle()
            .timeout(const Duration(seconds: 10));

        _isSuperuser = superuserRow != null;
      } catch (e) {
        debugPrint('Superuser check failed: $e');
        _isSuperuser = false;
      }

      final profile = await client
          .from('member_profiles')
          .select('id, display_name')
          .eq('user_id', user.id)
          .single();

      _displayName = profile['display_name'] as String;

      // Clubs via memberships
      final myId = (await client.rpc('my_member_profile_id')).toString();

      final memberships = await client
          .from('club_memberships')
          .select(
            'clubs(id, name, branding_set_no, primary_colour, secondary_colour)',
          )
          .eq('member_profile_id', myId)
          .eq('is_active', true);

      _clubs = memberships
          .map<Map<String, dynamic>>((m) => m['clubs'] as Map<String, dynamic>)
          .toList();
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _createClub() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create club'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Club name'),
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

    if (confirmed != true) return;

    final name = controller.text.trim();
    if (name.isEmpty) return;

    try {
      final client = Supabase.instance.client;

      // Create club
      final club = await client
          .from('clubs')
          .insert({'name': name})
          .select('id, name')
          .single();

      // Create membership as admin for current user
      final user = client.auth.currentUser!;
      final profile = await client
          .from('member_profiles')
          .select('id')
          .eq('user_id', user.id)
          .single();

      await client.from('club_memberships').insert({
        'club_id': club['id'],
        'member_profile_id': profile['id'],
        'role': 'admin',
        'is_active': true,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Created club: ${club['name']} ✅')),
        );
      }

      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Create club error: $e')));
      }
    }
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My clubs'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _signOut, icon: const Icon(Icons.logout)),
        ],
      ),
      floatingActionButton: _isSuperuser
          ? FloatingActionButton(
              onPressed: _createClub,
              child: const Icon(Icons.add),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Hello $_displayName',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                if (_clubs.isEmpty)
                  const Text('No clubs yet. Tap + to create one.'),
                for (final c in _clubs)
                  Card(
                    child: ListTile(
                      title: Text(c['name'] as String),
                      subtitle: Text('Club ID: ${c['id']}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        final clubId = c['id'].toString();
                        final clubName = c['name'] as String;

                        final prefs = await SharedPreferences.getInstance();

                        await prefs.setString('last_club_id', clubId);
                        await prefs.setInt(
                          'last_branding_set_no',
                          int.tryParse('${c['branding_set_no'] ?? 0}') ?? 0,
                        );

                        await prefs.setString(
                          'last_primary_colour',
                          c['primary_colour']?.toString() ?? '',
                        );

                        await prefs.setString(
                          'last_secondary_colour',
                          c['secondary_colour']?.toString() ?? '',
                        );

                        final client = Supabase.instance.client;
                        final myId = (await client.rpc(
                          'my_member_profile_id',
                        )).toString();

                        // 1) RSVP / unpublished items
                        final fixtures = await client
                            .from('fixtures')
                            .select('id, start_at, ts:team_selections(status)')
                            .eq('club_id', clubId)
                            .gte(
                              'start_at',
                              DateTime.now().toUtc().toIso8601String(),
                            );

                        final fixturesList = List<Map<String, dynamic>>.from(
                          fixtures,
                        );

                        final hasRsvpItems = fixturesList.any((f) {
                          final ts = f['ts'];
                          if (ts == null) return true;
                          if (ts is List && ts.isEmpty) return true;
                          if (ts is List)
                            return ts.first?['status']?.toString() !=
                                'published';
                          return (ts as Map?)?['status']?.toString() !=
                              'published';
                        });

                        // 2) Pending acceptance items
                        final needs = await client
                            .from('team_selection_members')
                            .select(
                              'team_selections(status, fixture:fixtures(club_id))',
                            )
                            .eq('member_profile_id', myId)
                            .eq('acceptance', 'pending');

                        final needsList = List<Map<String, dynamic>>.from(
                          needs,
                        );

                        final hasAcceptanceItems = needsList.any((r) {
                          final ts =
                              r['team_selections'] as Map<String, dynamic>?;
                          if (ts?['status']?.toString() != 'published')
                            return false;
                          final fx = ts?['fixture'] as Map<String, dynamic>?;
                          return fx?['club_id']?.toString() == clubId;
                        });

                        // 3) Accepted & upcoming items  <-- this is the missing piece
                        final accepted = await client
                            .from('team_selection_members')
                            .select(
                              'team_selections!inner('
                              '  status, '
                              '  fixture:fixtures!inner('
                              '    id, club_id, start_at'
                              '  )'
                              ')',
                            )
                            .eq('member_profile_id', myId)
                            .eq('acceptance', 'accepted')
                            .eq('team_selections.status', 'published')
                            .eq('team_selections.fixture.club_id', clubId);

                        final nowUtcIso = DateTime.now()
                            .toUtc()
                            .toIso8601String();

                        final acceptedList = List<Map<String, dynamic>>.from(
                          accepted,
                        );

                        final hasAcceptedUpcomingItems = acceptedList.any((r) {
                          final ts =
                              r['team_selections'] as Map<String, dynamic>?;
                          final fx = ts?['fixture'] as Map<String, dynamic>?;
                          if (fx == null) return false;

                          final startAt = fx['start_at']?.toString() ?? '';
                          return startAt.compareTo(nowUtcIso) >= 0;
                        });

                        final shouldShowDashboard =
                            hasRsvpItems ||
                            hasAcceptanceItems ||
                            hasAcceptedUpcomingItems;

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => shouldShowDashboard
                                ? ClubDashboardScreen(
                                    clubId: clubId,
                                    clubName: clubName,
                                  )
                                : ClubHomeScreen(
                                    clubId: clubId,
                                    clubName: clubName,
                                  ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}
