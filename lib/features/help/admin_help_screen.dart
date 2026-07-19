// lib/features/help/admin_help_screen.dart

import 'package:flutter/material.dart';

class AdminHelpScreen extends StatefulWidget {
  const AdminHelpScreen({super.key});

  @override
  State<AdminHelpScreen> createState() => _AdminHelpScreenState();
}

class _AdminHelpScreenState extends State<AdminHelpScreen> {
  final _scrollController = ScrollController();

  final _indexKey = GlobalKey();
  final _setupKey = GlobalKey();
  final _venuesKey = GlobalKey();
  final _fixtureTypesKey = GlobalKey();
  final _creatingFixturesKey = GlobalKey();
  final _workflowsKey = GlobalKey();
  final _teamsLifecycleKey = GlobalKey();
  final _rinksKey = GlobalKey();
  final _publishingKey = GlobalKey();
  final _notificationsKey = GlobalKey();
  final _internalKey = GlobalKey();
  final _captainsKey = GlobalKey();

  String _backgroundImageForWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (width >= 1000) {
      return 'assets/images/blank_bg_desktop_2.png';
    } else if (width >= 600) {
      return 'assets/images/blank_bg_tablet_2.png';
    } else {
      return 'assets/images/blank_bg_phone_2.png';
    }
  }

  Future<void> _jumpTo(GlobalKey key) async {
    final ctx = key.currentContext;
    if (ctx == null) return;

    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      alignment: 0.05,
    );
  }

  Widget _p(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          height: 1.45,
          color: Colors.black.withOpacity(0.85),
        ),
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Icon(Icons.circle, size: 7),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                height: 1.4,
                color: Colors.black.withOpacity(0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _subHeading(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
          color: Colors.black.withOpacity(0.9),
        ),
      ),
    );
  }

  Widget _topicButton(String label, GlobalKey key) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _jumpTo(key),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.65),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.35)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required GlobalKey key,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 26),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.80),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: Colors.black.withOpacity(0.9),
            ),
          ),
          const SizedBox(height: 14),
          ...children,
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () => _jumpTo(_indexKey),
            icon: const Icon(Icons.arrow_upward),
            label: const Text('Back to Topics'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin User Guide')),
      body: Stack(
        children: [
          Positioned.fill(
            child: Transform.scale(
              scale: 1.05,
              child: Image.asset(
                _backgroundImageForWidth(context),
                fit: BoxFit.cover,
                color: Colors.black.withOpacity(0.20),
                colorBlendMode: BlendMode.darken,
              ),
            ),
          ),
          Positioned.fill(
            child: Container(color: Colors.white.withOpacity(0.62)),
          ),
          SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  key: _indexKey,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.82),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.45)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bowls App Admin User Guide',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 10),
                      _p(
                        'This user guide explains how club admins, selectors, fixture secretaries and captains set up and manage the Bowls App, from venues and greens through to fixtures, teams, rinks, captains and notifications.',
                      ),
                      const SizedBox(height: 8),
                      _topicButton('1. First Club Setup', _setupKey),
                      _topicButton('2. Home Venues and Greens', _venuesKey),
                      _topicButton(
                        '3. Fixture Types and Workflows',
                        _fixtureTypesKey,
                      ),
                      _topicButton(
                        '4. Creating Fixtures',
                        _creatingFixturesKey,
                      ),
                      _topicButton(
                        '5. Fixture Workflows and Stages',
                        _workflowsKey,
                      ),
                      _topicButton(
                        '6. Using the App to Manage Teams',
                        _teamsLifecycleKey,
                      ),
                      _topicButton(
                        '7. Rink Allocation and Physical Rinks',
                        _rinksKey,
                      ),
                      _topicButton(
                        '8. Publishing Teams and Fixture Sheets',
                        _publishingKey,
                      ),
                      _topicButton(
                        '9. Notifications and Communication',
                        _notificationsKey,
                      ),
                      _topicButton(
                        '10. Member Booked Internal Fixtures',
                        _internalKey,
                      ),
                      _topicButton(
                        '11. Captains and Vice-Captains',
                        _captainsKey,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                _buildSection(
                  key: _setupKey,
                  title: '1. First Club Setup',
                  children: [
                    _p(
                      'Before fixtures can be managed properly, the club needs its basic playing structure set up. This includes home venues, greens, fixture types and the rules that control how each type of fixture behaves.',
                    ),
                    _bullet('Set up the club home venue or venues.'),
                    _bullet('Create the greens used at each home venue.'),
                    _bullet('Confirm the number and naming style of rinks.'),
                    _bullet('Create the fixture types used by the club.'),
                    _bullet(
                      'Decide which fixture types require RSVP, team selection, pre-selection or member booking.',
                    ),
                  ],
                ),

                _buildSection(
                  key: _venuesKey,
                  title: '2. Home Venues and Greens',
                  children: [
                    _p(
                      'The first practical setup task is normally to create the club’s home venue and then add the greens available at that venue.',
                    ),
                    _subHeading('Home Venue'),
                    _bullet('Create the main club venue.'),
                    _bullet('Add address and contact details where required.'),
                    _bullet('Mark the venue as a home venue.'),
                    _subHeading('Greens'),
                    _bullet('Add each green used by the club.'),
                    _bullet('Choose whether the green is indoor or outdoor.'),
                    _bullet('Set the rink numbering or labelling system.'),
                    _bullet(
                      'Enter the maximum number of rinks the green can support.',
                    ),
                    _p(
                      'If your club varies the width of rinks on a green, enter the maximum number of rinks that may be used. This gives the system enough capacity to manage different layouts later.',
                    ),
                  ],
                ),

                _buildSection(
                  key: _fixtureTypesKey,
                  title: '3. Fixture Types and Workflows',
                  children: [
                    _p(
                      'Fixture Types are one of the most important parts of the system. They do far more than describe the name of a match.',
                    ),
                    _p(
                      'A Fixture Type controls how a fixture behaves, what players see, what actions are expected, and how the fixture moves through the system.',
                    ),
                    _subHeading('What is a workflow?'),
                    _p(
                      'A workflow is the journey a fixture follows from creation through to play. Different types of fixtures may need different journeys.',
                    ),
                    _bullet('A friendly match may ask players to RSVP first.'),
                    _bullet(
                      'A league match may gather availability before a selector chooses the team.',
                    ),
                    _bullet(
                      'An internal competition may allow players to be selected directly.',
                    ),
                    _bullet(
                      'A member booked fixture may focus on booking a rink and adding the players involved.',
                    ),
                    _p(
                      'Setting up Fixture Types correctly is pivotal because it creates the structure of the whole system. It allows the app to know what process each fixture should follow.',
                    ),
                    _subHeading('Fixture Types may control'),
                    _bullet('Whether the fixture uses rinks.'),
                    _bullet(
                      'How many rinks and players are normally required.',
                    ),
                    _bullet('Whether players RSVP or declare availability.'),
                    _bullet('Whether players are selected directly.'),
                    _bullet(
                      'Whether members can create the fixture themselves.',
                    ),
                    _bullet('Whether captains or admins manage the fixture.'),
                    _bullet(
                      'What colours are used on the dashboard and diary.',
                    ),
                  ],
                ),

                _buildSection(
                  key: _creatingFixturesKey,
                  title: '4. Creating Fixtures',
                  children: [
                    _p(
                      'When creating a fixture, the selected Fixture Type should drive most of the process. Admins and selectors should start by choosing the correct type.',
                    ),
                    _subHeading('Typical details'),
                    _bullet('Fixture type.'),
                    _bullet('Date and start time.'),
                    _bullet('Home or away.'),
                    _bullet('Opponent or internal description.'),
                    _bullet('Venue.'),
                    _bullet('Green and rink requirements where applicable.'),
                    _bullet('Captain and vice-captain where known.'),
                    _subHeading('Good practice'),
                    _bullet('Choose the Fixture Type first.'),
                    _bullet('Check the default number of rinks and players.'),
                    _bullet(
                      'Confirm whether RSVP, availability or direct selection is required.',
                    ),
                    _bullet(
                      'Assign a captain where possible before publishing.',
                    ),
                  ],
                ),

                _buildSection(
                  key: _workflowsKey,
                  title: '5. Fixture Workflows and Stages',
                  children: [
                    _p(
                      'Different fixtures pass through different stages depending on their Fixture Type.',
                    ),
                    _subHeading('RSVP fixtures'),
                    _bullet('Players are asked whether they are available.'),
                    _bullet('Players may respond Yes, Maybe or No.'),
                    _bullet(
                      'Selectors or captains choose the team from the responses.',
                    ),
                    _bullet(
                      'Selected players are then asked to accept or decline.',
                    ),
                    _subHeading('Team selection fixtures'),
                    _bullet('Players indicate availability.'),
                    _bullet('The selector chooses the team.'),
                    _bullet('The fixture is published.'),
                    _bullet('Players confirm whether they can play.'),
                    _subHeading('Pre-select fixtures'),
                    _bullet(
                      'Players are selected directly by an admin, selector or captain.',
                    ),
                    _bullet('There may be no RSVP stage.'),
                    _bullet(
                      'The fixture can be published once the team or players are ready.',
                    ),
                    _subHeading('Member booked internal fixtures'),
                    _bullet('A member creates the fixture.'),
                    _bullet('The creator becomes the fixture captain.'),
                    _bullet('The rink is booked.'),
                    _bullet('Players, opponents and markers are added.'),
                    _bullet('Changes can be managed by the captain or admin.'),
                  ],
                ),

                _buildSection(
                  key: _teamsLifecycleKey,
                  title: '6. Using the App to Manage Teams',
                  children: [
                    _p(
                      'A team in the app is more than a static list of names. It is a working group of members who may be considered for a set of fixtures during the season.',
                    ),
                    _p(
                      'The team can be linked to fixtures, used to gather availability, used as the starting pool for selection, and then used to publish fixture sheets and communicate with selected players.',
                    ),
                    _subHeading('The people involved'),
                    _bullet(
                      'Club admins manage the wider setup of the app, including members, venues, greens, fixture types, teams and permissions.',
                    ),
                    _bullet(
                      'Fixture secretaries may enter the known fixtures for the season and link those fixtures to the correct teams.',
                    ),
                    _bullet(
                      'Selectors may review availability, choose players, arrange reserves and help prepare the team before publication.',
                    ),
                    _bullet(
                      'Captains may monitor availability and acceptance, organise players and deal with fixture changes.',
                    ),
                    _bullet(
                      'Vice-captains provide a second point of contact and can support the fixture captain where required.',
                    ),
                    _p(
                      'To keep the manual clear, the app uses the term fixture captain for the person in charge of an individual fixture. This may be the team captain, a selector, the fixture secretary or another authorised officer nominated for that match.',
                    ),
                    _p(
                      'The rest of this guide refers to the fixture captain as the person managing the fixture. However, club admins, fixture secretaries, selectors and captains can also view and interact with teams and team fixtures where their permissions allow.',
                    ),
                    _subHeading('Creating and maintaining a team'),
                    _bullet(
                      'Create the team for a league, division, competition squad or regular playing group.',
                    ),
                    _bullet(
                      'Add the members who should normally be considered for that team.',
                    ),
                    _bullet('Keep the team pool up to date during the season.'),
                    _bullet('Add players when they become part of the squad.'),
                    _bullet(
                      'Remove players who move to another team, play up to a higher division, or are no longer eligible for that team.',
                    ),
                    _subHeading('Creating fixtures early'),
                    _p(
                      'Once fixtures are known, the fixture secretary can enter them into the app as early as possible. As soon as a team fixture exists, members of that team can see it and register their availability.',
                    ),
                    _bullet('Members can check their diaries early.'),
                    _bullet('Members can respond Yes, Maybe or No.'),
                    _bullet(
                      'The fixture captain can see who is available, who is unsure, and who is not available.',
                    ),
                    _bullet(
                      'This gives the fixture captain useful information before any selection is made.',
                    ),
                    _subHeading('Selecting the team'),
                    _p(
                      'The fixture remains unpublished while the fixture captain prepares the selection. This allows players to be selected, deselected, moved into positions, or marked as reserves before the team is formally released.',
                    ),
                    _bullet('Select players from the team pool.'),
                    _bullet('Add other eligible players if required.'),
                    _bullet(
                      'Remove players who should not be considered for that fixture.',
                    ),
                    _bullet(
                      'Arrange players into pairs, triples, rinks or other team formats.',
                    ),
                    _bullet('Allocate reserves where appropriate.'),
                    _subHeading('Publishing the team'),
                    _p(
                      'Publishing is the point at which selected members are formally told that they have been chosen. The fixture appears on their dashboard and they are asked to accept or decline their selection. Selected members should also receive the fixture sheet by email, where email delivery is enabled.',
                    ),
                    _bullet('Selected members receive an in-app notification.'),
                    _bullet(
                      'Selected members receive an email where email is enabled.',
                    ),
                    _bullet(
                      'The email should include the fixture sheet as a PDF attachment or link, depending on the club email setup.',
                    ),
                    _bullet(
                      'The fixture sheet shows the fixture details, selected players, positions, reserves, captain details and rink information where entered.',
                    ),
                    _subHeading('Monitoring replies and sending reminders'),
                    _p(
                      'After publication, the fixture captain can monitor who has accepted, who has declined and who has not yet replied. This makes it easier to chase outstanding responses and arrange replacements if needed.',
                    ),
                    _bullet(
                      'The app may send reminders to players who have not replied after a period of time.',
                    ),
                    _bullet(
                      'A further reminder may be sent shortly before the fixture if a player still has not replied.',
                    ),
                    _bullet(
                      'The fixture captain can also send reminders manually at any stage.',
                    ),
                    _bullet(
                      'Reminders may be sent as both an in-app notification and an email.',
                    ),
                    _subHeading('Changes after publication'),
                    _p(
                      'A published team may still change. Players may decline, become unavailable, be promoted from reserve to player, change position, or need updated rink details. When important changes are made, affected members should be notified and asked to check the fixture again.',
                    ),
                  ],
                ),

                _buildSection(
                  key: _rinksKey,
                  title: '7. Rink Allocation and Physical Rinks',
                  children: [
                    _p(
                      'The system separates reserving rink capacity from assigning exact physical rinks.',
                    ),
                    _subHeading('Rink allocation'),
                    _p(
                      'Rink allocation means deciding how many rinks the fixture needs. For example, a match may require four rinks.',
                    ),
                    _bullet('This helps reserve space on the green.'),
                    _bullet('It gives the club visibility of green usage.'),
                    _bullet(
                      'It can be done before exact rink numbers are known.',
                    ),
                    _subHeading('Physical rink assignment'),
                    _p(
                      'Physical rink assignment means choosing the actual rink numbers or labels, such as Rink 1, Rink 2 or Rink A.',
                    ),
                    _bullet('This may happen when creating the fixture.'),
                    _bullet('It may also be done later in Fixture Details.'),
                    _bullet(
                      'Admins may adjust rinks if green conditions or layouts change.',
                    ),
                    _p(
                      'This distinction is important because clubs often know how many rinks they need before they know exactly which physical rinks will be used.',
                    ),
                  ],
                ),

                _buildSection(
                  key: _publishingKey,
                  title: '8. Publishing Teams and Fixture Sheets',
                  children: [
                    _p(
                      'Publishing a fixture makes the selected team or players visible to the relevant members.',
                    ),
                    _bullet('Players can see that they have been selected.'),
                    _bullet('Players may be asked to accept or decline.'),
                    _bullet('Captains can monitor responses.'),
                    _bullet(
                      'Fixture sheets or team sheets can be viewed where available.',
                    ),
                    _subHeading('Fixture sheets may show'),
                    _bullet('Date and time.'),
                    _bullet('Home or away information.'),
                    _bullet('Opponent or internal fixture details.'),
                    _bullet('Team or rink groupings.'),
                    _bullet('Captain and vice-captain details.'),
                    _bullet('Rink numbers where assigned.'),
                  ],
                ),

                _buildSection(
                  key: _notificationsKey,
                  title: '9. Notifications and Communication',
                  children: [
                    _p(
                      'The app is designed to notify the right people when important fixture events happen.',
                    ),
                    _subHeading('Players may receive notifications when'),
                    _bullet('they are invited to respond to a fixture.'),
                    _bullet('they are selected for a team or fixture.'),
                    _bullet('they are made a reserve.'),
                    _bullet('they are asked to act as marker or umpire.'),
                    _bullet('a fixture is published.'),
                    _bullet('the team, date, time or rink changes.'),
                    _bullet('they are promoted from reserve to player.'),
                    _subHeading('Captains may receive notifications when'),
                    _bullet('players accept their place.'),
                    _bullet('players decline their place.'),
                    _bullet('player assignments change.'),
                    _bullet('rinks or fixture details are updated.'),
                    _subHeading('Admins may receive notifications when'),
                    _bullet('fixtures require attention.'),
                    _bullet('member booked fixtures are created.'),
                    _bullet('important changes are made.'),
                    _bullet('reports or exceptions need review.'),
                    _p(
                      'Notifications may be delivered through in-app notifications, email or other messaging routes depending on club setup and rollout stage.',
                    ),
                  ],
                ),

                _buildSection(
                  key: _internalKey,
                  title: '10. Member Booked Internal Fixtures',
                  children: [
                    _p(
                      'Some internal Fixture Types allow members to create their own smaller fixtures, such as singles matches, pairs games, practice matches or internal competition games.',
                    ),
                    _subHeading('Process'),
                    _bullet(
                      'The member chooses the correct internal fixture type.',
                    ),
                    _bullet('The member enters the agreed date and time.'),
                    _bullet('The member books the required rink or rinks.'),
                    _bullet(
                      'The member adds the opponent, teammates, marker or umpire if required.',
                    ),
                    _bullet(
                      'The member who creates the fixture becomes the captain.',
                    ),
                    _subHeading('Admin role'),
                    _bullet(
                      'Set which internal Fixture Types members are allowed to book.',
                    ),
                    _bullet(
                      'Check that rink limits and player numbers are sensible.',
                    ),
                    _bullet('Monitor bookings if required.'),
                    _bullet(
                      'Step in where corrections or cancellations are needed.',
                    ),
                    _subHeading('Changes'),
                    _p(
                      'Because these fixtures are often arranged directly between players, date, time and rink changes may happen more often. Participants should be notified when important changes are made.',
                    ),
                  ],
                ),

                _buildSection(
                  key: _captainsKey,
                  title: '11. Captains and Vice-Captains',
                  children: [
                    _p(
                      'Captains and vice-captains allow responsibility for a fixture to be shared without giving every user full admin rights.',
                    ),
                    _subHeading('Fixture captain'),
                    _bullet('Acts as the main organiser for that fixture.'),
                    _bullet('Can monitor player responses.'),
                    _bullet(
                      'May manage operational details depending on permissions.',
                    ),
                    _bullet(
                      'Receives important notifications about that fixture.',
                    ),
                    _subHeading('Vice-captain'),
                    _bullet('Can support the captain.'),
                    _bullet('May help manage player or fixture changes.'),
                    _bullet('Provides a second point of contact.'),
                    _p(
                      'Captaincy is fixture-specific. A member can be captain for one fixture without becoming a club admin.',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
