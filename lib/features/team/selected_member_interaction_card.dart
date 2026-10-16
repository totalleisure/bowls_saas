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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
          if (constraints.maxWidth < 600 * scale) {
            return Padding(
              key: selectedMemberInteractionTileKey,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  title,
                  const SizedBox(height: 6),
                  subtitle,
                  if (trailing != null) ...[
                    const SizedBox(height: 8),
                    trailing!,
                  ],
                ],
              ),
            );
          }
          return ListTile(
            key: selectedMemberInteractionTileKey,
            dense: true,
            visualDensity: VisualDensity.compact,
            title: title,
            subtitle: subtitle,
            trailing: trailing,
          );
        },
      ),
    );
  }
}
