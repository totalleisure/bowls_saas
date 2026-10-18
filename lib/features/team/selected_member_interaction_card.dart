import 'package:flutter/material.dart';

const selectedMemberInteractionTileKey = Key('selected-member-card-tile');

class SelectedMemberInteractionCard extends StatelessWidget {
  const SelectedMemberInteractionCard({super.key, required this.color,
    required this.title, required this.subtitle, required this.trailing});
  final Color color;
  final Widget title;
  final Widget subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Card(
    color: color, margin: const EdgeInsets.symmetric(vertical: 4),
    child: Padding(key: selectedMemberInteractionTileKey,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          title, const SizedBox(height: 4), subtitle,
        ])),
        if (trailing != null) SizedBox(width: 48, child: trailing),
      ])),
  );
}
