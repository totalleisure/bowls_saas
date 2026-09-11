import 'package:flutter/material.dart';

/// Null means cancelled; false and true are the selected initial active status.
Future<bool?> showMemberImportOptions({
  required BuildContext context,
  required String fileName,
  required int bytes,
}) => showDialog<bool>(
  context: context,
  builder: (_) => _MemberImportOptionsDialog(fileName: fileName, bytes: bytes),
);

class _MemberImportOptionsDialog extends StatefulWidget {
  const _MemberImportOptionsDialog({
    required this.fileName,
    required this.bytes,
  });
  final String fileName;
  final int bytes;

  @override
  State<_MemberImportOptionsDialog> createState() =>
      _MemberImportOptionsDialogState();
}

class _MemberImportOptionsDialogState
    extends State<_MemberImportOptionsDialog> {
  bool _active = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Import members from CSV?'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('File: ${widget.fileName}\nSize: ${widget.bytes} bytes'),
          const SizedBox(height: 16),
          const Text('Should new memberships start Inactive or Active?'),
          const SizedBox(height: 8),
          DropdownButtonFormField<bool>(
            initialValue: _active,
            decoration: const InputDecoration(
              labelText: 'Starting status',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: false, child: Text('Inactive')),
              DropdownMenuItem(value: true, child: Text('Active')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _active = value);
            },
          ),
          const SizedBox(height: 16),
          const Text(
            'New memberships receive the Member role. Existing memberships keep their role and active status.\n\nNew accounts require a password in the CSV. No invitation emails will be sent.',
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _active),
        child: const Text('Import'),
      ),
    ],
  );
}
