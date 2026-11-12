import 'fixture_scorecard_availability.dart';
import 'scorecard_match_summary.dart';
import 'package:flutter/gestures.dart';
import 'scorecard_table.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'scorecard.dart';
import 'scorecard_repository.dart';
import 'scorecard_setup.dart';
import 'scorecard_pdf.dart';
import 'shared_scorecard_api.dart';
import 'shared_scorecard_screen.dart';

class ScorecardsScreen extends StatefulWidget {
  const ScorecardsScreen({
    super.key,
    this.repository,
    this.onClose,
    this.initialCard,
  });
  final ScorecardRepository? repository;
  final VoidCallback? onClose;
  final Scorecard? initialCard;
  @override
  State<ScorecardsScreen> createState() => _ScorecardsScreenState();
}

class _ScorecardsScreenState extends State<ScorecardsScreen> {
  late final repository = widget.repository ?? ScorecardRepository.instance;
  List<Scorecard> cards = [];
  String? error;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load().then((_) {
      if (mounted && widget.initialCard != null) open(widget.initialCard!);
    });
  }

  Future<void> load() async {
    try {
      final list = await repository.load();
      if (mounted) {
        setState(() {
          cards = list;
          loading = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = 'Unable to read local scorecards: $e';
          loading = false;
        });
      }
    }
  }

  Future<void> create() async {
    final card = await Navigator.of(context).push<Scorecard>(
      MaterialPageRoute(
        builder: (_) => ScorecardSetup(card: Scorecard.create()),
      ),
    );
    if (card == null || !mounted) return;
    try {
      await repository.save(card);
      if (!mounted) return;
      await open(card);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Not saved: $e')));
      }
    }
  }

  Future<void> open(Scorecard card) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ScorecardScreen(card: card, repository: repository),
      ),
    );
    await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: widget.onClose == null
          ? null
          : IconButton(
              onPressed: widget.onClose,
              icon: const Icon(Icons.close),
              tooltip: 'Return to Club App',
            ),
      title: const Text('Electronic Scorecards'),
      actions: [
        IconButton(
          onPressed: load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Reload local scorecards',
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Scorecards saved on this device\nManual cards are independent local records. Shared fixture cards upload from the designated scorer’s device; both sides agree through the fixture before result submission. Anyone using this device can open its local copies.',
            ),
          ),
        ),
        if (loading) const LinearProgressIndicator(),
        if (repository.recoveryNotice != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(repository.recoveryNotice!),
            ),
          ),
        if (error != null)
          SelectableText(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        FilledButton.icon(
          onPressed: loading || error != null ? null : create,
          icon: const Icon(Icons.add),
          label: const Text('New manual scorecard'),
        ),
        if (!loading && cards.isEmpty && error == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No scorecards saved yet. You can start a game without an internet connection.',
            ),
          ),
        for (final c in cards)
          Card(
            child: ListTile(
              title: Text(c.title),
              subtitle: Text(
                '${c.date} · ${c.sideA} ${c.totalA} – ${c.totalB} ${c.sideB}\n${c.resultConfirmed
                    ? "Admin confirmed"
                    : c.complete
                    ? "Finished"
                    : "In progress"} · saved on this device',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => open(c),
            ),
          ),
      ],
    ),
  );
}

class ScorecardScreen extends StatefulWidget {
  const ScorecardScreen({
    super.key,
    required this.card,
    required this.repository,
    this.sharedApi,
  });
  final Scorecard card;
  final ScorecardRepository repository;
  final SharedScorecardApi? sharedApi;
  @override
  State<ScorecardScreen> createState() => _ScorecardScreenState();
}

