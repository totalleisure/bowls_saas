import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'secrets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: Secrets.supabaseUrl,
    anonKey: Secrets.supabaseAnonKey,
  );

  runApp(const BowlsApp());
}

class BowlsApp extends StatelessWidget {
  const BowlsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bowls SaaS',
      theme: ThemeData(useMaterial3: true),
      home: const AuthGate()
    );
  }
}

class SupabaseSmokeTest extends StatelessWidget {
  const SupabaseSmokeTest({super.key});

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;

    return Scaffold(
      appBar: AppBar(title: const Text('Bowls SaaS')),
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            try {
              final session = client.auth.currentSession;
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Supabase connection OK ✅')),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Supabase error: $e')),
                );
              }
            }
          },
          child: const Text('Test Supabase connection'),
        ),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) return const AuthScreen();
        return const MyClubsScreen();
      },
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signUp(
        email: _email.text.trim(),
        password: _password.text,
        data: {'display_name': _email.text.trim()},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed up! Now sign in.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign up error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signIn() async {
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign in error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            if (_loading) const CircularProgressIndicator(),
            if (!_loading) ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _signIn,
                      child: const Text('Sign in'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _signUp,
                      child: const Text('Sign up'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class MyDashboardScreen extends StatefulWidget {
  const MyDashboardScreen({super.key});

  @override
  State<MyDashboardScreen> createState() => _MyDashboardScreenState();
}

class _MyDashboardScreenState extends State<MyDashboardScreen> {
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _myClubs = [];
  List<String> _clubIds = [];

  List<Map<String, dynamic>> _toRsvp = [];
  List<Map<String, dynamic>> _needsAcceptance = [];

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
      final myId = (await client.rpc('my_member_profile_id')).toString();

      // 1) My clubs (ids + names)
      final clubsRows = await client
          .from('club_memberships')
          .select('club_id, clubs(name)')
          .eq('member_profile_id', myId)
          .eq('is_active', true);

      _myClubs = List<Map<String, dynamic>>.from(clubsRows);
      _clubIds = _myClubs.map((r) => r['club_id'].toString()).toList();

      // 2a) Fixtures to RSVP (team not published yet)
      // NOTE: PostgREST will likely embed team_selections as an array.
      final fixturesRows = _clubIds.isEmpty
          ? <dynamic>[]
          : await client
              .from('fixtures')
              .select(
                'id, start_at, is_home, section, club_id, '
                'club:clubs(name), '
                'ts:team_selections(status)',
              )
              .inFilter('club_id', _clubIds)
              .gte('start_at', DateTime.now().toUtc().toIso8601String())
              .order('start_at');

      final allFixtures = List<Map<String, dynamic>>.from(fixturesRows);

      // Filter in Dart: include if no selection OR selection status == draft
      _toRsvp = allFixtures.where((f) {
        final ts = f['ts'];
        if (ts == null) return true;
        if (ts is List && ts.isEmpty) return true;
        if (ts is List) {
          final status = ts.first?['status']?.toString();
          return status != 'published';
        }
        // if it comes back as an object (rare), handle too
        final status = (ts as Map?)?['status']?.toString();
        return status != 'published';
      }).toList();

      // 2b) Fixtures needing my acceptance (published + I'm selected + pending)
      final needsRows = await client
          .from('team_selection_members')
          .select(
            'acceptance, role, '
            'team_selections(status, '
            '  fixture:fixtures(id, start_at, is_home, section, club:clubs(name))'
            ')',
          )
          .eq('member_profile_id', myId)
          .eq('acceptance', 'pending');

      final rawNeeds = List<Map<String, dynamic>>.from(needsRows);

      _needsAcceptance = rawNeeds.where((r) {
        final ts = r['team_selections'] as Map<String, dynamic>?;
        return ts?['status']?.toString() == 'published';
      }).toList();

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openFixtureById(String fixtureId) async {
    final client = Supabase.instance.client;

    // Fetch a full fixture record in the shape FixtureDetailsPage expects
    final row = await client
        .from('fixtures')
        .select(
          'id, club_id, '
          'captain_member_profile_id, vice_captain_member_profile_id, '
          'start_at, is_home, section, rinks_required, players_per_rink, orientation, '
          'venue:venues!fixtures_venue_id_fkey(name), '
          'opponent_venue:venues!fixtures_opponent_venue_id_fkey(name), '
          'green_areas(name, discipline, orientation_mode), '
          'captain:member_profiles!fixtures_captain_member_profile_id_fkey(display_name), '
          'vice:member_profiles!fixtures_vice_captain_member_profile_id_fkey(display_name)'
        )
        .eq('id', fixtureId)
        .single();

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FixtureDetailsPage(fixture: row)),
    );

    // refresh when returning (acceptance may have changed, etc.)
    await _load();
  }

  Widget _fixtureTile({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My dashboard'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [

                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => MyClubsScreen()),
                        );
                      },
                      icon: const Icon(Icons.home),
                      label: const Text('Choose club (admin area)'),
                    ),
                    const SizedBox(height: 16),

                    const SizedBox(height: 16),
                    Text('Needs your acceptance',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),

                    if (_needsAcceptance.isEmpty)
                      const Text('Nothing waiting for you.')
                    else
                      ..._needsAcceptance.map((r) {
                        final ts = r['team_selections'] as Map<String, dynamic>?;
                        final fx = ts?['fixture'] as Map<String, dynamic>?;
                        final club = fx?['club'] as Map<String, dynamic>?;

                        final clubName = (club?['name'] as String?) ?? '';
                        final when = DateTime.parse(fx?['start_at'] as String).toLocal();
                        final isHome = fx?['is_home'] == true;
                        final section = (fx?['section'] as String?) ?? '';

                        final title = '$clubName • ${isHome ? 'HOME' : 'AWAY'} • $section';
                        final subtitle = when.toString();

                        return _fixtureTile(
                          title: title,
                          subtitle: subtitle,
                          onTap: () => _openFixtureById(fx?['id'] as String),
                        );
                      }),

                    const SizedBox(height: 16),
                    Text('Fixtures to RSVP',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),

                    if (_toRsvp.isEmpty)
                      const Text('No upcoming fixtures to RSVP.')
                    else
                      ..._toRsvp.map((f) {
                        final club = f['club'] as Map<String, dynamic>?;
                        final clubName = (club?['name'] as String?) ?? '';

                        final when = DateTime.parse(f['start_at'] as String).toLocal();
                        final isHome = f['is_home'] == true;
                        final section = (f['section'] as String?) ?? '';

                        final title = '$clubName • ${isHome ? 'HOME' : 'AWAY'} • $section';
                        final subtitle = when.toString();

                        return _fixtureTile(
                          title: title,
                          subtitle: subtitle,
                          onTap: () => _openFixtureById(f['id'] as String),
                        );
                      }),
                  ],
                ),
    );
  }
}

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
          .select('clubs(id, name)')
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Create club error: $e')),
        );
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
      floatingActionButton: FloatingActionButton(
        onPressed: _createClub,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('Hello $_displayName', style: Theme.of(context).textTheme.titleLarge),
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

                            final client = Supabase.instance.client;
                            final myId = (await client.rpc('my_member_profile_id')).toString();

                            // Count: unpublished fixtures (future) for this club
                            final fixtures = await client
                                .from('fixtures')
                                .select('id, ts:team_selections(status)')
                                .eq('club_id', clubId)
                                .gte('start_at', DateTime.now().toUtc().toIso8601String());

                            final fixturesList = List<Map<String, dynamic>>.from(fixtures);

                            final hasRsvpItems = fixturesList.any((f) {
                              final ts = f['ts'];
                              if (ts == null) return true;
                              if (ts is List && ts.isEmpty) return true;
                              if (ts is List) return ts.first?['status']?.toString() != 'published';
                              return (ts as Map?)?['status']?.toString() != 'published';
                            });

                            // Count: pending acceptance for published team selections in this club
                            final needs = await client
                                .from('team_selection_members')
                                .select('team_selections(status, fixture:fixtures(club_id))')
                                .eq('member_profile_id', myId)
                                .eq('acceptance', 'pending');

                            final needsList = List<Map<String, dynamic>>.from(needs);

                            final hasAcceptanceItems = needsList.any((r) {
                              final ts = r['team_selections'] as Map<String, dynamic>?;
                              if (ts?['status']?.toString() != 'published') return false;
                              final fx = ts?['fixture'] as Map<String, dynamic>?;
                              return fx?['club_id']?.toString() == clubId;
                            });

                            final shouldShowDashboard = hasRsvpItems || hasAcceptanceItems;

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => shouldShowDashboard
                                    ? ClubDashboardScreen(clubId: clubId, clubName: clubName)
                                    : ClubHomeScreen(clubId: clubId, clubName: clubName),
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

class ClubDashboardScreen extends StatefulWidget {
  final String clubId;
  final String clubName;

  const ClubDashboardScreen({
    super.key,
    required this.clubId,
    required this.clubName,
  });

  @override
  State<ClubDashboardScreen> createState() => _ClubDashboardScreenState();
}

class _ClubDashboardScreenState extends State<ClubDashboardScreen> {
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _toRsvp = [];
  List<Map<String, dynamic>> _needsAcceptance = [];
  List<Map<String, dynamic>> _upcomingAccepted = [];

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
      final myId = (await client.rpc('my_member_profile_id')).toString();

      // Fixtures to RSVP (unpublished for this club)
      final fixturesRows = await client
          .from('fixtures')
          .select('id, start_at, is_home, section, club_id, ts:team_selections(status)')
          .eq('club_id', widget.clubId)
          .gte('start_at', DateTime.now().toUtc().toIso8601String())
          .order('start_at');

      final allFixtures = List<Map<String, dynamic>>.from(fixturesRows);

      _toRsvp = allFixtures.where((f) {
        final ts = f['ts'];
        if (ts == null) return true;
        if (ts is List && ts.isEmpty) return true;
        if (ts is List) {
          final status = ts.first?['status']?.toString();
          return status != 'published';
        }
        final status = (ts as Map?)?['status']?.toString();
        return status != 'published';
      }).toList();

      // Needs my acceptance (published team + pending) for this club only
      final needsRows = await client
          .from('team_selection_members')
          .select(
            'acceptance, role, team_selections(status, fixture:fixtures(id, club_id, start_at, is_home, section))',
          )
          .eq('member_profile_id', myId)
          .eq('acceptance', 'pending');

      final rawNeeds = List<Map<String, dynamic>>.from(needsRows);

      _needsAcceptance = rawNeeds.where((r) {
        final ts = r['team_selections'] as Map<String, dynamic>?;
        if (ts?['status']?.toString() != 'published') return false;
        final fx = ts?['fixture'] as Map<String, dynamic>?;
        return fx?['club_id']?.toString() == widget.clubId;
      }).toList();

      // 2c) Accepted & upcoming (strict: published + I'm selected + accepted)
      final acceptedRows = await client
          .from('team_selection_members')
          .select(
            'team_selections!inner('
            '  status, '
            '  fixture:fixtures!inner(id, club_id, start_at, is_home, section)'
            ')',
          )
          .eq('member_profile_id', myId)
          .eq('acceptance', 'accepted')
          .eq('team_selections.status', 'published')
          .eq('team_selections.fixture.club_id', widget.clubId);

      final nowUtcIso = DateTime.now().toUtc().toIso8601String();

      final tmp = <Map<String, dynamic>>[];
      for (final r in List<Map<String, dynamic>>.from(acceptedRows)) {
        final ts = r['team_selections'] as Map<String, dynamic>?;
        final fx = ts?['fixture'] as Map<String, dynamic>?;
        if (fx == null) continue;

        // future only
        final startAt = fx['start_at']?.toString() ?? '';
        if (startAt.compareTo(nowUtcIso) < 0) continue;

        tmp.add(fx);
      }

      // sort ascending by start_at
      tmp.sort((a, b) => (a['start_at'] as String).compareTo(b['start_at'] as String));

      _upcomingAccepted = tmp;

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openFixtureById(String fixtureId) async {
    final client = Supabase.instance.client;

    final row = await client
        .from('fixtures')
        .select(
          'id, club_id, captain_member_profile_id, vice_captain_member_profile_id, start_at, is_home, section, rinks_required, players_per_rink, orientation, '
          'venue:venues!fixtures_venue_id_fkey(name), '
          'opponent_venue:venues!fixtures_opponent_venue_id_fkey(name), '
          'green_areas(name, discipline, orientation_mode)',
        )
        .eq('id', fixtureId)
        .single();

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FixtureDetailsPage(fixture: row)),
    );

    await _load();
  }

  Widget _tile(String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.clubName),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ClubHomeScreen(
                              clubId: widget.clubId,
                              clubName: widget.clubName,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.settings),
                      label: const Text('Go to admin'),
                    ),
                    const SizedBox(height: 16),

                    Text('Needs your acceptance',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (_needsAcceptance.isEmpty)
                      const Text('Nothing waiting for you.')
                    else
                      ..._needsAcceptance.map((r) {
                        final ts = r['team_selections'] as Map<String, dynamic>?;
                        final fx = ts?['fixture'] as Map<String, dynamic>?;

                        final when = DateTime.parse(fx?['start_at'] as String).toLocal();
                        final isHome = fx?['is_home'] == true;
                        final section = (fx?['section'] as String?) ?? '';

                        final title = '${isHome ? 'HOME' : 'AWAY'} • $section';
                        final subtitle = when.toString();

                        return _tile(
                          title,
                          subtitle,
                          () => _openFixtureById(fx?['id'] as String),
                        );
                      }),

                    const SizedBox(height: 16),
                    Text('Fixtures to RSVP',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (_toRsvp.isEmpty)
                      const Text('No upcoming fixtures to RSVP.')
                    else
                      ..._toRsvp.map((f) {
                        final when = DateTime.parse(f['start_at'] as String).toLocal();
                        final isHome = f['is_home'] == true;
                        final section = (f['section'] as String?) ?? '';

                        final title = '${isHome ? 'HOME' : 'AWAY'} • $section';
                        final subtitle = when.toString();

                        return _tile(
                          title,
                          subtitle,
                          () => _openFixtureById(f['id'] as String),
                        );
                      }),

                    const SizedBox(height: 16),
                    Text('Accepted & published (upcoming)',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),

                    if (_upcomingAccepted.isEmpty)
                      const Text('No upcoming accepted fixtures.')
                    else
                      ..._upcomingAccepted.map((f) {
                        final when = DateTime.parse(f['start_at'] as String).toLocal();
                        final isHome = f['is_home'] == true;
                        final section = (f['section'] as String?) ?? '';

                        final title = '${isHome ? 'HOME' : 'AWAY'} • $section';
                        final subtitle = when.toString();

                        return Card(
                          color: const Color(0xFFE8F5E9), // soft green
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            title: Text(title),
                            subtitle: Text(subtitle),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openFixtureById(f['id'] as String),
                          ),
                        );
                      }),


                  ],
                ),
    );
  }
}

