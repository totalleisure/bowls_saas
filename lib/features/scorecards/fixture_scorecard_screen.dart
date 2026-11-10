import 'dart:convert';
import 'fixture_scorecard_preview.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'scorecard.dart';
import 'scorecard_repository.dart';
import 'scorecard_setup.dart';
import 'scorecard_recovery_host.dart';
import 'fixture_scorecard_template.dart';
import 'shared_scorecard_screen.dart';
import 'fixture_scorecard_identity.dart';

class FixtureScorecardScreen extends StatefulWidget {
  const FixtureScorecardScreen({
    super.key,
    required this.fixtureId,
    this.request,
    this.repository,
    this.clock,
  });
  final String fixtureId;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)?
  request;
  final ScorecardRepository? repository;
  final DateTime Function()? clock;
  @override
  State<FixtureScorecardScreen> createState() => _FixtureScorecardScreenState();
}

class _FixtureScorecardScreenState extends State<FixtureScorecardScreen> {
  late final repository = widget.repository ?? ScorecardRepository.instance;
  Map<String, dynamic>? state;
  String? error;
  bool busy = false;
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> params,
  ) async => widget.request != null
      ? widget.request!(name, params)
      : Map<String, dynamic>.from(
          await Supabase.instance.client.rpc(name, params: params) as Map,
        );
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await call('fixture_scorecard_context', {
        'p_fixture_id': widget.fixtureId,
      });
      if (mounted) setState(() => state = data);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Unable to load the fixture scorecard setup. Connect to the Club service and try again. Existing cards remain available in Offline scorecards.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> open(Map<String, dynamic> rink) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final currentFixture = Map<String, dynamic>.from(rink['snapshot'] as Map);
      if (!fixtureScoringDayReached(
        currentFixture,
        nowUtc: widget.clock?.call(),
      )) {
        final preview = scorecardFromFixture(
          currentFixture,
          applyEntryHandicap: (state!['rinks'] as List).length == 1,
        );
        if (!mounted) return;
        setState(() => busy = false);
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => FixtureScorecardPreview(card: preview),
          ),
        );
        return;
      }
      final user = '${state!['actorUserId']}';
      final saved = await repository.load();
      final existing = saved
          .where(
            (c) =>
                c.fixtureLink?['fixtureId'] == widget.fixtureId &&
                c.fixtureLink?['fixtureRinkId'] == rink['fixtureRinkId'] &&
                c.fixtureLink?['scorerUserId'] == user,
          )
          .toList();
      if (existing.isNotEmpty) {
        var localCard = existing.first;
        final currentSnapshot = Map<String, dynamic>.from(
          rink['snapshot'] as Map,
        );
        if (localCard.startedAt == null) {
          final current = scorecardFromFixture(
            currentFixture,
            applyEntryHandicap: false,
          );
          final stored = localCard.toJson();
          final fresh = current.toJson();
          var changed = false;
          for (final key in [
            'title',
            'date',
            'venue',
            'rink',
            'format',
            'sideA',
            'sideB',
            'playersA',
            'playersB',
            'marker',
            'suggestedSignerA',
            'suggestedSignerB',
          ]) {
            if (stored[key] != fresh[key]) {
              stored[key] = fresh[key];
              changed = true;
            }
          }
          final link = {...localCard.fixtureLink!, ...currentFixture};
          if (jsonEncode(link) != jsonEncode(localCard.fixtureLink)) {
            stored['fixtureLink'] = link;
            changed = true;
          }
          if (changed) {
            localCard = Scorecard.fromJson(stored);
            localCard.changed('Fixture details refreshed before match');
            await repository.save(localCard);
          }
        }
        final currentRules = currentSnapshot['rules'] as Map? ?? {};
        if (localCard.startedAt == null &&
            currentSnapshot['competitionId'] != null &&
            currentRules.containsKey('last_jack_before_end_minutes')) {
          final current = scorecardFromFixture(currentSnapshot);
          if (localCard.durationMinutes != current.durationMinutes ||
              localCard.lastJackMinutes != current.lastJackMinutes) {
            if (!mounted) return;
            setState(() => busy = false);
            final update = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Update competition timing?'),
                content: Text(
                  'The competition timing has changed. Match limit: ${current.durationMinutes == null ? "none" : "${current.durationMinutes} minutes"}. Last jack: ${current.lastJackMinutes == null ? "no separate deadline" : "${current.lastJackMinutes} minutes from starting"}. Update this card before starting?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Keep current timing'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Update timing'),
                  ),
                ],
              ),
            );
            if (mounted) setState(() => busy = true);
            if (update == true) {
              localCard = Scorecard.fromJson(localCard.toJson())
                ..durationMinutes = current.durationMinutes
                ..lastJackMinutes = current.lastJackMinutes;
              localCard.changed('Timing refreshed from competition rules');
              await repository.save(localCard);
            }
          }
        }
        if (mounted) {
          openOfflineScorecards(
            context,
            card: localCard,
            repository: repository,
          );
        }
        return;
      }
      var shared = (rink['setup'] as Map?)?.cast<String, dynamic>();
      final snapshot = currentFixture;
      var card = scorecardFromFixture(
        snapshot,
        conditions: (shared?['conditions'] as Map?)?.cast<String, dynamic>(),
        applyEntryHandicap: (state!['rinks'] as List).length == 1,
      );
      if (!mounted) return;
      if (shared == null) {
        final reviewed = await Navigator.of(context).push<Scorecard>(
          MaterialPageRoute(builder: (_) => ScorecardSetup(card: card)),
        );
        if (reviewed == null) return;
        shared = await call('prepare_fixture_scorecard_setup', {
          'p_fixture_id': widget.fixtureId,
          'p_fixture_rink_id': rink['fixtureRinkId'],
          'p_source_fingerprint': rink['sourceFingerprint'],
          'p_conditions': fixtureScorecardConditions(reviewed),
        });
        card = scorecardFromFixture(
          currentFixture,
          conditions: Map<String, dynamic>.from(shared['conditions'] as Map),
          applyEntryHandicap: (state!['rinks'] as List).length == 1,
        );
      }
      // Competition timing is authoritative for a newly created card, even if
      // an earlier scorer saved the shared setup before the rules were amended.
      final currentSnapshot = Map<String, dynamic>.from(
        rink['snapshot'] as Map,
      );
      final currentRules = currentSnapshot['rules'] as Map? ?? {};
      final savedRules = (shared['snapshot'] as Map)['rules'] as Map? ?? {};
      final timingChanged = [
        'time_limit_mode',
        'time_limit_minutes',
        'last_jack_before_end_minutes',
      ].any((key) => currentRules[key] != savedRules[key]);
      if (currentSnapshot['competitionId'] != null &&
          currentRules.containsKey('last_jack_before_end_minutes') &&
          timingChanged) {
        final current = scorecardFromFixture(currentSnapshot);
        card.durationMinutes = current.durationMinutes;
        card.lastJackMinutes = current.lastJackMinutes;
        card.fixtureLink!['rules'] = currentRules;
      }
      card.fixtureLink = {
        ...card.fixtureLink!,
        'fixtureScorecardMatchId': shared['matchId'],
        'fixtureScorecardRinkId': shared['id'],
        'scorerUserId': user,
      };
      card.changed('Scorecard created from fixture setup');
      await repository.save(card);
      if (mounted) {
        openOfflineScorecards(context, card: card, repository: repository);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : 'Unable to prepare this card. Check the connection and refresh; no fixture result has been changed.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Fixture Scorecards'),
      actions: [
        IconButton(
          onPressed: busy ? null : load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh fixture setup',
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Preview before match day. One player or the assigned marker keeps the shared card, with offline scoring on that device. Both sides review the uploaded final card and agree before submission for Admin confirmation.',
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        for (final raw in state?['rinks'] as List? ?? [])
          Builder(
            builder: (context) {
              final rink = Map<String, dynamic>.from(raw as Map);
              final snapshot = Map<String, dynamic>.from(
                rink['snapshot'] as Map,
              );
              final available = fixtureScoringDayReached(
                snapshot,
                nowUtc: widget.clock?.call(),
              );
              return Card(
                color: const Color(0xffdce8f7),
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Color(0xff9bb5d5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${snapshot['title']} · Rink ${snapshot['rink']}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      FixtureScorecardIdentity(snapshot: snapshot),
                      Text(
                        '${snapshot['format']} · ${snapshot['playersPerSide']} player(s) per side',
                      ),
                      Text(
                        state?['sharedWorkflow'] == true
                            ? 'One shared card for this rink. The scorer uploads when connected; reviewers see the last upload.'
                            : !available
                            ? 'Preview only — scoring is available from the fixture day.'
                            : rink['setup'] == null
                            ? 'No shared setup yet — review the playing conditions before creating your card.'
                            : 'Shared setup available — your card will copy its details, not another scorer’s scores.',
                      ),
                      if (rink['canScore'] == true)
                        FilledButton.icon(
                          onPressed: busy
                              ? null
                              : () async {
                                  if (state?['sharedWorkflow'] == true &&
                                      available) {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => SharedScorecardScreen(
                                          fixtureId: widget.fixtureId,
                                          rinkId: '${rink['fixtureRinkId']}',
                                        ),
                                      ),
                                    );
                                    await load();
                                  } else {
                                    await open(rink);
                                  }
                                },
                          icon: const Icon(Icons.scoreboard_outlined),
                          label: Text(
                            available && state?['sharedWorkflow'] == true
                                ? 'Open shared match scorecard'
                                : available
                                ? 'Open my scorecard'
                                : 'Preview scorecard',
                          ),
                        )
                      else
                        const Text(
                          'Only this rink’s selected players, assigned marker or Club Admins can open its scoring card.',
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        TextButton(
          onPressed: () => openOfflineScorecards(context),
          child: const Text('Open existing offline scorecards'),
        ),
      ],
    ),
  );
}
