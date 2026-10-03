import 'package:flutter/material.dart';

class ActionPill extends StatelessWidget {
  const ActionPill({
    super.key,
    required this.label,
    required this.onPressed,
    this.tone = ActionPillTone.purple,
  });

  final String label;
  final VoidCallback? onPressed;
  final ActionPillTone tone;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final background = switch (tone) {
      ActionPillTone.green => Colors.green.shade100,
      ActionPillTone.purple => Colors.deepPurple.shade100,
    };
    final foreground = switch (tone) {
      ActionPillTone.green => Colors.green.shade900,
      ActionPillTone.purple => Colors.deepPurple.shade900,
    };

    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: enabled ? foreground : Colors.grey.shade600,
        backgroundColor: enabled ? background : Colors.grey.shade200,
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }
}

enum ActionPillTone { green, purple }
