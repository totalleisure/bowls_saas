import 'package:flutter/material.dart';

class FixtureTimingControls extends StatelessWidget {
  const FixtureTimingControls({
    super.key,
    required this.start,
    required this.end,
    this.onEditStart,
    this.onEditEnd,
  });

  final String start;
  final String end;
  final VoidCallback? onEditStart;
  final VoidCallback? onEditEnd;

  Widget _control(String label, String value, VoidCallback? onPressed) {
    final parts = value.split(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label),
        const SizedBox(height: 6),
        OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.all(12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(parts.first),
              if (parts.length > 1)
                Text(parts.skip(1).join(', ').replaceAll(' ', '\u00a0')),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final first = _control('Start', start, onEditStart);
      final last = _control('End', end, onEditEnd);
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      if (size.maxWidth < 600 * scale) {
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
