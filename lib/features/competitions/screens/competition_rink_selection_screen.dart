import '../../fixtures/widgets/fixture_time_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/hex_color.dart';
import '../competition_repository.dart';
import '../competition_arrangement_repository.dart';

Future<({DateTime start, DateTime end})?> pickCompetitionWindow(
  BuildContext context, {
  DateTime? start,
  DateTime? end,
  int minutes = 150,
}) async {
  final window = await pickFixtureStart(context, start: start, end: end,
    defaultDuration: Duration(minutes: minutes));
  if (window == null || !context.mounted) return null;
  final finish = await pickFixtureEndTime(context, start: window.start, end: window.end);
  if (finish == null || !context.mounted) return null;
  final error = fixtureTimingError(window.start, finish);
  if (error != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    return null;
  }
  return (start: window.start, end: finish);
}

class CompetitionRinkSelectionScreen extends StatefulWidget {
  final CompetitionArrangementRepository repository;
  final List<CompetitionRow> greens;
  final DateTime start, end;
  final int requiredRinks;
  final String? initialGreenId;
  const CompetitionRinkSelectionScreen({
    super.key,
    required this.repository,
    required this.greens,
    required this.start,
    required this.end,
    required this.requiredRinks,
    this.initialGreenId,
  });
  @override
  State<CompetitionRinkSelectionScreen> createState() =>
      _CompetitionRinkSelectionScreenState();
}

class _CompetitionRinkSelectionScreenState
    extends State<CompetitionRinkSelectionScreen> {
  late DateTime start = widget.start, end = widget.end;
  late CompetitionRow green = widget.greens.firstWhere(
    (g) => g['id'] == widget.initialGreenId,
    orElse: () => widget.greens.first,
  );
  List<CompetitionRow> rinks = [];
  final selected = <String>{};
  bool loading = true;
  String? error, orientation;
  int generation = 0;
  List<String> get orientations =>
      List<String>.from(green['allowed_orientations'] as List? ?? []);
  bool get needsOrientation =>
      green['orientation_mode'] != 'not_applicable' && orientations.isNotEmpty;
  bool available(CompetitionRow rink) =>
      rink['is_booked'] != true &&
      ((rink['free_capacity_rinks'] as num?)?.toInt() ?? 0) >=
          widget.requiredRinks;
  @override
  void initState() {
    super.initState();
    orientation = needsOrientation ? orientations.first : null;
    load();
  }

  Future<void> load() async {
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
      selected.clear();
    });
    try {
      final rows = await widget.repository.availability(
        green['id'].toString(),
        start,
        end,
      );
      if (!mounted || request != generation) return;
      setState(() {
        rinks = rows;
        loading = false;
        final free = rows.where(available).toList();
        if (free.length == widget.requiredRinks)
          selected.addAll(free.map((r) => r['rink_label'].toString()));
      });
    } catch (e) {
      if (mounted && request == generation)
        setState(() {
          loading = false;
          error = '$e';
        });
    }
  }

  Future<void> changeTime() async {
    final window = await pickCompetitionWindow(context, start: start, end: end);
    if (window == null || !mounted) return;
    setState(() {
      start = window.start;
      end = window.end;
    });
    await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Choose green and rinks')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          DateFormat('EEEE d MMM yyyy').format(start),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(
          '${DateFormat('HH:mm').format(start)} – ${DateFormat('HH:mm').format(end)}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        OutlinedButton.icon(
          onPressed: changeTime,
          icon: const Icon(Icons.edit_calendar),
          label: const Text('Change date and time'),
        ),
        DropdownButtonFormField<String>(
          initialValue: green['id'].toString(),
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Green'),
          items: [
            for (final g in widget.greens)
              DropdownMenuItem(
                value: g['id'].toString(),
                child: Text('${g['name']}'),
              ),
          ],
          onChanged: (id) {
            if (id == null) return;
            setState(() {
              green = widget.greens.firstWhere((g) => g['id'] == id);
              orientation = needsOrientation ? orientations.first : null;
            });
            load();
          },
        ),
        if (needsOrientation)
          DropdownButtonFormField<String>(
            key: ValueKey(green['id']),
            initialValue: orientation,
            decoration: const InputDecoration(labelText: 'Direction of play'),
            items: [
              for (final o in orientations)
                DropdownMenuItem(value: o, child: Text(o.replaceAll('_', ' '))),
            ],
            onChanged: (v) => setState(() => orientation = v),
          ),
        const SizedBox(height: 16),
        Text(
          'Select ${widget.requiredRinks} rink${widget.requiredRinks == 1 ? '' : 's'} for the whole match. Availability is checked again when you confirm.',
        ),
        const SizedBox(height: 12),
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (!loading && error == null && rinks.isEmpty)
          const Text('No rinks are configured for this green.'),
        if (!loading && error == null)
          for (final rink in rinks)
            Builder(
              builder: (context) {
                final free = available(rink),
                    label = rink['rink_label'].toString(),
                    chosen = selected.contains(label);
                final bg = free
                    ? Colors.green.shade50
                    : colorFromHex(
                        rink['background_hex']?.toString(),
                        fallback: Colors.grey.shade200,
                      );
                final fg = free
                    ? Colors.green.shade900
                    : colorFromHex(
                        rink['foreground_hex']?.toString(),
                        fallback: Colors.grey.shade900,
                      );
                return Card(
                  color: bg,
                  surfaceTintColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: chosen
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: bg,
                      foregroundColor: fg,
                      child: Text(label),
                    ),
                    title: Text(
                      free ? 'Available' : 'Unavailable',
                      style: TextStyle(color: fg, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      free
                          ? '${DateFormat('HH:mm').format(start)} – ${DateFormat('HH:mm').format(end)}'
                          : (rink['booked_text']
                                    ?.toString()
                                    .trim()
                                    .isNotEmpty ??
                                false)
                          ? rink['booked_text'].toString()
                          : 'Capacity is reserved by other fixtures during this time.',
                      style: TextStyle(color: fg),
                    ),
                    trailing: Icon(
                      chosen
                          ? Icons.check_circle
                          : free
                          ? Icons.radio_button_unchecked
                          : Icons.lock_outline,
                      color: fg,
                    ),
                    onTap: !free
                        ? null
                        : () => setState(() {
                            if (chosen) {
                              selected.remove(label);
                            } else if (widget.requiredRinks == 1) {
                              selected
                                ..clear()
                                ..add(label);
                            } else if (selected.length < widget.requiredRinks) {
                              selected.add(label);
                            }
                          }),
                  ),
                );
              },
            ),
        OutlinedButton.icon(
          onPressed: loading ? null : load,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh availability'),
        ),
        FilledButton(
          onPressed:
              loading ||
                  error != null ||
                  selected.length != widget.requiredRinks
              ? null
              : () => Navigator.pop(
                  context,
                  CompetitionBookingChoice(
                    green: green,
                    start: start,
                    end: end,
                    rinkLabels: selected.toList(),
                    orientation: orientation,
                  ),
                ),
          child: const Text('Use selected rinks'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}