class ClubHomeScreen extends StatelessWidget {
  final String clubId;
  final String clubName;

  const ClubHomeScreen({
    super.key,
    required this.clubId,
    required this.clubName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(clubName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Club ID: $clubId'),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              title: const Text('Venues'),
              subtitle: const Text('Opponents, addresses, directions'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VenuesScreen(clubId: clubId, clubName: clubName),
                  ),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Greens / Rinks'),
              subtitle: const Text('Indoor/outdoor, rink naming, orientation'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GreenAreasScreen(clubId: clubId, clubName: clubName),
                  ),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Match formats'),
              subtitle: const Text('Pairs, triples, rinks + positions'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MatchFormatsScreen(clubId: clubId, clubName: clubName),
                  ),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Fixtures'),
              subtitle: const Text('Schedule matches + allocate greens'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FixturesScreen(
                      clubId: clubId,
                      clubName: clubName,
                    ),
                  ),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Members'),
              subtitle: const Text('Roster + roles (admin/captain/selector/member)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MembersScreen(clubId: clubId),
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
class MatchFormatsScreen extends StatelessWidget {
  final String clubId;
  final String clubName;

  const MatchFormatsScreen({
    super.key,
    required this.clubId,
    required this.clubName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Match formats')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Match formats for $clubName (to build next).'),
      ),
    );
  }
}

class VenuesScreen extends StatefulWidget {
  final String clubId;
  final String clubName;

  const VenuesScreen({super.key, required this.clubId, required this.clubName});

  @override
  State<VenuesScreen> createState() => _VenuesScreenState();
}

class _VenuesScreenState extends State<VenuesScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _venues = [];

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
      final rows = await Supabase.instance.client
          .from('venues')
          .select('id, name, is_home_venue, town_city, postcode')
          .eq('club_id', widget.clubId)
          .order('name');

      _venues = List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      _error = '$e';
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
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Venue name')),
                TextField(controller: town, decoration: const InputDecoration(labelText: 'Town/City (optional)')),
                TextField(controller: postcode, decoration: const InputDecoration(labelText: 'Postcode (optional)')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Venues — ${widget.clubName}'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createVenue,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : ListView.builder(
                  itemCount: _venues.length,
                  itemBuilder: (_, i) {
                    final v = _venues[i];
                    final name = v['name'] as String;
                    final isHome = v['is_home_venue'] as bool;
                    final town = v['town_city'] as String?;
                    final pc = v['postcode'] as String?;
                    return ListTile(
                      title: Text(name),
                      subtitle: Text([
                        if (isHome) 'Home' else 'Opponent',
                        if (town != null && town.isNotEmpty) town,
                        if (pc != null && pc.isNotEmpty) pc,
                      ].join(' • ')),
                    );
                  },
                ),
    );
  }
}

