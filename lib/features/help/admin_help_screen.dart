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
  final _topic1Key = GlobalKey();
  final _topic2Key = GlobalKey();
  final _topic3Key = GlobalKey();
  final _topic4Key = GlobalKey();
  final _topic5Key = GlobalKey();
  final _topic6Key = GlobalKey();
  final _topic7Key = GlobalKey();
  final _topic8Key = GlobalKey();
  final _topic9Key = GlobalKey();
  final _topic10Key = GlobalKey();
  final _topic11Key = GlobalKey();
  final _topic12Key = GlobalKey();
  final _topic13Key = GlobalKey();

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
          color: Colors.black.withValues(alpha: 0.85),
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
                color: Colors.black.withValues(alpha: 0.85),
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
          color: Colors.black.withValues(alpha: 0.9),
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
            color: Colors.white.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
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
        color: Colors.white.withValues(alpha: 0.80),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
              color: Colors.black.withValues(alpha: 0.9),
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
                color: Colors.black.withValues(alpha: 0.20),
                colorBlendMode: BlendMode.darken,
              ),
            ),
          ),
          Positioned.fill(
            child: Container(color: Colors.white.withValues(alpha: 0.62)),
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
                    color: Colors.white.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
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
                      _topicButton(
                        "1. Administration and Member Navigation",
                        _topic1Key,
                      ),
                      _topicButton(
                        "2. Club Setup, Venues and Greens",
                        _topic2Key,
                      ),
                      _topicButton(
                        "3. Fixture Types, Tags and Participation Modes",
                        _topic3Key,
                      ),
                      _topicButton(
                        "4. Creating Fixtures, Events and Open Sessions",
                        _topic4Key,
                      ),
                      _topicButton(
                        "5. Teams, Captains and Selection",
                        _topic5Key,
                      ),
                      _topicButton(
                        "6. Publishing and Confirming Team Changes",
                        _topic6Key,
                      ),
                      _topicButton(
                        "7. Rink Capacity, Positions and Maintenance",
                        _topic7Key,
                      ),
                      _topicButton(
                        "8. Fixture Sheets, Responses and Reminders",
                        _topic8Key,
                      ),
                      _topicButton(
                        "9. Rescheduling and Cancellation",
                        _topic9Key,
                      ),
                      _topicButton(
                        "10. Member-Booked Internal Fixtures",
                        _topic10Key,
                      ),
                      _topicButton(
                        "11. Membership Imports, Invitations and Accounts",
                        _topic11Key,
                      ),
                      _topicButton(
                        "12. Communication and Volunteer Lists",
                        _topic12Key,
                      ),
                      _topicButton(
                        "13. Supporting Members: Diary, Filters and Starting Screens",
                        _topic13Key,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                _buildSection(
                  key: _topic1Key,
                  title: "1. Administration and Member Navigation",
                  children: [
                    _p(
                      "This guide covers club setup and fixture management. Use Options → Club administration where your permissions allow it. A club role, team responsibility and responsibility for one fixture are not interchangeable.",
                    ),
                    _bullet(
                      "Options is the three-dot control at the right of the Dashboard and Diary toolbars. It provides view switching, Starting screen, membership/account actions, notifications and User Guide. Member booking and volunteer actions depend on access.",
                    ),
                    _bullet(
                      "Members can start in Dashboard, Monthly Diary or Diary List. The preference is saved per member and club on that device. Changing the current view does not change the preference.",
                    ),
                    _bullet(
                      "A fixture captain or vice-captain can have fixture-specific responsibilities without becoming a club administrator. Club administration and editing actions remain subject to permissions.",
                    ),
                    _bullet(
                      "An inactive membership or a view-only role must not be treated as an active playing membership. Check access when a member reports missing controls.",
                    ),
                  ],
                ),

                _buildSection(
                  key: _topic2Key,
                  title: "2. Club Setup, Venues and Greens",
                  children: [
                    _bullet(
                      "Create the club’s home venue and check its address and contact information. Mark the home venue correctly and maintain opponent venues for away matches.",
                    ),
                    _bullet(
                      "Add the relevant greens, indoor/outdoor settings, rink capacity and rink numbering or custom labels. If rink widths vary, use the supported maximum capacity and check the operating layout.",
                    ),
                    _bullet(
                      "Set up fixture types, colour schemes, participation modes and member-booking rules before loading the season.",
                    ),
                    _bullet(
                      "Create teams and maintain their member pools. Link season fixtures to the correct team where team availability and selection should apply.",
                    ),
                    _bullet(
                      "Review the club’s communications settings and responsible officers. Verify key details with a sample fixture before creating a large batch.",
                    ),
                  ],
                ),

                _buildSection(
                  key: _topic3Key,
                  title: "3. Fixture Types, Tags and Participation Modes",
                  children: [
                    _p(
                      "A Fixture Type defines behaviour as well as appearance. Its settings affect the creation form, participation controls, rink requirements and visibility under member filters.",
                    ),
                    _bullet(
                      "Team Selection: team availability and selection lead to publication and acceptance of selected places.",
                    ),
                    _bullet(
                      "RSVP: collect Yes, Maybe or No availability before selecting players where a playing team is required. Event attendance can also use RSVPs without team selection.",
                    ),
                    _bullet(
                      "Pre-Select: choose participants directly using the fixture’s supported controls, without relying on an RSVP pool.",
                    ),
                    _bullet(
                      "Open Session: activity without team-selection acceptance or RSVP attendance controls. Choose another supported mode if responses are required.",
                    ),
                    _bullet(
                      "Uses rinks distinguishes playing/green bookings from no-rinks events. Check default rink numbers, formats, player numbers, internal status and whether members may create bookings.",
                    ),
                    _bullet(
                      "Colours identify fixture types on cards and in the diary. Use readable foreground/background combinations.",
                    ),
                    _bullet(
                      "Tags group fixture types in filters. They are not separate fixture counts. A type can belong to more than one tag; overlapping groups affect the selected-type counts.",
                    ),
                    _bullet(
                      "Check section and tag settings carefully. They influence what members see when filtering; a misclassified event or fixture can be hidden by an otherwise reasonable filter.",
                    ),
                  ],
                ),

                _buildSection(
                  key: _topic4Key,
                  title: "4. Creating Fixtures, Events and Open Sessions",
                  children: [
                    _bullet(
                      "Choose the Fixture Type first, then check the date, start/end time, home/away setting, opponent, venue, team and Fixture label.",
                    ),
                    _bullet(
                      "Fixture label gives an event or open session a useful name. Check how the saved card reads rather than relying only on a generic type name.",
                    ),
                    _bullet(
                      "For playing fixtures, check green, rink requirements, playing formats and captain/vice-captain. Selecting players and assigning them to positions are separate checks.",
                    ),
                    _bullet(
                      "For a no-rinks Club Event, assign an Organiser. A Deputy Organiser is optional and must be a different member. The event cannot be left without an Organiser.",
                    ),
                    _bullet(
                      "Use Request RSVPs for an event when attendance numbers are needed. When enabled, members can answer Yes, No or Maybe; when disabled, attendance is open without a response requirement.",
                    ),
                    _bullet(
                      "For a genuine Open Session, check the label, time and relevant rink/green details. Do not expect team-acceptance or RSVP attendance buttons.",
                    ),
                    _bullet(
                      "Read any playing-format warning before continuing. Format changes can remove draft rink, player, opponent or marker assignments that no longer fit; inspect the resulting arrangement.",
                    ),
                  ],
                ),

                _buildSection(
                  key: _topic5Key,
                  title: "5. Teams, Captains and Selection",
                  children: [
                    _p(
                      "A team is a reusable member pool. A fixture’s selection is the group chosen for that particular match. Keeping the team pool current does not remove the need to review each fixture.",
                    ),
                    _bullet(
                      "Enter known season fixtures early and link them to the intended team so eligible members can respond to availability requests.",
                    ),
                    _bullet(
                      "Review Yes, Maybe and No responses. The available selection pool depends on whether the fixture uses a team, RSVP or direct selection.",
                    ),
                    _bullet(
                      "Select the required players and reserves. Allocate playing members to the correct rink/team and position; being selected alone does not prove the positions are filled.",
                    ),
                    _bullet(
                      "Check mixed-format arrangements rink by rink. Do not assume every rink has the same number of players.",
                    ),
                    _bullet(
                      "The fixture captain manages that match; the vice-captain supports them. Events use Organiser and Deputy Organiser terminology. Verify the nominated people and contacts.",
                    ),
                    _bullet(
                      "Before publication, selections are drafts. Members should not receive a published-team acceptance request merely because they were selected or put in a position.",
                    ),
                  ],
                ),

                _buildSection(
                  key: _topic6Key,
                  title: "6. Publishing and Confirming Team Changes",
                  children: [
                    _subHeading("First publication"),
                    _bullet(
                      "Review selected players, reserves, positions, rinks and contacts before publishing. Publication is the point at which selected members are formally asked to respond.",
                    ),
                    _bullet(
                      "The app can warn that the team is incomplete and offer Publish anyway. Treat this as a deliberate decision after checking the gaps, not evidence that the fixture is fully staffed.",
                    ),
                    _bullet(
                      "Publishing an incomplete team is not, by itself, a new rule to keep RSVP recruitment open. Check the fixture’s actual participation and rescheduling state.",
                    ),
                    _subHeading("Changes to an already published team"),
                    _bullet(
                      "Where Confirm Team Changes is shown, player, reserve, position and team-structure edits are staged for review. Apply in a sub-dialog applies the draft change; it is not the final save.",
                    ),
                    _bullet(
                      "Resolve any unpositioned players, then press Confirm Team Changes. Read Review team changes, including affected players and the messages that will be queued.",
                    ),
                    _bullet(
                      "Confirm and save saves the reviewed changes together. Keep editing returns without saving or sending them. Do not leave assuming staged changes have already been applied.",
                    ),
                    _bullet(
                      "Publication controls are unavailable while staged changes still need confirmation. Finish the review rather than repeatedly trying Publish.",
                    ),
                    _bullet(
                      "For promotions, removals, reserve changes and replacements, use the current review to see who will be notified. Do not assume every small edit sends the same message to everyone.",
                    ),
                  ],
                ),

                _buildSection(
                  key: _topic7Key,
                  title: "7. Rink Capacity, Positions and Maintenance",
                  children: [
                    _p(
                      "Rink capacity, physical rink assignment and player position are different things. A fixture can reserve a number of rinks before the actual rink labels are assigned.",
                    ),
                    _bullet(
                      "Check the fixture’s start/end time and required rink capacity. Review availability before choosing physical rinks.",
                    ),
                    _bullet(
                      "Assign the actual rink numbers or labels when known. Check player positions within each playing team separately.",
                    ),
                    _bullet(
                      "Use Diary → Rinks to inspect usage and active maintenance. Check that bookings do not conflict with blocked periods or the operating layout.",
                    ),
                    _bullet(
                      "Active green maintenance also appears in Diary List for members permitted to see it. Its details show the green, rink, reason and time interval.",
                    ),
                    _bullet(
                      "If changing a published team’s formats or structure, review the affected assignments and complete Confirm Team Changes where offered. Recheck the resulting fixture sheet.",
                    ),
                  ],
                ),

                _buildSection(
                  key: _topic8Key,
                  title: "8. Fixture Sheets, Responses and Reminders",
                  children: [
                    _bullet(
                      "Review the current fixture sheet for date/time, venue, home/away status, team/rink groupings, formats, positions, reserves and captain details.",
                    ),
                    _bullet(
                      "A downloaded or emailed sheet reflects the details at the time it was produced. Issue or view the current sheet after confirmed changes as appropriate.",
                    ),
                    _bullet(
                      "Monitor pending, accepted and declined responses. An RSVP Yes is availability, not acceptance of a published selection.",
                    ),
                    _bullet(
                      "Use Send reminder where offered for members who still need to respond. Do not assume an automatic reminder has been sent or that a delivered email has been read.",
                    ),
                    _bullet(
                      "If someone declines or withdraws, review the replacement and affected positions. Complete the applicable confirmation process before treating the new team as final.",
                    ),
                    _bullet(
                      "Email and teamsheet delivery depend on club settings, valid addresses and processing. A queued message is not a guarantee of inbox delivery.",
                    ),
                  ],
                ),

                _buildSection(
                  key: _topic9Key,
                  title: "9. Rescheduling and Cancellation",
                  children: [
                    _bullet(
                      "Use the fixture’s rescheduling or cancellation controls and read the confirmation. Check linked fixtures and the resulting date, time, rinks and current status.",
                    ),
                    _bullet(
                      "Rescheduling can reopen RSVP availability so the same players can reconfirm the new arrangements, including players already selected. This is intentional and is separate from whether every team position is filled.",
                    ),
                    _bullet(
                      "A member can therefore see a fixture in an accepted section and still have an open RSVP for the changed date. Check the response state before treating this as a duplicate or a lost reply.",
                    ),
                    _bullet(
                      "Review player acceptance requirements and communications after the change; do not assume old availability still applies to the new date.",
                    ),
                    _bullet(
                      "Cancelled entries are labelled in Diary List and excluded from its Next match lookup. Remind members to check the latest fixture details rather than an old PDF or email.",
                    ),
                  ],
                ),

                _buildSection(
                  key: _topic10Key,
                  title: "10. Member-Booked Internal Fixtures",
                  children: [
                    _bullet(
                      "Enable member booking only for the intended fixture types. Check sensible rink, format and participant requirements.",
                    ),
                    _bullet(
                      "Members enter through Options → My fixture bookings where their membership permits it. View-only members do not have the same booking controls.",
                    ),
                    _bullet(
                      "The creating member normally becomes the fixture captain. Check actual player, opponent and marker assignments; captaincy is not itself a playing position.",
                    ),
                    _bullet(
                      "Members agree the time, create the fixture, reserve/assign rinks and add participants using the fixture-type controls. Administrators can assist with corrections where authorised.",
                    ),
                    _bullet(
                      "For subsequent changes, review availability, rink usage and any confirmation or publication requirements. Use the current fixture details as the source of truth.",
                    ),
                  ],
                ),

                _buildSection(
                  key: _topic11Key,
                  title: "11. Membership Imports, Invitations and Accounts",
                  children: [
                    _bullet(
                      "Maintain accurate names, contact details, membership roles and active status. Check for an existing member before creating a duplicate.",
                    ),
                    _bullet(
                      "Importing member data and sending invitations are separate operations. Review import results before opening Review member invitations.",
                    ),
                    _bullet(
                      "Choose and preview the appropriate guide/email content, then Prepare invitation review. Resolve exceptions and select the intended recipients before Send invitations.",
                    ),
                    _bullet(
                      "Leave Resend invitations to previously invited members unchecked unless a deliberate resend is needed. Previously accepted invitations are skipped by default.",
                    ),
                    _bullet(
                      "Review the sending results. If sending stops after a rejected or uncertain result, prepare a new review before retrying; do not blindly resend the entire batch.",
                    ),
                    _bullet(
                      "Accepted for sending means the email service accepted the request, not that the invitation reached the inbox. Check delivery information and contact details when investigating a missing invitation.",
                    ),
                    _bullet(
                      "Members change login email and password through Options → Account and Security. Changing a directory contact value is not the same as changing the sign-in email.",
                    ),
                    _bullet(
                      "Membership directory contact visibility follows members’ sharing choices and your access. Use appropriate permissions rather than sharing administrator credentials.",
                    ),
                  ],
                ),

                _buildSection(
                  key: _topic12Key,
                  title: "12. Communication and Volunteer Lists",
                  children: [
                    _bullet(
                      "Use Options → Notifications to review in-app messages. Member and captain messages depend on the action performed and the club’s communications settings.",
                    ),
                    _bullet(
                      "Published selections, confirmed composition changes, reserves, response changes, cancellations and rescheduling can generate notifications and email. Check the review/results rather than assuming every edit sends a message.",
                    ),
                    _bullet(
                      "Members use Options → Volunteer Lists to join or leave available lists. Club mailing-list administration is a separate responsibility.",
                    ),
                    _bullet(
                      "Check recipient selection and message content before sending. Review failures or uncertain outcomes before retrying to avoid duplicate communications.",
                    ),
                    _bullet(
                      "Do not promise mobile push alerts, automatic reminders or inbox delivery solely because a message was queued. Ask members to check the app’s current fixture details and notifications.",
                    ),
                  ],
                ),

                _buildSection(
                  key: _topic13Key,
                  title:
                      "13. Supporting Members: Diary, Filters and Starting Screens",
                  children: [
                    _p(
                      "The Dashboard is personal and action-focused. Month, List, Day and Rinks are diary views. A member who wants general club activity can choose Monthly Diary or Diary List as their starting screen.",
                    ),
                    _bullet(
                      "The Dashboard protects acceptance requests, accepted upcoming fixtures and managed fixtures from its filters. Diary List applies filters strictly to every entry, including those commitments.",
                    ),
                    _bullet(
                      "Type tags select groups using OR between selected types. Section, period and the Diary’s home/team/search controls further narrow the results. None is a deliberate empty selection.",
                    ),
                    _bullet(
                      "Next calendar month excludes this month. Next 3 months is a rolling range from today, not this month plus three complete months. Diary All dates also supports browsing backwards.",
                    ),
                    _bullet(
                      "Diary filters are separate from Dashboard filters. Diary filters and starting-screen choices are saved per account and club on the device; they do not automatically follow a member to a second device.",
                    ),
                    _bullet(
                      "Diary List counts cover its displayed loaded-date range. Use Earlier dates, Later dates, Choose date, Today and Refresh diary when investigating missing activity.",
                    ),
                    _bullet(
                      "Diary involvement badges distinguish playing, reserve, pending acceptance and managing/organising. Draft selections are not shown as published involvement.",
                    ),
                    _bullet(
                      "Next match finds the next upcoming accepted selection, including reserves, and excludes cancelled fixtures. If filters/search hide it, members can open details without the filters being changed.",
                    ),
                    _bullet(
                      "Ask which view, date range, filters and account the member is using before changing a fixture. Check type/section/tag settings, membership access and publication status if the entry is still missing.",
                    ),
                    _bullet(
                      "In staging, the orange footer identifies the test environment. Confirm which environment is being used before investigating or making administrative changes.",
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
