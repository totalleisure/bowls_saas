import 'package:flutter/material.dart';

class PoolRecruitmentConfirmation extends StatelessWidget {
  const PoolRecruitmentConfirmation({super.key, required this.declinedNames, required this.unavailableNames});
  final List<String> declinedNames;
  final List<String> unavailableNames;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(declinedNames.isNotEmpty ? 'Add previously declined players?' : 'Override Not available?'),
    content: SingleChildScrollView(child: Text([
      if (declinedNames.isNotEmpty) '${declinedNames.join(', ')} previously declined team selection.',
      if (unavailableNames.isNotEmpty) '${unavailableNames.join(', ')} previously answered Not available.',
      'Confirm their availability before adding them back to the pool. This does not put them in the team or mark them as accepted. They will need to respond again if selected.',
    ].join('\n\n'))),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm and add to pool')),
    ],
  );
}