class _ScorecardScreenState extends State<ScorecardScreen>
    with WidgetsBindingObserver {
  late Scorecard card;
  Timer? timer;
  bool saving = false;
  String? error;
  DateTime now = DateTime.now().toUtc();
  final warned = <int>{};
  int? editingEnd;
  int draftA = 0, draftB = 0;
  late final sharedApi = widget.sharedApi ?? SharedScorecardApi();
  bool syncing = false;
  int uploadedSequence = -1;
  String? uploadError;
  String? remotePhase;
  String? correctionMessage;
  Future<void>? syncTask;
  bool get isShared => SharedScorecardApi.isShared(card);
  String? get requestedCorrection =>
      card.fixtureLink?['sharedCorrectionRequest'] as String?;
  @override
  void initState() {
    super.initState();
    card = widget.card;
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    if (isShared) unawaited(syncShared());
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) tick();
  }

  void tick() {
    if (!mounted) return;
    setState(() => now = DateTime.now().toUtc());
    if (isShared &&
        now.second % 5 == 0 &&
        (uploadedSequence < card.saveVersion || now.second % 10 == 0)) {
      unawaited(syncShared());
    }
    if (card.startedAt != null &&
        !card.complete &&
        card.lastJackMinutes != null) {
      final remaining = card.lastJackMinutes! * 60 - card.elapsedSeconds(now);
      for (final threshold in [600, 300, 0]) {
        if (remaining <= threshold && warned.add(threshold)) {
          SystemSound.play(SystemSoundType.alert);
          HapticFeedback.heavyImpact();
        }
      }
    }
  }

  Future<void> syncShared() {
    if (!isShared || !mounted) return Future.value();
    return syncTask ??= uploadShared().whenComplete(() => syncTask = null);
  }

  Future<void> uploadShared() async {
    final saved = Scorecard.fromJson(
      jsonDecode(jsonEncode(card.toJson())) as Map<String, dynamic>,
    );
    setState(() => syncing = true);
    try {
      Map<String, dynamic> result;
      try {
        result = card.resultConfirmed
            ? await sharedApi.call(
                'shared_scorecard_state',
                SharedScorecardApi.location(card),
              )
            : await sharedApi.sync(saved);
      } catch (uploadFailure) {
        // A submitted card may reject an old device upload. Read its final state.
        final latest = await sharedApi.call(
          'shared_scorecard_state',
          SharedScorecardApi.location(card),
        );
        if ((latest['shared'] as Map?)?['competitionStatus'] != 'completed') {
          rethrow;
        }
        result = latest;
      }
      final cloud = Map<String, dynamic>.from(result['shared'] as Map? ?? {});
      await widget.repository.rememberSignatures(cloud);
      await widget.repository.rememberConfirmation(cloud);
      if (mounted) {
        setState(() {
          final metadata = SharedScorecardApi.confirmationMetadata(cloud);
          if (metadata.isNotEmpty) {
            card.fixtureLink = {...card.fixtureLink!, ...metadata};
          }
          uploadedSequence = saved.saveVersion;
          uploadError = null;
          remotePhase = (result['shared'] as Map?)?['phase'] as String?;
          correctionMessage =
              (result['shared'] as Map?)?['correctionNote'] as String?;
        });
      }
    } catch (e) {
      if (mounted) setState(() => uploadError = '$e');
    } finally {
      if (mounted) setState(() => syncing = false);
    }
  }

  Future<void> reviewShared() async {
    await syncShared();
    if (uploadedSequence < card.saveVersion && uploadError == null) {
      await syncShared();
    }
    if (!mounted) return;
    if (uploadedSequence < card.saveVersion) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The latest scores are still saved only on this device. Reconnect and sync before final review.',
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SharedScorecardScreen(
          fixtureId: '${card.fixtureLink!['fixtureId']}',
          rinkId: '${card.fixtureLink!['fixtureRinkId']}',
          api: sharedApi,
          repository: widget.repository,
        ),
      ),
    );
    final latest = (await widget.repository.load())
        .where((c) => c.id == card.id)
        .firstOrNull;
    if (mounted && latest != null) setState(() => card = latest);
  }

  Future<void> apply(void Function(Scorecard) edit) async {
    if (saving || card.resultConfirmed) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final next = Scorecard.fromJson(
        jsonDecode(jsonEncode(card.toJson())) as Map<String, dynamic>,
      );
      edit(next);
      if (next.complete &&
          next.fixtureLink?['sharedCorrectionRequest'] != null) {
        next.fixtureLink = {...next.fixtureLink!}
          ..remove('sharedCorrectionRequest');
      }
      if (isShared && card.complete && !next.complete) {
        // Invalidate cloud agreements BEFORE permitting a local correction.
        // An offline scorer can finish, but cannot reopen a finished shared card.
        await syncShared();
        if (uploadedSequence < card.saveVersion) {
          throw StateError(
            'Connect and upload the finished card before reopening.',
          );
        }
        await sharedApi.reopen(card);
      }
      await widget.repository.save(next);
      if (mounted) {
        setState(() {
          card = next;
          now = DateTime.now().toUtc();
        });
        if (isShared) unawaited(syncShared());
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error =
              'Not saved: ${e.toString().replaceFirst("Bad state: ", "")}',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void selectEnd(int index) {
    if (saving || card.complete || card.resultConfirmed) return;
    setState(() {
      editingEnd = card.ends[index]['a'] == null ? null : index;
      draftA = card.ends[index]['a'] as int? ?? 0;
      draftB = card.ends[index]['b'] as int? ?? 0;
    });
  }

  Future<void> acceptEnd() async {
    final index =
        editingEnd ?? (card.endInProgress ? card.ends.length - 1 : -1);
    if (index < 0) return;
    await apply(
      (c) => c.acceptEndScore(index, draftA, draftB, DateTime.now().toUtc()),
    );
    if (mounted && error == null) {
      setState(() {
        editingEnd = null;
        draftA = draftB = 0;
      });
    }
  }

  Future<void> details() async {
    final updated = await Navigator.of(context).push<Scorecard>(
      MaterialPageRoute(builder: (_) => ScorecardSetup(card: card)),
    );
    if (updated != null) {
      // Save the complete edited document, not just the displayed fields.
      setState(() => saving = true);
      try {
        await widget.repository.save(updated);
        if (mounted) {
          setState(() => card = updated);
          if (isShared) unawaited(syncShared());
        }
      } catch (e) {
        if (mounted) setState(() => error = 'Not saved: $e');
      } finally {
        if (mounted) setState(() => saving = false);
      }
    }
  }

  Future<void> confirmFinish() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          requestedCorrection != null
              ? 'Review corrected final score'
              : isShared
              ? 'Finish match?'
              : 'Finish and review scorecard?',
        ),
        content: Text(
          '${card.sideA}: ${card.totalA}\n${card.sideB}: ${card.totalB}\n\n${card.endInProgress ? "The automatically started end has no score and will be removed. If it has been played, cancel and record its score first.\n\n" : ""}${isShared ? "Confirm the final score, then both sides review and agree. ${card.fixtureLink?['competitionMatchId'] != null ? 'Admin confirmation is still required before progression.' : ''}" : "Both sides can sign after reviewing. This does not submit a competition result."}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              requestedCorrection != null
                  ? 'Send corrected score for agreement'
                  : isShared
                  ? 'Confirm final score'
                  : 'Finish scorecard',
            ),
          ),
        ],
      ),
    );
    if (yes == true) {
      await apply((c) => c.finish(DateTime.now().toUtc()));
      if (mounted && isShared && card.complete && error == null) {
        await reviewShared();
      }
    }
  }

  Widget sharedNextAction(bool canFinish) => SafeArea(
    top: false,
    child: Material(
      elevation: 6,
      child: Align(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  requestedCorrection != null && !card.complete
                      ? 'Correct the requested end · Both sides must agree again'
                      : card.resultConfirmed
                      ? 'Admin confirmed · Scorecard locked'
                      : uploadedSequence >= card.saveVersion
                      ? 'Shared card up to date'
                      : 'Saved on this device · Upload pending',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 4),
                FilledButton(
                  onPressed: saving || syncing
                      ? null
                      : card.complete
                      ? reviewShared
                      : canFinish
                      ? confirmFinish
                      : null,
                  child: Text(
                    card.resultConfirmed
                        ? 'View confirmed result'
                        : card.complete
                        ? 'Review result'
                        : requestedCorrection != null
                        ? 'Finish corrected score'
                        : 'Finish match',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> sign(bool side) async {
    final result = await Navigator.of(context).push<SignatureResult>(
      MaterialPageRoute(
        builder: (_) => SignatureScreen(
          sideName: side ? card.sideA : card.sideB,
          score: '${card.totalA} : ${card.totalB}',
          initialName:
              (side ? card.signatureA : card.signatureB)?['name']?.toString() ??
              (side ? card.suggestedSignerA : card.suggestedSignerB),
        ),
      ),
    );
    if (result != null) {
      await apply((c) => c.sign(side, result.name, result.strokes));
    }
  }

  String clock(int seconds) {
    final s = seconds.abs();
    return '${seconds < 0 ? "−" : ""}${(s ~/ 3600).toString().padLeft(2, "0")}:${(s % 3600 ~/ 60).toString().padLeft(2, "0")}:${(s % 60).toString().padLeft(2, "0")}';
  }

  @override
  Widget build(BuildContext context) {
    final deadline = card.deadlineReached(now);
    final elapsed = card.elapsedSeconds(now);
    final pendingClaim = card.fixtureLink?['sharedPendingClaim'] == true;
    final scoringAvailable =
        !card.resultConfirmed &&
        !pendingClaim &&
        (card.fixtureLink == null ||
            fixtureScoringDayReached(card.fixtureLink!, nowUtc: now));
    final canFinish =
        !card.resultConfirmed &&
        !card.complete &&
        editingEnd == null &&
        card.ends.isNotEmpty &&
        (!card.endInProgress || card.ends.last['automatic'] == true);
    return Scaffold(
      bottomNavigationBar: isShared
          ? sharedNextAction(canFinish)
          : card.fixtureLink == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  isShared
                      ? 'Shared fixture card · Offline saves on this scoring device'
                      : 'Fixture linked · Saved on this device · Live sharing not enabled yet',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
      appBar: AppBar(
        title: Text(card.title),
        actions: [
          if (isShared)
            IconButton(
              onPressed: syncing ? null : reviewShared,
              icon: const Icon(Icons.cloud_sync),
              tooltip: 'View shared match',
            ),
          IconButton(
            onPressed: saving
                ? null
                : () async {
                    try {
                      if (!context.mounted) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ScorecardPdfScreen(card: card),
                        ),
                      );
                    } catch (e) {
                      if (mounted) {
                        setState(() => error = 'Unable to create PDF: $e');
                      }
                    }
                  },
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'View / share / print scorecard PDF',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Column(
              children: [
                Text(
                  isShared
                      ? '${card.totalA} : ${card.totalB}'
                      : '${card.sideA}  ${card.totalA} : ${card.totalB}  ${card.sideB}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  '${card.complete ? "Finished" : "End ${card.ends.length}${card.endInProgress ? " in progress" : " completed"}"} · Saved on this device',
                ),
                if (isShared)
                  Text(
                    card.resultConfirmed
                        ? 'Admin confirmed · Scorecard locked'
                        : remotePhase == 'correction_requested'
                        ? 'Correction requested — reopen online to amend'
                        : remotePhase == 'submitted'
                        ? 'Submitted for Admin confirmation'
                        : uploadedSequence >= card.saveVersion
                        ? 'Saved on this device and uploaded to the shared card'
                        : 'Saved on this device — waiting to sync',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                if (card.resultConfirmed && card.confirmedWinner != null)
                  Text(
                    'Winner: ${card.confirmedWinner}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                if (card.startedAt != null)
                  Text(
                    'Elapsed ${clock(elapsed)}${!card.complete && !card.resultConfirmed && card.lastJackMinutes != null ? " · Last jack ${clock(card.lastJackMinutes! * 60 - elapsed)}" : ""}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                if (!card.complete &&
                    !card.resultConfirmed &&
                    card.durationMinutes != null &&
                    card.startedAt != null)
                  Text(
                    'Playing time remaining: ${clock(card.durationMinutes! * 60 - elapsed)}',
                  ),
              ],
            ),
          ),
          if (deadline && !card.complete && !card.resultConfirmed)
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: now.second.isEven
                  ? Colors.red.shade100
                  : Colors.amber.shade100,
              child: Text(
                card.endInProgress
                    ? 'Last-jack deadline reached — complete the current end.'
                    : 'Last-jack deadline reached — no further end may start.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          if (saving) const LinearProgressIndicator(),
          if (card.startedAt == null &&
              card.fixtureLink?['competitionId'] != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(card.playingSummary, textAlign: TextAlign.center),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (!card.complete && !card.resultConfirmed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  if (card.startedAt == null)
                    FilledButton.icon(
                      onPressed: saving || !scoringAvailable
                          ? null
                          : () => apply(
                              (c) => c.startMatch(DateTime.now().toUtc()),
                            ),
                      icon: const Icon(Icons.play_arrow),
                      label: Text(
                        pendingClaim
                            ? 'Complete the shared-card claim online'
                            : scoringAvailable
                            ? 'Start match timer'
                            : 'Scorecard available on the day of the Fixture',
                      ),
                    )
                  else ...[
                    if (editingEnd == null && !card.endInProgress)
                      FilledButton.icon(
                        onPressed: saving || card.cannotStartEnd(now) != null
                            ? null
                            : () => apply(
                                (c) => c.startEnd(DateTime.now().toUtc()),
                              ),
                        icon: const Icon(Icons.sports),
                        label: Text(
                          'Jack delivered / Start end ${card.ends.length + 1}',
                        ),
                      ),
                    EndScoreControls(
                      card: card,
                      end:
                          (editingEnd ??
                              (card.endInProgress
                                  ? card.ends.length - 1
                                  : card.ends.length)) +
                          1,
                      a: draftA,
                      b: draftB,
                      enabled:
                          !saving && (editingEnd != null || card.endInProgress),
                      onChanged: (a, b) => setState(() {
                        draftA = a;
                        draftB = b;
                      }),
                      onAccept: acceptEnd,
                      onCancel: editingEnd == null
                          ? null
                          : () => setState(() {
                              editingEnd = null;
                              draftA = draftB = 0;
                            }),
                    ),
                    if (!card.endInProgress &&
                        editingEnd == null &&
                        card.cannotStartEnd(now) != null)
                      Text(card.cannotStartEnd(now)!),
                  ],
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ScorecardTableHeader(
              card: card,
              showClubNames: card.complete || card.startedAt == null,
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (requestedCorrection != null && !card.complete)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Editing requested correction',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(requestedCorrection!),
                          const Text(
                            'Tap the played end below, change its score and accept it. Then choose Finish corrected score.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ScorecardTable(
                  card: card,
                  showHeader: false,
                  selectedEnd:
                      editingEnd ??
                      (card.endInProgress ? card.ends.length - 1 : null),
                  onSelect: saving || card.complete || card.resultConfirmed
                      ? null
                      : selectEnd,
                ),
                if (isShared) ...[
                  if (correctionMessage != null)
                    Text('Correction requested: $correctionMessage'),
                  if (uploadError != null)
                    const Text(
                      'Upload unavailable. Scores are safe on this device; reviewers see the last upload. Reconnect before agreement.',
                    ),
                ],
                if (!isShared && canFinish)
                  FilledButton(
                    onPressed: saving ? null : confirmFinish,
                    child: const Text('Finish and review'),
                  ),
                if (card.complete) ...[
                  Text(
                    card.resultConfirmed
                        ? 'Admin confirmed the result. This scorecard is locked.'
                        : isShared
                        ? 'Use Review result to agree from separate accounts or let both parties sign on this device. The App uploads automatically when connected. Competition results still need the Competition Secretary’s confirmation.'
                        : 'Review the totals, then ask one representative from each side to sign. Signatures acknowledge this scorecard; they do not confirm a competition result.',
                  ),
                  if (!isShared)
                    for (final side in [true, false])
                      OutlinedButton.icon(
                        onPressed: saving ? null : () => sign(side),
                        icon: Icon(
                          (side ? card.signatureA : card.signatureB) == null
                              ? Icons.draw
                              : Icons.verified_outlined,
                        ),
                        label: Text(
                          '${side ? card.sideA : card.sideB}: ${(side ? card.signatureA : card.signatureB)?['name'] ?? "Sign scorecard"}',
                        ),
                      ),
                  if (!card.resultConfirmed)
                    TextButton(
                      onPressed: saving
                          ? null
                          : () async {
                              final yes = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text(
                                    isShared
                                        ? 'Reopen and clear agreements?'
                                        : 'Reopen and clear signatures?',
                                  ),
                                  content: const Text(
                                    'You can correct earlier ends. Both sides must approve the revised scorecard again. Shared cards require a connection to clear previous agreements before reopening.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Reopen'),
                                    ),
                                  ],
                                ),
                              );
                              if (yes == true) await apply((c) => c.reopen());
                            },
                      child: Text(
                        isShared
                            ? 'Reopen to correct scores (clears agreements)'
                            : 'Reopen to correct scores (clears signatures)',
                      ),
                    ),
                ],
                ExpansionTile(
                  collapsedBackgroundColor: const Color(0xffdce8f7),
                  backgroundColor: const Color(0xffedf3fb),
                  collapsedShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: Color(0xffa5bddc)),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: Color(0xffa5bddc)),
                  ),
                  childrenPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text(
                    'Players and Match Details',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  children: [
                    ScorecardMatchSummary(card: card),
                    if (!card.complete)
                      TextButton(
                        onPressed: saving ? null : details,
                        child: const Text('Edit details'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                ExpansionTile(
                  collapsedBackgroundColor: const Color(0xffdce8f7),
                  backgroundColor: const Color(0xffedf3fb),
                  collapsedShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: Color(0xffa5bddc)),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: Color(0xffa5bddc)),
                  ),
                  title: const Text(
                    'Correction / Change History',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  children: [
                    for (final (index, e) in card.history.reversed.indexed)
                      Container(
                        decoration: BoxDecoration(
                          color: index.isEven
                              ? Colors.white
                              : const Color(0xffd4e0ef),
                          border: const Border(
                            bottom: BorderSide(color: Color(0xffb7c7dc)),
                          ),
                        ),
                        child: ListTile(
                          dense: true,
                          title: Text('${e['action']}'),
                          subtitle: Text(
                            [
                              e['at'],
                              if (e['before'] != null &&
                                  '${e['before']}'.isNotEmpty)
                                'Before: ${e['before']}',
                              if (e['after'] != null &&
                                  '${e['after']}'.isNotEmpty)
                                'After: ${e['after']}',
                            ].join('\n'),
                          ),
                        ),
                      ),
                  ],
                ),
                if (!isShared)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '• No cloud score backup or competition result submission.',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '• Export a PDF before removing the App or clearing its data.',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '• Timer alerts require this screen to remain visible.',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SignatureResult {
  SignatureResult(this.name, this.strokes);
  final String name;
  final List<List<Map<String, double>>> strokes;
}

class SignatureScreen extends StatefulWidget {
  const SignatureScreen({
    super.key,
    required this.sideName,
    required this.score,
    this.initialName = '',
  });
  final String sideName, score, initialName;
  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  late final name = TextEditingController(text: widget.initialName);
  final strokes = <List<Map<String, double>>>[];
  final canvasKey = GlobalKey();
  int? activePointer;
  Map<String, double> point(PointerEvent event) {
    final box = canvasKey.currentContext!.findRenderObject()! as RenderBox;
    final local = box.globalToLocal(event.position);
    return {
      'x': (local.dx / box.size.width).clamp(0, 1).toDouble(),
      'y': (local.dy / box.size.height).clamp(0, 1).toDouble(),
    };
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sign scorecard')),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          '${widget.sideName} · Final score ${widget.score}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text(
          'I acknowledge the scores recorded on this scorecard. Draw your signature below using a finger, stylus or mouse.',
        ),
        TextField(
          controller: name,
          decoration: const InputDecoration(
            labelText: 'Representative’s printed name',
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 220,
          child: RawGestureDetector(
            key: const ValueKey('scorecard-signature-pad'),
            behavior: HitTestBehavior.opaque,
            gestures: {
              EagerGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                    EagerGestureRecognizer.new,
                    (_) {},
                  ),
            },
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) {
                if (activePointer != null ||
                    (event.kind == PointerDeviceKind.mouse &&
                        event.buttons & kPrimaryButton == 0)) {
                  return;
                }
                activePointer = event.pointer;
                setState(() => strokes.add([point(event)]));
              },
              onPointerMove: (event) {
                if (event.pointer == activePointer) {
                  setState(() => strokes.last.add(point(event)));
                }
              },
              onPointerUp: (event) {
                if (event.pointer == activePointer) activePointer = null;
              },
              onPointerCancel: (event) {
                if (event.pointer == activePointer) activePointer = null;
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.indigo, width: 2),
                ),
                child: ClipRect(
                  child: CustomPaint(
                    key: canvasKey,
                    painter: _SignaturePainter(strokes),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ),
        ),
        TextButton(
          onPressed: () => setState(strokes.clear),
          child: const Text('Clear signature'),
        ),
        FilledButton(
          onPressed: () {
            if (name.text.trim().isEmpty || !strokes.any((s) => s.length > 1)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Enter your name and draw your signature.'),
                ),
              );
              return;
            }
            Navigator.pop(context, SignatureResult(name.text.trim(), strokes));
          },
          child: const Text('Accept and save signature'),
        ),
      ],
    ),
  );
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.strokes);
  final List<List<Map<String, double>>> strokes;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.indigo
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (final stroke in strokes) {
      for (var i = 1; i < stroke.length; i++) {
        canvas.drawLine(
          Offset(
            stroke[i - 1]['x']! * size.width,
            stroke[i - 1]['y']! * size.height,
          ),
          Offset(stroke[i]['x']! * size.width, stroke[i]['y']! * size.height),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}

class ScorecardPdfScreen extends StatefulWidget {
  const ScorecardPdfScreen({super.key, required this.card});
  final Scorecard card;
  @override
  State<ScorecardPdfScreen> createState() => _ScorecardPdfScreenState();
}

class _ScorecardPdfScreenState extends State<ScorecardPdfScreen> {
  bool includeAudit = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scorecard PDF')),
    body: Column(
      children: [
        SwitchListTile(
          title: const Text('Include audit history'),
          subtitle: const Text(
            'Adds separate audit pages. Off by default for sharing or printing the card.',
          ),
          value: includeAudit,
          onChanged: (value) => setState(() => includeAudit = value),
        ),
        Expanded(
          child: PdfPreview(
            key: ValueKey(includeAudit),
            build: (_) => scorecardPdf(widget.card, includeAudit: includeAudit),
            pdfFileName:
                'Scorecard-${widget.card.date}${includeAudit ? "-with-audit" : ""}.pdf',
            initialPageFormat: scorecardPdfPageFormat,
            canChangePageFormat: false,
            canChangeOrientation: false,
            dynamicLayout: false,
          ),
        ),
      ],
    ),
  );
}
