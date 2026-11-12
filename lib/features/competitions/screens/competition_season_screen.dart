import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../../core/widgets/club_member_picker_page.dart';
import '../competition_repository.dart';
import '../competition_arrangement_repository.dart';
import '../widgets/competition_card_style.dart';
import '../widgets/competition_result_card.dart';
import '../../clubs/club_access.dart';
import '../competition_draw_pdf.dart';
import 'competition_setup_screen.dart';
import 'competition_publication_screen.dart';
import 'competition_publish_screen.dart';
import 'competition_preliminary_screen.dart';
import 'competition_arrangement_screen.dart';

class CompetitionSeasonScreen extends StatefulWidget {
  final String clubId, competitionId;
  final bool canManage;
  final String? memberId;
  final CompetitionRepository repository;
  const CompetitionSeasonScreen({
    super.key,
    required this.clubId,
    required this.competitionId,
    required this.canManage,
    this.memberId,
    required this.repository,
  });
  @override
  State<CompetitionSeasonScreen> createState() =>
      _CompetitionSeasonScreenState();
}

class _CompetitionSeasonScreenState extends State<CompetitionSeasonScreen> {
  CompetitionData? data;
  Set<String> ownEntryIds = {};
  bool busy = false;
  bool publicationEnabled = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = await widget.repository.load(
        widget.clubId,
        widget.competitionId,
      );
      final memberId =
          widget.memberId ??
          (widget.canManage
              ? ''
              : (await loadClubAccess(clubId: widget.clubId)).currentMemberId);
      final mine = memberId.isEmpty
          ? <CompetitionRow>[]
          : await widget.repository.myEntries(memberId, [widget.competitionId]);
      final canPublish =
          widget.canManage &&
          await widget.repository.publicationEnabled(widget.clubId);
      if (mounted) {
        setState(() {
          ownEntryIds = mine.map((e) => e['entry_id'].toString()).toSet();
          data = result;
          publicationEnabled = canPublish;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> act(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> addEntry() async {
    final playersPerEntry =
        data!.competition['settings']['players_per_entry'] as int;
    final members = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => ClubMemberPickerPage(
          clubId: widget.clubId,
          title: playersPerEntry == 1
              ? 'Add competition players'
              : playersPerEntry == 2
              ? 'Add pairs — select partners consecutively'
              : 'Add teams — select each team consecutively',
          useFixtureSection: false,
          allowMultiple: true,
          reviewSelectionOrder: true,
          selectionGroupSize: playersPerEntry == 1 ? null : playersPerEntry,
          excludeMemberProfileIds: data!.enteredMemberIds,
        ),
      ),
    );
    if (members == null || members.isEmpty || !mounted) return;
    if (playersPerEntry == 1) {
      await act(() async {
        await widget.repository.addSingles(widget.competitionId, members);
      });
      return;
    }
    if (members.length % playersPerEntry != 0) return;
    await act(() async {
      final added = await widget.repository.addTeams(
        widget.competitionId,
        members,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$added ${playersPerEntry == 2 ? 'pairs' : 'teams'} saved.',
            ),
          ),
        );
      }
    });
  }

  Future<void> editHandicap(CompetitionRow entry) async {
    if (data!.competition['settings']['handicap_mode'] == 'team_difference') {
      await editMemberHandicaps(entry);
      return;
    }
    var value = entry['handicap']?.toString() ?? '';
    final form = GlobalKey<FormState>();
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Handicap — ${entry['name']}'),
        content: Form(
          key: form,
          child: TextFormField(
            initialValue: value,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(
              signed: true,
              decimal: true,
            ),
            decoration: const InputDecoration(
              labelText: 'Handicap',
              helperText: 'Positive or negative, for example +3 or -2.',
            ),
            onChanged: (text) => value = text,
            validator: (text) {
              final n = num.tryParse(text?.trim() ?? '');
              return n == null || !n.isFinite || n < -100000 || n > 100000
                  ? 'Enter a positive or negative number'
                  : null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Save handicap'),
          ),
        ],
      ),
    );
    if (approved == true && mounted) {
      await act(
        () => widget.repository.setHandicap(
          entry['id'].toString(),
          num.parse(value.trim()),
        ),
      );
    }
  }

  Future<void> editMemberHandicaps(CompetitionRow entry) async {
    final values = <String, String>{};
    try {
      final rows = await widget.repository.entryHandicaps(
        entry['id'].toString(),
      );
      if (!mounted) return;
      for (final row in rows) {
        values[row['member_profile_id'].toString()] =
            row['individual_handicap']?.toString() ?? '';
      }
      final key = GlobalKey<FormState>();
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Player handicaps — ${entry['name']}'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: key,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'The pair total is calculated automatically. Against each opponent, the lower-total pair starts with the difference.',
                    ),
                    for (final row in rows)
                      TextFormField(
                        initialValue:
                            values[row['member_profile_id'].toString()],
                        onChanged: (value) =>
                            values[row['member_profile_id'].toString()] = value,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                        ),
                        decoration: InputDecoration(
                          labelText:
                              '${row['member']['first_name']} ${row['member']['last_name']}',
                        ),
                        validator: (value) {
                          final n = int.tryParse(value?.trim() ?? '');
                          return n == null || n.abs() > 1000
                              ? 'Enter a whole number between -1000 and 1000'
                              : null;
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (key.currentState!.validate()) Navigator.pop(context, true);
              },
              child: const Text('Save player handicaps'),
            ),
          ],
        ),
      );
      if (accepted == true && mounted) {
        await act(
          () => widget.repository.setMemberHandicaps(entry['id'].toString(), {
            for (final item in values.entries)
              item.key: int.parse(item.value.trim()),
          }),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Widget entryControls(CompetitionRow entry, bool drawCreated) {
    final teamDifference =
        data!.competition['settings']['handicap_mode'] == 'team_difference';
    final handicap = entry['handicap'] as num?;
    final handicapLabel = teamDifference
        ? (handicap == null ? 'Set player handicaps' : 'Team total $handicap')
        : handicap == null
        ? 'Handicap'
        : 'Handicap ${handicap >= 0 ? '+' : ''}$handicap';
    if (!widget.canManage) {
      return Text(
        '${entry['payment_status'] == 'paid' ? 'Paid' : 'Payment not recorded as paid'}${handicap == null ? '' : ' · $handicapLabel'}',
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilterChip(
          label: const Text('Paid'),
          selected: entry['payment_status'] == 'paid',
          showCheckmark: true,
          checkmarkColor: Colors.green.shade900,
          selectedColor: Colors.green.shade100,
          labelStyle: entry['payment_status'] == 'paid'
              ? TextStyle(
                  color: Colors.green.shade900,
                  fontWeight: FontWeight.bold,
                )
              : null,
          side: entry['payment_status'] == 'paid'
              ? BorderSide(color: Colors.green.shade700)
              : null,
          onSelected: busy
              ? null
              : (paid) => act(
                  () => widget.repository.setPaid(entry['id'].toString(), paid),
                ),
        ),
        if (teamDifference)
          ActionChip(
            avatar: const Icon(Icons.calculate_outlined, size: 18),
            label: Text(handicapLabel),
            onPressed: busy || data!.competition['status'] != 'draft'
                ? null
                : () => editHandicap(entry),
          ),
        if (!teamDifference)
          Tooltip(
            message: drawCreated
                ? 'Handicaps are locked after creating the draw'
                : 'Set or clear a signed handicap',
            child: FilterChip(
              label: Text(handicapLabel),
              selected: handicap != null,
              onSelected: busy || drawCreated
                  ? null
                  : (enabled) => enabled
                        ? editHandicap(entry)
                        : act(
                            () => widget.repository.setHandicap(
                              entry['id'].toString(),
                              null,
                            ),
                          ),
            ),
          ),
        if (!teamDifference && handicap != null && !drawCreated)
          IconButton(
            tooltip: 'Edit handicap',
            icon: const Icon(Icons.edit_outlined),
            onPressed: busy ? null : () => editHandicap(entry),
          ),
      ],
    );
  }

  Future<void> buildDraw() async {
    final order = [...data!.orderedEntries];
    var capacity = 2;
    while (capacity < order.length) {
      capacity *= 2;
    }
    final preliminaryPlayers = (order.length - capacity ~/ 2) * 2;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Review draw order'),
          content: SizedBox(
            width: 500,
            height: 400,
            child: Column(
              children: [
                Text(
                  capacity == order.length
                      ? 'Drag entries into draw order. Consecutive entries play each other. Entries will be locked.'
                      : 'The first $preliminaryPlayers players play the preliminary round in consecutive pairs. The remaining ${capacity - order.length} receive byes into the next round. Drag to match your supplied draw.',
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: order.length,
                    onReorderItem: (a, b) => update(() {
                      order.insert(b, order.removeAt(a));
                    }),
                    itemBuilder: (context, i) => ListTile(
                      key: ValueKey(order[i]['id']),
                      leading: Text('${i + 1}'),
                      title: Text('${order[i]['name']}'),
                      subtitle: Text(
                        i < preliminaryPlayers
                            ? 'Opening match ${i ~/ 2 + 1} · ${i.isEven ? 'Side A' : 'Side B'}'
                            : 'Bye into the next round',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create draw'),
            ),
          ],
        ),
      ),
    );
    if (approved == true && mounted) {
      await act(
        () => widget.repository.build(
          widget.competitionId,
          order.map((e) => e['id'].toString()).toList(),
        ),
      );
    }
  }

  Future<void> editPublishedDeadline(CompetitionRow round) async {
    var deadline = DateTime.tryParse('${round['play_by']}');
    final affected = data!.matches
        .where(
          (m) =>
              m['round_id'] == round['id'] &&
              !['completed', 'bye'].contains(m['status']) &&
              (m['side_a_entry_id'] != null || m['side_b_entry_id'] != null),
        )
        .length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('${round['name']} play-by date'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  deadline == null
                      ? 'Play-by date not set'
                      : DateFormat('EEE d MMM yyyy').format(deadline!),
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final value = await showDatePicker(
                    context: context,
                    initialDate: deadline ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (value != null) update(() => deadline = value);
                },
              ),
              TextButton(
                onPressed: () => update(() => deadline = null),
                child: const Text('Clear deadline'),
              ),
              Text(
                publicationEnabled
                    ? '$affected unfinished match(es) affected. A changed date automatically notifies their players. In staging, only approved test addresses receive mail. Existing fixture bookings stay unchanged.'
                    : '$affected unfinished match(es) affected. Reconciliation mode: save this date without sending emails. Existing fixture bookings stay unchanged.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                publicationEnabled
                    ? 'Save and notify affected players'
                    : 'Save date — no emails',
              ),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      await act(
        () => widget.repository.updateRound(
          round['id'].toString(),
          deadline == null ? null : DateFormat('yyyy-MM-dd').format(deadline!),
          Map<String, dynamic>.from(round['rule_overrides'] as Map? ?? {}),
        ),
      );
    }
  }

  Future<void> editRound(CompetitionRow round) async {
    if (data!.competition['status'] == 'published') {
      await editPublishedDeadline(round);
      return;
    }
    var deadline = DateTime.tryParse('${round['play_by']}');
    final overrides = Map<String, dynamic>.from(
      round['rule_overrides'] as Map? ?? {},
    );
    bool noLimit = overrides['time_limit_mode'] == 'none';
    var notes = overrides['rules']?.toString() ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('${round['name']} rules and conditions'),
          content: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    deadline == null
                        ? 'Play-by deadline not set'
                        : DateFormat('EEE d MMM yyyy').format(deadline!),
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: deadline ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) update(() => deadline = d);
                  },
                ),
                TextButton(
                  onPressed: () => update(() => deadline = null),
                  child: const Text('Clear deadline'),
                ),
                SwitchListTile(
                  title: const Text('No playing time limit in this round'),
                  subtitle: const Text(
                    'Otherwise inherit the competition time limit.',
                  ),
                  value: noLimit,
                  onChanged: (v) => update(() => noLimit = v),
                ),
                TextFormField(
                  initialValue: notes,
                  onChanged: (value) => notes = value,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Round-specific rules',
                    helperText: 'Leave blank to use the competition rules.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save round'),
            ),
          ],
        ),
      ),
    );
    final savedOverrides = Map<String, dynamic>.from(overrides)
      ..['rules'] = notes.trim();
    if (noLimit) {
      savedOverrides['time_limit_mode'] = 'none';
    } else if (savedOverrides['time_limit_mode'] == 'none') {
      savedOverrides.remove('time_limit_mode');
    }
    if (ok == true && mounted) {
      await act(
        () => widget.repository.updateRound(
          round['id'].toString(),
          deadline == null ? null : DateFormat('yyyy-MM-dd').format(deadline!),
          savedOverrides,
        ),
      );
    }
  }

  Future<void> showMatch(CompetitionRow match) async {
    final d = data!;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CompetitionMatchScreen(
          data: d,
          match: match,
          canManage: widget.canManage,
          ownEntryIds: ownEntryIds,
          canSubmit:
              ownEntryIds.contains(match['side_a_entry_id']) ||
              ownEntryIds.contains(match['side_b_entry_id']),
          repository: widget.repository,
        ),
      ),
    );
    if (mounted) await load();
  }

  Future<void> printDraw() async {
    final canPrintA3 =
        data!
            .matchesForRound(data!.orderedRounds.first['id'].toString())
            .length <=
        32;
    var layout = canPrintA3
        ? CompetitionPrintLayout.compactA4
        : CompetitionPrintLayout.readableA4;
    var orientation = CompetitionPrintOrientation.landscape;
    var blankWinnerLabels = true;
    var printBackground = false;
    var printRules = false;
    final hasRules = competitionPrintRules(data!).isNotEmpty;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Print competition draw'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<CompetitionPrintLayout>(
                    initialValue: layout,
                    decoration: const InputDecoration(
                      labelText: 'Print format',
                    ),
                    items: [
                      DropdownMenuItem(
                        value: CompetitionPrintLayout.compactA4,
                        enabled: canPrintA3,
                        child: const Text('Compact A4 — single sheet'),
                      ),
                      const DropdownMenuItem(
                        value: CompetitionPrintLayout.readableA4,
                        child: Text('Readable A4 — sections'),
                      ),
                      DropdownMenuItem(
                        value: CompetitionPrintLayout.wholeA3,
                        enabled: canPrintA3,
                        child: const Text('Whole draw on A3'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) update(() => layout = value);
                    },
                  ),
                  if (!canPrintA3)
                    const Text(
                      'Single-sheet formats support up to 64 entries. Use readable A4 sections for larger draws.',
                    ),
                  DropdownButtonFormField<CompetitionPrintOrientation>(
                    initialValue: orientation,
                    decoration: const InputDecoration(labelText: 'Orientation'),
                    items: const [
                      DropdownMenuItem(
                        value: CompetitionPrintOrientation.landscape,
                        child: Text('Landscape'),
                      ),
                      DropdownMenuItem(
                        value: CompetitionPrintOrientation.portrait,
                        child: Text('Portrait'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) update(() => orientation = value);
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Print competition rules'),
                    subtitle: Text(
                      hasRules
                          ? 'Bordered box at the top right, clear of the draw.'
                          : 'Add rules or scoring in competition settings first.',
                    ),
                    value: printRules,
                    onChanged: hasRules
                        ? (value) => update(() => printRules = value)
                        : null,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Print background'),
                    subtitle: const Text(
                      'Club background at a very faint 7% opacity.',
                    ),
                    value: printBackground,
                    onChanged: (value) => update(() => printBackground = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Leave winner labels blank'),
                    subtitle: const Text(
                      'Space for handwritten winners. Known player names remain visible.',
                    ),
                    value: blankWinnerLabels,
                    onChanged: (value) =>
                        update(() => blankWinnerLabels = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Preview'),
            ),
          ],
        ),
      ),
    );
    if (approved != true || !mounted) return;
    await act(() async {
      final d = data!;
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(
              title: Text(
                'Competition draw preview — ${layout == CompetitionPrintLayout.wholeA3 ? 'A3' : 'A4'} ${orientation.name}',
              ),
            ),
            body: PdfPreview(
              pdfFileName: 'Competition-draw.pdf',
              initialPageFormat: competitionPageFormat(layout, orientation),
              canChangePageFormat: false,
              canChangeOrientation: false,
              allowPrinting: true,
              allowSharing: true,
              dynamicLayout: true,
              build: (printerFormat) => buildCompetitionDrawPdf(
                d,
                layout: layout,
                orientation: orientation,
                blankWinnerLabels: blankWinnerLabels,
                printBackground: printBackground,
                printRules: printRules,
                pageFormat: printerFormat,
              ),
            ),
          ),
        ),
      );
    });
  }

  void viewDrawPdf() {
    final d = data!;
    if (d.competition['status'] != 'published' || d.rounds.isEmpty) return;
    final layout =
        d.matchesForRound(d.orderedRounds.first['id'].toString()).length <= 32
        ? CompetitionPrintLayout.compactA4
        : CompetitionPrintLayout.readableA4;
    const orientation = CompetitionPrintOrientation.landscape;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text('${d.competition['name']} — Draw PDF')),
          body: PdfPreview(
            pdfFileName: 'Competition-draw.pdf',
            initialPageFormat: competitionPageFormat(layout, orientation),
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            allowPrinting: false,
            allowSharing: false,
            build: (format) => buildCompetitionDrawPdf(
              d,
              layout: layout,
              orientation: orientation,
              blankWinnerLabels: false,
              pageFormat: format,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (d == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Competition')),
        body: Center(
          child: error == null
              ? const CircularProgressIndicator()
              : Text(error!),
        ),
      );
    }
    final published = d.competition['status'] == 'published';
    final settings = d.competition['settings'] as Map;
    final palette = CompetitionCardStyle(context, d.competition);
    return DefaultTabController(
      length: 3,
      initialIndex: widget.canManage && d.entries.isEmpty ? 0 : 1,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${d.competition['name']}'),
          backgroundColor: palette.background,
          foregroundColor: palette.foreground,
          actions: [
            if (widget.canManage && publicationEnabled)
              PopupMenuButton<String>(
                tooltip: 'Competition admin tools',
                onSelected: (_) => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CompetitionPublicationScreen(
                      clubId: widget.clubId,
                      competitionId: widget.competitionId,
                    ),
                  ),
                ),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'test-email',
                    child: Text('Test tools: preview player email'),
                  ),
                ],
              ),
            if (widget.canManage && d.rounds.isNotEmpty)
              IconButton(
                tooltip: 'Print competition bracket',
                onPressed: busy ? null : printDraw,
                icon: const Icon(Icons.print_outlined),
              ),
            if (!widget.canManage && published && d.rounds.isNotEmpty)
              IconButton(
                tooltip: 'View draw PDF',
                onPressed: busy ? null : viewDrawPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
              ),
          ],
          bottom: TabBar(
            labelColor: palette.foreground,
            unselectedLabelColor: palette.foreground.withValues(alpha: .75),
            indicatorColor: palette.foreground,
            tabs: const [
              Tab(text: 'Entries'),
              Tab(text: 'Draw'),
              Tab(text: 'Rules'),
            ],
          ),
        ),
        body: Column(
          children: [
            if (busy) const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '${d.competition['season']} · ${published ? 'Published' : 'Draft — organisers only'}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (widget.canManage && d.rounds.isEmpty)
                        FilledButton.icon(
                          onPressed: busy ? null : addEntry,
                          icon: const Icon(Icons.person_add_outlined),
                          label: Text(
                            settings['players_per_entry'] == 1
                                ? 'Add players'
                                : settings['players_per_entry'] == 2
                                ? 'Add pairs'
                                : 'Add teams',
                          ),
                        ),
                      Text(
                        '${widget.canManage ? d.orderedEntries.length : ownEntryIds.length} entries · ${settings['players_per_entry']} player(s) per entry',
                      ),
                      for (final e in d.orderedEntries.where(
                        (e) =>
                            widget.canManage || ownEntryIds.contains(e['id']),
                      ))
                        Card(
                          child: ListTile(
                            title: Text(d.entrant(e['id'].toString())),
                            leading: Text('${d.orderedEntries.indexOf(e) + 1}'),
                            trailing: widget.canManage && d.rounds.isEmpty
                                ? IconButton(
                                    tooltip: 'Remove entry',
                                    icon: const Icon(
                                      Icons.person_remove_outlined,
                                    ),
                                    onPressed: busy
                                        ? null
                                        : () async {
                                            final approved = await showDialog<bool>(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                title: const Text(
                                                  'Remove entry?',
                                                ),
                                                content: Text(
                                                  '${e['name']} will be removed from this draft competition.',
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          context,
                                                          false,
                                                        ),
                                                    child: const Text(
                                                      'Keep entry',
                                                    ),
                                                  ),
                                                  FilledButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          context,
                                                          true,
                                                        ),
                                                    child: const Text(
                                                      'Remove entry',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (approved == true && mounted) {
                                              await act(
                                                () => widget.repository
                                                    .removeEntry(
                                                      e['id'].toString(),
                                                    ),
                                              );
                                            }
                                          },
                                  )
                                : null,
                            subtitle: entryControls(e, d.rounds.isNotEmpty),
                          ),
                        ),
                    ],
                  ),
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (d.rounds.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Add at least two entries, then review their order and create the draw.',
                          ),
                        ),
                      if (widget.canManage && d.rounds.isEmpty)
                        FilledButton(
                          onPressed: busy || d.orderedEntries.length < 2
                              ? null
                              : buildDraw,
                          child: const Text('Review and create draw'),
                        ),
                      if (widget.canManage && d.rounds.isNotEmpty && !published)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.undo),
                          label: const Text('Discard draft draw'),
                          onPressed: busy
                              ? null
                              : () async {
                                  final approved = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text(
                                        'Discard unused draft draw?',
                                      ),
                                      content: const Text(
                                        'This removes the draft pairings and round deadlines so you can add more players. Entries, Paid settings and handicaps are kept. Draws with results or linked fixtures cannot be discarded.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('Keep draw'),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text('Discard draw'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (approved == true && mounted) {
                                    await act(
                                      () => widget.repository.discardDraftDraw(
                                        widget.competitionId,
                                      ),
                                    );
                                  }
                                },
                        ),
                      if (widget.canManage && !publicationEnabled)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'Reconciliation mode: check entries, draws and printed records. Publishing and competition emails are disabled.',
                            ),
                          ),
                        ),
                      if (widget.canManage &&
                          publicationEnabled &&
                          d.rounds.isNotEmpty)
                        FilledButton.icon(
                          icon: const Icon(Icons.publish),
                          onPressed: busy
                              ? null
                              : () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => CompetitionPublishScreen(
                                        clubId: widget.clubId,
                                        competitionId: widget.competitionId,
                                      ),
                                    ),
                                  );
                                  if (mounted) await load();
                                },
                          label: Text(
                            published
                                ? 'Publication emails / status'
                                : 'Publish competition',
                          ),
                        ),
                      for (final r in d.orderedRounds) ...[
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${r['name']}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          subtitle: Text(competitionRoundDeadline(r)),
                          trailing: widget.canManage
                              ? TextButton.icon(
                                  label: Text(
                                    published
                                        ? 'Edit play-by date'
                                        : 'Edit round rules',
                                  ),
                                  onPressed: busy ? null : () => editRound(r),
                                  icon: const Icon(Icons.edit_outlined),
                                )
                              : null,
                        ),
                        for (final m
                            in d
                                .matchesForRound(r['id'].toString())
                                .where(
                                  (m) =>
                                      m['status'] != 'bye' &&
                                      (widget.canManage ||
                                          published ||
                                          ownEntryIds.contains(
                                            m['side_a_entry_id'],
                                          ) ||
                                          ownEntryIds.contains(
                                            m['side_b_entry_id'],
                                          )),
                                ))
                          Card(
                            color: palette.tint,
                            surfaceTintColor: Colors.transparent,
                            shape: palette.shape,
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(16),
                              leading: const Icon(Icons.emoji_events_outlined),
                              title: Text(
                                '${d.side(m, 'a')}\nv ${d.side(m, 'b')}',
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      '${d.reference(m)} · ${d.status(m)}${m['status'] == 'completed' || m['score_a'] == null ? '' : '\nScore: ${m['score_a']}–${m['score_b']}'}',
                                    ),
                                    if (d.startingScores(m)
                                        case final String starts)
                                      Text(starts),
                                    if (m['status'] == 'completed' &&
                                        m['winner_entry_id'] != null)
                                      CompetitionResultCard(
                                        data: d,
                                        match: m,
                                        ownEntryIds: ownEntryIds,
                                      ),
                                  ],
                                ),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: busy ? null : () => showMatch(m),
                            ),
                          ),
                        if ((widget.canManage || published) &&
                            d.matches.any(
                              (m) =>
                                  m['round_id'] == r['id'] &&
                                  m['status'] == 'bye',
                            ))
                          ExpansionTile(
                            title: Text(
                              '${d.matches.where((m) => m['round_id'] == r['id'] && m['status'] == 'bye').length} players receive byes into the next round',
                            ),
                            subtitle: const Text(
                              'These players do not play a preliminary match.',
                            ),
                            children: [
                              for (final m
                                  in d
                                      .matchesForRound(r['id'].toString())
                                      .where((m) => m['status'] == 'bye'))
                                ListTile(
                                  title: Text(d.entrant(m['winner_entry_id'])),
                                  trailing: const Icon(
                                    Icons.skip_next_outlined,
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ],
                  ),
                  ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (widget.canManage)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit competition setup'),
                          onPressed: busy
                              ? null
                              : () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute<String>(
                                      builder: (_) => CompetitionSetupScreen(
                                        clubId: widget.clubId,
                                        repository: widget.repository,
                                        initial: d.competition,
                                        structureLocked:
                                            d.entries.isNotEmpty ||
                                            d.rounds.isNotEmpty,
                                      ),
                                    ),
                                  );
                                  if (mounted) await load();
                                },
                        ),
                      ListTile(
                        title: const Text('Fixture Type'),
                        subtitle: Text(
                          '${(d.competition['fixture_type'] as Map?)?['name'] ?? 'Not yet selected'}',
                        ),
                      ),
                      for (final pair in <String, String>{
                        'section': 'Section',
                        'playing_format': 'Playing format',
                        'players_per_entry': 'Players per entry',
                        'rinks_required': 'Rinks per match',
                        'woods_per_player': 'Woods per player',
                        'scoring': 'Winning condition',
                        'booking_minutes': 'Rink-booking minutes',
                        'dress': 'Dress',
                        'eligibility': 'Eligibility / partners',
                        'handicap': 'Handicap rules',
                        'rules': 'Rules and notes',
                      }.entries)
                        ListTile(
                          title: Text(pair.value),
                          subtitle: Text(
                            '${settings[pair.key] ?? 'Not confirmed'}',
                          ),
                        ),
                      ListTile(
                        title: const Text('Playing time limit'),
                        subtitle: Text(
                          settings['time_limit_mode'] == 'none'
                              ? 'No playing time limit'
                              : settings['time_limit_mode'] == 'minutes'
                              ? '${settings['time_limit_minutes']} minutes'
                              : 'Not yet confirmed',
                        ),
                      ),
                      if (settings['time_limit_mode'] == 'minutes' &&
                          settings['last_jack_before_end_minutes'] != null)
                        ListTile(
                          title: const Text('Last jack'),
                          subtitle: Text(
                            '${settings['last_jack_before_end_minutes']} minutes before the time limit (${(settings['time_limit_minutes'] as num).toInt() - (settings['last_jack_before_end_minutes'] as num).toInt()} minutes from starting)',
                          ),
                        ),
                      for (final round in d.orderedRounds)
                        ListTile(
                          title: Text('${round['name']} rules'),
                          subtitle: Text(
                            ((round['rule_overrides'] as Map?)?['rules']
                                        ?.toString()
                                        .trim()
                                        .isNotEmpty ??
                                    false)
                                ? '${round['rule_overrides']['rules']}'
                                : 'Uses competition rules',
                          ),
                          trailing: widget.canManage
                              ? TextButton(
                                  onPressed: busy
                                      ? null
                                      : () => editRound(round),
                                  child: Text(
                                    published
                                        ? 'Edit play-by date'
                                        : 'Edit round rules',
                                  ),
                                )
                              : null,
                        ),
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Round conditions can override the competition rules. Playing time, booking duration and play-by deadlines are separate.',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CompetitionMatchScreen extends StatefulWidget {
  final CompetitionData data;
  final CompetitionRow match;
  final bool canManage;
  final bool canSubmit;
  final Set<String> ownEntryIds;
  final CompetitionRepository repository;
  final CompetitionArrangementRepository? arrangementRepository;
  const CompetitionMatchScreen({
    super.key,
    required this.data,
    required this.match,
    required this.canManage,
    this.canSubmit = false,
    this.ownEntryIds = const {},
    required this.repository,
    this.arrangementRepository,
  });
  @override
  State<CompetitionMatchScreen> createState() => _CompetitionMatchScreenState();
}

