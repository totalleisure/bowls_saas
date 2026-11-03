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

class ScorecardsScreen extends StatefulWidget {
  const ScorecardsScreen({super.key, this.repository, this.onClose});
  final ScorecardRepository? repository;
  final VoidCallback? onClose;
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
    load();
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
              'Offline scorecards · saved on this device\nCreate a manual game, record ends and signatures, then export a PDF. These cards are not synchronised or submitted to Club competitions yet. Anyone using this device can open them.',
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
                '${c.date} · ${c.sideA} ${c.totalA} – ${c.totalB} ${c.sideB}\n${c.complete ? "Finished" : "In progress"} · saved on this device',
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
  });
  final Scorecard card;
  final ScorecardRepository repository;
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
  @override
  void initState() {
    super.initState();
    card = widget.card;
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
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

  Future<void> apply(void Function(Scorecard) edit) async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final next = Scorecard.fromJson(
        jsonDecode(jsonEncode(card.toJson())) as Map<String, dynamic>,
      );
      edit(next);
      await widget.repository.save(next);
      if (mounted) {
        setState(() {
          card = next;
          now = DateTime.now().toUtc();
        });
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
    if (saving || card.complete) return;
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
        if (mounted) setState(() => card = updated);
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
        title: const Text('Finish and review scorecard?'),
        content: Text(
          '${card.sideA}: ${card.totalA}\n${card.sideB}: ${card.totalB}\n\n${card.endInProgress ? "The automatically started end has no score and will be removed. If it has been played, cancel and record its score first.\n\n" : ""}Both sides can sign after reviewing. This does not submit a competition result.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Finish scorecard'),
          ),
        ],
      ),
    );
    if (yes == true) await apply((c) => c.finish(DateTime.now().toUtc()));
  }

  Future<void> sign(bool side) async {
    final result = await Navigator.of(context).push<SignatureResult>(
      MaterialPageRoute(
        builder: (_) => SignatureScreen(
          sideName: side ? card.sideA : card.sideB,
          score: '${card.totalA} : ${card.totalB}',
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
    return Scaffold(
      appBar: AppBar(
        title: Text(card.title),
        actions: [
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
                  '${card.sideA}  ${card.totalA} : ${card.totalB}  ${card.sideB}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  '${card.complete ? "Finished" : "End ${card.ends.length}${card.endInProgress ? " in progress" : " completed"}"} · Saved on this device',
                ),
                if (card.startedAt != null)
                  Text(
                    'Elapsed ${clock(elapsed)}${card.lastJackMinutes != null ? " · Last jack ${clock(card.lastJackMinutes! * 60 - elapsed)}" : ""}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                if (card.durationMinutes != null && card.startedAt != null)
                  Text(
                    'Playing time remaining: ${clock(card.durationMinutes! * 60 - elapsed)}',
                  ),
              ],
            ),
          ),
          if (deadline && !card.complete)
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
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (!card.complete)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  if (card.startedAt == null)
                    FilledButton.icon(
                      onPressed: saving
                          ? null
                          : () => apply(
                              (c) => c.startMatch(DateTime.now().toUtc()),
                            ),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start match timer'),
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
                ScorecardTable(
                  card: card,
                  showHeader: false,
                  selectedEnd:
                      editingEnd ??
                      (card.endInProgress ? card.ends.length - 1 : null),
                  onSelect: saving || card.complete ? null : selectEnd,
                ),
                if (!card.complete &&
                    editingEnd == null &&
                    card.ends.isNotEmpty &&
                    (!card.endInProgress ||
                        card.ends.last['automatic'] == true))
                  OutlinedButton(
                    onPressed: saving ? null : confirmFinish,
                    child: const Text('Finish and review'),
                  ),
                if (card.complete) ...[
                  const Text(
                    'Review the totals, then ask one representative from each side to sign. Signatures acknowledge this scorecard; they do not confirm a competition result.',
                  ),
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
                  TextButton(
                    onPressed: saving
                        ? null
                        : () async {
                            final yes = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text(
                                  'Reopen and clear signatures?',
                                ),
                                content: const Text(
                                  'You can correct earlier ends. Both sides must sign the revised scorecard again.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
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
                    child: const Text(
                      'Reopen to correct scores (clears signatures)',
                    ),
                  ),
                ],
                ExpansionTile(
                  title: const Text('Players and match details'),
                  children: [
                    ListTile(
                      title: Text(
                        '${card.sideA}: ${card.playersA}\n${card.sideB}: ${card.playersB}',
                      ),
                      subtitle: Text(
                        '${card.date} · ${card.venue} · Rink ${card.rink}\n${card.format} · ${card.woods} woods\n${card.notes}',
                      ),
                    ),
                    if (!card.complete)
                      TextButton(
                        onPressed: saving ? null : details,
                        child: const Text('Edit details'),
                      ),
                  ],
                ),
                ExpansionTile(
                  title: const Text('Correction / change history'),
                  children: [
                    for (final e in card.history.reversed)
                      ListTile(
                        dense: true,
                        title: Text('${e['action']}'),
                        subtitle: Text(
                          '${e['at']}\n${e['before'] ?? ""} → ${e['after'] ?? ""}',
                        ),
                      ),
                  ],
                ),
                const Text(
                  'Standalone card • no cloud backup or competition submission. Export a PDF before removing the App or clearing its data. Timer alerts require this screen to remain visible.',
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
  });
  final String sideName, score;
  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  final name = TextEditingController();
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