class GreenAreasScreen extends StatefulWidget {
  final String clubId;
  final String clubName;

  const GreenAreasScreen({super.key, required this.clubId, required this.clubName});

  @override
  State<GreenAreasScreen> createState() => _GreenAreasScreenState();
}

class _GreenAreasScreenState extends State<GreenAreasScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _venues = [];
  List<Map<String, dynamic>> _greenAreas = [];

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

      final venues = await client
          .from('venues')
          .select('id, name')
          .eq('club_id', widget.clubId)
          .eq('is_home_venue', true)
          .order('name');

      final greens = await client
          .from('green_areas')
          .select('id, name, discipline, rink_count, scheme_type, venue_id, orientation_mode, venues(is_home_venue)')
          .eq('club_id', widget.clubId)
          .order('name');

      _venues = List<Map<String, dynamic>>.from(venues);
      _greenAreas = List<Map<String, dynamic>>.from(greens)
          .where((g) => (g['venues']?['is_home'] as bool?) == true)
          .toList();
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createGreenArea() async {
    if (_venues.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a venue first.')),
      );
      return;
    }

    final name = TextEditingController();
    int rinkCount = 6;
    String discipline = 'indoor';
    String schemeType = 'numeric';
    String prefix = '';
    int padding = 0;
    String customLabelsCsv = '';
    String orientationMode = 'not_applicable';
    List<String> allowedOrients = [];
    String venueId = _venues.first['id'] as String;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: const Text('Create green area'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  value: venueId,
                  items: _venues
                      .map<DropdownMenuItem<String>>(
                        (v) => DropdownMenuItem<String>(
                          value: v['id'] as String,
                          child: Text(v['name'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setD(() => venueId = v!),
                  decoration: const InputDecoration(labelText: 'Venue'),
                ),
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Green area name')),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: discipline,
                  items: const [
                    DropdownMenuItem(value: 'indoor', child: Text('Indoor')),
                    DropdownMenuItem(value: 'outdoor', child: Text('Outdoor')),
                  ],
                  onChanged: (v) => setD(() {
                    discipline = v!;
                    // auto-adjust orientation defaults
                    orientationMode = (discipline == 'outdoor') ? 'required' : 'not_applicable';
                    allowedOrients = (discipline == 'outdoor') ? ['north_south'] : [];
                  }),
                  decoration: const InputDecoration(labelText: 'Discipline'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: rinkCount.toString(),
                  decoration: const InputDecoration(labelText: 'Rink count'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => setD(() => rinkCount = int.tryParse(v) ?? rinkCount),
                ),
                const Divider(height: 24),
                DropdownButtonFormField<String>(
                  value: schemeType,
                  items: const [
                    DropdownMenuItem(value: 'numeric', child: Text('Numeric (1..N)')),
                    DropdownMenuItem(value: 'alpha', child: Text('Alpha (A..Z)')),
                    DropdownMenuItem(value: 'custom_list', child: Text('Custom list')),
                  ],
                  onChanged: (v) => setD(() => schemeType = v!),
                  decoration: const InputDecoration(labelText: 'Rink naming scheme'),
                ),
                TextField(
                  decoration: const InputDecoration(labelText: 'Prefix (optional)'),
                  onChanged: (v) => setD(() => prefix = v),
                ),
                TextFormField(
                  initialValue: padding.toString(),
                  decoration: const InputDecoration(labelText: 'Padding (0..6)'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => setD(() => padding = int.tryParse(v) ?? padding),
                ),
                if (schemeType == 'custom_list')
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Custom labels (CSV)',
                      hintText: 'e.g. R1,R2,R3,R4,...',
                    ),
                    onChanged: (v) => setD(() => customLabelsCsv = v),
                  ),
                const Divider(height: 24),
                DropdownButtonFormField<String>(
                  value: orientationMode,
                  items: const [
                    DropdownMenuItem(value: 'not_applicable', child: Text('Not applicable')),
                    DropdownMenuItem(value: 'required', child: Text('Required')),
                    DropdownMenuItem(value: 'optional', child: Text('Optional')),
                  ],
                  onChanged: (v) => setD(() => orientationMode = v!),
                  decoration: const InputDecoration(labelText: 'Outdoor orientation rule'),
                ),
                if (discipline == 'outdoor' && orientationMode != 'not_applicable')
                  Column(
                    children: [
                      CheckboxListTile(
                        value: allowedOrients.contains('north_south'),
                        onChanged: (v) => setD(() {
                          v == true ? allowedOrients.add('north_south') : allowedOrients.remove('north_south');
                        }),
                        title: const Text('North/South'),
                      ),
                      CheckboxListTile(
                        value: allowedOrients.contains('east_west'),
                        onChanged: (v) => setD(() {
                          v == true ? allowedOrients.add('east_west') : allowedOrients.remove('east_west');
                        }),
                        title: const Text('East/West'),
                      ),
                    ],
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

    final greenName = name.text.trim();
    if (greenName.isEmpty) return;

    final customLabels = schemeType == 'custom_list'
        ? customLabelsCsv
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList()
        : null;

    try {
      await Supabase.instance.client.from('green_areas').insert({
        'club_id': widget.clubId,
        'venue_id': venueId,
        'name': greenName,
        'discipline': discipline,
        'rink_count': rinkCount,
        'scheme_type': schemeType,
        'scheme_prefix': prefix,
        'scheme_padding': padding,
        'custom_labels': customLabels,
        'orientation_mode': orientationMode,
        'allowed_orientations': allowedOrients,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Green area created ✅')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Create green area error: $e')));
      }
    }
  }

  String _venueNameFor(String venueId) {
    final v = _venues.firstWhere((x) => x['id'] == venueId, orElse: () => {'name': 'Unknown'});
    return v['name'] as String;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Greens — ${widget.clubName}'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createGreenArea,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : ListView.builder(
                  itemCount: _greenAreas.length,
                  itemBuilder: (_, i) {
                    final g = _greenAreas[i];
                    final name = g['name'] as String;
                    final discipline = g['discipline'] as String;
                    final rinks = g['rink_count'] as int;
                    final scheme = g['scheme_type'] as String;
                    final venue = _venueNameFor(g['venue_id'] as String);
                    final om = g['orientation_mode'] as String;
                    return ListTile(
                      title: Text(name),
                      subtitle: Text('$venue • $discipline • $rinks rinks • $scheme • orient:$om'),
                    );
                  },
                ),
    );
  }
}

