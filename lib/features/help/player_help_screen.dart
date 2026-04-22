import 'package:flutter/material.dart';

class PlayerHelpScreen extends StatefulWidget {
  const PlayerHelpScreen({super.key});

  @override
  State<PlayerHelpScreen> createState() => _PlayerHelpScreenState();
}

class _PlayerHelpScreenState extends State<PlayerHelpScreen> {
  final _scrollController = ScrollController();

  final _indexKey = GlobalKey();
  final _gettingStartedKey = GlobalKey();
  final _whatAppDoesKey = GlobalKey();
  final _dashboardOverviewKey = GlobalKey();
  final _playerJourneyKey = GlobalKey();
  final _fixturesKey = GlobalKey();
  final _notificationsKey = GlobalKey();
  final _internalFixturesKey = GlobalKey();
  final _fixtureSheetsKey = GlobalKey();
  final _commonQuestionsKey = GlobalKey();

  Future<void> _jumpTo(GlobalKey key) async {
    final context = key.currentContext;
    if (context == null) return;

    await Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      alignment: 0.05,
    );
  }

  String _backgroundImageForWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (width >= 1000) {
      return 'assets/images/auth_bg_desktop.png';
    } else if (width >= 600) {
      return 'assets/images/auth_bg_tablet.png';
    } else {
      return 'assets/images/auth_bg_phone.png';
    }
  }
  
  Widget _buildSection({
    required GlobalKey key,
    required String title,
    required List<Widget> children,
    bool showBackToTopics = true,
  }) {
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 28),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          ...children,
          if (showBackToTopics) ...[
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _jumpTo(_indexKey),
                icon: const Icon(Icons.arrow_upward),
                label: const Text('Back to Topics'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _p(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.45),
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
            padding: EdgeInsets.only(top: 4),
            child: Icon(Icons.circle, size: 8),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style:
                  Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.4),
            ),
          ),
        ],
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
            border: Border.all(color: Colors.grey.shade300),
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

  Widget _subHeading(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
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
      appBar: AppBar(
        title: const Text('Help & User Guide'),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              _backgroundImageForWidth(context),
              fit: BoxFit.cover,
              color: Colors.black.withOpacity(0.45),
              colorBlendMode: BlendMode.darken,
            ),
          ),
          Positioned.fill(
            child: Container(
              color: Colors.white.withOpacity(0.65),
            ),
          ),
          SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  key: _indexKey,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.75),
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
                        'Bowls App Player Guide',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 10),
                      _p(
                        'This guide explains how to use the Bowls App from a player\'s point of view. You can scroll through the full guide or jump straight to any topic below.',
                      ),
                      const SizedBox(height: 8),
                      _topicButton('1. Getting Started', _gettingStartedKey),
                      _topicButton('2. What the App Does', _whatAppDoesKey),
                      _topicButton('3. Dashboard Overview', _dashboardOverviewKey),
                      _topicButton('4. Your Journey as a Player', _playerJourneyKey),
                      _topicButton('5. Fixtures and Match Interaction', _fixturesKey),
                      _topicButton('6. Notifications', _notificationsKey),
                      _topicButton('7. Internal Match Fixtures', _internalFixturesKey),
                      _topicButton('8. Fixture Sheets', _fixtureSheetsKey),
                      _topicButton('9. Common Questions', _commonQuestionsKey),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                _buildSection(
                  key: _gettingStartedKey,
                  title: '1. Getting Started',
                  children: [
                    _p(
                      'The Bowls App helps you keep track of matches, club activity, competitions, team selection and green usage.',
                    ),
                    _subHeading('Registering'),
                    _bullet('Open the app and choose Register if you are a new user.'),
                    _bullet('Enter your email address and create a password.'),
                    _bullet('Follow any confirmation steps if your club has enabled them.'),
                    _subHeading('Logging In'),
                    _bullet('Enter your email address and password on the login screen.'),
                    _bullet('After logging in, you will be taken to your home area or dashboard.'),
                    _subHeading('Need Help'),
                    _bullet('Use the Need Help button on the login screen if you want guidance before signing in.'),
                  ],
                ),

                _buildSection(
                  key: _whatAppDoesKey,
                  title: '2. What the App Does',
                  children: [
                    _p(
                      'The Bowls App is more than a match selection tool. It can act as a day-to-day club diary and player information hub.',
                    ),
                    _bullet('View matches, competitions and club fixtures'),
                    _bullet('See meetings, events and club activities'),
                    _bullet('Track daily green usage and rink use'),
                    _bullet('Respond to invitations and team selections'),
                    _bullet('View published teams and fixture details'),
                    _bullet('Receive important updates about changes'),
                  ],
                ),

                _buildSection(
                  key: _dashboardOverviewKey,
                  title: '3. Dashboard Overview',
                  children: [
                    _p(
                      'The dashboard is the main player home screen. It is designed to show the actions that matter most to you.',
                    ),
                    _subHeading('Needs Your Acceptance'),
                    _p(
                      'This section shows fixtures where you have already been selected to play and now need to accept or decline your place.',
                    ),
                    _subHeading('Fixtures to RSVP'),
                    _p(
                      'This section shows fixtures where you are invited to say whether you are available. You may be able to answer Yes, Maybe or No.',
                    ),
                    _subHeading('Awaiting Team Selection'),
                    _p(
                      'This section shows fixtures where availability is being gathered before the team is chosen. Your response helps the selector or captain decide who can play.',
                    ),
                    _subHeading('Accepted Fixtures'),
                    _p(
                      'This section shows your upcoming fixtures that you have already accepted. These are your confirmed matches and events.',
                    ),
                  ],
                ),

                _buildSection(
                  key: _playerJourneyKey,
                  title: '4. Your Journey as a Player',
                  children: [
                    _p(
                      'Most players move through the app in a simple journey from invitation to confirmed match.',
                    ),
                    _bullet('First, you may be invited to a fixture and asked to RSVP or declare availability.'),
                    _bullet('Next, a captain or selector reviews the responses.'),
                    _bullet('If selected, the fixture moves into the acceptance stage for you.'),
                    _bullet('You then accept or decline your place.'),
                    _bullet('Once accepted, the fixture appears in your upcoming accepted fixtures list.'),
                    _p(
                      'The quicker and clearer your responses are, the easier it is for captains and selectors to organise teams.',
                    ),
                  ],
                ),

                _buildSection(
                  key: _fixturesKey,
                  title: '5. Fixtures and Match Interaction',
                  children: [
                    _p(
                      'Fixtures may appear in slightly different ways depending on the type of match and how your club runs selection.',
                    ),
                    _subHeading('RSVP Stage'),
                    _bullet('Yes means you are available and wish to be considered.'),
                    _bullet('Maybe means you may be available but are not certain.'),
                    _bullet('No means you are unavailable.'),
                    _subHeading('Selection Stage'),
                    _bullet('If chosen, you may be selected as a player, reserve, marker or umpire depending on the fixture type.'),
                    _subHeading('Acceptance Stage'),
                    _bullet('When selected, you should accept promptly if you can play.'),
                    _bullet('If you cannot play, decline as soon as possible so changes can be made.'),
                    _subHeading('Changes'),
                    _bullet('If teams, rinks, dates or times change after publication, you may receive an update and should check the fixture again.'),
                  ],
                ),

                _buildSection(
                  key: _notificationsKey,
                  title: '6. Notifications',
                  children: [
                    _p(
                      'The app is designed to keep players and captains informed as fixtures move through their life-cycle. Some notification delivery channels are still being completed, but the expected behaviour is set out below.',
                    ),
                    _subHeading('Players may receive notifications when'),
                    _bullet('they are selected for a fixture or team match'),
                    _bullet('they are made a reserve'),
                    _bullet('they are asked to act as a marker or umpire'),
                    _bullet('a fixture is first published'),
                    _bullet('a date, time, rink or team arrangement changes'),
                    _bullet('they are promoted from reserve to player'),
                    _subHeading('Captains may receive notifications when'),
                    _bullet('a player accepts their place'),
                    _bullet('a player declines their place'),
                    _bullet('changes happen to a fixture they are responsible for'),
                    _subHeading('Notification channels'),
                    _bullet('In-app notifications'),
                    _bullet('Email notifications where enabled'),
                    _bullet('Other messaging routes as these are developed'),
                    _subHeading('Turning on mobile notifications'),
                    _p(
                      'On iPhone and Android, notifications usually need to be allowed on the device the first time the app asks. If declined, they can normally be turned back on in the phone\'s Settings under Apps or Notifications for the Bowls App.',
                    ),
                  ],
                ),

                _buildSection(
                  key: _internalFixturesKey,
                  title: '7. Internal Match Fixtures',
                  children: [
                    _p(
                      'Some internal fixtures may be arranged directly by members. These are simplified fixtures intended for smaller member-organised matches and competitions.',
                    ),
                    _subHeading('How they work'),
                    _bullet('A member creates the internal fixture.'),
                    _bullet('The creator automatically becomes the captain and takes responsibility for the fixture.'),
                    _bullet('The key task is usually agreeing a date and time and booking the rink or rinks needed.'),
                    _bullet('The players involved, and where needed a marker or umpire, are then added.'),
                    _subHeading('Why this matters'),
                    _p(
                      'These fixtures are often arranged directly between the players, so changes to time or date are more likely than in normal club-managed fixtures.',
                    ),
                    _subHeading('Expected notifications'),
                    _bullet('All involved players should be informed when the fixture is created'),
                    _bullet('All involved players should be told if the date or time changes'),
                    _bullet('All involved players should be told if rink bookings or player details change'),
                    _p(
                      'This area of the app is still being mapped out in more detail, but players should expect a simple, practical process focused on arranging the game and securing the rink booking.',
                    ),
                  ],
                ),

                _buildSection(
                  key: _fixtureSheetsKey,
                  title: '8. Fixture Sheets',
                  children: [
                    _p(
                      'Once a fixture has been published, you may be able to view the fixture sheet or team sheet for that match.',
                    ),
                    _bullet('Check the date and start time carefully'),
                    _bullet('Check whether the match is home or away'),
                    _bullet('Check your rink and team position if shown'),
                    _bullet('Check the captain and any important contact information'),
                    _bullet('Check again nearer the day in case any updates have been made'),
                  ],
                ),

                _buildSection(
                  key: _commonQuestionsKey,
                  title: '9. Common Questions',
                  children: [
                    _subHeading('Why can’t I see a fixture?'),
                    _p(
                      'It may not yet have been published to players, or it may not apply to you.',
                    ),
                    _subHeading('Can I change my response?'),
                    _p(
                      'In many cases yes, provided selection or publication has not passed the point where changes are locked down.',
                    ),
                    _subHeading('What should I do if I accepted and can no longer play?'),
                    _p(
                      'You should tell the fixture captain or club organiser as soon as possible.',
                    ),
                    _subHeading('Why have I received a change notification?'),
                    _p(
                      'This usually means something important about the fixture has been updated, such as the team, rink, date or time.',
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