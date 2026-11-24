import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/venues_screen.dart';
import '../config/green_areas_screen.dart';
import '../competitions/screens/competition_type_list_screen.dart';
import '../members/members_screen.dart';
import '../team/teams_screen.dart';
import 'club_onboarding_repository.dart';
import 'club_onboarding_state.dart';

enum ClubSetupTool { venues, greens, fixtureTypes, members, teams }

Widget clubSetupToolPage(ClubSetupTool tool, String clubId, String clubName) =>
    switch (tool) {
      ClubSetupTool.venues => VenuesScreen(clubId: clubId, clubName: clubName),
      ClubSetupTool.greens => GreenAreasScreen(
        clubId: clubId,
        clubName: clubName,
      ),
      ClubSetupTool.fixtureTypes => CompetitionTypeListScreen(clubId: clubId),
      ClubSetupTool.members => MembersScreen(clubId: clubId),
      ClubSetupTool.teams => TeamsScreen(clubId: clubId, clubName: clubName),
    };

class ClubOnboardingScreen extends StatefulWidget {
  const ClubOnboardingScreen({
    super.key,
    required this.clubId,
    required this.clubName,
    this.accountId,
    this.snapshotLoader,
    this.toolBuilder,
    this.progressLoader,
    this.progressSaver,
  });
  final String clubId, clubName;
  final String? accountId;
  final Future<ClubSetupSnapshot> Function()? snapshotLoader;
  final Widget Function(ClubSetupTool)? toolBuilder;
  final Future<ClubOnboardingProgress> Function()? progressLoader;
  final Future<void> Function(ClubOnboardingProgress)? progressSaver;
  @override
  State<ClubOnboardingScreen> createState() => _ClubOnboardingScreenState();
}

