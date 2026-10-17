import 'package:flutter/material.dart';

class PublicationInstructionsDialog extends StatefulWidget {
  const PublicationInstructionsDialog({
    super.key,
    required this.initialInstructions,
    this.onSave,
    this.published = false,
    this.readOnly = false,
  });
  final String initialInstructions;
  final Future<void> Function(String notes, bool sendUpdate)? onSave;
  final bool published;
  final bool readOnly;
  @override
  State<PublicationInstructionsDialog> createState() =>
      _PublicationInstructionsDialogState();
}

class _PublicationInstructionsDialogState
    extends State<PublicationInstructionsDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialInstructions,
  );
  bool _busy = false;
  String? _error;
  Future<void> _submit(bool send) async {
    if (_busy) return;
    final notes = _controller.text.trim();
    if (widget.onSave == null) {
      Navigator.pop(context, notes);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave!(notes, send);
      if (mounted) Navigator.pop(context, notes);
    } catch (e) {
      if (mounted)
        setState(() {
          _busy = false;
          _error = 'Could not save instructions: $e';
        });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Special instructions'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.readOnly) ...[
                Text(
                  widget.onSave == null
                      ? 'Any instructions for the team? These will be included in the team-sheet email and match reminder. Leave blank if none are needed.'
                      : widget.published
                      ? 'Save changes without sending, or choose Send Update to save and email the current players, reserves, captain and vice-captain. Clearing the text sends a notice that the instructions have been removed.'
                      : 'Save instructions for the match reminder and the email sent when the team is published. Saving does not send an email.',
                ),
                const SizedBox(height: 12),
              ],
              if (widget.readOnly)
                SelectableText(
                  widget.initialInstructions.trim().isEmpty
                      ? 'No special instructions have been added.'
                      : widget.initialInstructions,
                )
              else
                TextField(
                  controller: _controller,
                  enabled: !_busy,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: 5000,
                  decoration: const InputDecoration(
                    labelText: 'Special instructions',
                    hintText: 'Arrival time, dress code or travel arrangements',
                    border: OutlineInputBorder(),
                  ),
                ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(widget.readOnly ? 'Close' : 'Cancel'),
        ),
        if (!widget.readOnly) ...[
          if (widget.onSave != null && widget.published)
            OutlinedButton(
              onPressed: _busy ? null : () => _submit(false),
              child: const Text('Save'),
            ),
          FilledButton(
            onPressed: _busy ? null : () => _submit(widget.published),
            child: Text(
              widget.onSave == null
                  ? 'Continue to publish'
                  : widget.published
                  ? 'Send Update'
                  : 'Save',
            ),
          ),
        ],
      ],
    ),
  );
}
