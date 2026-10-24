import 'dart:math' as math;
import 'package:flutter/material.dart';

class FixtureTimingControls extends StatelessWidget {
  const FixtureTimingControls({
    super.key,
    required this.start,
    required this.end,
    this.onEditStart,
    this.onEditEnd,
  });
  final String start, end;
  final VoidCallback? onEditStart, onEditEnd;

  List<String> _lines(String value) {
    final parts = value.split(', ');
    return [
      parts.first,
      if (parts.length > 1) parts.skip(1).join(', ').replaceAll(' ', '\u00a0'),
    ];
  }

  Widget _control(
    String label,
    String value,
    VoidCallback? onPressed,
    TextStyle style,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label),
      const SizedBox(height: 6),
      OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.all(12),
          textStyle: style,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in _lines(value)) Text(line, style: style),
          ],
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final style = Theme.of(
        context,
      ).textTheme.labelLarge!.copyWith(fontWeight: FontWeight.bold);
      double requiredWidth(String value) {
        double width = 0;
        for (final line in _lines(value)) {
          final painter = TextPainter(
            text: TextSpan(text: line, style: style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          width = math.max(width, painter.width);
          painter.dispose();
        }
        return math.max(48, width.ceilToDouble() + 26);
      }

      final first = _control('Start', start, onEditStart, style);
      final last = _control('End', end, onEditEnd, style);
      if ((size.maxWidth - 12) / 2 <
          math.max(requiredWidth(start), requiredWidth(end))) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [first, const SizedBox(height: 12), last],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          const SizedBox(width: 12),
          Expanded(child: last),
        ],
      );
    },
  );
}