class _CompetitionMatchScreenState extends State<CompetitionMatchScreen> {
  final scoreA = TextEditingController(), scoreB = TextEditingController();
  String? winner, error;
  bool busy = false;
  late CompetitionRow match = Map.of(widget.match);
  @override
  void initState() {
    super.initState();
    syncScores();
  }

  void syncScores() {
    scoreA.text = match['score_a']?.toString() ?? '';
    scoreB.text = match['score_b']?.toString() ?? '';
    winner = (match['proposed_winner_entry_id'] ?? match['winner_entry_id'])
        ?.toString();
  }

  Future<void> arrangeFixture() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CompetitionArrangementScreen(
          data: widget.data,
          match: match,
          repository: widget.arrangementRepository,
        ),
      ),
    );
    if (!mounted) return;
    try {
      final refreshed = await widget.repository.load(
        widget.data.competition['club_id'].toString(),
        widget.data.competition['id'].toString(),
      );
      if (mounted) {
        setState(() {
          match = refreshed.matches.firstWhere((m) => m['id'] == match['id']);
          syncScores();
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  void dispose() {
    scoreA.dispose();
    scoreB.dispose();
    super.dispose();
  }

  Future<void> submit({bool confirm = false}) async {
    final a = confirm ? match['score_a'] as int? : int.tryParse(scoreA.text);
    final b = confirm ? match['score_b'] as int? : int.tryParse(scoreB.text);
    final w = confirm ? match['proposed_winner_entry_id'] as String? : winner;
    if (a == null || b == null || a < 0 || b < 0 || w == null) {
      setState(() => error = 'Enter both scores and select the winner.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.result(
        match['id'].toString(),
        a,
        b,
        w,
        confirm: confirm,
      );
      final refreshed = await widget.repository.load(
        widget.data.competition['club_id'].toString(),
        widget.data.competition['id'].toString(),
      );
      if (mounted) {
        setState(() {
          match = refreshed.matches.firstWhere((m) => m['id'] == match['id']);
          syncScores();
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> awardWalkover() async {
    String? selectedWinner, reason, validation;
    var note = '';
    const reasons = {
      'pulled_out': 'Pulled out',
      'injured_unwell': 'Injured / unwell',
      'deadline': 'Unable to arrange before the deadline',
      'no_show': 'Did not attend',
      'ineligible': 'Disqualified / ineligible',
      'other': 'Other',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Award walkover?'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'The selected entry wins by W/O and advances immediately. No score is recorded. The reason is kept in the Admin audit history.',
                  ),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Entry receiving the walkover',
                    ),
                    items: [
                      for (final side in ['a', 'b'])
                        DropdownMenuItem(
                          value: match['side_${side}_entry_id'].toString(),
                          child: Text(widget.data.side(match, side)),
                        ),
                    ],
                    onChanged: (v) => update(() => selectedWinner = v),
                  ),
                  if (selectedWinner != null)
                    Text(
                      'Other entry: ${widget.data.entrant((selectedWinner == match['side_a_entry_id'] ? match['side_b_entry_id'] : match['side_a_entry_id']).toString())}',
                    ),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Reason for the other entry conceding',
                    ),
                    items: [
                      for (final r in reasons.entries)
                        DropdownMenuItem(value: r.key, child: Text(r.value)),
                    ],
                    onChanged: (v) => update(() => reason = v),
                  ),
                  TextFormField(
                    maxLength: 2000,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Admin explanation (required for Other)',
                    ),
                    onChanged: (v) => note = v,
                  ),
                  if (match['fixture_id'] != null)
                    const Text(
                      'A fixture is already booked. Awarding this walkover will not cancel that booking. Review it separately.',
                    ),
                  if (validation != null)
                    Text(
                      validation!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (selectedWinner == null ||
                    reason == null ||
                    (reason == 'other' && note.trim().isEmpty)) {
                  update(
                    () => validation =
                        'Choose the winning entry and reason. Other requires an explanation.',
                  );
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Confirm walkover'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.awardWalkover(
        match,
        selectedWinner!,
        reason!,
        note.trim(),
      );
      final refreshed = await widget.repository.load(
        widget.data.competition['club_id'].toString(),
        widget.data.competition['id'].toString(),
      );
      if (mounted) {
        setState(() {
          match = refreshed.matches.firstWhere((m) => m['id'] == match['id']);
          syncScores();
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget resultCard(CompetitionData d, bool playable) {
    if (match['status'] == 'completed') {
      final result = CompetitionResultCard(
        key: const ValueKey('competition-result-card'),
        data: d,
        match: match,
        ownEntryIds: widget.ownEntryIds,
      );
      if (!widget.canManage || match['result_kind'] != 'walkover') {
        return result;
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          result,
          TextButton.icon(
            icon: const Icon(Icons.history),
            label: const Text('View walkover audit'),
            onPressed: () async {
              try {
                final audit = await widget.repository.walkoverAudit(
                  match['id'].toString(),
                );
                if (!mounted) return;
                await showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Walkover — Admin record'),
                    content: Text(
                      audit == null
                          ? 'No audit record available.'
                          : 'Reason: ${audit['reason']}\n${audit['note'] ?? ''}\nRecorded: ${audit['recorded_at']}',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Unable to load the Admin audit record.'),
                    ),
                  );
                }
              }
            },
          ),
        ],
      );
    }
    final tint = Color.alphaBlend(
      (match['status'] == 'result_pending' ? Colors.amber : Colors.lightBlue)
          .withValues(alpha: .16),
      Theme.of(context).colorScheme.surface,
    );
    final pending = match['status'] == 'result_pending';
    final canEdit =
        playable && !pending && (widget.canManage || widget.canSubmit);
    return Card(
      key: const ValueKey('competition-result-card'),
      color: tint,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: match['status'] == 'result_pending'
              ? Colors.amber.shade700
              : Colors.blue.shade400,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Match result', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (pending)
              const Text(
                'Awaiting Club Admin confirmation.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            if (match['status'] == 'completed')
              const Text(
                'Result confirmed.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            if (!canEdit &&
                (match['winner_entry_id'] ??
                        match['proposed_winner_entry_id']) !=
                    null)
              Text(
                '${pending ? 'Proposed winner' : 'Winner'}: ${d.entrant((match['winner_entry_id'] ?? match['proposed_winner_entry_id'])?.toString())}',
              ),
            if (!canEdit && match['score_a'] != null)
              Text(
                '${d.side(match, 'a')}: ${match['score_a']}\n${d.side(match, 'b')}: ${match['score_b']}',
              ),
            if (canEdit) ...[
              const Text(
                'Enter the final scores and select the winner under the competition rules. A Club Admin must confirm the result before the winner advances. Handicap adjustments must be checked by the organiser.',
              ),
              TextField(
                controller: scoreA,
                enabled: !busy,
                decoration: InputDecoration(
                  labelText: 'Score — ${d.side(match, 'a')}',
                ),
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                controller: scoreB,
                enabled: !busy,
                decoration: InputDecoration(
                  labelText: 'Score — ${d.side(match, 'b')}',
                ),
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
              ),
              DropdownButtonFormField<String>(
                key: ValueKey(
                  'winner-${match['status']}-${match['proposed_winner_entry_id']}',
                ),
                initialValue: winner,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Winner'),
                items: [
                  for (final side in ['a', 'b'])
                    DropdownMenuItem(
                      value: match['side_${side}_entry_id'].toString(),
                      child: Text(
                        d.side(match, side),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (value) => setState(() => winner = value),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: busy ? null : () => submit(),
                child: const Text('Submit result for confirmation'),
              ),
            ],
            if (pending && widget.canManage) ...[
              const SizedBox(height: 12),
              const Text(
                'Check the submitted scores and winner, then confirm to advance the winner.',
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: busy ? null : () => submit(confirm: true),
                child: const Text('Confirm result and advance winner'),
              ),
              const Text(
                'For shared scorecard corrections, open the shared card and choose Return to scorer for correction from More match actions.',
              ),
            ],
            if (widget.canManage && playable && !pending)
              OutlinedButton.icon(
                onPressed: busy ? null : awardWalkover,
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Award walkover'),
              ),
            if (!canEdit && !pending && playable)
              const Text(
                'Only a player in this match or a Club Admin may submit a result.',
              ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final palette = CompetitionCardStyle(context, d.competition);
    final instructionsPalette = CompetitionCardStyle(
      context,
      d.competition,
      strength: .08,
    );
    final round = d.rounds.firstWhere((r) => r['id'] == match['round_id']);
    final conditions = <String, dynamic>{
      ...Map<String, dynamic>.from(d.competition['settings'] as Map),
      ...Map<String, dynamic>.from(round['rule_overrides'] as Map? ?? {}),
    };
    final timeLimit = conditions['time_limit_mode'] == 'none'
        ? 'No playing time limit'
        : conditions['time_limit_mode'] == 'minutes'
        ? '${conditions['time_limit_minutes']} minutes'
        : 'Playing time limit not yet confirmed';
    final playable =
        match['side_a_entry_id'] != null &&
        match['side_b_entry_id'] != null &&
        !['bye', 'completed'].contains(match['status']);
    return Scaffold(
      appBar: AppBar(title: Text(d.reference(match))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                key: const ValueKey('competition-heading-card'),
                color: palette.background,
                surfaceTintColor: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${d.competition['name']}',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: palette.foreground,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        '${d.reference(match)} · ${d.status(match)}',
                        style: TextStyle(color: palette.foreground),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                key: const ValueKey('competition-names-card'),
                color: palette.tint,
                surfaceTintColor: Colors.transparent,
                shape: palette.shape,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        d.side(match, 'a'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Text('versus'),
                      Text(
                        d.side(match, 'b'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      if (d.startingScores(match) case final String starts)
                        Text(
                          starts,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      Text('Play by ${round['play_by'] ?? 'not set'}'),
                    ],
                  ),
                ),
              ),
              if (widget.canManage &&
                  d.competition['status'] == 'published' &&
                  match['status'] == 'to_be_arranged' &&
                  match['fixture_id'] == null &&
                  playable)
                FilledButton.icon(
                  key: const ValueKey('admin-arrange-competition-fixture'),
                  onPressed: busy ? null : arrangeFixture,
                  icon: const Icon(Icons.event_available),
                  label: const Text('Arrange fixture for these players'),
                ),
              if (widget.canManage &&
                  ['a', 'b'].any(
                    (side) =>
                        match['side_${side}_entry_id'] != null &&
                        preliminaryBye(
                              d,
                              match,
                              match['side_${side}_entry_id'].toString(),
                            ) !=
                            null,
                  ))
                OutlinedButton.icon(
                  icon: const Icon(Icons.account_tree_outlined),
                  label: const Text('Add preliminary match'),
                  onPressed: () async {
                    final changed = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => CompetitionPreliminaryScreen(
                          data: d,
                          match: match,
                          repository: widget.repository,
                        ),
                      ),
                    );
                    if (changed == true && mounted) Navigator.of(context).pop();
                  },
                ),
              if (match['challenger_entry_id'] != null)
                Text(
                  'Challengers: ${d.entrant(match['challenger_entry_id'].toString())}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              if (d.competition['status'] == 'published' &&
                  (playable || match['status'] == 'completed'))
                resultCard(d, playable),
              for (final next in d.matches.where(
                (m) =>
                    m['side_a_source_id'] == match['id'] ||
                    m['side_b_source_id'] == match['id'],
              ))
                Text('Winner advances to ${d.reference(next)}.'),
              if (match['status'] == 'bye')
                const Text('This entry advances without a playable fixture.'),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('View draw'),
              ),
              Card(
                key: const ValueKey('competition-instructions-card'),
                color: instructionsPalette.tint,
                surfaceTintColor: Colors.transparent,
                shape: instructionsPalette.shape,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Playing conditions',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${conditions['section']} · ${conditions['playing_format']}',
                      ),
                      Text(
                        '${conditions['players_per_entry']} player(s) per entry · ${conditions['rinks_required'] ?? 'Not confirmed'} rink(s)',
                      ),
                      Text(
                        'Woods per player: ${conditions['woods_per_player'] ?? 'Not confirmed'}',
                      ),
                      Text(
                        'Scoring: ${conditions['scoring'] ?? 'Not confirmed'}',
                      ),
                      Text(timeLimit),
                      Text(
                        'Rink-booking duration: ${conditions['booking_minutes']} minutes',
                      ),
                      if ('${conditions['dress'] ?? ''}'.isNotEmpty)
                        Text('Dress: ${conditions['dress']}'),
                      if ('${d.competition['settings']['rules'] ?? ''}'
                          .isNotEmpty)
                        Text('${d.competition['settings']['rules']}'),
                      if ('${round['rule_overrides']['rules'] ?? ''}'
                          .isNotEmpty)
                        Text(
                          'Round rules: ${round['rule_overrides']['rules']}',
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
