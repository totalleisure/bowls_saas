import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'scorecard.dart';
import 'scorecard_repository.dart';
import 'scorecard_screen.dart';

/// Local scoring is hosted outside the authenticated Club Navigator. Session
/// expiry or a failed membership check must never remove the local scorecard.
class ScorecardRecoveryHost extends StatefulWidget {
  const ScorecardRecoveryHost({
    super.key,
    required this.child,
    this.repository,
  });
  final Widget child;
  final ScorecardRepository? repository;
  @override
  State<ScorecardRecoveryHost> createState() => _ScorecardRecoveryHostState();
}

class _ScorecardRecoveryHostState extends State<ScorecardRecoveryHost> {
  late final repository = widget.repository ?? ScorecardRepository.instance;
  bool checked = false, local = false, recovering = false;
  List<Scorecard> unfinished = [];
  String? checkError;
  bool shortcutHidden = false;
  int shortcutRevision = 0;
  static const shortcutPreference = 'offline_scorecards_shortcut_hidden_v1';

  Future<void> loadShortcutPreference() async {
    final revision = shortcutRevision;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted && revision == shortcutRevision) {
        setState(
          () => shortcutHidden = prefs.getBool(shortcutPreference) ?? false,
        );
      }
    } catch (_) {
      // A device preference must never prevent access to saved scorecards.
    }
  }

  void setShortcutHidden(bool hidden) {
    if (!mounted) return;
    shortcutRevision++;
    setState(() => shortcutHidden = hidden);
    saveShortcutPreference(hidden);
  }

  Future<void> saveShortcutPreference(bool hidden) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(shortcutPreference, hidden);
    } catch (_) {
      // The shortcut still follows the choice for this app session.
    }
  }

  void restoreShortcut() {
    if (shortcutHidden) setShortcutHidden(false);
  }

  @override
  void initState() {
    super.initState();
    loadShortcutPreference();
    check();
  }

  Future<void> check() async {
    try {
      final cards = await repository.load();
      final active = cards
          .where((c) => c.startedAt != null && !c.complete)
          .toList();
      String recent(Scorecard c) => c.history.isNotEmpty
          ? '${c.history.last['at']}'
          : c.startedAt!.toIso8601String();
      active.sort((a, b) => recent(b).compareTo(recent(a)));
      if (mounted) {
        setState(() {
          unfinished = active;
          checked = true;
          local = active.isNotEmpty;
          recovering = local;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          checked = true;
          local = true;
          recovering = true;
          checkError =
              'The saved scorecards could not be checked. Your files have not been changed. Open local scorecards for details, or continue to the Club App.';
        });
      }
    }
  }

  Scorecard? selectedCard;
  void open([Scorecard? card]) {
    setShortcutHidden(false);
    setState(() {
      selectedCard = card;
      local = true;
      recovering = false;
    });
  }

  void close() => setState(() => local = false);
  @override
  Widget build(BuildContext context) {
    if (!checked) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return _LocalScorecardAccess(
      open: open,
      shortcutHidden: shortcutHidden,
      hide: () => setShortcutHidden(true),
      restore: restoreShortcut,
      child: Stack(
        textDirection: TextDirection.ltr,
        fit: StackFit.expand,
        children: [
          Offstage(offstage: local, child: widget.child),
          if (local)
            MaterialApp(
              key: ValueKey(recovering),
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                useMaterial3: true,
                colorSchemeSeed: const Color(0xff0057b8),
              ),
              home: recovering
                  ? Builder(
                      builder: (context) => Scaffold(
                        appBar: AppBar(title: const Text('Resume scoring')),
                        body: ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                            Text(
                              checkError == null
                                  ? 'Unfinished scorecard found'
                                  : 'Check saved scorecards',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              checkError ??
                                  'Your scores and original match start time are saved on this device. Resume scoring without signing in or connecting to the Club database.',
                            ),
                            if (repository.recoveryNotice != null)
                              Text(repository.recoveryNotice!),
                            for (final c in unfinished)
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        c.title,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                      Text(
                                        '${c.date}\n${c.sideA} ${c.totalA} : ${c.totalB} ${c.sideB}\n${c.ends.length} end(s)${c.endInProgress ? " — current end awaiting score" : " recorded"}',
                                      ),
                                      FilledButton.icon(
                                        onPressed: () async {
                                          await Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: (_) => ScorecardScreen(
                                                card: c,
                                                repository: repository,
                                              ),
                                            ),
                                          );
                                          if (mounted) {
                                            await check();
                                          }
                                        },
                                        icon: const Icon(Icons.play_arrow),
                                        label: const Text('Resume scorecard'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            OutlinedButton(
                              onPressed: open,
                              child: const Text('Open all local scorecards'),
                            ),
                            TextButton(
                              onPressed: close,
                              child: const Text(
                                'Not now — continue to Club App',
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ScorecardsScreen(
                      repository: repository,
                      onClose: close,
                      initialCard: selectedCard,
                    ),
            ),
        ],
      ),
    );
  }
}

class _LocalScorecardAccess extends InheritedWidget {
  const _LocalScorecardAccess({
    required this.open,
    required this.shortcutHidden,
    required this.hide,
    required this.restore,
    required super.child,
  });
  final bool shortcutHidden;
  final VoidCallback hide;
  final VoidCallback restore;
  final void Function([Scorecard? card]) open;
  @override
  bool updateShouldNotify(covariant _LocalScorecardAccess oldWidget) =>
      shortcutHidden != oldWidget.shortcutHidden;
}

void openOfflineScorecards(
  BuildContext context, {
  Scorecard? card,
  ScorecardRepository? repository,
}) {
  final access = context.getInheritedWidgetOfExactType<_LocalScorecardAccess>();
  if (access != null) {
    access.open(card);
    return;
  }
  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          ScorecardsScreen(initialCard: card, repository: repository),
    ),
  );
}

/// Hide affects only the welcome shortcut, never saved cards or recovery.
class OfflineScorecardsShortcut extends StatelessWidget {
  const OfflineScorecardsShortcut({super.key});
  @override
  Widget build(BuildContext context) {
    final access = context
        .dependOnInheritedWidgetOfExactType<_LocalScorecardAccess>();
    if (access?.shortcutHidden ?? false) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.extended(
          heroTag: 'offline-scorecards',
          onPressed: () => openOfflineScorecards(context),
          icon: const Icon(Icons.scoreboard_outlined),
          label: const Text('Offline scorecards'),
        ),
        if (access != null) ...[
          const SizedBox(width: 8),
          Tooltip(
            message: 'Hide this shortcut until you next open Scorecards',
            child: FilledButton.tonal(
              onPressed: access.hide,
              child: const Text('Hide'),
            ),
          ),
        ],
      ],
    );
  }
}

/// Called on entry to either local or fixture scorecards.
void restoreOfflineScorecardsShortcut(BuildContext context) {
  final access = context.getInheritedWidgetOfExactType<_LocalScorecardAccess>();
  if (access == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) => access.restore());
}
