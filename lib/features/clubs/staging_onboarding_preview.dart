import 'club_online_scaffold.dart';
// Offline test harness, reachable only from the staging entrypoint's preview mode.
// No Supabase client, credentials, email sender or database writes are used here.
import 'package:flutter/material.dart';
import 'club_onboarding_screen.dart';
import 'club_onboarding_state.dart';
import 'club_registration_policy.dart';
import 'onboarding_activities_screen.dart';
import 'onboarding_member_import.dart';
import 'onboarding_members_screen.dart';

enum StagingClubScenario { fictional, notFound, duplicate, unavailable }

class StagingOnboardingPreview extends StatefulWidget {
  const StagingOnboardingPreview({super.key});
  @override
  State<StagingOnboardingPreview> createState() =>
      _StagingOnboardingPreviewState();
}

class _StagingOnboardingPreviewState extends State<StagingOnboardingPreview> {
  final _name = TextEditingController(text: 'Test Bowls Club');
  final _address = TextEditingController(text: '1 Example Green, Test Town');
  final _email = TextEditingController(text: 'secretary@example.invalid');
  final _phone = TextEditingController(text: '02000000000');
  final _code = TextEditingController();
  final _reason = TextEditingController();
  final _secretaryFirst = TextEditingController(text: 'Test');
  final _secretarySurname = TextEditingController(text: 'Secretary');
  String? _provisionedFor;
  List<OnboardingMember> _roster = [];
  Set<String> _activities = {
    for (final activity in onboardingActivities) activity.id,
  };
  StagingClubScenario _scenario = StagingClubScenario.fictional;
  bool _codeIssued = false, _verified = false, _manualRequested = false;
  bool _authority = false;
  String? _message;
  ManualClubDecision _manual = ManualClubDecision.pending;
  ClubOnboardingProgress _progress = const ClubOnboardingProgress();
  int _venues = 0, _greens = 0, _types = 0, _teams = 0;
  bool _hours = false;
  final _savedToolValues = <ClubSetupTool, String>{};
  final _snapshots = <String>[];

