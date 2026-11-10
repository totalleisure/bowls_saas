import 'package:flutter/material.dart';
import 'scorecard.dart';

Color _sideTint(
  BuildContext context,
  bool home, {
  bool heading = false,
  bool selected = false,
}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final opacity = selected
      ? (dark ? .27 : .15)
      : heading
      ? (dark ? .21 : .10)
      : (dark ? .12 : .045);
  return Color.alphaBlend(
    (home ? Colors.red : Colors.blue).withValues(alpha: opacity),
    Theme.of(context).colorScheme.surface,
  );
}

class ScorecardTeamNames extends StatelessWidget {
  const ScorecardTeamNames({super.key, required this.card});
  final Scorecard card;
  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final home in [true, false])
          Expanded(
            child: Card(
              color: _sideTint(context, home, heading: true),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: (home ? Colors.red : Colors.blue).withValues(
                    alpha: .28,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Center(
                  child: Text(
                    home ? card.sideA : card.sideB,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Familiar paper-card order: shots, total, end, shots, total.
class ScorecardTable extends StatelessWidget {
  const ScorecardTable({
    super.key,
    required this.card,
    this.selectedEnd,
    this.onSelect,
    this.showHeader = true,
  });
  final Scorecard card;
  final bool showHeader;
  final int? selectedEnd;
  final ValueChanged<int>? onSelect;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = theme.colorScheme.outline;
    Widget cell(String text, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          fontSize: 16,
        ),
      ),
    );
    TableRow row(List<String> values, {int? end, bool heading = false}) =>
        TableRow(
          children: [
            for (var i = 0; i < values.length; i++)
              InkWell(
                key: end == null ? null : ValueKey('scorecard-row-$end-$i'),
                onTap: end == null || onSelect == null
                    ? null
                    : () => onSelect!(end),
                child: ColoredBox(
                  color: i == 2
                      ? (end != null && end == selectedEnd
                            ? (end + 1 == card.maxEnds
                                  ? theme.colorScheme.tertiaryContainer
                                  : theme.colorScheme.primaryContainer)
                            : theme.colorScheme.surface)
                      : _sideTint(
                          context,
                          i < 2,
                          selected: end != null && end == selectedEnd,
                        ),
                  child: cell(values[i], bold: heading || end == selectedEnd),
                ),
              ),
          ],
        );
    int a = card.handicapA, b = card.handicapB;
    final rows = <TableRow>[
      row(['${card.handicapA}', '$a', '0', '${card.handicapB}', '$b']),
    ];
    for (var i = 0; i < card.ends.length; i++) {
      final e = card.ends[i];
      a += e['a'] as int? ?? 0;
      b += e['b'] as int? ?? 0;
      String shots(dynamic n) => n == null
          ? '…'
          : n == 0
          ? '–'
          : '$n';
      rows.add(
        row([shots(e['a']), '$a', '${i + 1}', shots(e['b']), '$b'], end: i),
      );
    }
    // A blank next row is a placeholder, not a declaration that a jack was delivered.
    if (!card.complete &&
        !card.endInProgress &&
        card.startedAt != null &&
        card.cannotStartEnd(DateTime.now().toUtc()) == null) {
      rows.add(row(['', '', '${card.ends.length + 1}', '', '']));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader) ScorecardTableHeader(card: card),
        Table(
          border: TableBorder.all(color: border),
          columnWidths: const {
            0: FlexColumnWidth(),
            1: FlexColumnWidth(),
            2: FixedColumnWidth(48),
            3: FlexColumnWidth(),
            4: FlexColumnWidth(),
          },
          children: rows,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            onSelect == null
                ? 'End 0 shows starting handicaps.'
                : 'End 0 shows starting handicaps. Tap a played end to correct it.',
          ),
        ),
      ],
    );
  }
}

