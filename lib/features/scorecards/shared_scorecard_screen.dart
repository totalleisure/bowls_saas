import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../competitions/competition_repository.dart';
import '../competitions/screens/competition_season_screen.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'scorecard.dart';
import 'scorecard_repository.dart';
import 'scorecard_setup.dart';
import 'scorecard_table.dart';
import 'scorecard_match_summary.dart';
import 'scorecard_screen.dart';
import 'fixture_scorecard_template.dart';
import 'shared_scorecard_api.dart';
import 'fixture_scorecard_identity.dart';

class SharedScorecardScreen extends StatefulWidget {
  const SharedScorecardScreen({
    super.key,
    required this.fixtureId,
    required this.rinkId,
    this.api,
    this.repository,
    this.competitionRepository,
  });
  final String fixtureId, rinkId;
  final SharedScorecardApi? api;
  final ScorecardRepository? repository;
  final CompetitionRepository? competitionRepository;
  @override
  State<SharedScorecardScreen> createState() => _SharedScorecardScreenState();
}

class _SharedScorecardScreenState extends State<SharedScorecardScreen> {
  late final api = widget.api ?? SharedScorecardApi();
  late final repository = widget.repository ?? ScorecardRepository.instance;
  Map<String, dynamic>? state;
  String? error;
  bool busy = false;
  bool capturingSignatures = false;
  Timer? poll;
  int requestGeneration = 0;
  Map<String, dynamic> get location => {
    'p_fixture_id': widget.fixtureId,
    'p_rink_id': widget.rinkId,
  };
  Map<String, dynamic> get actor =>
      (state?['actor'] as Map? ?? {}).cast<String, dynamic>();
  Map<String, dynamic>? get shared =>
      (state?['shared'] as Map?)?.cast<String, dynamic>();

