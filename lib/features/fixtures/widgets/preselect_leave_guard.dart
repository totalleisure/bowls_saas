import 'package:flutter/material.dart';

class PreselectLeaveGuard extends StatefulWidget {
  const PreselectLeaveGuard({super.key, required this.hasChanges,
    required this.saving, required this.child});
  final bool hasChanges;
  final bool saving;
  final Widget child;
  @override
  State<PreselectLeaveGuard> createState() => _PreselectLeaveGuardState();
}

class _PreselectLeaveGuardState extends State<PreselectLeaveGuard> {
  bool _allowLeave = false;
  bool _asking = false;

  Future<void> _requestLeave(Object? result) async {
    if (_asking || widget.saving || !widget.hasChanges) return;
    _asking = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard selection changes?'),
        content: const Text('Your player, opponent and marker changes have not been saved. '
            'Leaving now will discard them.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep editing')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Discard changes')),
        ],
      ),
    );
    _asking = false;
    if (!mounted || discard != true) return;
    setState(() => _allowLeave = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: !widget.saving && (_allowLeave || !widget.hasChanges),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _requestLeave(result);
    },
    child: widget.child,
  );
}