class FixturesScreen extends StatefulWidget {
  final String clubId;
  final String clubName;

  const FixturesScreen({
    super.key,
    required this.clubId,
    required this.clubName,
  });

  @override
  State<FixturesScreen> createState() => _FixturesScreenState();
}

class _FixturesScreenState extends State<FixturesScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _fixtures = [];

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
      final rows = await Supabase.instance.client
          .from('fixtures')
          .select(
            'id, club_id, captain_member_profile_id, vice_captain_member_profile_id, start_at, is_home, section, rinks_required, players_per_rink, orientation, '
            'venue:venues!fixtures_venue_id_fkey(name), '
            'opponent_venue:venues!fixtures_opponent_venue_id_fkey(name), '
            'green_areas(name, discipline, orientation_mode)',
          )
          .eq('club_id', widget.clubId)
          .order('start_at');

      _fixtures = List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _createFixture() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateFixturePage(
          clubId: widget.clubId,
          clubName: widget.clubName,
        ),
      ),
    );

    if (created == true) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Fixtures — ${widget.clubName}'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createFixture,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _buildGroupedFixtureList(),
    );
  }

  Widget _buildGroupedFixtureList() {
    if (_fixtures.isEmpty) {
      return const Center(child: Text('No fixtures yet. Tap + to create one.'));
    }

    final Map<String, List<Map<String, dynamic>>> groups = {};

    for (final f in _fixtures) {
      final when = DateTime.parse(f['start_at'] as String).toLocal();
      final key =
          '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';

      groups.putIfAbsent(key, () => []).add(f);
    }

    final keys = groups.keys.toList()..sort();

    return ListView.builder(
      itemCount: keys.length,
      itemBuilder: (_, idx) {
        final dateKey = keys[idx];
        final fixtures = groups[dateKey]!;
        final parts = dateKey.split('-'); // yyyy-mm-dd
        final headerDate = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                _friendlyDate(headerDate),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ...fixtures.map(_fixtureTile).toList(),
          ],
        );
      },
    );
  }

  String _friendlyDate(DateTime d) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${weekdays[d.weekday - 1]} ${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Widget _fixtureTile(Map<String, dynamic> f) {

    final when = DateTime.parse(f['start_at'] as String).toLocal();
    final isHome = f['is_home'] as bool;
    final venue = (f['venue']?['name'] as String?) ?? '';
    final opponent = (f['opponent_venue']?['name'] as String?) ?? '';
    final section = f['section'] as String;
    final rinks = f['rinks_required'] as int;
    final ppr = f['players_per_rink'] as int;
    final orientation = f['orientation'] as String?;
    final ga = f['green_areas'] as Map<String, dynamic>?;
    final greenName = (ga?['name'] as String?) ?? '';
    final discipline = ga?['discipline'] as String?;
    final orientationMode = ga?['orientation_mode'] as String?;

    final showOrientation =
        isHome && discipline == 'outdoor' && orientationMode != 'not_applicable';

    String formatLabel(int p) {
      if (p == 2) return 'Pairs';
      if (p == 3) return 'Triples';
      return 'Rinks';
    }

    return ListTile(
      title: Row(
        children: [
          Expanded(
            child: Text(isHome ? '$venue — $greenName' : venue),
          ),

          const SizedBox(width: 8),
          _Badge(text: isHome ? 'HOME' : 'AWAY'),
        ],
      ),
      subtitle: Text(
        '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}'
        ' • $section • ${formatLabel(ppr)} • $rinks rinks'
        '${showOrientation ? ' • orient: ${orientation ?? 'not set'}' : ''}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FixtureDetailsPage(fixture: f),
          ),
        );
      },
    );
  }

}

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
    final selectedGreen = _greens
        .where((g) => g['id'] == _greenAreaId)
        .cast<Map<String, dynamic>>()
        .toList()
        .cast<Map<String, dynamic>>()
        .firstOrNull;

    final orientationMode =
        selectedGreen != null ? selectedGreen['orientation_mode'] : null;

    final allowedOrients =
        selectedGreen != null ? selectedGreen['allowed_orientations'] : [];

    return Scaffold(
      appBar: AppBar(title: Text('Create Fixture — ${widget.clubName}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ListTile(
              title: const Text('Start time'),
              subtitle: Text(_startAt.toLocal().toString()),
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

                // Reload the venue list for the new mode (home venues vs opponent venues)
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
                onChanged: (v) => setState(() => _greenAreaId = v),
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
              decoration:
                  const InputDecoration(labelText: 'Players per rink'),
              items: const [
                DropdownMenuItem(value: 2, child: Text('Pairs')),
                DropdownMenuItem(value: 3, child: Text('Triples')),
                DropdownMenuItem(value: 4, child: Text('Rinks')),
              ],
              onChanged: (v) => setState(() => _playersPerRink = v!),
            ),
            TextFormField(
              initialValue: _rinksRequired.toString(),
              decoration:
                  const InputDecoration(labelText: 'Rinks required'),
              keyboardType: TextInputType.number,
              onChanged: (v) =>
                  _rinksRequired = int.tryParse(v) ?? _rinksRequired,
            ),
            if (_isHome)
              if (orientationMode == 'required' ||
                  orientationMode == 'optional')
                DropdownButtonFormField<String>(
                  value: _orientation,
                  decoration:
                      const InputDecoration(labelText: 'Orientation'),
                  items: (allowedOrients as List)
                      .map<DropdownMenuItem<String>>(
                        (o) => DropdownMenuItem<String>(
                          value: o as String,
                          child: Text(o),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _orientation = v),
                ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const CircularProgressIndicator()
                  : const Text('Create fixture'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class FixtureDetailsPage extends StatefulWidget {
  final Map<String, dynamic> fixture;

  const FixtureDetailsPage({super.key, required this.fixture});

  @override
  State<FixtureDetailsPage> createState() => _FixtureDetailsPageState();
}

class _FixtureDetailsPageState extends State<FixtureDetailsPage> {
  String? _myRsvp; // 'yes' | 'maybe' | 'no' | null

  String _formatLabel(int p) {
    if (p == 2) return 'Pairs';
    if (p == 3) return 'Triples';
    return 'Rinks';
  }

  @override
  void initState() {
    super.initState();
    _loadMyRsvp();
  }

  Future<void> _setRsvp(String status, String label) async {
    final previous = _myRsvp;

    // Update UI immediately
    setState(() => _myRsvp = status);

    try {
      final client = Supabase.instance.client;
      final fixtureId = widget.fixture['id'] as String;

      final myId = (await client.rpc('my_member_profile_id')).toString();

      await client.from('fixture_rsvps').upsert({
        'fixture_id': fixtureId,
        'member_profile_id': myId,
        'status': status,
        'responded_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'fixture_id,member_profile_id');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('RSVP set to $label')),
      );
    } catch (e) {
      // Revert highlight if DB write fails
      if (mounted) {
        setState(() => _myRsvp = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('RSVP error: $e')),
        );
      }
    
    await _loadMyRsvp();

    }
  }

  Future<void> _loadMyRsvp() async {
    try {
      final client = Supabase.instance.client;
      final fixtureId = widget.fixture['id'] as String;
      final myId = (await client.rpc('my_member_profile_id')).toString();

      final row = await client
          .from('fixture_rsvps')
          .select('status')
          .eq('fixture_id', fixtureId)
          .eq('member_profile_id', myId)
          .maybeSingle();

      if (!mounted) return;
      setState(() => _myRsvp = row?['status'] as String?);
    } catch (_) {
      // ignore load errors for now (no highlight is fine)
    }
  }

  Widget _rsvpChoiceButton(String status, String label) {
    final isSelected = _myRsvp == status;

    return ElevatedButton(
      style: isSelected
          ? ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            )
          : null,
      onPressed: () => _setRsvp(status, label),
      child: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fixture = widget.fixture;

    final when = DateTime.parse(fixture['start_at'] as String).toLocal();

    final venue = (fixture['venue']?['name'] as String?) ?? '';
    final opponent = (fixture['opponent_venue']?['name'] as String?) ?? '';
    final green = (fixture['green_areas']?['name'] as String?) ?? '';

    final isHome = fixture['is_home'] as bool;
    final section = fixture['section'] as String;

    final rinks = fixture['rinks_required'] as int;
    final ppr = fixture['players_per_rink'] as int;

    final orientation = fixture['orientation'] as String?;
    final ga = fixture['green_areas'] as Map<String, dynamic>?;
    final greenDiscipline = ga?['discipline'] as String?;
    final greenOrientationMode = ga?['orientation_mode'] as String?;

    final showOrientation =
        isHome && greenDiscipline == 'outdoor' && greenOrientationMode != 'not_applicable';

    final captainName = (fixture['captain']?['display_name'] as String?) ?? '';
    final viceName = (fixture['vice']?['display_name'] as String?) ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Fixture details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            green.isEmpty ? venue : '$venue — $green',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Badge(text: isHome ? 'HOME' : 'AWAY'),
              if (captainName.isNotEmpty) _Badge(text: 'CAPT: $captainName'),
              if (viceName.isNotEmpty) _Badge(text: 'VICE: $viceName'),

              _Badge(text: section.toUpperCase()),
              _Badge(text: _formatLabel(ppr).toUpperCase()),
              _Badge(text: '$rinks RINKS'),
              if (showOrientation)
                _Badge(text: ('ORIENT: ${orientation ?? 'NOT SET'}').toUpperCase()),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              title: const Text('Start time'),
              subtitle: Text(when.toString()),
            ),
          ),

          SetCaptainSection(fixture: fixture),
          const SizedBox(height: 16),

          const SizedBox(height: 24),
          Text('Your availability', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            children: [
              _rsvpChoiceButton('yes', 'Yes'),
              _rsvpChoiceButton('maybe', 'Maybe'),
              _rsvpChoiceButton('no', 'No'),
            ],
          ),

          const SizedBox(height: 24),
          TeamSection(fixture: fixture),

          const SizedBox(height: 24),
          CaptainViewSection(fixture: fixture),
        ],
      ),
    );
  }
}