  @override
  void dispose() {
    for (final c in [
      _name,
      _address,
      _email,
      _phone,
      _code,
      _reason,
      _secretaryFirst,
      _secretarySurname,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  ClubRegistrationDecision get _decision => clubRegistrationDecision(
    lookup: switch (_scenario) {
      StagingClubScenario.notFound => ClubLookupResult.notFound,
      StagingClubScenario.unavailable => ClubLookupResult.unavailable,
      _ => ClubLookupResult.found,
    },
    duplicate: _scenario == StagingClubScenario.duplicate,
    emailVerified: _verified,
    manual: _manual,
  );

  void _resetVerification() => setState(() {
    _codeIssued = false;
    _verified = false;
    _code.clear();
    _message = null;
    _manualRequested = false;
    _manual = ManualClubDecision.pending;
    _reason.clear();
  });

  void _requestCode() {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim())) {
      setState(() => _message = 'Enter an email address with a valid format.');
      return;
    }
    setState(() {
      _codeIssued = true;
      _verified = false;
      _code.clear();
      _message = 'Test code generated. No email has been sent.';
    });
  }

  void _verifyCode() => setState(() {
    _verified = _codeIssued && _code.text.trim() == '246810';
    _message = _verified
        ? 'Email verification simulated successfully.'
        : 'That test code is not correct. Please try again.';
  });

  void _review(bool approve) {
    if (_reason.text.trim().isEmpty) {
      setState(() => _message = 'Enter a test reviewer note first.');
      return;
    }
    setState(() {
      _manual = approve
          ? ManualClubDecision.approved
          : ManualClubDecision.declined;
      _snapshots.add(
        '${approve ? 'Approved' : 'Declined'}: ${_reason.text.trim()}',
      );
      _message =
          'Manual ${approve ? 'approval' : 'decline'} simulated. No real application was changed.';
    });
  }

  Future<void> _begin({int? step}) async {
    if (_decision != ClubRegistrationDecision.proceed ||
        !_authority ||
        _name.text.trim().isEmpty ||
        _address.text.trim().isEmpty ||
        _secretaryFirst.text.trim().isEmpty ||
        _secretarySurname.text.trim().isEmpty ||
        _phone.text.trim().isEmpty) {
      setState(
        () => _message =
            'Complete the club and contact details and the verification checks first.',
      );
      return;
    }
    final key = '${_name.text.trim()}|${_email.text.trim().toLowerCase()}';
    if (_provisionedFor != key) {
      _provisionedFor = key;
      _roster = [
        OnboardingMember(
          firstName: _secretaryFirst.text.trim(),
          surname: _secretarySurname.text.trim(),
          email: _email.text.trim(),
          phone: _phone.text.trim(),
          role: 'admin',
          active: true,
        ),
      ];
      _activities = {for (final activity in onboardingActivities) activity.id};
      _venues = 0;
      _greens = 0;
      _types = 0;
      _teams = 0;
      _hours = false;
      _progress = const ClubOnboardingProgress();
      _savedToolValues.clear();
    }
    if (step != null) {
      _progress = ClubOnboardingProgress(
        step: step,
        reviewed: _progress.reviewed,
      );
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClubOnboardingScreen(
          clubId: 'offline-preview',
          clubName: _name.text.trim(),
          accountId: 'offline-tester',
          snapshotLoader: () async => ClubSetupSnapshot(
            clubName: _name.text.trim(),
            homeVenues: _venues,
            greens: _greens,
            hoursReady: _hours,
            fixtureTypes: _types,
            members: _roster.where((m) => m.active).length,
            teams: _teams,
          ),
          progressLoader: () async => _progress,
          progressSaver: (value) async {
            _progress = value;
          },
          toolBuilder: (tool) {
            if (tool == ClubSetupTool.fixtureTypes) {
              return OnboardingActivitiesScreen(
                initial: _activities,
                onSave: (choices) {
                  _activities = choices;
                  _types = choices.length;
                },
              );
            }
            if (tool == ClubSetupTool.members) {
              return OnboardingMembersScreen(
                initial: _roster,
                onSave: (members) {
                  _roster = members;
                },
              );
            }
            return _PreviewSetupTool(
              tool: tool,
              initial:
                  _savedToolValues[tool] ??
                  switch (tool) {
                    ClubSetupTool.venues => '${_name.text.trim()} home venue',
                    ClubSetupTool.greens => 'Main green — rinks 1 to 6',
                    ClubSetupTool.teams => 'Club team',
                    _ => 'Test setup',
                  },
              onSave: (value) {
                _savedToolValues[tool] = value;
                switch (tool) {
                  case ClubSetupTool.venues:
                    _venues = 1;
                    _hours = true;
                  case ClubSetupTool.greens:
                    _greens = 1;
                  case ClubSetupTool.fixtureTypes:
                    _types = 1;
                  case ClubSetupTool.members:
                    break;
                  case ClubSetupTool.teams:
                    _teams = 1;
                }
              },
            );
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _clubHome() {
    final missing = <(String, int)>[
      if (_venues == 0) ('Add your home venue', 2),
      if (_greens == 0) ('Add a green and its rinks', 3),
      if (!_hours) ('Save your opening hours', 4),
      if (_types == 0) ('Choose at least one fixture type', 5),
    ];
    final complete = missing.isEmpty && _progress.reviewed;
    return ClubOnlineScaffold(
      appBar: AppBar(title: Text(_name.text.trim())),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'TEST CLUB · rehearsal only',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  'Welcome to ${_name.text.trim()}',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text('${_roster.first.name} · Secretary and administrator'),
                const SizedBox(height: 16),
                Card(
                  color: complete
                      ? const Color(0xffe9f3ed)
                      : const Color(0xfffff4da),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          complete
                              ? 'Your club setup is complete'
                              : missing.isEmpty
                              ? 'Your settings are saved — review and finish'
                              : '${missing.length} things still to do',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          complete
                              ? 'You are now in your test club. There is no need to repeat registration.'
                              : 'Your test entries are kept while the rehearsal is open. '
                                    'Use the buttons below to pick up exactly where needed.',
                        ),
                        for (final item in missing)
                          OutlinedButton(
                            onPressed: () => _begin(step: item.$2),
                            child: Text('Step ${item.$2 + 1}: ${item.$1}'),
                          ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => _begin(
                            step: missing.isEmpty ? 9 : _progress.step,
                          ),
                          child: Text(
                            complete
                                ? 'Review club setup'
                                : missing.isEmpty
                                ? 'Review and finish setup'
                                : 'Continue saved setup',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Your club at a glance',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  'Home venues: $_venues · Greens: $_greens · '
                  'Opening hours: ${_hours ? 'saved' : 'not saved'}',
                ),
                if (_savedToolValues[ClubSetupTool.venues]
                    case final String venue)
                  Text('Venue: $venue'),
                if (_savedToolValues[ClubSetupTool.greens]
                    case final String greens)
                  Text('Greens and rinks: $greens'),
                const SizedBox(height: 12),
                Text('Activities selected: $_types'),
                for (final activity in onboardingActivities.where(
                  (a) => _activities.contains(a.id),
                ))
                  Text('• ${activity.name}'),
                OutlinedButton(
                  onPressed: () => _begin(step: 5),
                  child: const Text('View or change club activities'),
                ),
                const SizedBox(height: 12),
                Text('Members: ${_roster.length} · Invitations sent: 0'),
                for (final member in _roster)
                  ListTile(
                    title: Text(member.name),
                    subtitle: Text(
                      member.role == 'admin'
                          ? 'Active member · Administrator'
                          : 'Not invited',
                    ),
                  ),
                OutlinedButton(
                  onPressed: () => _begin(step: 6),
                  child: const Text('View or import members'),
                ),
                const SizedBox(height: 16),
                const Text(
                  'This is the test club home for the onboarding rehearsal. '
                  'No live club, bookings or sign-in accounts have been created. '
                  'No invitations are sent. Closing the rehearsal clears its test data.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _provisionedFor != null
      ? _clubHome()
      : ClubOnlineScaffold(
          appBar: AppBar(title: const Text('STAGING onboarding rehearsal')),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_provisionedFor != null)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            _progress.reviewed
                                ? 'Setup review finished. You are back at the rehearsal start. '
                                      'No invitations were sent. You can revisit your setup below.'
                                : 'You have left setup. Your test entries are kept while this '
                                      'rehearsal stays open. Continue below to return to your saved step. '
                                      'No invitations were sent.',
                          ),
                        ),
                      ),
                    const Text(
                      'SIMULATION · No database records or messages',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xff944000),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Use fictional details to rehearse the journey. Google results, '
                      'codes and reviewer decisions are simulated here. They do not verify '
                      'a real club or person. Closing this rehearsal clears its temporary data.',
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<StagingClubScenario>(
                      key: const Key('registration-scenario'),
                      initialValue: _scenario,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Staging test scenario',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: StagingClubScenario.fictional,
                          child: Text(
                            'Fictional club — simulate a Google match',
                          ),
                        ),
                        DropdownMenuItem(
                          value: StagingClubScenario.notFound,
                          child: Text('Club not found — manual review'),
                        ),
                        DropdownMenuItem(
                          value: StagingClubScenario.duplicate,
                          child: Text('Already registered — stop'),
                        ),
                        DropdownMenuItem(
                          value: StagingClubScenario.unavailable,
                          child: Text('Google unavailable — retry'),
                        ),
                      ],
                      onChanged: (s) {
                        if (s != null) {
                          _scenario = s;
                          _resetVerification();
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'Test club name',
                      ),
                    ),
                    TextField(
                      controller: _address,
                      decoration: const InputDecoration(
                        labelText: 'Test club address',
                      ),
                    ),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Secretary email',
                      ),
                      onChanged: (_) => _resetVerification(),
                    ),
                    TextField(
                      controller: _secretaryFirst,
                      decoration: const InputDecoration(
                        labelText: 'Secretary first name',
                      ),
                    ),
                    TextField(
                      controller: _secretarySurname,
                      decoration: const InputDecoration(
                        labelText: 'Secretary surname',
                      ),
                    ),
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Secretary telephone',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _authority,
                      title: const Text('I am authorised to set up this club'),
                      subtitle: const Text(
                        'A declaration, not independent proof of authority.',
                      ),
                      onChanged: (v) => setState(() => _authority = v ?? false),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _requestCode,
                      child: const Text('Generate test email code'),
                    ),
                    if (_codeIssued) ...[
                      const Text(
                        'Preview only: use code 246810. No email was delivered.',
                      ),
                      TextField(
                        controller: _code,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Verification code',
                        ),
                      ),
                      OutlinedButton(
                        onPressed: _verifyCode,
                        child: const Text('Check test code'),
                      ),
                    ],
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(_message!),
                      ),
                    const Divider(height: 32),
                    Text(switch (_decision) {
                      ClubRegistrationDecision.verifyEmail =>
                        'Verify your email to continue.',
                      ClubRegistrationDecision.alreadyRegistered =>
                        'This club is already registered. Contact its administrator to request access.',
                      ClubRegistrationDecision.contactUs =>
                        'We couldn’t find your club. Please contact Total Leisure so we can confirm the details with you.',
                      ClubRegistrationDecision.declined =>
                        'We need to discuss your club details before you can continue. Please contact Total Leisure.',
                      ClubRegistrationDecision.retryLookup =>
                        'We couldn’t check Google just now. Please try again later. Your club has not been created.',
                      ClubRegistrationDecision.proceed =>
                        'Registration checks passed in this simulation. You can rehearse setup.',
                    }, style: Theme.of(context).textTheme.titleMedium),
                    if (_scenario == StagingClubScenario.notFound) ...[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: !_verified
                            ? null
                            : () => setState(() {
                                _manualRequested = true;
                                _message =
                                    'Test application awaiting a reviewer. No message sent.';
                              }),
                        child: const Text('Request manual verification'),
                      ),
                      if (!_verified)
                        const Text(
                          'Verify the test email before requesting review.',
                        ),
                      if (_manualRequested)
                        Card(
                          color: const Color(0xfffff4da),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'TEST OPERATOR CONTROLS · Not available to real applicants',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const Text(
                                  'Simulate the decision after a call with the applicant. '
                                  'Approval still requires email verification and cannot override a duplicate club.',
                                ),
                                TextField(
                                  controller: _reason,
                                  decoration: const InputDecoration(
                                    labelText: 'Test reviewer note',
                                  ),
                                ),
                                Wrap(
                                  spacing: 12,
                                  children: [
                                    OutlinedButton(
                                      onPressed: () => _review(true),
                                      child: const Text('Simulate approval'),
                                    ),
                                    OutlinedButton(
                                      onPressed: () => _review(false),
                                      child: const Text('Simulate decline'),
                                    ),
                                  ],
                                ),
                                for (final note in _snapshots) Text(note),
                              ],
                            ),
                          ),
                        ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed:
                          _decision == ClubRegistrationDecision.proceed &&
                              _authority &&
                              _phone.text.trim().isNotEmpty
                          ? _begin
                          : null,
                      child: const Text('Continue to ten-step setup'),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'This tests the screen flow only. Live Google matching, email delivery, '
                      'abuse limits and server-enforced manual approval require separate integration tests.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
}