class ScorecardTableHeader extends StatelessWidget {
  const ScorecardTableHeader({
    super.key,
    required this.card,
    this.showClubNames = true,
  });
  final Scorecard card;
  final bool showClubNames;
  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;
    Widget text(String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showClubNames) ScorecardTeamNames(card: card),
        Table(
          key: const ValueKey('scorecard-fixed-column-header'),
          border: TableBorder.all(color: colours.outline),
          columnWidths: const {
            0: FlexColumnWidth(),
            1: FlexColumnWidth(),
            2: FixedColumnWidth(48),
            3: FlexColumnWidth(),
            4: FlexColumnWidth(),
          },
          children: [
            TableRow(
              decoration: BoxDecoration(color: colours.surfaceContainerHighest),
              children: [
                for (final entry in [
                  'Shots',
                  'Total',
                  'End',
                  'Shots',
                  'Total',
                ].asMap().entries)
                  ColoredBox(
                    color: entry.key == 2
                        ? colours.surfaceContainerHighest
                        : _sideTint(context, entry.key < 2, heading: true),
                    child: text(entry.value),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class EndScoreControls extends StatelessWidget {
  const EndScoreControls({
    super.key,
    required this.card,
    required this.end,
    required this.a,
    required this.b,
    required this.enabled,
    required this.onChanged,
    required this.onAccept,
    this.onCancel,
  });
  final Scorecard card;
  final int end, a, b;
  final bool enabled;
  final void Function(int, int) onChanged;
  final VoidCallback onAccept;
  final VoidCallback? onCancel;
  @override
  Widget build(BuildContext context) {
    Widget counter(String name, int value, bool home) => Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Subtract shot for $name',
                onPressed: !enabled || value == 0
                    ? null
                    : () =>
                          onChanged(home ? value - 1 : a, home ? b : value - 1),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Expanded(
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              IconButton(
                tooltip: 'Add shot for $name',
                onPressed: !enabled
                    ? null
                    : () => onChanged(
                        home
                            ? value + 1
                            : card.scoring == 'shots'
                            ? 0
                            : a,
                        home ? (card.scoring == 'shots' ? 0 : b) : value + 1,
                      ),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ],
      ),
    );
    final valid = card.scoring == '100up' ? a + b == 10 : !(a > 0 && b > 0);
    return Column(
      children: [
        ScorecardTeamNames(card: card),
        Card(
          key: const ValueKey('score-entry-card'),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outline,
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    key: const ValueKey('score-end-pill'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      color: end == card.maxEnds
                          ? Theme.of(context).colorScheme.tertiaryContainer
                          : Theme.of(context).colorScheme.primaryContainer,
                    ),
                    child: Text(
                      '${onCancel != null ? "Correct" : "Score"} end $end${end == card.maxEnds ? " · LAST END" : ""}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (card.scoring == '100up')
                  HundredUpScoreControls(
                    key: ValueKey('${card.id}:$end:${onCancel != null}'),
                    card: card,
                    a: a,
                    b: b,
                    enabled: enabled,
                    onChanged: onChanged,
                    onAccept: onAccept,
                    acceptLabel: onCancel != null
                        ? 'Save correction'
                        : 'Accept end $end',
                  )
                else ...[
                  Row(
                    children: [
                      counter(card.sideA, a, true),
                      const SizedBox(width: 8),
                      counter(card.sideB, b, false),
                    ],
                  ),
                  FilledButton(
                    onPressed: enabled && valid ? onAccept : null,
                    child: Text(
                      onCancel != null ? 'Save correction' : 'Accept end $end',
                    ),
                  ),
                ],
                if (onCancel != null)
                  TextButton(
                    onPressed: enabled ? onCancel : null,
                    child: const Text('Cancel correction'),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Each value is awarded once. Saved cards retain totals, not individual
/// awards, so corrections require an explicit fresh allocation rather than
/// guessing which values produced an existing total (5 can be 4+1 or 3+2).
class HundredUpScoreControls extends StatefulWidget {
  const HundredUpScoreControls({
    super.key,
    required this.card,
    required this.a,
    required this.b,
    required this.enabled,
    required this.onChanged,
    required this.onAccept,
    required this.acceptLabel,
  });

  final Scorecard card;
  final int a, b;
  final bool enabled;
  final void Function(int, int) onChanged;
  final VoidCallback onAccept;
  final String acceptLabel;

  @override
  State<HundredUpScoreControls> createState() => _HundredUpScoreControlsState();
}

class _HundredUpScoreControlsState extends State<HundredUpScoreControls> {
  final Map<int, bool> awards = {};

  void toggle(int value, bool sideA) {
    setState(() {
      if (awards[value] == sideA) {
        awards.remove(value);
      } else {
        awards[value] = sideA;
      }
    });
    int total(bool side) => awards.entries
        .where((entry) => entry.value == side)
        .fold(0, (sum, entry) => sum + entry.key);
    widget.onChanged(total(true), total(false));
  }

  Widget side(bool sideA) {
    final name = sideA ? widget.card.sideA : widget.card.sideB;
    return Expanded(
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final value in [4, 3, 2, 1])
            if (awards.containsKey(value) && awards[value] != sideA)
              const SizedBox(width: 48, height: 48)
            else
              SizedBox(
                width: 48,
                height: 48,
                child: Semantics(
                  selected: awards[value] == sideA,
                  child: Tooltip(
                    message:
                        '${awards[value] == sideA ? 'Release' : 'Award'} $value points ${awards[value] == sideA ? 'from' : 'to'} $name',
                    child: OutlinedButton(
                      key: ValueKey('100up-${sideA ? 'a' : 'b'}-$value'),
                      onPressed: widget.enabled
                          ? () => toggle(value, sideA)
                          : null,
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor: _sideTint(
                          context,
                          sideA,
                          selected: awards[value] == sideA,
                        ),
                        side: BorderSide(
                          color: awards[value] == sideA
                              ? (sideA ? Colors.red : Colors.blue)
                              : Theme.of(context).colorScheme.outline,
                          width: awards[value] == sideA ? 3 : 1,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        '$value',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Assign 4, 3, 2 and 1 once each. Tap a selected value to release it.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [side(true), const SizedBox(width: 8), side(false)],
      ),
      const SizedBox(height: 8),
      Text(
        '100 Up: ${widget.a} + ${widget.b} = ${widget.a + widget.b} / 10 points · ${awards.length}/4 assigned',
        textAlign: TextAlign.center,
      ),
      FilledButton(
        onPressed: widget.enabled && awards.length == 4
            ? widget.onAccept
            : null,
        child: Text(widget.acceptLabel),
      ),
    ],
  );
}
