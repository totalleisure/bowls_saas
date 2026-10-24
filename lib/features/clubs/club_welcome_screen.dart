import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'club_start_screen.dart';

const _views = [
  ClubStartView.list,
  ClubStartView.month,
  ClubStartView.dashboard,
];
const labels = ['List View', 'Month View', 'Dashboard'];
const headlines = [
  "What's happening at your Club?",
  'Your Club at a glance',
  'Playing for your Club?',
];
const descriptions = [
  'Browse upcoming activities, matches, roll-ups and competitions in date order. Find your next reason to come to the Club.',
  "See the whole month's activities in a familiar calendar. Plan ahead and make room for the games you love.",
  'Manage your matches, team selections, invitations and responses. Keep everything you need to play for your Club together.',
];
const photos = [
  'Members enjoying a friendly indoor bowls roll-up',
  'Option 2 · The Bigger Picture\nSeveral games across a large indoor bowling green',
  'Option 3 · Preparing to Play\nTeammates chatting and holding bowls',
];
const colors = [Color(0xffd73500), Color(0xff096621), Color(0xff123ea3)];

class ClubWelcomeScreen extends StatefulWidget {
  const ClubWelcomeScreen({
    super.key,
    required this.userId,
    required this.clubId,
    required this.clubName,
    required this.onOpen,
    this.initialChoice,
  });
  final String userId;
  final String clubId;
  final String clubName;
  final ClubStartView? initialChoice;
  final ValueChanged<ClubStartView> onOpen;
  @override
  State<ClubWelcomeScreen> createState() => _ClubWelcomeScreenState();
}

class _ClubWelcomeScreenState extends State<ClubWelcomeScreen> {
  int _brandingSetNo = 0;
  Color _brandInk = const Color(0xff234575);
  final ScrollController _introScroll = ScrollController();
  bool _introScrollable = false;
  @override
  void dispose() {
    _introScroll.dispose();
    super.dispose();
  }

