import 'package:flutter/material.dart';

/// Edits reserved capacity; assigning/unassigning a physical rink is separate.
class OpenFixtureRinksDialog extends StatefulWidget {
  final int initialRequired;
  final int assigned;
  final int maximum;
  final Future<void> Function(int required) onSave;

  const OpenFixtureRinksDialog({
    super.key,
    required this.initialRequired,
    required this.assigned,
    required this.maximum,
    required this.onSave,
  });

  @override
  State<OpenFixtureRinksDialog> createState() => _OpenFixtureRinksDialogState();
}

class _OpenFixtureRinksDialogState extends State<OpenFixtureRinksDialog> {
  late int _required = widget.initialRequired;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_required);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final minimum = widget.assigned > 1 ? widget.assigned : 1;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('Rinks required'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Number of rinks reserved for this Open fixture.'),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Reduce rinks required',
                    onPressed: !_saving && _required > minimum
                        ? () => setState(() => _required--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text(
                    '$_required',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  IconButton(
                    tooltip: 'Increase rinks required',
                    onPressed: !_saving && _required < widget.maximum
                        ? () => setState(() => _required++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              Text('${widget.assigned} physically assigned'),
              Text('${_required - widget.assigned} awaiting assignment'),
              const SizedBox(height: 12),
              const Text(
                'To reduce below the assigned number, close this box and long-press a rink to unassign it first. Unassigning keeps the number required unchanged.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _saving || _required == widget.initialRequired
                ? null
                : _save,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }
}