class CaptainViewSection extends StatefulWidget {
  final Map<String, dynamic> fixture;
  const CaptainViewSection({super.key, required this.fixture});

  @override
  State<CaptainViewSection> createState() => _CaptainViewSectionState();
}

class _CaptainViewSectionState extends State<CaptainViewSection> {
  bool _loading = true;
  String? _error;

  String? _myProfileId;
  bool _isCaptain = false;

  List<Map<String, dynamic>> _yes = [];
  List<Map<String, dynamic>> _maybe = [];
  List<Map<String, dynamic>> _no = [];
  List<Map<String, dynamic>> _noResponse = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String> _getMyProfileId() async {
    // Calls your existing SQL function: public.my_member_profile_id()
    final res = await Supabase.instance.client.rpc('my_member_profile_id');
    return res.toString(); // uuid returned as string-like
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final fixtureId = widget.fixture['id'] as String;
      final clubId = widget.fixture['club_id'] as String;
      final captainId = widget.fixture['captain_member_profile_id'] as String?;

      final myId = await _getMyProfileId();
      _myProfileId = myId;

      _isCaptain = (captainId != null && captainId == myId);

      if (!_isCaptain) {
        // Not captain: hide details, but don't treat as error.
        setState(() => _loading = false);
        return;
      }

      // 1) Load RSVPs for this fixture
      final rsvpRows = await Supabase.instance.client
          .from('fixture_rsvps')
          .select('status, responded_at, member_profiles(display_name)')
          .eq('fixture_id', fixtureId);

      final rsvps = List<Map<String, dynamic>>.from(rsvpRows);

      // 2) Load all active members in the club (for "no response yet")
      final memberRows = await Supabase.instance.client
          .from('club_memberships')
          .select('member_profile_id, member_profiles(display_name)')
          .eq('club_id', clubId)
          .eq('is_active', true);

      final members = List<Map<String, dynamic>>.from(memberRows);

      // Build a set of member_profile_ids who responded
      final respondedIds = <String>{};
      for (final r in rsvps) {
        // r has member_profiles but not member_profile_id; we need it.
        // Easiest: fetch member_profile_id as well in RSVP query.
      }

      // Re-load RSVPs including member_profile_id (fix above)
      final rsvpRows2 = await Supabase.instance.client
          .from('fixture_rsvps')
          .select('member_profile_id, status, responded_at, member_profiles(display_name)')
          .eq('fixture_id', fixtureId);

      final rsvps2 = List<Map<String, dynamic>>.from(rsvpRows2);

      respondedIds.clear();
      for (final r in rsvps2) {
        respondedIds.add(r['member_profile_id'] as String);
      }

      // Split RSVPs by status
      List<Map<String, dynamic>> byStatus(String s) {
        final rows = rsvps2.where((r) => r['status'] == s).toList();
        rows.sort((a, b) {
          final an = (a['member_profiles']?['display_name'] as String?) ?? '';
          final bn = (b['member_profiles']?['display_name'] as String?) ?? '';
          return an.compareTo(bn);
        });
        return rows;
      }

      final yes = byStatus('yes');
      final maybe = byStatus('maybe');
      final no = byStatus('no');

      // No response list
      final noResp = <Map<String, dynamic>>[];
      for (final m in members) {
        final mpId = m['member_profile_id'] as String;
        if (!respondedIds.contains(mpId)) {
          noResp.add(m);
        }
      }
      noResp.sort((a, b) {
        final an = (a['member_profiles']?['display_name'] as String?) ?? '';
        final bn = (b['member_profiles']?['display_name'] as String?) ?? '';
        return an.compareTo(bn);
      });

      setState(() {
        _yes = yes;
        _maybe = maybe;
        _no = no;
        _noResponse = noResp;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Widget _nameFromRow(Map<String, dynamic> row) {
    final mp = row['member_profiles'] as Map<String, dynamic>?;
    final name = (mp?['display_name'] as String?) ?? '(no name)';
    return Text(name);
  }

  Widget _section(String title, List<Map<String, dynamic>> rows) {
    return ExpansionTile(
      title: Text('$title (${rows.length})'),
      children: rows.isEmpty
          ? [ListTile(title: Text('None'))]
          : rows.map((r) => ListTile(title: _nameFromRow(r))).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Card(
        child: ListTile(
          title: const Text('Captain view error'),
          subtitle: Text(_error!),
          trailing: IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ),
      );
    }

    if (!_isCaptain) {
      return const SizedBox.shrink(); // hide completely
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            ListTile(
              title: const Text('Captain view'),
              subtitle: Text('You are the captain.'),
              trailing: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _load,
              ),
            ),
            _section('Yes', _yes),
            _section('Maybe', _maybe),
            _section('No', _no),
            _section('No response yet', _noResponse),
          ],
        ),
      ),
    );
  }
}

class SetCaptainSection extends StatefulWidget {
  final Map<String, dynamic> fixture;
  const SetCaptainSection({super.key, required this.fixture});

  @override
  State<SetCaptainSection> createState() => _SetCaptainSectionState();
}

class _SetCaptainSectionState extends State<SetCaptainSection> {
  bool _loading = true;
  String? _error;

  bool _isAdmin = false;

  List<Map<String, dynamic>> _members = [];