  @override
  void initState() {
    super.initState();
    refresh();
    poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!busy && ModalRoute.of(context)?.isCurrent == true) {
        refresh(quiet: true);
      }
    });
  }

  @override
  void dispose() {
    poll?.cancel();
    super.dispose();
  }

  Future<void> refresh({bool quiet = false}) async {
    if (busy) return;
    final generation = ++requestGeneration;
    if (!quiet) setState(() => busy = true);
    try {
      final result = await api.call('shared_scorecard_state', location);
      if (mounted && generation == requestGeneration) {
        final confirmed = result['shared'];
        if (confirmed is Map &&
            confirmed['isOwner'] == true &&
            (confirmed['signedOnOneDevice'] == true ||
                confirmed['phase'] == 'correction_requested')) {
          await repository.rememberSignatures(
            Map<String, dynamic>.from(confirmed),
          );
        }
        if (confirmed is Map && confirmed['competitionStatus'] == 'completed') {
          await repository.rememberConfirmation(
            Map<String, dynamic>.from(confirmed),
          );
        }
        if (!mounted || generation != requestGeneration) return;
        setState(() {
          state = result;
          error = null;
        });
      }
    } catch (e) {
      if (mounted && generation == requestGeneration) {
        setState(
          () => error =
              'Unable to refresh. Showing the last uploaded card. ${SharedScorecardApi.errorMessage(e)}',
        );
      }
    } finally {
      if (mounted && !quiet) setState(() => busy = false);
    }
  }

  Future<void> action(String name, Map<String, dynamic> params) async {
    if (busy) return;
    ++requestGeneration;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await api.call(name, {...location, ...params});
      if (mounted) setState(() => state = result);
    } catch (e) {
      if (mounted) setState(() => error = SharedScorecardApi.errorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> signOnDevice(Scorecard card) async {
    if (busy || shared == null) return;
    final version = shared!['version'];
    ++requestGeneration;
    setState(() {
      busy = true;
      capturingSignatures = true;
      error = null;
    });
    try {
      final review = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Review and sign together'),
          content: Text(
            '${card.sideA}: ${card.totalA}\n${card.sideB}: ${card.totalB}\n\n'
            'Check the ends and final totals together. A representative from each side will sign on this device. '
            'These signatures acknowledge this version of the scores; the Competition Secretary still confirms the competition result.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue to signatures'),
            ),
          ],
        ),
      );
      if (review != true || !mounted) return;
      final signatures = <Map<String, dynamic>>[];
      for (final home in [true, false]) {
        final signed = await Navigator.of(context).push<SignatureResult>(
          MaterialPageRoute(
            builder: (_) => SignatureScreen(
              sideName: home ? card.sideA : card.sideB,
              score: '${card.totalA} : ${card.totalB}',
              initialName: home ? card.suggestedSignerA : card.suggestedSignerB,
            ),
          ),
        );
        if (signed == null || !mounted) return;
        signatures.add({'name': signed.name, 'strokes': signed.strokes});
      }
      if (mounted) setState(() => capturingSignatures = false);
      final result = await api.call('sign_shared_scorecard_on_device', {
        ...location,
        'p_version': version,
        'p_signature_a': signatures[0],
        'p_signature_b': signatures[1],
      });
      await repository.rememberSignatures(
        Map<String, dynamic>.from(result['shared'] as Map),
      );
      if (mounted) setState(() => state = result);
    } catch (e) {
      if (mounted) setState(() => error = SharedScorecardApi.errorMessage(e));
    } finally {
      if (mounted)
        setState(() {
          busy = false;
          capturingSignatures = false;
        });
    }
  }

  Future<void> keep() async {
    if (busy || state == null) return;
    final local = await repository.load();
    if (!mounted) return;
    final existing = local
        .where(
          (c) =>
              (c.fixtureLink?['sharedCardId'] == shared?['id'] ||
                  c.fixtureLink?['sharedPendingClaim'] == true) &&
              c.fixtureLink?['scorerUserId'] == actor['userId'] &&
              c.fixtureLink?['sharedWriterToken'] != null &&
              c.fixtureLink?['fixtureId'] == widget.fixtureId &&
              c.fixtureLink?['fixtureRinkId'] == widget.rinkId,
        )
        .toList();
    if (shared != null &&
        (existing.isEmpty ||
            existing.first.fixtureLink?['sharedPendingClaim'] != true)) {
      if (existing.isEmpty) {
        if (mounted) {
          setState(
            () => error =
                'This card is kept on the device that claimed it. Continue there; do not create a second card.',
          );
        }
        return;
      }
      if (!mounted) return;
      var scorerCard = existing.first;
      final request = shared?['correctionNote']?.toString();
      if (shared?['phase'] == 'correction_requested') {
        final approved = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Review correction request'),
            content: SingleChildScrollView(
              child: Text(
                '${request ?? 'Check the scores.'}\n\n'
                'Choose Edit requested scores to unlock your card. Tap the end that needs changing, save its corrected score, then finish. '
                'No score changes automatically. Both sides must agree the revised result.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Edit requested scores'),
              ),
            ],
          ),
        );
        if (approved != true || !mounted) return;
        ++requestGeneration;
        setState(() {
          busy = true;
          error = null;
        });
        try {
          await api.reopen(scorerCard);
          final reopened = Scorecard.fromJson(scorerCard.toJson());
          reopened.fixtureLink = {
            ...reopened.fixtureLink!,
            'sharedCorrectionRequest': request ?? 'Check the scores.',
          };
          reopened.reopen();
          await repository.save(reopened);
          scorerCard = reopened;
        } catch (e) {
          if (mounted) {
            setState(
              () => error =
                  'Could not start the correction. ${SharedScorecardApi.errorMessage(e)}',
            );
          }
          return;
        } finally {
          if (mounted) setState(() => busy = false);
        }
        if (!mounted) return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ScorecardScreen(
            card: scorerCard,
            repository: repository,
            sharedApi: api,
          ),
        ),
      );
      await refresh();
      return;
    }
    final snapshot = Map<String, dynamic>.from(state!['snapshot'] as Map);
    final initial = scorecardFromFixture(snapshot);
    final reviewed =
        existing.isNotEmpty &&
            existing.first.fixtureLink?['sharedPendingClaim'] == true
        ? existing.first
        : await Navigator.of(context).push<Scorecard>(
            MaterialPageRoute(builder: (_) => ScorecardSetup(card: initial)),
          );
    if (reviewed == null || !mounted) return;
    final token =
        reviewed.fixtureLink?['sharedWriterToken'] ?? const Uuid().v4();
    ++requestGeneration;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      reviewed.fixtureLink = {
        ...snapshot,
        'sharedWriterToken': token,
        'scorerUserId': actor['userId'],
        'sharedPendingClaim': true,
      };
      // Persist the claim credential before the network round trip. A timeout
      // after server commit can then be recovered idempotently on this device.
      await repository.save(reviewed);
      final result = await api.call('claim_shared_scorecard', {
        ...location,
        'p_fingerprint': state!['fingerprint'],
        'p_writer_token': token,
        'p_document': reviewed.toJson(),
      });
      final cloud = Map<String, dynamic>.from(result['shared'] as Map);
      reviewed.fixtureLink = {
        ...snapshot,
        'sharedCardId': cloud['id'],
        'sharedWriterToken': token,
        'scorerUserId': actor['userId'],
      };
      await repository.save(reviewed);
      if (!mounted) return;
      setState(() {
        state = result;
        busy = false;
      });
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ScorecardScreen(
            card: reviewed,
            repository: repository,
            sharedApi: api,
          ),
        ),
      );
      await refresh();
    } catch (e) {
      if (mounted) {
        setState(
          () => error =
              'Unable to claim or save the card: ${SharedScorecardApi.errorMessage(e)}',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> correction({bool adminReturn = false}) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          adminReturn
              ? 'Return to scorer for correction'
              : 'Request a correction',
        ),
        content: TextField(
          controller: controller,
          maxLength: 1000,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'What needs correcting?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Send request'),
          ),
        ],
      ),
    );
    // The dialog's closing animation may still be using its text controller.
    if (note == null || note.trim().isEmpty) return;
    await action(
      adminReturn
          ? 'return_shared_scorecard_for_correction'
          : 'request_shared_scorecard_correction',
      {'p_version': shared!['version'], 'p_note': note},
    );
  }

  Widget nextAction(Map<String, dynamic>? cloud, Scorecard? card) {
    final phase = cloud?['phase'];
    final side = actor['side'];
    final ownAgreed =
        (side == 'a' && cloud?['agreedA'] == true) ||
        (side == 'b' && cloud?['agreedB'] == true);
    final bothAgreed = cloud?['agreedA'] == true && cloud?['agreedB'] == true;
    String label, status;
    VoidCallback? press;
    if (cloud == null) {
      label = 'Keep the match scorecard';
      status = 'One player or marker keeps the card';
      if (actor['canKeep'] == true && actor['available'] == true) press = keep;
    } else if (cloud['competitionStatus'] == 'completed') {
      label = 'Admin confirmed';
      status = 'Result confirmed — winner advanced';
      final link = card?.fixtureLink;
      if (link?['clubId'] != null && link?['competitionId'] != null) {
        label = 'View competition draw';
        press = () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CompetitionSeasonScreen(
              clubId: link!['clubId'].toString(),
              competitionId: link['competitionId'].toString(),
              canManage: actor['admin'] == true,
              repository:
                  widget.competitionRepository ??
                  CompetitionRepository(Supabase.instance.client),
            ),
          ),
        );
      }
    } else if (phase == 'submitted') {
      label = 'Awaiting Admin confirmation';
      status = 'Both sides agreed — result submitted';
    } else if (cloud['sourceChanged'] == true) {
      label = 'Fixture review required';
      status = 'Ask Club Admin to review the changed fixture';
    } else if (phase == 'correction_requested') {
      label = cloud['isOwner'] == true
          ? 'Review correction request'
          : 'Waiting for scorer’s correction';
      status = 'Both sides must agree again after correction';
      if (cloud['isOwner'] == true) press = keep;
    } else if (phase == 'review' && bothAgreed) {
      status =
          '${cloud['signedOnOneDevice'] == true ? 'Signed by both parties' : 'Both sides agreed'} · ${cloud['totalA']}–${cloud['totalB']}';
      if (card?.fixtureLink?['competitionMatchId'] != null &&
          (side != null || actor['admin'] == true)) {
        label = 'Submit agreed result';
        press = () =>
            action('submit_shared_scorecard', {'p_version': cloud['version']});
      } else {
        status =
            '${cloud['signedOnOneDevice'] == true ? 'Signed by both parties' : 'Both sides agreed'} · No further action needed';
        label = 'Result agreed · ${cloud['totalA']}–${cloud['totalB']}';
      }
    } else if (phase == 'review' && side != null && !ownAgreed) {
      label = 'Review and agree scores';
      status = 'Agree for ${side == 'a' ? card!.sideA : card!.sideB}';
      press = () =>
          action('agree_shared_scorecard', {'p_version': cloud['version']});
    } else if (phase == 'review') {
      label = ownAgreed
          ? 'Waiting for opponent’s agreement'
          : 'Waiting for both sides’ agreement';
      status = ownAgreed
          ? 'Your side has agreed'
          : 'Only playing members can agree for their side';
    } else {
      label = cloud['isOwner'] == true
          ? 'Continue scoring'
          : 'Waiting for scorer to finish';
      status = 'Match in progress · ${cloud['totalA']}–${cloud['totalB']}';
      if (cloud['isOwner'] == true) press = keep;
    }
    return SafeArea(
      key: const ValueKey('shared-next-action'),
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
                  if (phase == 'review' &&
                      !bothAgreed &&
                      cloud?['isOwner'] == true &&
                      cloud?['sourceChanged'] != true &&
                      card != null)
                    OutlinedButton.icon(
                      key: const ValueKey('shared-sign-on-device'),
                      onPressed: busy ? null : () => signOnDevice(card),
                      icon: const Icon(Icons.draw),
                      label: const Text('Both parties sign on this device'),
                    ),
                  Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  if (phase == 'review' &&
                      bothAgreed &&
                      card?.fixtureLink?['competitionMatchId'] == null)
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    )
                  else
                    FilledButton(
                      onPressed: busy ? null : press,
                      child: Text(label),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cloud = shared;
    final doc = cloud?['document'] as Map?;
    final card = doc == null
        ? null
        : Scorecard.fromJson(Map<String, dynamic>.from(doc));
    final phase = cloud?['phase'];
    final canAgree =
        actor['side'] != null &&
        phase == 'review' &&
        cloud?['sourceChanged'] != true;
    final bothAgreed = cloud?['agreedA'] == true && cloud?['agreedB'] == true;
    return Scaffold(
      bottomNavigationBar: state == null ? null : nextAction(cloud, card),
      appBar: AppBar(
        title: const Text('Shared match scorecard'),
        actions: [
          if (card != null)
            IconButton(
              tooltip: 'View scorecard PDF',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: busy
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ScorecardPdfScreen(card: card),
                      ),
                    ),
            ),
          if (canAgree ||
              (cloud?['isOwner'] == true && phase == 'review') ||
              (actor['admin'] == true &&
                  phase == 'submitted' &&
                  cloud?['competitionStatus'] == 'result_pending'))
            PopupMenuButton<String>(
              tooltip: 'More match actions',
              onSelected: (value) {
                if (value == 'edit') {
                  keep();
                } else {
                  correction(adminReturn: value == 'return');
                }
              },
              itemBuilder: (_) => [
                if (canAgree)
                  const PopupMenuItem(
                    value: 'correct',
                    child: Text('Request correction'),
                  ),
                if (cloud?['isOwner'] == true && phase == 'review')
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Open scorecard for correction'),
                  ),
                if (actor['admin'] == true &&
                    phase == 'submitted' &&
                    cloud?['competitionStatus'] == 'result_pending')
                  const PopupMenuItem(
                    value: 'return',
                    child: Text('Return to scorer for correction'),
                  ),
              ],
            ),
          IconButton(
            onPressed: busy ? null : refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh shared card',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (busy && !capturingSignatures) const LinearProgressIndicator(),
          if (error != null)
            SelectableText(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (state == null && !busy)
            const Text('Connect to load the shared card.'),
          if (state != null && cloud == null) ...[
            Text(
              '${(state!['snapshot'] as Map)['title']} · Rink ${(state!['snapshot'] as Map)['rink']}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            FixtureScorecardIdentity(
              snapshot: Map<String, dynamic>.from(state!['snapshot'] as Map),
            ),
            const Text(
              'Choose one player or the assigned marker to keep this match card. Other participants review the same uploaded scores. The scorer can continue offline on the claiming device.',
            ),
            if (actor['available'] != true)
              const Text('Scoring is available from the fixture day.'),
          ],
          if (cloud != null && card != null) ...[
            if (cloud['correctionNote'] != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Correction requested',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text('${cloud['correctionNote']}'),
                      Text(
                        cloud['isOwner'] == true
                            ? 'Use Review correction request below to continue.'
                            : 'The scorer will review this request. Scores have not changed yet.',
                      ),
                    ],
                  ),
                ),
              ),
            Text(
              'Kept by ${cloud['ownerName'] ?? 'designated scorer'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('Last uploaded: ${cloud['updatedAt']}'),
            Text(
              'Status: ${cloud['competitionStatus'] == 'completed'
                  ? 'Admin confirmed'
                  : phase == 'review'
                  ? bothAgreed
                        ? (card.fixtureLink?['competitionMatchId'] == null ? 'Result agreed — no further action needed' : 'Both sides agreed')
                        : 'Finished — awaiting agreement'
                  : phase == 'submitted'
                  ? 'Submitted for Admin confirmation'
                  : phase == 'correction_requested'
                  ? 'Correction requested'
                  : 'In progress'}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (cloud['sourceChanged'] == true)
              const Text(
                'Fixture details have changed. Ask Club Admin to review before agreement or submission.',
              ),
            Text(
              '${card.title} · Rink ${card.rink}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '${phase == 'playing' ? 'Score' : 'Final score'}: ${cloud['totalA']}–${cloud['totalB']}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (cloud['competitionStatus'] == 'completed' &&
                SharedScorecardApi.confirmationMetadata(
                      cloud,
                    )['sharedWinnerName'] !=
                    null)
              Text(
                'Winner: ${SharedScorecardApi.confirmationMetadata(cloud)['sharedWinnerName']}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ScorecardTable(card: card),
            ExpansionTile(
              title: const Text('Match details'),
              children: [ScorecardMatchSummary(card: card)],
            ),
            Text(
              '${card.sideA}: ${cloud['signedOnOneDevice'] == true
                  ? 'Signed by ${card.signatureA?['name']}'
                  : cloud['agreedA'] == true
                  ? 'Agreed'
                  : 'Not agreed'}',
            ),
            Text(
              '${card.sideB}: ${cloud['signedOnOneDevice'] == true
                  ? 'Signed by ${card.signatureB?['name']}'
                  : cloud['agreedB'] == true
                  ? 'Agreed'
                  : 'Not agreed'}',
            ),
            if (actor['side'] == null)
              const Text(
                'Each side can agree from its own account, or both representatives can sign together on the designated scorer’s device.',
              ),
            if (cloud['competitionStatus'] == 'completed')
              const Text(
                'Admin confirmed the result. The winner has advanced.',
              ),
            if (phase == 'submitted' &&
                cloud['competitionStatus'] != 'completed')
              const Text(
                'A Club Admin must confirm the result in the competition draw before the winner advances.',
              ),
          ],
        ],
      ),
    );
  }
}
