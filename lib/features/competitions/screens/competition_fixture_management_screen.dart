import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/club_member_picker_page.dart';
import '../competition_repository.dart';
import '../competition_arrangement_repository.dart';
import '../competition_fixture_management_repository.dart';
import 'competition_rink_selection_screen.dart';

class CompetitionFixtureManagementScreen extends StatefulWidget {
  final String fixtureId;
  final CompetitionFixtureManagementRepository? repository;
  final Future<({DateTime start, DateTime end})?> Function(
    BuildContext,
    DateTime,
    DateTime,
  )?
  windowPicker;
  final Future<String?> Function(BuildContext, Set<String>)? markerPicker;
  const CompetitionFixtureManagementScreen({
    super.key,
    required this.fixtureId,
    this.repository,
    this.windowPicker,
    this.markerPicker,
  });
  @override
  State<CompetitionFixtureManagementScreen> createState() =>
      _CompetitionFixtureManagementScreenState();
}

class _CompetitionFixtureManagementScreenState
    extends State<CompetitionFixtureManagementScreen> {
  late final repo =
      widget.repository ??
      CompetitionFixtureManagementRepository(
        Supabase.instance.client,
        widget.fixtureId,
      );
  CompetitionRow? data;
  bool loading = true, busy = false, changed = false;
  String? error;
  CompetitionRow get fixture =>
      Map<String, dynamic>.from(data!['fixture'] as Map);
  List<CompetitionRow> get rinks =>
      List<CompetitionRow>.from(data!['rinks'] as List);
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await repo.load();
      if (mounted)
        setState(() {
          data = value;
          loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          error = '$e';
          loading = false;
          data = null;
        });
    }
  }

  Future<void> perform(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      changed = true;
      await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> changeBooking() async {
    final expected = fixture;
    final labels = rinks.map((r) => r['home_rink_label']?.toString()).toList();
    final start = parseClubTime(expected['start_at'].toString()),
        end = parseClubTime(expected['end_at'].toString());
    final window = widget.windowPicker != null
        ? await widget.windowPicker!(context, start, end)
        : await pickCompetitionWindow(context, start: start, end: end);
    if (window == null || !mounted) return;
    final now = parseClubTime(DateTime.now().toUtc().toIso8601String());
    if (!window.start.isAfter(now) || !window.end.isAfter(window.start)) {
      setState(() => error = 'Choose a future start and a valid end time.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    CompetitionBookingChoice? choice;
    try {
      final greens = await repo.greens(expected['club_id'].toString());
      if (!mounted) return;
      if (greens.isEmpty) {
        setState(() => error = 'No home greens are available.');
        return;
      }
      choice = await Navigator.of(context).push<CompetitionBookingChoice>(
        MaterialPageRoute(
          builder: (_) => CompetitionRinkSelectionScreen(
            repository: repo,
            greens: greens,
            start: window.start,
            end: window.end,
            requiredRinks: (expected['rinks_required'] as num).toInt(),
            initialGreenId: expected['green_area_id']?.toString(),
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (choice == null || !mounted) return;
    final selected = choice;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update competition booking?'),
        content: Text(
          '${DateFormat('EEE d MMM yyyy, HH:mm').format(selected.start)} – ${DateFormat('HH:mm').format(selected.end)}\n${selected.green['name']} · Rink ${selected.rinkLabels.join(', ')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep current booking'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save booking'),
          ),
        ],
      ),
    );
    if (approved == true && mounted)
      await perform(() => repo.changeBooking(selected, expected, labels));
  }

  Future<void> selectMarker(CompetitionRow rink) async {
    final exclude = Set<String>.from(
      (data!['assigned_member_ids'] as List).map((id) => id.toString()),
    )..remove(rink['marker_member_id']?.toString());
    String? id;
    if (widget.markerPicker != null) {
      id = await widget.markerPicker!(context, exclude);
    } else {
      final result = await Navigator.of(context).push<List<String>>(
        MaterialPageRoute(
          builder: (_) => ClubMemberPickerPage(
            clubId: fixture['club_id'].toString(),
            title: 'Select marker',
            fixtureId: widget.fixtureId,
            useFixtureSection: false,
            excludeMemberProfileIds: exclude,
          ),
        ),
      );
      id = result?.firstOrNull;
    }
    if (id != null && mounted)
      await perform(() => repo.setMarker(rink, true, id));
  }

  @override
  Widget build(BuildContext context) => PopScope<bool>(
    canPop: !busy && !changed,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && !busy) Navigator.of(context).pop(changed);
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Manage competition booking'),
        leading: BackButton(
          onPressed: busy ? null : () => Navigator.pop(context, changed),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: busy ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (data != null) ...[
                  Text(
                    '${fixture['name']}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text('${fixture['round']}'),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            formatWhenLocal(fixture['start_at'].toString()),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            'Ends ${DateFormat('HH:mm').format(parseClubTime(fixture['end_at'].toString()))}',
                          ),
                          Text(
                            'Rink ${rinks.map((r) => r['home_rink_label'] ?? 'Unassigned').join(', ')}',
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: busy ? null : changeBooking,
                            icon: const Icon(Icons.edit_calendar),
                            label: const Text(
                              'Change date, time, green or rink',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Markers',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  for (final rink in rinks)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Team ${rink['number']} · Rink ${rink['home_rink_label'] ?? 'Unassigned'}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Marker required'),
                              value: rink['marker_required'] == true,
                              onChanged: busy
                                  ? null
                                  : (value) => perform(
                                      () => repo.setMarker(
                                        rink,
                                        value,
                                        value
                                            ? rink['marker_member_id']
                                                  ?.toString()
                                            : null,
                                      ),
                                    ),
                            ),
                            if (rink['marker_required'] == true) ...[
                              Text(
                                rink['marker_name']?.toString() ??
                                    'No marker assigned',
                              ),
                              OutlinedButton(
                                onPressed: busy
                                    ? null
                                    : () => selectMarker(rink),
                                child: const Text('Choose marker'),
                              ),
                              if (rink['marker_member_id'] != null)
                                TextButton(
                                  onPressed: busy
                                      ? null
                                      : () => perform(
                                          () =>
                                              repo.setMarker(rink, true, null),
                                        ),
                                  child: const Text('Clear marker'),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  if (busy) const LinearProgressIndicator(),
                ] else
                  TextButton(onPressed: load, child: const Text('Try again')),
              ],
            ),
    ),
  );
}
