import 'package:flutter/material.dart';

/// A venue sheet heading with actions that retain their natural width.
class VenuePickerHeader extends StatelessWidget {
  const VenuePickerHeader({
    super.key,
    required this.title,
    required this.actions,
  });

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final heading = Text(
        title,
        style: Theme.of(context).textTheme.titleLarge,
      );
      if (actions.isEmpty) return heading;
      final actionWrap = Wrap(spacing: 8, children: actions);
      if (constraints.maxWidth < 600) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [heading, actionWrap],
        );
      }
      return Row(
        children: [
          Expanded(child: heading),
          Flexible(child: actionWrap),
        ],
      );
    },
  );
}