  String? _selectedCaptainId;
  String? _selectedViceCaptainId;

  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _selectedCaptainId = widget.fixture['captain_member_profile_id'] as String?;
    _selectedViceCaptainId =
        widget.fixture['vice_captain_member_profile_id'] as String?;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      final clubId = widget.fixture['club_id'] as String;
      final fixtureId = widget.fixture['id'] as String;

      // Fetch latest captain + vice from DB
      final fx = await client
          .from('fixtures')
          .select('captain_member_profile_id, vice_captain_member_profile_id')
          .eq('id', fixtureId)
          .single();

      _selectedCaptainId = fx['captain_member_profile_id'] as String?;
      _selectedViceCaptainId = fx['vice_captain_member_profile_id'] as String?;

      // Who am I?
      final myId = (await client.rpc('my_member_profile_id')).toString();

      // Am I admin of this club?
      final cm = await client
          .from('club_memberships')
          .select('role, is_active')
          .eq('club_id', clubId)
          .eq('member_profile_id', myId)
          .maybeSingle();

      _isAdmin = cm != null && (cm['is_active'] == true) && (cm['role'] == 'admin');

      if (!_isAdmin) {
        setState(() => _loading = false);
        return;
      }

      // Load active members
      final rows = await client
          .from('club_memberships')
          .select('member_profile_id, member_profiles(display_name)')
          .eq('club_id', clubId)
          .eq('is_active', true);

      _members = List<Map<String, dynamic>>.from(rows);

      _members.sort((a, b) {
        final an = (a['member_profiles']?['display_name'] as String?) ?? '';
        final bn = (b['member_profiles']?['display_name'] as String?) ?? '';
        return an.compareTo(bn);
      });

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _nameForMemberId(String? id) {
    if (id == null) return 'None';
    final match = _members.where((m) => m['member_profile_id'] == id).toList();
    if (match.isEmpty) return 'Unknown';
    final mp = match.first['member_profiles'] as Map<String, dynamic>?;
    return (mp?['display_name'] as String?) ?? 'Unknown';
    }

