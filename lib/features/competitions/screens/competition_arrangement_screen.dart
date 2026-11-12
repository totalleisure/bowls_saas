import '../widgets/competition_deadline_warning.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/hex_color.dart';
import '../../../core/utils/date_format.dart';
import '../../fixtures/fixture_details_page.dart';
import '../competition_repository.dart';
import '../competition_arrangement_repository.dart';
import 'competition_rink_selection_screen.dart';

class CompetitionArrangementScreen extends StatefulWidget {
  final CompetitionData data;
  final CompetitionRow match;
  final CompetitionArrangementRepository? repository;
  final Future<({DateTime start, DateTime end})?> Function(
    BuildContext context,
    DateTime? start,
    DateTime? end,
    int minutes,
  )?
  windowPicker;
  const CompetitionArrangementScreen({
    super.key,
    required this.data,
    required this.match,
    this.repository,
    this.windowPicker,
  });
  @override
  State<CompetitionArrangementScreen> createState() =>
      _CompetitionArrangementScreenState();
}

class _CompetitionArrangementScreenState
    extends State<CompetitionArrangementScreen> {
  late final repo =
      widget.repository ??
      CompetitionArrangementRepository(Supabase.instance.client);
  List<CompetitionRow> players = [];
  bool loading = true, saving = false, choosingRinks = false;
  String? error, bookedFixture;
  CompetitionBookingChoice? choice;
  late final round = widget.data.rounds.firstWhere(
    (r) => r['id'] == widget.match['round_id'],
  );
  late final settings = <String, dynamic>{
    ...Map<String, dynamic>.from(widget.data.competition['settings'] as Map),
    ...Map<String, dynamic>.from(round['rule_overrides'] as Map? ?? {}),
  };
  int get rinksRequired => (settings['rinks_required'] as num?)?.toInt() ?? 1;
  @override
  void initState() {
    super.initState();
    bookedFixture = widget.match['fixture_id']?.toString();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await repo.players(widget.match);
      if (mounted) {
        setState(() {
          players = result;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          error = '$e';
          loading = false;
        });
    }
  }

  Future<void> chooseTime() async {
    final minutes = (settings['booking_minutes'] as num?)?.toInt() ?? 150;
    final window = widget.windowPicker != null
        ? await widget.windowPicker!(
            context,
            choice?.start,
            choice?.end,
            minutes,
          )
        : await pickCompetitionWindow(
            context,
            start: choice?.start,
            end: choice?.end,
            minutes: minutes,
          );
    if (window == null || !mounted) return;
    final now = parseClubTime(DateTime.now().toUtc().toIso8601String());
    if (!window.end.isAfter(window.start) || !window.start.isAfter(now)) {
      setState(
        () => error =
            'Enter a future date, start time and end time before checking rinks.',
      );
      return;
    }
    setState(() {
      choosingRinks = true;
      error = null;
    });
    try {
      // Do not even load greens or availability until the time window is complete.
      final availableGreens = await repo.greens(
        widget.data.competition['club_id'].toString(),
      );
      if (!mounted) return;
      if (availableGreens.isEmpty) {
        setState(
          () => error = 'No home greens are available. Contact a Club Admin.',
        );
        return;
      }
      final result = await Navigator.of(context).push<CompetitionBookingChoice>(
        MaterialPageRoute(
          builder: (_) => CompetitionRinkSelectionScreen(
            repository: repo,
            greens: availableGreens,
            start: window.start,
            end: window.end,
            requiredRinks: rinksRequired,
            initialGreenId: choice?.green['id']?.toString(),
          ),
        ),
      );
      if (result != null && mounted) {
        setState(() {
          choice = result;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => choosingRinks = false);
    }
  }

  Future<void> confirm() async {
    final selected = choice;
    if (selected == null || saving) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm competition fixture?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.data.competition['name']}\n${DateFormat('EEE d MMM yyyy, HH:mm').format(selected.start)} – ${DateFormat('HH:mm').format(selected.end)}\n${selected.green['name']} · Rink ${selected.rinkLabels.join(', ')}',
            ),
            CompetitionDeadlineWarning(
              scheduledClubTime: selected.start,
              playBy: round['play_by']?.toString(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep arranging'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Book fixture'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final id = await repo.book(widget.match['id'].toString(), selected);
      if (mounted)
        setState(() {
          bookedFixture = id;
          saving = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          saving = false;
          error = '$e';
        });
    }
  }

  List<String> names(String side) {
    final entry = widget.match['side_${side}_entry_id'];
    final names = players.where((p) => p['entry_id'] == entry).map((p) {
      final profile = p['member_profile'] as Map;
      return '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'
          .trim();
    }).toList();
    final display = widget.data.entrant(entry?.toString()).toLowerCase();
    names.sort((a, b) {
      final ai = display.indexOf(a.toLowerCase()),
          bi = display.indexOf(b.toLowerCase());
      return (ai < 0 ? 9999 : ai).compareTo(bi < 0 ? 9999 : bi);
    });
    return names.map((name) {
      final player = players.where((p) {
        final profile = p['member_profile'] as Map;
        return p['entry_id'] == entry &&
            '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'
                    .trim() ==
                name;
      }).firstOrNull;
      return widget.data.playerLabel(name, player?['individual_handicap']);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.data.competition['fixture_type'] as Map?;
    final scheme = type?['colour_scheme'] as Map?;
    final background = colorFromHex(
      scheme?['background_hex']?.toString(),
      fallback: Theme.of(context).colorScheme.surface,
    );
    final foreground = colorFromHex(
      scheme?['foreground_hex']?.toString(),
      fallback: Theme.of(context).colorScheme.onSurface,
    );
    final a = names('a'), b = names('b');
    final size =
        (widget.data.competition['settings']['players_per_entry'] as num?)
            ?.toInt() ??
        1;
    return Scaffold(
      appBar: AppBar(title: const Text('Arrange competition match')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      color: background,
                      surfaceTintColor: Colors.transparent,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '${widget.data.competition['name']}',
                              style: TextStyle(
                                color: foreground,
                                fontSize: 23,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (type?['name'] != null)
                              Text(
                                '${type!['name']}',
                                style: TextStyle(color: foreground),
                              ),
                            Text(
                              widget.data.reference(widget.match),
                              style: TextStyle(color: foreground),
                            ),
                            Text(
                              'Play by: ${round['play_by'] == null ? 'Not yet set' : DateFormat('EEE d MMM yyyy').format(DateTime.parse(round['play_by'].toString()))}',
                              style: TextStyle(
                                color: foreground,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    CompetitionDeadlineWarning(
                      scheduledClubTime: choice?.start,
                      playBy: round['play_by']?.toString(),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (players.isEmpty)
                      TextButton(
                        onPressed: load,
                        child: const Text('Reload match players'),
                      ),
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              bookedFixture == null
                                  ? 'Set the date and time'
                                  : 'Fixture booked',
                              style: Theme.of(context).textTheme.titleLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            if (bookedFixture == null) ...[
                              const Text(
                                'Choose a date and time, then check the green and select the available rink. Nothing is booked until you confirm.',
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed:
                                    saving || choosingRinks || players.isEmpty
                                    ? null
                                    : chooseTime,
                                icon: const Icon(Icons.calendar_month),
                                label: Text(
                                  choice == null
                                      ? 'Choose date and time'
                                      : 'Change date, time or rink',
                                ),
                              ),
                              if (choosingRinks)
                                const LinearProgressIndicator(),
                              if (choice != null) ...[
                                Text(
                                  '${DateFormat('EEE d MMM yyyy, HH:mm').format(choice!.start)} – ${DateFormat('HH:mm').format(choice!.end)}',
                                  textAlign: TextAlign.center,
                                ),
                                Text(
                                  '${choice!.green['name']} · Rink ${choice!.rinkLabels.join(', ')}',
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                FilledButton(
                                  onPressed: saving ? null : confirm,
                                  child: Text(
                                    saving ? 'Booking…' : 'Confirm fixture',
                                  ),
                                ),
                              ],
                              TextButton(
                                onPressed: saving
                                    ? null
                                    : () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                            ] else ...[
                              const Text(
                                'This competition match is linked to its fixture.',
                              ),
                              FilledButton(
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => FixtureDetailsPage(
                                      fixtureId: bookedFixture!,
                                    ),
                                  ),
                                ),
                                child: const Text('Open fixture'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Card(
                      margin: const EdgeInsets.only(top: 8, bottom: 20),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Players and opponents',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.black12),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                children: [
                                  for (var i = 0; i < size; i++)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 10,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          for (final side in ['a', 'b']) ...[
                                            if (side == 'b')
                                              const SizedBox(width: 6),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  Text(
                                                    '${side == 'a' ? 'Player' : 'Opponent'} ${i + 1}',
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.bodySmall,
                                                  ),
                                                  const SizedBox(height: 3),
                                                  OutlinedButton(
                                                    onPressed: null,
                                                    style:
                                                        OutlinedButton.styleFrom(
                                                          disabledForegroundColor:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .onSurface,
                                                        ),
                                                    child: Text(
                                                      i <
                                                              (side == 'a'
                                                                      ? a
                                                                      : b)
                                                                  .length
                                                          ? (side == 'a'
                                                                ? a
                                                                : b)[i]
                                                          : 'Awaiting player',
                                                      maxLines: 2,
                                                      textAlign:
                                                          TextAlign.center,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Text(
                      'Playing conditions',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    for (final key in [
                      'playing_format',
                      'section',
                      'dress',
                      'scoring',
                      'woods_per_player',
                      'rules',
                    ])
                      if (settings[key]?.toString().trim().isNotEmpty ?? false)
                        ListTile(
                          title: Text(
                            {
                              'playing_format': 'Format',
                              'section': 'Section',
                              'dress': 'Dress',
                              'scoring': 'Winning condition',
                              'woods_per_player': 'Woods per player',
                              'rules': 'Rules',
                            }[key]!,
                          ),
                          subtitle: Text('${settings[key]}'),
                        ),
                  ],
                ),
              ),
            ),
    );
  }
}