class _ClubOnboardingScreenState extends State<ClubOnboardingScreen> {
  static const titles = [
    'A warm welcome',
    'Your club',
    'Your home venue',
    'Your greens and rinks',
    'When your club is open',
    'The activities you offer',
    'Your people',
    'Your teams',
    'A gentle first check',
    'Your setup summary',
  ];
  static const descriptions = [
    'Let’s get your club ready, one small step at a time. Allow about ten minutes '
        'for the essentials; a large member list or a full season can wait.',
    'You’re setting up the club shown below. We’ll use its existing records, '
        'so you won’t need to enter information twice.',
    'Start with the place where your club plays. Add its name and address and '
        'mark it as a home venue. Opponents’ venues can wait.',
    'Add a green at your home venue and choose the number and names of its rinks. '
        'Use the labels members recognise from the club.',
    'Open your home venue and check Club Start Time and Club End Time. '
        'These describe opening hours; particular booking restrictions belong to Fixture Types.',
    'All choices here can be changed later. Once your general club settings are set up, '
        'you can review and edit all these settings in Fixture Types. '
        'Choose a small set of Fixture Types for the activities your club actually runs. '
        'Each type supplies reusable defaults; a one-off exception belongs on the fixture.',
    'Check your own membership first. You can add or import the rest later. '
        'For a quiet start, choose No invitation emails when importing. '
        'Importing records and inviting people are separate decisions.',
    'If you select teams, add your first team and its pool of players. '
        'If your club is starting with rink bookings, leave this until later.',
    'Before inviting the whole club, walk through the diary with a small pilot group. '
        'Check the correct venue, rink names, activity choices and booking rules. '
        'Any booking, publication or message in the normal app is a real action.',
    'Here is what is saved for your club. This summary checks the essentials; '
        'it does not certify every booking rule or send invitations. '
        'A small pilot is the next step before a wider launch.',
  ];
  ClubSetupSnapshot? _snapshot;
  int _step = 0;
  bool _loading = true, _busy = false, _canExit = false;
  bool _reviewed = false;
  bool _completed = false;
  String? _error;
  final _scroll = ScrollController();
  String get _account =>
      widget.accountId ?? Supabase.instance.client.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_account.isEmpty) throw StateError('Sign in again to continue.');
      final progress =
          await (widget.progressLoader?.call() ??
              ClubOnboardingProgress.load(_account, widget.clubId));
      final snapshot = await _read();
      if (!mounted) return;
      setState(() {
        _step = progress.step;
        _reviewed = progress.reviewed;
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              'We couldn’t check your club just now. Nothing has been changed '
              'by this check. Check your connection and administrator access, then try again.';
        });
      }
    }
  }

  Future<ClubSetupSnapshot> _read() =>
      widget.snapshotLoader?.call() ??
      ClubOnboardingRepository(Supabase.instance.client).load(widget.clubId);

  Future<void> _save(int step, {bool reviewed = false}) async {
    final progress = ClubOnboardingProgress(step: step, reviewed: reviewed);
    if (widget.progressSaver != null) {
      await widget.progressSaver!(progress);
    } else {
      await progress.save(_account, widget.clubId);
    }
  }

  Future<void> _move(int next) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Refresh before showing the final summary; cached success is insufficient.
      final snapshot = next == 9 ? await _read() : _snapshot;
      await _save(next);
      if (mounted) {
        setState(() {
          _step = next;
          _reviewed = false;
          _snapshot = snapshot;
        });
        if (_scroll.hasClients) _scroll.jumpTo(0);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'We couldn’t save or check your progress. '
              'You’re still on this step. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pause({bool finish = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (finish) {
        final latest = await _read();
        if (!latest.essentialsReady) {
          if (mounted) {
            setState(() {
              _snapshot = latest;
              _error =
                  'A few essentials still need attention. You can return to those '
                  'steps or save your place for later.';
            });
          }
          return;
        }
      }
      await _save(_step, reviewed: finish);
      if (!mounted) return;
      if (finish) {
        setState(() {
          _completed = true;
          _reviewed = true;
        });
        return;
      }
      setState(() => _canExit = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Your place could not be saved. '
              'Keep this screen open and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(ClubSetupTool tool) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _save(_step);
      await _read(); // Recheck access before opening a setup tool.
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              widget.toolBuilder?.call(tool) ??
              clubSetupToolPage(tool, widget.clubId, widget.clubName),
        ),
      );
      final snapshot = await _read();
      if (mounted) {
        setState(() {
          _snapshot = snapshot;
          _reviewed = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'We couldn’t check the saved settings. '
              'Your last screen may have saved successfully. Refresh the checks before continuing.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _card(IconData icon, String title, String body, Color colour) => Card(
    color: colour,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(body),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  List<Widget> _status() {
    final s = _snapshot!;
    final checks = <(String, bool, int)>[
      ('Home venue saved', s.homeVenues > 0, 2),
      ('Green with rinks saved', s.greens > 0, 3),
      ('Opening hours saved for each home venue', s.hoursReady, 4),
      ('At least one active Fixture Type', s.fixtureTypes > 0, 5),
    ];
    return [
      for (final c in checks)
        ListTile(
          leading: Icon(
            c.$2 ? Icons.check_circle_outline : Icons.radio_button_unchecked,
          ),
          title: Text(c.$1),
          subtitle: Text(c.$2 ? 'In place' : 'Still to do'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _busy ? null : () => _move(c.$3),
        ),
    ];
  }

  Widget _remainingEssentials() {
    final s = _snapshot!;
    final missing = <(String, int)>[
      if (s.homeVenues == 0) ('Add your home venue', 2),
      if (s.greens == 0) ('Add a green and its rinks', 3),
      if (!s.hoursReady) ('Save your opening hours', 4),
      if (s.fixtureTypes == 0) ('Choose at least one fixture type', 5),
    ];
    return Card(
      color: const Color(0xfffff4da),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${missing.length} things still to do',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'You have reached the end of the guide, but these settings have not '
              'been saved yet. Choose an item below to finish it. '
              'You can also save and leave, then return later.',
            ),
            for (final item in missing)
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _move(item.$2),
                icon: const Icon(Icons.arrow_forward),
                label: Text('Step ${item.$2 + 1}: ${item.$1}'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _completed
      ? Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: const Text('Club setup complete'),
          ),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 64,
                      color: Color(0xff315c47),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Your club setup is complete',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _snapshot!.clubName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Your venue, greens and rinks, opening hours and activity '
                      'choices are in place. You can change them later from your club.',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No invitations have been sent. Adding more members and '
                      'teams can wait until you are ready.',
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.home_outlined),
                      label: const Text('Go to my club'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        )
      : PopScope(
          canPop: _canExit,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && !_busy) _pause();
          },
          child: Scaffold(
            backgroundColor: const Color(0xfff6f8fa),
            bottomNavigationBar: _loading || _snapshot == null
                ? null
                : SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          if (_step == 9 && _snapshot!.essentialsReady)
                            FilledButton(
                              onPressed: _busy
                                  ? null
                                  : () => _pause(finish: true),
                              child: const Text('Finish and leave setup'),
                            ),
                          OutlinedButton(
                            onPressed: _busy ? null : _pause,
                            child: const Text('Save and leave setup'),
                          ),
                        ],
                      ),
                    ),
                  ),
            appBar: AppBar(
              title: const Text('Get your club ready'),
              leading: IconButton(
                tooltip: 'Save and close',
                onPressed: _busy ? null : _pause,
                icon: const Icon(Icons.close),
              ),
            ),
            body: _loading
                ? const Center(child: CircularProgressIndicator())
                : _snapshot == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error ?? 'Your club could not be checked.'),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('Try again'),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() => _canExit = true);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) Navigator.of(context).pop();
                              });
                            },
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    ),
                  )
                : Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 780),
                      child: SingleChildScrollView(
                        controller: _scroll,
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Step ${_step + 1} of 10',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 10),
                            LinearProgressIndicator(
                              value: (_step + 1) / 10,
                              semanticsLabel: 'Setup step ${_step + 1} of 10',
                            ),
                            const SizedBox(height: 24),
                            Text(
                              titles[_step],
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              descriptions[_step],
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                            const SizedBox(height: 20),
                            if (_step == 9 && !_snapshot!.essentialsReady)
                              _remainingEssentials(),
                            _card(
                              Icons.shield_outlined,
                              'You’re in control',
                              'Moving between these steps sends no invitations. Setup tools save '
                                  'settings when you choose Save. You can revisit those settings later.',
                              const Color(0xffe9f3ed),
                            ),
                            if (_step == 0)
                              _card(
                                Icons.schedule,
                                'Make a small start',
                                'Have your club name, home venue, rink labels and opening hours to hand. '
                                    'You can pause at any time; your place is saved for this account and club '
                                    'on this device.',
                                const Color(0xffeaf1fa),
                              ),
                            if (_step == 1)
                              _card(
                                Icons.home_outlined,
                                _snapshot!.clubName,
                                'You have administrator access to this club. If this is not the right '
                                'club, save and close, then select the correct one from My clubs.',
                                Colors.white,
                              ),
                            if (_step == 2 || _step == 4)
                              _tool(
                                ClubSetupTool.venues,
                                _step == 2
                                    ? 'Set up your home venue'
                                    : 'Check your venue opening hours',
                              ),
                            if (_step == 3)
                              _tool(
                                ClubSetupTool.greens,
                                'Set up your greens and rinks',
                              ),
                            if (_step == 5)
                              _tool(
                                ClubSetupTool.fixtureTypes,
                                'Choose your Fixture Types',
                              ),
                            if (_step == 6)
                              _tool(
                                ClubSetupTool.members,
                                'Review your members',
                              ),
                            if (_step == 7)
                              _tool(
                                ClubSetupTool.teams,
                                'Set up your first team',
                              ),
                            if (_step == 8)
                              _card(
                                Icons.lightbulb_outline,
                                'Try it with a few people first',
                                'Ask a Secretary, captain and ordinary member to check their own views. '
                                    'Do not use an administrator’s view to judge what a member can book. '
                                    'Keep invitations limited to your chosen pilot group.',
                                const Color(0xfffff4da),
                              ),
                            if (_step == 9) ...[
                              ..._status(),
                              if (!_snapshot!.essentialsReady)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Text(
                                    'Some essentials still need attention, so setup is not complete. '
                                    'You can save and leave setup using the button below, '
                                    'then return to finish later. This does not close the app.',
                                  ),
                                ),
                              _card(
                                Icons.people_outline,
                                'You can add more later',
                                '${_snapshot!.members} active memberships · ${_snapshot!.teams} active teams. '
                                    'Full membership imports, competitions and a season of fixtures can follow '
                                    'after the essentials.',
                                Colors.white,
                              ),
                              _card(
                                Icons.mail_outline,
                                'Invitations are a separate decision',
                                'Finishing here sends nothing. When you are ready, use the member '
                                    'invitation review to check the recipients and message before sending.',
                                const Color(0xffeaf1fa),
                              ),
                              if (_reviewed && _snapshot!.essentialsReady)
                                const Text(
                                  'You previously reviewed these essentials on this device. '
                                  'The checks above have been refreshed from the club’s saved settings.',
                                ),
                              FilledButton(
                                onPressed: _busy || !_snapshot!.essentialsReady
                                    ? null
                                    : () => _pause(finish: true),
                                child: const Text('Finish setup review'),
                              ),
                            ],
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            if (_busy)
                              const LinearProgressIndicator(
                                semanticsLabel: 'Saving and checking',
                              ),
                            const SizedBox(height: 20),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                if (_step > 0)
                                  OutlinedButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _move(_step - 1),
                                    child: const Text('Back'),
                                  ),
                                if (_step < 9)
                                  FilledButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _move(_step + 1),
                                    child: Text(
                                      _step == 0 ? 'Let’s begin' : 'Continue',
                                    ),
                                  ),
                                TextButton(
                                  onPressed: _busy ? null : _pause,
                                  child: const Text('Save and come back later'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Your place is saved when you continue, go back or close. '
                              'Club settings are shared; your place in this guide stays on this device.',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        );

  Widget _tool(ClubSetupTool tool, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: OutlinedButton.icon(
      onPressed: _busy ? null : () => _open(tool),
      icon: const Icon(Icons.edit_outlined),
      label: Text(label),
    ),
  );
}
