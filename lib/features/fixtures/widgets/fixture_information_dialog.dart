import 'package:flutter/material.dart';

class FixtureInformationDialog extends StatefulWidget {
  const FixtureInformationDialog({
    super.key,
    required this.initialText,
    required this.isEvent,
  });

  final String initialText;
  final bool isEvent;

  @override
  State<FixtureInformationDialog> createState() =>
      _FixtureInformationDialogState();
}

class _FixtureInformationDialogState extends State<FixtureInformationDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    // showDialog completes before its closing animation finishes. Keep the
    // controller alive until the text field itself leaves the widget tree.
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.isEvent ? 'Edit event information' : 'Edit special instructions',
      ),
      content: SizedBox(
        width: 560,
        child: TextField(
          controller: _controller,
          autofocus: true,
          minLines: 5,
          maxLines: 12,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 5000,
          decoration: InputDecoration(
            labelText: widget.isEvent
                ? 'Event information'
                : 'Special instructions',
            hintText:
                'Add details, instructions, timings or other information for members.',
            alignLabelWithHint: true,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _controller.text),
          icon: const Icon(Icons.save),
          label: const Text('Save'),
        ),
      ],
    );
  }
}
