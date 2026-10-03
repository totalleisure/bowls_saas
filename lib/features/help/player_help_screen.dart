import 'package:flutter/material.dart';
import 'admin_help_screen.dart';

class PlayerHelpScreen extends StatefulWidget {
  final bool showAdminGuide;

  const PlayerHelpScreen({super.key, this.showAdminGuide = false});

  @override
  State<PlayerHelpScreen> createState() => _PlayerHelpScreenState();
}

class _PlayerHelpScreenState extends State<PlayerHelpScreen> {
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
  final _adminGuideKey = GlobalKey();

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
      return 'assets/images/blank_bg_desktop_2.png';
    } else if (width >= 600) {
      return 'assets/images/blank_bg_tablet_2.png';
    } else {
      return 'assets/images/blank_bg_phone_2.png';
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
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
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
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(height: 1.4),
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
            color: Colors.white.withValues(alpha: 0.65),
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
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
      appBar: AppBar(title: const Text('User Guide')),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              _backgroundImageForWidth(context),
              fit: BoxFit.cover,
              color: Colors.black.withValues(alpha: 0.45),
              colorBlendMode: BlendMode.darken,
            ),
          ),
          Positioned.fill(
            child: Container(color: Colors.white.withValues(alpha: 0.65)),
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
                    color: Colors.white.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
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
                        'Bowls App Player User Guide',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      _p(
                        'This guide explains how to use the Bowls App from a player\'s point of view. You can scroll through the full guide or jump straight to any topic below.',
                      ),
                      const SizedBox(height: 8),
                      _topicButton("1. Getting Started", _topic1Key),
                      _topicButton("2. Options and Navigation", _topic2Key),
                      _topicButton(
                        "3. Dashboard and Your Commitments",
                        _topic3Key,
                      ),
                      _topicButton("4. The Four Diary Views", _topic4Key),
                      _topicButton(
                        "5. Filters: What Is Shown and Hidden",
                        _topic5Key,
                      ),
                      _topicButton(
                        "6. Availability, Selection and Acceptance",
                        _topic6Key,
                      ),
                      _topicButton("7. Events and Open Sessions", _topic7Key),
                      _topicButton(
                        "8. Your Internal Fixture Bookings",
                        _topic8Key,
                      ),
                      _topicButton(
                        "9. Fixture Details, Sheets and Notifications",
                        _topic9Key,
                      ),
                      _topicButton(
                        "10. Membership, Account and Volunteer Lists",
                        _topic10Key,
                      ),
                      _topicButton("11. Common Questions", _topic11Key),
                      if (widget.showAdminGuide)
                        _topicButton(
                          "12. Club Admin & Selector Guide",
                          _adminGuideKey,
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                _buildSection(
                  key: _topic1Key,
                  title: "1. Getting Started",
                  children: [
                    _p(
                      "Use this guide for playing, organising your own bookings and following club activity. Tap a topic to jump to it, or use Back to Topics at the end of a section.",
                    ),
                    _bullet(
                      "Install or update the app using the link or instructions supplied by your club. Follow your invitation instructions to set up access; an existing account may already have a password.",
                    ),
                    _bullet(
                      "Sign in with your login email and password, then select your club. If an invitation or recovery email is missing, check Junk or Spam and confirm the address with the club.",
                    ),
                    _bullet(
                      "Opening a club uses your chosen starting screen: Dashboard, Monthly Diary or Diary List. Dashboard is the default.",
                    ),
                    _bullet(
                      "Use Options → Starting screen to change this. The choice is saved for your account and that club on this device; choose it separately on another device.",
                    ),
                    _bullet(
                      "An inactive membership or account-access issue may prevent entry. Contact the club rather than creating another account.",
                    ),
                    _bullet(
                      "Use Need Help on the sign-in screen for guidance before logging in.",
                    ),
                  ],
                ),

                _buildSection(
                  key: _topic2Key,
                  title: "2. Options and Navigation",
                  children: [
                    _p(
                      "Options is the three-dot button at the right of the toolbar. It is available from the Dashboard and Diary views. The coloured icons help distinguish actions; your permissions determine which actions are available.",
                    ),
                    _bullet(
                      "Dashboard, Monthly Diary and Diary List switch your current view. Switching views does not change your saved starting screen.",
                    ),
                    _bullet(
                      "Starting screen chooses the view to open next time you enter the club.",
                    ),
                    _bullet(
                      "Membership Details opens the membership directory and details available to you. Respect members’ contact-sharing preferences.",
                    ),
                    _bullet(
                      "Account and Security lets you change your login email or password.",
                    ),
                    _bullet(
                      "Volunteer Lists lets eligible members join or leave the club lists available to them. My fixture bookings opens your member-booking view.",
                    ),
                    _bullet(
                      "Notifications opens your in-app messages. User Guide returns to this guide.",
                    ),
                    _bullet(
                      "Club administration appears only when your permissions allow it. View-only members do not receive the same editing and booking controls as active playing members.",
                    ),
                    _p(
                      "Within the Diary, use Month, List, Day and Rinks to change the diary view. Use Back to return to the previous screen.",
                    ),
                  ],
                ),

                _buildSection(
                  key: _topic3Key,
                  title: "3. Dashboard and Your Commitments",
                  children: [
                    _p(
                      "The Dashboard is personal: it highlights responses, commitments and responsibilities. Use the Diary to browse wider club activity.",
                    ),
                    _subHeading("Dashboard sections"),
                    _bullet(
                      "Fixtures needing your Acceptance: you have a published selection and must accept or decline. Selecting or allocating a player in a draft team does not itself create this request.",
                    ),
                    _bullet(
                      "Fixtures you have Accepted (upcoming): your accepted upcoming selections. Check whether you are a player or reserve and read the fixture details.",
                    ),
                    _bullet(
                      "Fixtures you can RSVP to: availability or attendance responses that are open to you. An existing Yes, Maybe or No can still be displayed here.",
                    ),
                    _bullet(
                      "Fixtures you are managing: fixtures for which you are a captain, vice-captain, organiser or deputy, as applicable. A fixture can also appear in a personal section when you participate in it.",
                    ),
                    _bullet(
                      "Fixtures Awaiting Team Selection and Open Sessions and Events show further relevant activity.",
                    ),
                    _subHeading("Protected sections"),
                    _p(
                      "Dashboard filters do not hide fixtures needing your acceptance, your upcoming accepted fixtures or fixtures you manage. For example, a male manager can still see a Ladies fixture he manages when browsing with a Men filter.",
                    ),
                    _p(
                      "Other Dashboard sections can be narrowed by filters. Check the active-filter summary and the showing/filtered-out counts before assuming a fixture is missing.",
                    ),
                  ],
                ),

                _buildSection(
                  key: _topic4Key,
                  title: "4. The Four Diary Views",
                  children: [
                    _bullet(
                      "Month: see activity arranged in a monthly calendar. Move between months, return to today, or open a date or fixture.",
                    ),
                    _bullet(
                      "List: browse date-grouped cards for club activity you are permitted to see, including matches, events, open sessions and active green maintenance.",
                    ),
                    _bullet(
                      "Day: inspect activity for a particular day and move to neighbouring days.",
                    ),
                    _bullet(
                      "Rinks: inspect the day’s green and rink usage, including maintenance. Booking or editing controls depend on your role.",
                    ),
                    _subHeading("Using Diary List"),
                    _bullet(
                      "Scroll towards earlier or later dates. Earlier dates and Later dates also load more dates when the current range is empty or filtered. The loaded date range is shown above the cards.",
                    ),
                    _bullet(
                      "Choose date jumps to a date. Today returns to today when you have moved away. Refresh diary reloads the current date range; use it after changes made elsewhere.",
                    ),
                    _bullet(
                      "Search by words from the fixture label, type, team, opponent, venue or green. All entered words must match the descriptive information; search works together with your filters.",
                    ),
                    _bullet(
                      "Tap a fixture or event card for its existing details. A maintenance card opens its maintenance details. Cancelled entries are labelled; check the current status before travelling.",
                    ),
                    _bullet(
                      "The showing and filtered-out counts refer to the loaded dates, not every entry in the club’s entire diary.",
                    ),
                    _subHeading("Your involvement and Next match"),
                    _bullet(
                      "Small badges identify published selections: You’re playing, You’re a reserve, or Awaiting your acceptance. You’re managing or You’re organising identifies your responsibility. A card can carry more than one badge.",
                    ),
                    _bullet(
                      "Next match finds your next upcoming, published, accepted selection, including a reserve selection. Cancelled fixtures are excluded. It can find a fixture beyond the currently loaded dates and jump to its card.",
                    ),
                    _bullet(
                      "If filters or search hide that fixture, the app explains this and offers Open details or Keep browsing. It does not change or override your filters.",
                    ),
                    _bullet(
                      "If personal markers cannot be loaded, the club diary remains available with an explanatory message. Refresh to try again; absence of a badge is not proof that you are uninvolved.",
                    ),
                  ],
                ),

                _buildSection(
                  key: _topic5Key,
                  title: "5. Filters: What Is Shown and Hidden",
                  children: [
                    _p(
                      "The Dashboard and Diary List have different purposes and separate saved filters. Diary List initially shows all permitted activity. Its filters are saved for your account and club on this device.",
                    ),
                    _subHeading("Fixture types, tags and sections"),
                    _bullet(
                      "All types includes every fixture type. None selects no types. A deliberate empty selection stays empty; it does not mean All.",
                    ),
                    _bullet(
                      "Tags select groups of fixture types. From All, selecting a tag narrows the types to that group. Adding other groups or individual types includes them too: this is OR between the selected types.",
                    ),
                    _bullet(
                      "Selecting a fully selected tag removes its group. Selecting a partly selected tag includes the whole group. Shared types can affect the counts shown on other tags.",
                    ),
                    _bullet(
                      "Counts such as Leagues (9 of 10) describe selected fixture types in that tag, not the number of fixtures. Review the individual type selections if unsure.",
                    ),
                    _bullet(
                      "Section applies to every selected type. All sections includes Open / everyone, Men, Ladies and Mixed. Selecting none hides all ordinary filtered entries.",
                    ),
                    _subHeading("Periods"),
                    _bullet(
                      "Rest of this month runs from today to the end of the current month. Next calendar month excludes the current month.",
                    ),
                    _bullet(
                      "Next 3 months runs from today through the corresponding date three months ahead, using the last valid day if necessary. It does not mean this month plus three complete calendar months.",
                    ),
                    _bullet(
                      "All upcoming is the Dashboard’s unrestricted upcoming period. All dates in Diary List also permits earlier entries as you browse backwards.",
                    ),
                    _subHeading("Additional Diary List controls"),
                    _bullet(
                      "Home / away and team choices combine with the type, section, period and search criteria. An entry must pass all these restrictions. No team shows entries with no team assigned.",
                    ),
                    _bullet(
                      "Every Diary List entry obeys the filters, including your own accepted or managed fixtures. There are no protected-section exceptions in this view.",
                    ),
                    _bullet(
                      "Clear search removes the search words. Clear filters in Diary List removes all narrowing, including search. Reset on the filter screen resets that screen’s choices; use Return to apply them.",
                    ),
                    _bullet(
                      "Saved filters can survive a restart. Check Filters active and the filtered-out count whenever the diary looks unexpectedly quiet. Filters never grant access to entries you are not permitted to see.",
                    ),
                  ],
                ),

                _buildSection(
                  key: _topic6Key,
                  title: "6. Availability, Selection and Acceptance",
                  children: [
                    _p(
                      "Availability and acceptance are different steps. Saying you can play does not mean you have been selected or accepted a published place.",
                    ),
                    _bullet(
                      "For an RSVP or availability request, Yes means available, Maybe means uncertain, and No means unavailable. Use the controls offered on that fixture.",
                    ),
                    _bullet(
                      "The captain or selector reviews the pool and prepares the team. A draft selection or rink position is not yet a published invitation.",
                    ),
                    _bullet(
                      "Once the team is published, selected players and reserves should check their role and respond to the acceptance request promptly.",
                    ),
                    _bullet(
                      "Accept if you can fulfil that selection. Decline promptly if you cannot, so a replacement can be arranged.",
                    ),
                    _bullet(
                      "If you can no longer play after accepting, use the response or withdrawal controls available in the fixture and contact the captain promptly. Do not assume changing an RSVP alone withdraws a published selection.",
                    ),
                    _bullet(
                      "A declined RSVP can remain visible while responses are open. Its presence does not mean your decline was lost.",
                    ),
                    _bullet(
                      "After rescheduling, availability can be requested again, including from players already selected. Recheck the new date and respond again as requested; a fixture may be both an accepted commitment and open for RSVP.",
                    ),
                  ],
                ),

                _buildSection(
                  key: _topic7Key,
                  title: "7. Events and Open Sessions",
                  children: [
                    _p(
                      "A non-playing event, such as a quiz, AGM or meeting, can request attendance numbers without using team selection or rinks.",
                    ),
                    _bullet(
                      "When the organiser enables Request RSVPs, open the event and use its attendance controls. These responses help the organiser estimate numbers; they are not acceptance of a playing position.",
                    ),
                    _bullet(
                      "When Request RSVPs is off, attendance is open and no response is required. No-rinks event cards omit playing formats and rink counts.",
                    ),
                    _bullet(
                      "A Club Event has an Organiser and can have a Deputy Organiser. Open its details for the event information and contacts.",
                    ),
                    _bullet(
                      "A genuine Open Session is for activity without team-selection acceptance or RSVP attendance controls. Open its card for the label, time and relevant green/rink information.",
                    ),
                  ],
                ),

                _buildSection(
                  key: _topic8Key,
                  title: "8. Your Internal Fixture Bookings",
                  children: [
                    _p(
                      "Where your club enables member booking for a fixture type, use Options → My fixture bookings. Only the types and actions available to your membership can be used.",
                    ),
                    _bullet(
                      "Agree the match arrangements, then choose the appropriate internal fixture type, date, start/end time and Fixture label where useful.",
                    ),
                    _bullet(
                      "Check the green, rink requirement and available time. Reserving rink capacity and assigning actual rink numbers are separate steps.",
                    ),
                    _bullet(
                      "Add the players, opponents and any required marker or officials using the controls offered by that fixture type. Being the creator or captain is not a substitute for checking the playing positions.",
                    ),
                    _bullet(
                      "The creating member normally becomes the fixture captain. Check this and the assignments before confirming the booking.",
                    ),
                    _bullet(
                      "Review the saved fixture and any outstanding responses. Maintain the date, time, rink and participant details, and communicate changes to those affected.",
                    ),
                    _bullet(
                      "If a change affects a published team, follow its review and confirmation process. Read warnings before changing a playing format because incompatible assignments may be removed.",
                    ),
                  ],
                ),

                _buildSection(
                  key: _topic9Key,
                  title: "9. Fixture Details, Sheets and Notifications",
                  children: [
                    _bullet(
                      "Open a fixture card to check its date/time, home or away status, venue, organiser or captain, team position and assigned rink. A rink number may be allocated later.",
                    ),
                    _bullet(
                      "Use fixture or team sheets where available. Recheck the current app details after a change; an older downloaded PDF or email can be out of date.",
                    ),
                    _bullet(
                      "Use Options → Notifications, or the Dashboard notification bell, for in-app messages. Open a relevant message to review the fixture.",
                    ),
                    _bullet(
                      "Selection, reserves, confirmed changes, cancellations and rescheduling can generate messages. Email depends on the club’s settings, your address and delivery status.",
                    ),
                    _bullet(
                      "Do not rely solely on an email arriving or a phone alert appearing. Check the app for current selections and messages, and check Junk or Spam when an expected email is missing.",
                    ),
                  ],
                ),

                _buildSection(
                  key: _topic10Key,
                  title: "10. Membership, Account and Volunteer Lists",
                  children: [
                    _bullet(
                      "Options → Membership Details opens the membership information available to you. Keep your own contact details accurate and review any contact-sharing choices.",
                    ),
                    _bullet(
                      "Options → Account and Security → Change login email asks for your current password and the new address. Complete the confirmation-code step sent to the new address. Editing a contact field is not a substitute for changing your login email.",
                    ),
                    _bullet(
                      "Change password asks for the current password and matching new-password entries. Follow the requirements shown. If you cannot sign in, use the sign-in recovery options or contact the club.",
                    ),
                    _bullet(
                      "Options → Volunteer Lists lets you join or leave available lists where your membership allows this. These list preferences are separate from team selection and fixture RSVP responses.",
                    ),
                    _bullet(
                      "If an action is missing, it may not be available to your membership role. Ask a club administrator rather than using another member’s account.",
                    ),
                  ],
                ),

                _buildSection(
                  key: _topic11Key,
                  title: "11. Common Questions",
                  children: [
                    _subHeading("Why is a fixture missing?"),
                    _p(
                      "Check the current view, loaded dates, search, sections, types, period and home/team choices. Clear filters and refresh if appropriate. The Dashboard is personal; the Diary is broader, subject to your access permissions.",
                    ),
                    _subHeading(
                      "Why can I still see an accepted fixture with Dashboard filters set to None?",
                    ),
                    _p(
                      "Acceptance requests, accepted upcoming fixtures and managed fixtures are protected on the Dashboard. Diary List has no such exceptions.",
                    ),
                    _subHeading(
                      "Why did my chosen starting screen not appear on another device?",
                    ),
                    _p(
                      "Starting-screen choices are saved per account and club on each device. Set the preference again there.",
                    ),
                    _subHeading(
                      "Why am I seeing RSVP for a fixture I already accepted?",
                    ),
                    _p(
                      "A rescheduled fixture can reopen availability so the same players can confirm the new arrangements. Read the new date and the current response status.",
                    ),
                    _subHeading(
                      "Why does Next match say my fixture is hidden?",
                    ),
                    _p(
                      "Your current Diary filters or search exclude it. Open details directly or change the filters yourself; the shortcut does not silently override them.",
                    ),
                    _subHeading("The diary has not reflected a recent change"),
                    _p(
                      "Refresh the view. If a load or connection error remains, keep the exact message and contact the club. Avoid repeatedly submitting a booking or response whose result is unclear.",
                    ),
                  ],
                ),

                if (widget.showAdminGuide)
                  _buildSection(
                    key: _adminGuideKey,
                    title: "12. Club Admin & Selector Guide",
                    children: [
                      _p(
                        'The administrator guide covers setup, fixture types, team publication and confirmation, rescheduling, invitations and member support. Available actions still depend on your permissions.',
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.admin_panel_settings_outlined),
                        label: const Text('Open Admin Guide'),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const AdminHelpScreen(),
                          ),
                        ),
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
