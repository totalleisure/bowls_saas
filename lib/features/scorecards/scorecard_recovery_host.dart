import 'package:flutter/material.dart';
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
  @override
  void initState() {
    super.initState();
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

  void open() => setState(() {
    local = true;
    recovering = false;
  });
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
                  : ScorecardsScreen(repository: repository, onClose: close),
            ),
        ],
      ),
    );
  }
}

class _LocalScorecardAccess extends InheritedWidget {
  const _LocalScorecardAccess({required this.open, required super.child});
  final VoidCallback open;
  @override
  bool updateShouldNotify(covariant _LocalScorecardAccess oldWidget) => false;
}

void openOfflineScorecards(BuildContext context) {
  final access = context.getInheritedWidgetOfExactType<_LocalScorecardAccess>();
  if (access != null) {
    access.open();
    return;
  }
  Navigator.of(
    context,
    rootNavigator: true,
  ).push(MaterialPageRoute<void>(builder: (_) => const ScorecardsScreen()));
}