  List<DropdownMenuItem<String?>> _dropdownItems() {
    return [
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('None'),
      ),
      ..._members.map<DropdownMenuItem<String?>>((m) {
        final id = m['member_profile_id'] as String;
        final mp = m['member_profiles'] as Map<String, dynamic>?;
        final name = (mp?['display_name'] as String?) ?? '(no name)';
        return DropdownMenuItem<String?>(
          value: id,
          child: Text(name),
        );
      }),
    ];
  }

  Future<void> _saveCaptaincy() async {
    try {
      final client = Supabase.instance.client;
      final fixtureId = widget.fixture['id'] as String;

      final updated = await client
          .from('fixtures')
          .update({
            'captain_member_profile_id': _selectedCaptainId,
            'vice_captain_member_profile_id': _selectedViceCaptainId,
          })
          .eq('id', fixtureId)
          .select('captain_member_profile_id, vice_captain_member_profile_id')
          .single();

      setState(() {
        _selectedCaptainId = updated['captain_member_profile_id'] as String?;
        _selectedViceCaptainId =
            updated['vice_captain_member_profile_id'] as String?;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Captaincy saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Card(
        child: ListTile(
          title: const Text('Captaincy'),
          subtitle: Text(_error!),
          trailing: IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ),
      );
    }

    if (!_isAdmin) return const SizedBox.shrink();

    final captainName = _nameForMemberId(_selectedCaptainId);
    final viceName = _nameForMemberId(_selectedViceCaptainId);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Captaincy', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),

            if (!_editing) ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Captain',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(captainName),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Vice-captain',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(viceName),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => setState(() => _editing = true),
                    child: const Text('Amend'),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: _selectedCaptainId,
                      decoration: const InputDecoration(labelText: 'Captain'),
                      items: _dropdownItems(),
                      onChanged: (v) =>
                          setState(() => _selectedCaptainId = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: _selectedViceCaptainId,
                      decoration:
                          const InputDecoration(labelText: 'Vice-captain'),
                      items: _dropdownItems(),
                      onChanged: (v) =>
                          setState(() => _selectedViceCaptainId = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      await _saveCaptaincy();
                      setState(() => _editing = false);
                    },
                    child: const Text('Save'),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => setState(() => _editing = false),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class MembersScreen extends StatefulWidget {
  final String clubId;
  const MembersScreen({super.key, required this.clubId});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  bool _loading = true;
  String? _error;

  bool _isAdmin = false;

  List<Map<String, dynamic>> _rows = [];

  final _emailCtrl = TextEditingController();
  String _role = 'member';

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

      // Admin check (direct membership lookup, reliable)
      final myId = (await client.rpc('my_member_profile_id')).toString();
      final cm = await client
          .from('club_memberships')
          .select('role, is_active')
          .eq('club_id', widget.clubId)
          .eq('member_profile_id', myId)
          .maybeSingle();

      _isAdmin = cm != null && cm['is_active'] == true && cm['role'] == 'admin';

      final rows = await client
          .from('club_memberships')
          .select('member_profile_id, role, is_active, member_profiles(display_name, phone)')
          .eq('club_id', widget.clubId)
          .order('created_at');

      setState(() {
        _rows = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _addByEmail() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;

    try {
      await Supabase.instance.client.rpc(
        'add_member_to_club_by_email',
        params: {'p_club_id': widget.clubId, 'p_email': email, 'p_role': _role},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added $email as $_role')),
        );
      }
      _emailCtrl.clear();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Add member failed: $e')),
        );
      }
    }
  }

  Future<void> _updateMembership({
    required String memberProfileId,
    required String role,
    required bool isActive,
  }) async {
    try {
      await Supabase.instance.client.rpc(
        'admin_update_membership',
        params: {
          'p_club_id': widget.clubId,
          'p_member_profile_id': memberProfileId,
          'p_role': role,
          'p_is_active': isActive,
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member updated')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Members'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_isAdmin) ...[
                      Text('Add member by email',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _emailCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Member email',
                          hintText: 'e.g. member.name@example.com',
                          helperText: 'They must already have a login (Auth user) in the system',
                        ),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _role,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: const [
                          DropdownMenuItem(value: 'member', child: Text('member')),
                          DropdownMenuItem(value: 'captain', child: Text('captain')),
                          DropdownMenuItem(value: 'selector', child: Text('selector')),
                          DropdownMenuItem(value: 'admin', child: Text('admin')),
                        ],
                        onChanged: (v) => setState(() => _role = v ?? 'member'),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _addByEmail,
                        child: const Text('Add member'),
                      ),
                      const Divider(height: 32),
                    ],
                    Text('Club roster',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ..._rows.map((r) {
                      final mp = r['member_profiles'] as Map<String, dynamic>?;
                      final name = (mp?['display_name'] as String?) ?? '(no name)';
                      final phone = (mp?['phone'] as String?) ?? '';
                      final role = r['role'].toString();
                      final active = r['is_active'] == true;

                      final memberProfileId = r['member_profile_id'].toString();

                      if (!_isAdmin) {
                        return ListTile(
                          title: Text(name),
                          subtitle: Text([
                            role,
                            if (phone.isNotEmpty) phone,
                            active ? 'active' : 'inactive',
                          ].join(' • ')),
                        );
                      }

                      return _EditableMemberRow(
                        name: name,
                        phone: phone,
                        initialRole: role,
                        initialActive: active,
                        onSave: (newRole, newActive) => _updateMembership(
                          memberProfileId: memberProfileId,
                          role: newRole,
                          isActive: newActive,
                        ),
                      );

                      // Admin view: role dropdown + active toggle + save
                      String pendingRole = role;
                      bool pendingActive = active;

                      return StatefulBuilder(
                        builder: (context, setRowState) {
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                dense: true,
                                title: Text(name),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (phone.isNotEmpty) Text(phone),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: DropdownButtonFormField<String>(
                                            value: pendingRole,
                                            decoration: const InputDecoration(
                                              labelText: 'Role',
                                              isDense: true,
                                            ),
                                            items: const [
                                              DropdownMenuItem(value: 'member', child: Text('member')),
                                              DropdownMenuItem(value: 'captain', child: Text('captain')),
                                              DropdownMenuItem(value: 'selector', child: Text('selector')),
                                              DropdownMenuItem(value: 'admin', child: Text('admin')),
                                            ],
                                            onChanged: (v) => setRowState(() {
                                              pendingRole = v ?? pendingRole;
                                            }),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Column(
                                          children: [
                                            const Text('Active', style: TextStyle(fontSize: 12)),
                                            Switch(
                                              value: pendingActive,
                                              onChanged: (v) => setRowState(() {
                                                pendingActive = v;
                                              }),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.save),
                                  tooltip: 'Save',
                                  onPressed: () => _updateMembership(
                                    memberProfileId: memberProfileId,
                                    role: pendingRole,
                                    isActive: pendingActive,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    }),
                  ],
                ),
    );
  }
}

class _EditableMemberRow extends StatefulWidget {
  final String name;
  final String phone;
  final String initialRole;
  final bool initialActive;
  final Future<void> Function(String role, bool active) onSave;

  const _EditableMemberRow({
    required this.name,
    required this.phone,
    required this.initialRole,
    required this.initialActive,
    required this.onSave,
  });

  @override
  State<_EditableMemberRow> createState() => _EditableMemberRowState();
}

class _EditableMemberRowState extends State<_EditableMemberRow> {
  late String _role;
  late bool _active;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _role = widget.initialRole;
    _active = widget.initialActive;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        dense: true,
        title: Text(widget.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.phone.isNotEmpty) Text(widget.phone),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _role,
                    decoration: const InputDecoration(labelText: 'Role', isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'member', child: Text('member')),
                      DropdownMenuItem(value: 'captain', child: Text('captain')),
                      DropdownMenuItem(value: 'selector', child: Text('selector')),
                      DropdownMenuItem(value: 'admin', child: Text('admin')),
                    ],
                    onChanged: _saving ? null : (v) => setState(() => _role = v ?? _role),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  children: [
                    const Text('Active', style: TextStyle(fontSize: 12)),
                    Switch(
                      value: _active,
                      onChanged: _saving ? null : (v) => setState(() => _active = v),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        trailing: _saving
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : IconButton(
                icon: const Icon(Icons.save),
                tooltip: 'Save',
                onPressed: () async {
                  setState(() => _saving = true);
                  await widget.onSave(_role, _active);
                  if (mounted) setState(() => _saving = false);
                },
              ),
      ),
    );
  }
}

class TeamSection extends StatefulWidget {
  final Map<String, dynamic> fixture;
  const TeamSection({super.key, required this.fixture});

  @override
  State<TeamSection> createState() => _TeamSectionState();
}

class _TeamSectionState extends State<TeamSection> {
  bool _loading = true;
  String? _error;

  String? _selectionId;
  String _status = 'draft';

  bool _canManage = false;

  String? _myProfileId;

  List<Map<String, dynamic>> _players = [];
  List<Map<String, dynamic>> _reserves = [];

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

      final fixtureId = widget.fixture['id'] as String;
      final clubId = widget.fixture['club_id'] as String;

      // who am I?
      final myId = (await client.rpc('my_member_profile_id')).toString();
      _myProfileId = myId;

      // can I manage? (admin/selector/captain in this club)
      final cm = await client
          .from('club_memberships')
          .select('role, is_active')
          .eq('club_id', clubId)
          .eq('member_profile_id', myId)
          .maybeSingle();

      final role = cm?['role']?.toString();
      final active = cm?['is_active'] == true;
      _canManage = active && (role == 'admin' || role == 'selector' || role == 'captain');

      // load selection header (may not exist yet)
      final sel = await client
          .from('team_selections')
          .select('id, status')
          .eq('fixture_id', fixtureId)
          .maybeSingle();

      if (sel == null) {
        // No selection yet
        setState(() {
          _selectionId = null;
          _status = 'draft';
          _players = [];
          _reserves = [];
          _loading = false;
        });
        return;
      }

      _selectionId = sel['id'] as String;
      _status = sel['status'].toString();

      // load members of selection
      final rows = await client
          .from('team_selection_members')
          .select('member_profile_id, role, acceptance, responded_at, member_profiles(display_name, phone)')
          .eq('team_selection_id', _selectionId!)
          .order('created_at');

      final all = List<Map<String, dynamic>>.from(rows);

      final players = all.where((r) => r['role'] == 'player').toList();
      final reserves = all.where((r) => r['role'] == 'reserve').toList();

      setState(() {
        _players = players;
        _reserves = reserves;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  bool _amISelected() {
    if (_myProfileId == null) return false;
    final all = [..._players, ..._reserves];
    return all.any((r) => r['member_profile_id'] == _myProfileId);
  }

  String? _myAcceptance() {
    if (_myProfileId == null) return null;
    final all = [..._players, ..._reserves];
    final me = all.where((r) => r['member_profile_id'] == _myProfileId).toList();
    if (me.isEmpty) return null;
    return me.first['acceptance']?.toString();
  }

  Future<void> _setAcceptance(String acceptance) async {
    try {
      final client = Supabase.instance.client;
      if (_selectionId == null || _myProfileId == null) return;

      await client
          .from('team_selection_members')
          .update({
            'acceptance': acceptance,
            'responded_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('team_selection_id', _selectionId!)
          .eq('member_profile_id', _myProfileId!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Set acceptance: $acceptance')),
        );
      }

      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Acceptance error: $e')),
        );
      }
    }
  }

  Widget _memberRow(Map<String, dynamic> r) {
    final mp = r['member_profiles'] as Map<String, dynamic>?;
    final name = (mp?['display_name'] as String?) ?? '(no name)';
    final acceptance = (r['acceptance']?.toString() ?? 'pending');

    Color bgColor;
    if (acceptance == 'accepted') {
      bgColor = const Color(0xFFE8F5E9); // soft green
    } else if (acceptance == 'declined') {
      bgColor = const Color(0xFFFFEBEE); // soft red
    } else {
      bgColor = const Color(0xFFFFF8E1); // soft amber
    }

    return Card(
      color: bgColor,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(acceptance),
      ),
    );

  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Card(
        child: ListTile(
          title: const Text('Team'),
          subtitle: Text(_error!),
          trailing: IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ),
      );
    }

    final hasSelection = _selectionId != null;
    final isPublished = _status == 'published';
    final iAmSelected = _amISelected();
    final myAcc = _myAcceptance();

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            ListTile(
              title: const Text('Team'),
              subtitle: Text(
                hasSelection
                    ? (isPublished ? 'Published' : 'Draft (not published)')
                    : 'No team selected yet',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _load,
                  ),
                  if (_canManage)
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ManageTeamScreen(fixture: widget.fixture),
                          ),
                        );
                        await _load();
                      },
                    ),
                ],
              ),
            ),

            if (hasSelection) ...[
              ExpansionTile(
                title: Text('Players (${_players.length})'),
                initiallyExpanded: true,
                children: _players.isEmpty
                    ? [ListTile(title: Text('None'))]
                    : _players.map(_memberRow).toList(),
              ),
              ExpansionTile(
                title: Text('Reserves (${_reserves.length}/3)'),
                children: _reserves.isEmpty
                    ? [ListTile(title: Text('None'))]
                    : _reserves.map(_memberRow).toList(),
              ),

              if (isPublished && iAmSelected) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your confirmation',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text('Current: ${myAcc ?? 'pending'}'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        children: [
                          ElevatedButton(
                            onPressed: () => _setAcceptance('accepted'),
                            child: const Text('Accept'),
                          ),
                          ElevatedButton(
                            onPressed: () => _setAcceptance('declined'),
                            child: const Text('Decline'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class ManageTeamScreen extends StatefulWidget {
  final Map<String, dynamic> fixture;
  const ManageTeamScreen({super.key, required this.fixture});

  @override
  State<ManageTeamScreen> createState() => _ManageTeamScreenState();
}

class _ManageTeamScreenState extends State<ManageTeamScreen> {
  bool _loading = true;
  String? _error;

  String? _selectionId;
  String _status = 'draft';

  List<Map<String, dynamic>> _pool = [];      // RSVP yes/maybe
  List<Map<String, dynamic>> _selected = [];  // team_selection_members

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _buildPublishedTeamMessage() {
    final fixture = widget.fixture;

    final when = DateTime.parse(fixture['start_at'] as String).toLocal();
    final isHome = fixture['is_home'] as bool;

    final venue = (fixture['venue']?['name'] as String?) ?? '';    
    final opponent = (fixture['opponent_name'] as String?) ?? ''; // if you have it; else blank
    final homeAway = isHome ? 'Home' : 'Away';

    String fmtName(Map<String, dynamic> r) {
      final mp = r['member_profiles'] as Map<String, dynamic>?;
      return (mp?['display_name'] as String?) ?? '(no name)';
    }

    final players = _selected.where((s) => s['role'] == 'player').toList();
    final reserves = _selected.where((s) => s['role'] == 'reserve').toList();

    String line(Map<String, dynamic> r, int i) {
      final name = fmtName(r);
      final acc = (r['acceptance']?.toString() ?? 'pending').toUpperCase();
      return '${i + 1}. $name ($acc)';
    }

    final sb = StringBuffer();
    sb.writeln('Team published');
    sb.writeln('${when.toString()} • $homeAway');
    if (venue.isNotEmpty) sb.writeln('Venue: $venue');
    if (!isHome && opponent.isNotEmpty) sb.writeln('Opponent: $opponent');
    sb.writeln('');

    sb.writeln('Players:');
    for (var i = 0; i < players.length; i++) {
      sb.writeln(line(players[i], i));
    }

    sb.writeln('');
    sb.writeln('Reserves:');
    if (reserves.isEmpty) {
      sb.writeln('None');
    } else {
      for (var i = 0; i < reserves.length; i++) {
        sb.writeln('R${i + 1}. ${fmtName(reserves[i])} (${(reserves[i]['acceptance']?.toString() ?? 'pending').toUpperCase()})');
      }
    }

    sb.writeln('');
    sb.writeln('Please confirm acceptance in the app.');

    return sb.toString();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      final fixtureId = widget.fixture['id'] as String;

      // get or create selection
      final existing = await client
          .from('team_selections')
          .select('id, status')
          .eq('fixture_id', fixtureId)
          .maybeSingle();

      if (existing == null) {
        final created = await client
            .from('team_selections')
            .insert({'fixture_id': fixtureId})
            .select('id, status')
            .single();

        _selectionId = created['id'] as String;
        _status = created['status'].toString();
      } else {
        _selectionId = existing['id'] as String;
        _status = existing['status'].toString();
      }

      // pool: RSVPs yes/maybe
      final poolRows = await client
          .from('fixture_rsvps')
          .select('member_profile_id, status, member_profiles(display_name, phone)')
          .eq('fixture_id', fixtureId)
          .inFilter('status', ['yes', 'maybe']);

      _pool = List<Map<String, dynamic>>.from(poolRows);

      // current selected
      final selRows = await client
          .from('team_selection_members')
          .select('member_profile_id, role, acceptance, member_profiles(display_name, phone)')
          .eq('team_selection_id', _selectionId!)
          .order('created_at');

      _selected = List<Map<String, dynamic>>.from(selRows);

      // sort pool by name
      _pool.sort((a, b) {
        final an = (a['member_profiles']?['display_name'] as String?) ?? '';
        final bn = (b['member_profiles']?['display_name'] as String?) ?? '';
        return an.compareTo(bn);
      });

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? _selectedRowFor(String memberId) {
    final rows = _selected.where((r) => r['member_profile_id'] == memberId).toList();
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> _togglePlayer(String memberId) async {
    if (_selectionId == null) return;
    final client = Supabase.instance.client;

    final existing = _selectedRowFor(memberId);
    try {
      if (existing == null) {
        await client.from('team_selection_members').insert({
          'team_selection_id': _selectionId,
          'member_profile_id': memberId,
          'role': 'player',
          'acceptance': 'pending',
        });
      } else {
        await client
            .from('team_selection_members')
            .delete()
            .eq('team_selection_id', _selectionId!)
            .eq('member_profile_id', memberId);
      }

      await _load();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update team error: $e')),
      );
    }
  }

  Future<void> _setRole(String memberId, String role) async {
    if (_selectionId == null) return;
    try {
      await Supabase.instance.client
          .from('team_selection_members')
          .update({'role': role})
          .eq('team_selection_id', _selectionId!)
          .eq('member_profile_id', memberId);

      await _load();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Set role error: $e')),
      );
    }
  }

  Future<void> _publish() async {
    if (_selectionId == null) return;
    try {
      final client = Supabase.instance.client;
      final myId = (await client.rpc('my_member_profile_id')).toString();

      await client
          .from('team_selections')
          .update({
            'status': 'published',
            'published_at': DateTime.now().toUtc().toIso8601String(),
            'published_by_member_profile_id': myId,
          })
          .eq('id', _selectionId!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Team published')),
        );
      }
      await _load();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Publish error: $e')),
      );
    }
  }

  Widget _poolRow(Map<String, dynamic> r) {
    final memberId = r['member_profile_id'] as String;
    final mp = r['member_profiles'] as Map<String, dynamic>?;
    final name = (mp?['display_name'] as String?) ?? '(no name)';
    final rsvp = r['status']?.toString() ?? '';

    final sel = _selectedRowFor(memberId);
    final isSelected = sel != null;
    final role = sel?['role']?.toString();

    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: isSelected ? const Icon(Icons.check, size: 18) : const SizedBox(width: 18),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(isSelected ? '${role ?? ''} • RSVP: $rsvp' : 'RSVP: $rsvp'),
      onTap: () => _togglePlayer(memberId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPublished = _status == 'published';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage team'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: ListTile(
                        title: Text(isPublished ? 'Status: Published' : 'Status: Draft'),
                        subtitle: const Text('Tap members to add/remove as players.'),
                      ),
                    ),

                    if (!isPublished) ...[
                      ElevatedButton(
                        onPressed: _publish,
                        child: const Text('Publish team'),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final msg = _buildPublishedTeamMessage();
                                await Clipboard.setData(ClipboardData(text: msg));
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Team message copied')),
                                  );
                                }
                              },
                              icon: const Icon(Icons.copy),
                              label: const Text('Copy'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                final msg = _buildPublishedTeamMessage();
                                Share.share(msg);
                              },
                              icon: const Icon(Icons.share),
                              label: const Text('Share'),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 16),
                    Text('Selected',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),

                    if (_selected.isEmpty)
                      const Text('No one selected yet.')
                    else
                      ..._selected.map((s) {
                        final memberId = s['member_profile_id'] as String;
                        final mp = s['member_profiles'] as Map<String, dynamic>?;
                        final name = (mp?['display_name'] as String?) ?? '(no name)';
                        final role = s['role']?.toString() ?? 'player';
                        final acceptance = s['acceptance']?.toString() ?? 'pending';

                        Color bgColor;
                        if (acceptance == 'accepted') {
                          bgColor = const Color(0xFFE8F5E9); // soft green
                        } else if (acceptance == 'declined') {
                          bgColor = const Color(0xFFFFEBEE); // soft red
                        } else {
                          bgColor = const Color(0xFFFFF8E1); // soft amber
                        }

                        return Card(
                          color: bgColor,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            title: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text('Role: $role • $acceptance'),
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) => _setRole(memberId, v),
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'player', child: Text('Make player')),
                                PopupMenuItem(value: 'reserve', child: Text('Make reserve')),
                              ],
                            ),
                          ),
                        );
                      }
                    ),
                    const SizedBox(height: 16),
                    Text('RSVP pool (Yes/Maybe)',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ..._pool.map(_poolRow),
                  ],
                ),
    );
  }
}
