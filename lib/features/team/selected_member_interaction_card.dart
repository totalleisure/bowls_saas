import 'package:flutter/material.dart';

const selectedMemberInteractionTileKey = Key('selected-member-card-tile');

class SelectedMemberInteractionCard extends StatelessWidget {
  const SelectedMemberInteractionCard({
    super.key,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final Color color;
  final Widget title;
  final Widget subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        key: selectedMemberInteractionTileKey,
        dense: true,
        visualDensity: VisualDensity.compact,
        title: title,
        subtitle: subtitle,
        trailing: trailing,
      ),
    );
  }
}
