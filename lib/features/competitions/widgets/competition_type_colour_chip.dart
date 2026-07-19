import 'package:flutter/material.dart';
import '../../../core/utils/hex_color.dart';

class CompetitionTypeColourChip extends StatelessWidget {
  final String text;
  final String? backgroundHex;
  final String? foregroundHex;

  const CompetitionTypeColourChip({
    super.key,
    required this.text,
    required this.backgroundHex,
    required this.foregroundHex,
  });

  @override
  Widget build(BuildContext context) {
    final bg = colorFromHex(backgroundHex, fallback: Colors.grey.shade300);
    final fg = colorFromHex(foregroundHex, fallback: Colors.black87);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(
        text.trim().isEmpty ? 'Example Name' : text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}