class _PreviewSetupTool extends StatefulWidget {
  const _PreviewSetupTool({
    required this.tool,
    required this.initial,
    required this.onSave,
  });
  final ClubSetupTool tool;
  final String initial;
  final ValueChanged<String> onSave;
  @override
  State<_PreviewSetupTool> createState() => _PreviewSetupToolState();
}

class _PreviewSetupToolState extends State<_PreviewSetupTool> {
  late final _value = TextEditingController(text: widget.initial);
  String? _error;
  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClubOnlineScaffold(
    appBar: AppBar(title: Text('SIMULATION · ${widget.tool.name}')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'A small test substitute for the normal setup screen. '
            'You can accept the supplied example without typing anything. '
            'Press Save rehearsal value to keep it. '
            'This saves a temporary rehearsal value only. No club records are created.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _value,
            decoration: InputDecoration(
              labelText: 'Test setup value',
              errorText: _error,
            ),
          ),
          if (widget.tool == ClubSetupTool.venues)
            const Text(
              'The rehearsal uses opening hours 09:00–22:00 after this save. '
              'The live setup requires you to review and save your actual venue hours.',
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              if (_value.text.trim().isEmpty) {
                setState(
                  () => _error =
                      'Enter a value, or keep the supplied example, then save.',
                );
                return;
              }
              widget.onSave(_value.text.trim());
              Navigator.of(context).pop();
            },
            child: const Text('Save rehearsal value'),
          ),
        ],
      ),
    ),
  );
}