  bool _introducing = true;
  int? selected = 0;
  int? saved;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _loadBranding();
    saved = widget.initialChoice == null
        ? null
        : _views.indexOf(widget.initialChoice!);
  }

  Future<void> _loadBranding() async {
    final prefs = await SharedPreferences.getInstance();
    // The club chooser already stores these settings. Never apply another
    // club's remembered branding when this route is opened independently.
    if (!mounted || prefs.getString('last_club_id') != widget.clubId) return;
    final requested = prefs.getInt('last_branding_set_no') ?? 0;
    final raw = (prefs.getString('last_primary_colour') ?? '').replaceAll(
      '#',
      '',
    );
    final parsed = raw.length == 6 ? int.tryParse('ff$raw', radix: 16) : null;
    setState(() {
      _brandingSetNo = {0, 2}.contains(requested) ? requested : 0;
      _brandInk = parsed == null ? const Color(0xff234575) : Color(parsed);
    });
  }

  String _background(double width) =>
      'assets/images/blank_bg_${width < 650
          ? 'phone'
          : width < 1100
          ? 'tablet'
          : 'desktop'}_$_brandingSetNo.png';

  Future<void> _setStartingView(int? index) async {
    setState(() => _saving = true);
    try {
      if (index == null) {
        await ClubStartPreference.clear(widget.userId, widget.clubId);
      } else {
        await ClubStartPreference.save(
          widget.userId,
          widget.clubId,
          _views[index],
        );
      }
      if (mounted) setState(() => saved = index);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Your starting screen could not be saved. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 44,
      title: Text(
        widget.clubName,
        maxLines: 2,
        style: const TextStyle(fontSize: 17, height: 1.1),
      ),
    ),
    body: SafeArea(
      top: false,
      child: _introducing ? introduction() : welcomeBody(),
    ),
  );

  Widget introduction() => LayoutBuilder(
    builder: (context, size) {
      final wide = size.maxWidth >= 1200;
      final tablet = size.maxWidth >= 650 && !wide;
      final compact = size.maxWidth < 650;
      final tight = wide && size.maxHeight < 1050;
      final spacing = tight ? 8.0 : 14.0;
      Widget explanation(int i) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(viewIcon(i), color: colors[i], size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: colors[i],
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing),
            Text(
              headlines[i],
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w800,
                height: 1.12,
                color: Color(0xff1d3657),
              ),
            ),
            ...[
              const SizedBox(height: 10),
              Text(
                [
                  'For discovering activities and finding your next visit to the Club.',
                  'For planning ahead and seeing how Club life fits into your month.',
                  'For members who play in matches, teams or competitions.',
                ][i],
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.4,
                  color: Color(0xff253751),
                ),
              ),
            ],
            SizedBox(height: spacing),
            for (final point in features(i))
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•', style: TextStyle(color: colors[i], fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        point,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.25,
                          color: Color(0xff253751),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(height: spacing),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: ValueKey('intro-choice-$i'),
                onPressed: () => setState(() {
                  selected = i;
                  _introducing = false;
                }),
                style: FilledButton.styleFrom(
                  backgroundColor: colors[i],
                  foregroundColor: Colors.white,
                  minimumSize: const Size(48, 48),
                ),
                icon: const Icon(Icons.arrow_forward, size: 20),
                label: Text('Explore ${labels[i]}'),
              ),
            ),
          ],
        ),
      );

      Widget optionImage(int i) => AspectRatio(
        aspectRatio: i == 0
            ? 2000 / 1971
            : i == 1
            ? 2000 / 1012
            : 2000 / 1439,
        child: photo(i, thumbnail: true),
      );
      Widget choice(int i) => Container(
        decoration: BoxDecoration(
          color: [
            const Color(0xfffff0da),
            const Color(0xffeaf5df),
            const Color(0xffe5efff),
          ][i],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors[i].withValues(alpha: .18)),
        ),
        clipBehavior: Clip.antiAlias,
        child: tablet
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      key: ValueKey('intro-image-$i'),
                      width: (size.maxWidth * .28).clamp(160, 250),
                      child: optionImage(i),
                    ),
                  ),
                  Expanded(child: explanation(i)),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!compact)
                    KeyedSubtree(
                      key: ValueKey('intro-image-$i'),
                      child: optionImage(i),
                    ),
                  explanation(i),
                ],
              ),
      );
      return DecoratedBox(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(_background(size.maxWidth)),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.white.withValues(alpha: .65),
              BlendMode.screen,
            ),
          ),
        ),
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: (notification) {
            final needed = notification.metrics.maxScrollExtent > 1;
            if (needed != _introScrollable) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && needed != _introScrollable) {
                  setState(() => _introScrollable = needed);
                }
              });
            }
            return false;
          },
          child: Column(
            children: [
              Expanded(
                child: Scrollbar(
                  controller: _introScroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _introScroll,
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 16 : 24,
                      vertical: tight ? 10 : 16,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1320),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: compact ? 28 : 44,
                                  height: compact ? 28 : 44,
                                  child: const FittedBox(child: BowlMark()),
                                ),
                                SizedBox(width: compact ? 14 : 32),
                                Flexible(
                                  child: Text(
                                    'Welcome to your Club App',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: compact ? 26 : 38,
                                      fontWeight: FontWeight.w800,
                                      color: _brandInk,
                                      height: 1.1,
                                    ),
                                  ),
                                ),
                                SizedBox(width: compact ? 14 : 32),
                                SizedBox(
                                  width: compact ? 28 : 44,
                                  height: compact ? 28 : 44,
                                  child: const FittedBox(child: BowlMark()),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Keep up with Club activities, plan your visits and take part in matches and teams — all in one place.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.3,
                                color: Color(0xff253751),
                              ),
                            ),
                            SizedBox(height: tight ? 6 : 10),
                            const Text(
                              'There are different ways to use the App. The choice is yours. Choose the option that best describes how you interact with your Club.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.3,
                                color: Color(0xff253751),
                              ),
                            ),
                            SizedBox(height: spacing),
                            Container(
                              padding: EdgeInsets.all(tight ? 10 : 14),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .8),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.tune,
                                    color: Color(0xff174a90),
                                    size: 20,
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'You can change your view at any stage using the Options menu in the App. Exploring a view here will not change your saved starting screen.',
                                      style: TextStyle(
                                        fontSize: 14,
                                        height: 1.3,
                                        color: Color(0xff253751),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: spacing),
                            if (wide)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (int i = 0; i < 3; i++)
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                        ),
                                        child: choice(i),
                                      ),
                                    ),
                                ],
                              )
                            else ...[
                              for (int i = 0; i < 3; i++)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: choice(i),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_introScrollable)
                Material(
                  color: const Color(0xffedf3fc),
                  child: InkWell(
                    onTap: () => _introScroll.animateTo(
                      (_introScroll.offset + size.maxHeight * .65).clamp(
                        0,
                        _introScroll.position.maxScrollExtent,
                      ),
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOut,
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.keyboard_arrow_down,
                            color: Color(0xff174a90),
                          ),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Scroll to see all options and buttons',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xff174a90),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );

  Widget welcomeBody() => LayoutBuilder(
    builder: (context, constraints) {
      final tablet = constraints.maxWidth >= 700;
      final wideOverview = constraints.maxWidth >= 1000;
      final i = selected ?? 0;
      return Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(_background(constraints.maxWidth)),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.white.withValues(alpha: .65),
              BlendMode.screen,
            ),
          ),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(tablet ? 24 : 12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _introducing = true),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back to welcome'),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const BowlMark(),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          widget.clubName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xff174a90),
                            fontSize: 20,
                            height: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Your Club. Your Way.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: tablet ? 40 : 27,
                      color: _brandInk,
                      letterSpacing: -1,
                    ),
                  ),
                  const Text(
                    'Choose the view that suits you best',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xff536072), fontSize: 17),
                  ),
                  const SizedBox(height: 16),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeInOutCubic,
                    alignment: Alignment.topCenter,
                    child: selected == null
                        ? (wideOverview
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (int n = 0; n < 3; n++)
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.all(5),
                                          child: overviewCard(n),
                                        ),
                                      ),
                                  ],
                                )
                              : Column(
                                  children: [
                                    for (int n = 0; n < 3; n++)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        child: overviewCard(n),
                                      ),
                                  ],
                                ))
                        : AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: KeyedSubtree(
                              key: ValueKey(i),
                              child: tablet
                                  ? IntrinsicHeight(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(flex: 11, child: photo(i)),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            flex: 10,
                                            child: details(i, tablet),
                                          ),
                                        ],
                                      ),
                                    )
                                  : Column(
                                      children: [
                                        SizedBox(
                                          height: (constraints.maxWidth * .65)
                                              .clamp(225, 340),
                                          width: double.infinity,
                                          child: photo(i),
                                        ),
                                        Transform.translate(
                                          offset: const Offset(0, -16),
                                          child: details(i, tablet),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                  ),
                  if (selected != null) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'OR TRY ANOTHER VIEW',
                        style: TextStyle(
                          color: Color(0xff5b6575),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (int n = 0; n < 3; n++)
                          if (n != i)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: selector(n, !tablet),
                              ),
                            ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Material(
                      color: Colors.white.withValues(alpha: .6),
                      borderRadius: BorderRadius.circular(18),
                      child: SwitchListTile(
                        secondary: const Icon(
                          Icons.settings,
                          color: Color(0xff5b6575),
                        ),
                        title: const Text(
                          'Make this my starting view',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          _saving
                              ? 'Saving your choice…'
                              : 'Saved for your account and this club on this device',
                          style: const TextStyle(fontSize: 12),
                        ),
                        value: saved == i,
                        onChanged: _saving
                            ? null
                            : (v) => _setStartingView(v ? i : null),
                      ),
                    ),
                  ],
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    children: [
                      TextButton(
                        onPressed: () => setState(() => selected = null),
                        child: const Text('Show all three views'),
                      ),
                      Text(
                        saved == null
                            ? 'Choose a starting view whenever you are ready'
                            : 'Starting view: ${labels[saved!]}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xff536072),
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    'Welcome is always available from Options. Your choice only changes when you set it here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Color(0xff66716d)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget photo(int i, {bool thumbnail = false}) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: SizedBox(
      width: double.infinity,
      height: 440,
      child: ColoredBox(
        color: const Color(0xffdae5c9),
        child: Image.asset(
          [
            'assets/images/welcome_list.png',
            'assets/images/welcome_month.png',
            'assets/images/welcome_dashboard.png',
          ][i],
          fit: thumbnail || i == 1 ? BoxFit.contain : BoxFit.cover,
          alignment: i == 1
              ? Alignment.center
              : thumbnail
              ? const Alignment(0, -.25)
              : Alignment.topCenter,
          semanticLabel: photos[i],
        ),
      ),
    ),
  );

  Widget badge(IconData icon, int i) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: .65),
      border: Border.all(color: colors[i].withValues(alpha: .15)),
    ),
    child: Icon(icon, color: colors[i], size: 30),
  );
  IconData viewIcon(int i) =>
      [Icons.format_list_bulleted, Icons.calendar_month, Icons.groups][i];
  Widget details(int i, bool tablet) => Container(
    padding: EdgeInsets.all(tablet ? 22 : 16),
    decoration: BoxDecoration(
      color: [
        const Color(0xfffff2df),
        const Color(0xffedf6e9),
        const Color(0xffedf3fd),
      ][i],
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: colors[i].withValues(alpha: .16)),
      boxShadow: [
        BoxShadow(
          color: colors[i].withValues(alpha: .06),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            badge(viewIcon(i), i),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                labels[i],
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  color: colors[i],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          headlines[i],
          style: TextStyle(
            fontSize: tablet ? 30 : 25,
            fontWeight: FontWeight.w800,
            height: 1.08,
            color: const Color(0xff17130f),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          i == 0
              ? 'From friendly roll-ups to competitions and social events, explore your Club diary in one easy-to-follow list. Find a game, see what’s coming up, and plan your next visit.'
              : descriptions[i],
          style: const TextStyle(fontSize: 16, height: 1.4),
        ),
        const SizedBox(height: 12),
        for (final item in features(i).indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors[i].withValues(alpha: .09),
                  ),
                  child: Icon(
                    [
                      Icons.calendar_month,
                      Icons.search,
                      Icons.groups,
                      Icons.tune,
                    ][item.$1],
                    size: 22,
                    color: colors[i],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    item.$2,
                    style: const TextStyle(fontSize: 15, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _saving ? null : () => widget.onOpen(_views[i]),
            style: FilledButton.styleFrom(backgroundColor: colors[i]),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    'Open ${labels[i]}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.arrow_forward),
              ],
            ),
          ),
        ),
      ],
    ),
  );
  List<String> features(int i) => i == 0
      ? [
          'See all Club activities in date order',
          'Find a suitable time for a game',
          'Matches, roll-ups, competitions and social events',
          'Filter to show what interests you',
        ]
      : i == 1
      ? [
          'See the whole month at a glance',
          'Plan your next visit',
          'Find roll-ups and Club events',
          'Browse a familiar calendar',
        ]
      : [
          'Manage upcoming matches',
          'See your team selections',
          'Keep track of invitations',
          'Send and review your responses',
        ];
  Widget selector(int i, bool compact) => Semantics(
    button: true,
    label: 'Explore ${labels[i]}',
    child: Material(
      color: colors[i].withValues(alpha: .10),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => setState(() => selected = i),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 88),
          child: Padding(
            padding: EdgeInsets.all(compact ? 12 : 16),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(viewIcon(i), color: colors[i], size: 26),
                      const SizedBox(height: 8),
                      Text(
                        labels[i],
                        style: TextStyle(
                          color: colors[i],
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        shortDescription(i),
                        style: TextStyle(
                          color: colors[i],
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      badge(viewIcon(i), i),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              labels[i],
                              style: TextStyle(
                                color: colors[i],
                                fontWeight: FontWeight.w800,
                                fontSize: 19,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              shortDescription(i),
                              style: TextStyle(color: colors[i], fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: colors[i]),
                    ],
                  ),
          ),
        ),
      ),
    ),
  );
  String shortDescription(int i) => [
    'Find your next club activity.',
    'See what’s on this month.',
    'Your matches, teams and invitations.',
  ][i];
  Widget overviewCard(int i) => Container(
    decoration: BoxDecoration(
      color: const Color(0xfffff2df),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 200, child: photo(i)),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                labels[i],
                style: TextStyle(
                  color: colors[i],
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                headlines[i],
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => setState(() => selected = i),
                child: Text('Explore ${labels[i]}'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class BowlMark extends StatelessWidget {
  const BowlMark({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Decorative bowl',
    child: Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: Alignment(-.4, -.5),
          colors: [Color(0xff5a9ee2), Color(0xff174a90), Color(0xff092d63)],
        ),
      ),
      child: Center(
        child: Transform.rotate(
          angle: -.35,
          child: Container(
            width: 27,
            height: 35,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xffffd654), width: 1.2),
            ),
            child: Center(
              child: Container(
                width: 18,
                height: 25,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xffffd654), width: .8),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
