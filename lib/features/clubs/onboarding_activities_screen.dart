import 'club_online_scaffold.dart';
import 'onboarding_fixture_colours.dart';
import 'package:flutter/material.dart';

class OnboardingActivity {
  const OnboardingActivity(this.id, this.name, this.hint, {this.event = false});
  final String id, name, hint;
  final bool event;
}

const onboardingActivities = [
  OnboardingActivity(
    'rollups',
    'Roll-ups and open sessions',
    'Informal bowling organised on the day.',
  ),
  OnboardingActivity(
    'drives',
    'Drives',
    'Organised bowling with changing teams or opponents.',
  ),
  OnboardingActivity(
    'aggregates',
    'Aggregates',
    'Regular bowling where individual scores accumulate.',
  ),
  OnboardingActivity(
    'friendlies',
    'Friendly matches',
    'Members sign up with their availability before players are selected.',
  ),
  OnboardingActivity(
    'leagues',
    'League matches',
    'Selected teams for your league programme.',
  ),
  OnboardingActivity(
    'internal',
    'Internal competitions',
    'Club competitions with named players and linked matches.',
  ),
  OnboardingActivity(
    'nationals',
    'National & County Matches',
    'Member bookings for national and county competitions, with pre-selected players.',
  ),
  OnboardingActivity(
    'coaching',
    'Coaching',
    'Open coaching sessions organised by the club.',
  ),
  OnboardingActivity(
    'practice',
    'Practice',
    'Member-bookable practice with pre-selected players.',
  ),
  OnboardingActivity(
    'trials',
    'Team Trials',
    'Members sign up to offer their availability for trials.',
  ),
  OnboardingActivity(
    'bookings',
    'Member rink bookings',
    'Members book a rink within the club’s rules.',
  ),
  OnboardingActivity(
    'committee',
    'Committee meetings',
    'Club business without reserving bowling rinks.',
    event: true,
  ),
  OnboardingActivity(
    'social',
    'Social events',
    'Social activities with optional attendance replies.',
    event: true,
  ),
  OnboardingActivity(
    'meals',
    'Meals and celebrations',
    'Meals, presentations and celebrations.',
    event: true,
  ),
  OnboardingActivity(
    'fundraising',
    'Fundraising events',
    'Events supporting club funds.',
    event: true,
  ),
  OnboardingActivity(
    'agm',
    'Club meetings and AGMs',
    'Meetings open to the appropriate members.',
    event: true,
  ),
  OnboardingActivity(
    'other',
    'Other club events',
    'A general starter for another recurring event.',
    event: true,
  ),
];

class OnboardingActivitiesScreen extends StatefulWidget {
  const OnboardingActivitiesScreen({
    super.key,
    required this.initial,
    required this.onSave,
    this.rehearsal = true,
  });
  final Set<String> initial;
  final ValueChanged<Set<String>> onSave;
  final bool rehearsal;
  @override
  State<OnboardingActivitiesScreen> createState() =>
      _OnboardingActivitiesScreenState();
}

class _OnboardingActivitiesScreenState
    extends State<OnboardingActivitiesScreen> {
  late final _selected = {...widget.initial};
  bool _reviewing = false;
  @override
  Widget build(BuildContext context) => ClubOnlineScaffold(
    appBar: AppBar(
      title: Text(
        _reviewing ? 'Review your activities' : 'What does your club offer?',
      ),
    ),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.rehearsal
                    ? 'STAGING REHEARSAL · Starter choices only; no live Fixture Types are created.'
                    : 'These choices will be saved as fixture types when you create the club.',
              ),
              const SizedBox(height: 12),
              const Text(
                'All choices here can be changed later. Once your general club settings '
                'are set up, you can review and edit all these settings in Fixture Types.',
              ),
              const SizedBox(height: 12),
              Text(
                _reviewing
                    ? 'Check the activities you want to start with. General events do not '
                          'reserve rinks by default. Names, participation and booking defaults need review '
                          'when these starter choices become live Fixture Types.'
                    : 'Choose just the activities you need now. You can add more later.',
              ),
              for (final events in [false, true]) ...[
                const SizedBox(height: 20),
                Text(
                  events ? 'General club events' : 'Bowling activities',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                for (final activity in onboardingActivities.where(
                  (a) =>
                      a.event == events &&
                      (!_reviewing || _selected.contains(a.id)),
                ))
                  Card(
                    color: onboardingFixtureColours[activity.name]?.background,
                    surfaceTintColor: Colors.transparent,
                    child: _reviewing
                        ? ListTile(
                            title: Text(
                              activity.name,
                              style: TextStyle(
                                color: onboardingFixtureColours[activity.name]
                                    ?.foreground,
                              ),
                            ),
                            subtitle: Text(
                              '${activity.hint}\n${events ? 'No rinks by default' : 'Uses greens and rinks'}',
                              style: TextStyle(
                                color: onboardingFixtureColours[activity.name]
                                    ?.foreground,
                              ),
                            ),
                          )
                        : CheckboxListTile(
                            value: _selected.contains(activity.id),
                            activeColor: onboardingFixtureColours[activity.name]
                                ?.foreground,
                            checkColor: onboardingFixtureColours[activity.name]
                                ?.background,
                            side: BorderSide(
                              color:
                                  onboardingFixtureColours[activity.name]
                                      ?.foreground ??
                                  Colors.black87,
                            ),
                            title: Text(
                              activity.name,
                              style: TextStyle(
                                color: onboardingFixtureColours[activity.name]
                                    ?.foreground,
                              ),
                            ),
                            subtitle: Text(
                              activity.hint,
                              style: TextStyle(
                                color: onboardingFixtureColours[activity.name]
                                    ?.foreground,
                              ),
                            ),
                            onChanged: (yes) => setState(() {
                              if (yes == true) {
                                _selected.add(activity.id);
                              } else {
                                _selected.remove(activity.id);
                              }
                            }),
                          ),
                  ),
              ],
              const SizedBox(height: 20),
              if (_reviewing)
                OutlinedButton(
                  onPressed: () => setState(() => _reviewing = false),
                  child: const Text('Change choices'),
                ),
              FilledButton(
                onPressed: _selected.isEmpty
                    ? null
                    : () {
                        if (!_reviewing) {
                          setState(() => _reviewing = true);
                        } else {
                          widget.onSave({..._selected});
                          Navigator.of(context).pop();
                        }
                      },
                child: Text(
                  _reviewing
                      ? 'Use these activities'
                      : 'Review selected activities',
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Decide later'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
