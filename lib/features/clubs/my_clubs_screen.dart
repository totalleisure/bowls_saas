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
  String? _errorTitle;
  String? _displayName;
  List<Map<String, dynamic>> _clubs = [];

  bool _isSuperuser = false;

  int _brandingSetNo = 0;

  @override
  void initState() {
    super.initState();
    _loadRememberedBranding();
    _load();
  }

  bool _looksLikeConnectionError(Object error) {
    final text = error.toString().toLowerCase();

    return text.contains('authretryablefetchexception') ||
        text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('no address associated with hostname') ||
        text.contains('network is unreachable') ||
        text.contains('connection timed out') ||
        text.contains('connection closed') ||
        text.contains('clientexception') ||
        text.contains('semaphore timeout');
  }

  bool _looksLikeTimeout(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('timeout') || text.contains('timed out');
  }

  String _friendlyLoadErrorTitle(Object error) {
    if (_looksLikeConnectionError(error) || _looksLikeTimeout(error)) {
      return 'Unable to connect';
    }

    return 'Unable to load your clubs';
  }

  String _friendlyLoadError(Object error) {
    if (_looksLikeTimeout(error)) {
      return 'The Bowls Club service is taking longer than expected to '
          'respond. Please wait a moment and tap Retry.';
    }

    if (_looksLikeConnectionError(error)) {
      return 'The app could not contact the Bowls Club service. Your internet '
          'connection may still be working, so please wait a moment and tap '
          'Retry.';
    }

    return 'Your club information could not be loaded. Please tap Retry. '
        'If the problem continues, close and reopen the app.';
  }

  Future<void> _loadOnce() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null) {
      throw Exception('No signed-in user is available.');
    }

    var loadedIsSuperuser = false;

    try {
      final superuserRow = await client
          .from('app_superusers')
          .select('user_id')
          .eq('user_id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      loadedIsSuperuser = superuserRow != null;
    } catch (e) {
      debugPrint('Superuser check failed: $e');

      // A temporary connection failure should retry the whole load rather
      // than silently treating a superuser as an ordinary member.
      if (_looksLikeConnectionError(e) || _looksLikeTimeout(e)) {
        rethrow;
      }
    }

    final profile = await client
        .from('member_profiles')
        .select('id, display_name')
        .eq('user_id', user.id)
        .single()
        .timeout(const Duration(seconds: 15));

    final loadedDisplayName =
        (profile['display_name'] ?? '').toString().trim();

    // Clubs via memberships
    final myId = (await client
            .rpc('my_member_profile_id')
            .timeout(const Duration(seconds: 15)))
        .toString();

    final memberships = await client
        .from('club_memberships')
        .select(
          'clubs(id, name, branding_set_no, primary_colour, secondary_colour)',
        )
        .eq('member_profile_id', myId)
        .eq('is_active', true)
        .timeout(const Duration(seconds: 15));

    final loadedClubs = memberships
        .where((m) => m['clubs'] is Map<String, dynamic>)
        .map<Map<String, dynamic>>(
          (m) => Map<String, dynamic>.from(
            m['clubs'] as Map<String, dynamic>,
          ),
        )
        .toList();

    _isSuperuser = loadedIsSuperuser;
    _displayName = loadedDisplayName;
    _clubs = loadedClubs;
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _errorTitle = null;
      });
    }

    Object? failure;
    StackTrace? failureStack;

    // One quiet automatic retry deals with many short-lived DNS and Wi-Fi
    // interruptions without bothering the member.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _loadOnce();

        if (!mounted) return;

        setState(() {
          _loading = false;
          _error = null;
          _errorTitle = null;
        });
        return;
      } catch (e, stackTrace) {
        failure = e;
        failureStack = stackTrace;

        debugPrint(
          'MyClubsScreen load attempt ${attempt + 1} failed: $e',
        );
        debugPrintStack(stackTrace: stackTrace);

        final canRetry =
            attempt == 0 &&
            (_looksLikeConnectionError(e) || _looksLikeTimeout(e));

        if (!canRetry) break;

        await Future<void>.delayed(const Duration(milliseconds: 900));
      }
    }

    if (!mounted) return;

    final error = failure ?? Exception('Unknown club loading error');

    setState(() {
      _loading = false;
      _errorTitle = _friendlyLoadErrorTitle(error);
      _error = _friendlyLoadError(error);
    });

    if (failureStack != null) {
      debugPrintStack(stackTrace: failureStack);
    }
  }

  Widget _buildLoadErrorCard() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_outlined,
                    size: 52,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _errorTitle ?? 'Unable to load your clubs',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _error ?? 'Please try again.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your sign-in and club information have not been removed.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _blankBackgroundImageForWidth(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = size.width;
    final shortestSide = size.shortestSide;

    const existingBrandingSets = {0, 2};
    final suffix = existingBrandingSets.contains(_brandingSetNo)
        ? _brandingSetNo
        : 0;

    if (width >= 1000) {
      return 'assets/images/blank_bg_desktop_$suffix.png';
    } else if (shortestSide >= 600) {
      return 'assets/images/blank_bg_tablet_$suffix.png';
    } else {
      return 'assets/images/blank_bg_phone_$suffix.png';
    }
  }

  Future<void> _loadRememberedBranding() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
      _brandingSetNo = prefs.getInt('last_branding_set_no') ?? 0;
    });
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
          IconButton(
            tooltip: 'Refresh clubs',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(onPressed: _signOut, icon: const Icon(Icons.logout)),
        ],
      ),
      floatingActionButton: _isSuperuser
          ? FloatingActionButton(
              onPressed: _createClub,
              child: const Icon(Icons.add),
            )
          : null,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              _blankBackgroundImageForWidth(context),
              fit: BoxFit.cover,
            ),
          ),

          _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? _buildLoadErrorCard()
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
                                .select(
                                  'id, start_at, ts:team_selections(status)',
                                )
                                .eq('club_id', clubId)
                                .gte(
                                  'start_at',
                                  DateTime.now().toUtc().toIso8601String(),
                                );

                            final fixturesList =
                                List<Map<String, dynamic>>.from(fixtures);

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
                              final fx =
                                  ts?['fixture'] as Map<String, dynamic>?;
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

                            final acceptedList =
                                List<Map<String, dynamic>>.from(accepted);

                            final hasAcceptedUpcomingItems = acceptedList.any((
                              r,
                            ) {
                              final ts =
                                  r['team_selections'] as Map<String, dynamic>?;
                              final fx =
                                  ts?['fixture'] as Map<String, dynamic>?;
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
        ],
      ),
    );
  }
}
