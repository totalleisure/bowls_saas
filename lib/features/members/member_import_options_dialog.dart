import 'package:flutter/material.dart';

class MemberImportOptions {
  const MemberImportOptions({
    required this.importMembers,
    required this.newMembersActive,
    required this.sendInvitations,
  });
  final bool importMembers;
  final bool newMembersActive;
  final bool sendInvitations;
}

Future<MemberImportOptions?> showMemberImportOptions({
  required BuildContext context,
  required String fileName,
  required int bytes,
}) => showDialog<MemberImportOptions>(
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
  bool _import = true;
  bool _active = false;
  bool _invite = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Import and invitations'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('File: ${widget.fileName}\nSize: ${widget.bytes} bytes'),
            const SizedBox(height: 16),
            DropdownButtonFormField<bool>(
              key: const Key('import-choice'),
              initialValue: _import,
              decoration: const InputDecoration(
                labelText: 'Import members from this CSV?',
              ),
              items: const [
                DropdownMenuItem(
                  value: true,
                  child: Text('Yes — import members'),
                ),
                DropdownMenuItem(
                  value: false,
                  child: Text('No — existing members only'),
                ),
              ],
              onChanged: (v) => setState(() => _import = v ?? true),
            ),
            if (_import) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<bool>(
                key: const Key('active-choice'),
                initialValue: _active,
                decoration: const InputDecoration(
                  labelText: 'New memberships start',
                ),
                items: const [
                  DropdownMenuItem(value: false, child: Text('Inactive')),
                  DropdownMenuItem(value: true, child: Text('Active')),
                ],
                onChanged: (v) => setState(() => _active = v ?? false),
              ),
              const SizedBox(height: 12),
              const Text(
                'New memberships receive the Member role. Existing memberships keep their role and active status. New accounts require a password in the CSV.',
              ),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<bool>(
              key: const Key('invite-choice'),
              initialValue: _invite,
              decoration: const InputDecoration(
                labelText: 'Send invitation emails?',
              ),
              items: const [
                DropdownMenuItem(
                  value: false,
                  child: Text('No invitation emails'),
                ),
                DropdownMenuItem(
                  value: true,
                  child: Text('Yes — review invitations'),
                ),
              ],
              onChanged: (v) => setState(() => _invite = v ?? false),
            ),
            if (_invite) ...[
              const SizedBox(height: 12),
              const Text(
                'You will review recipients, the personalised email and both PDF guides before sending. Inactive members must be activated before they can be invited.',
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: !_import && !_invite
            ? null
            : () => Navigator.pop(
                context,
                MemberImportOptions(
                  importMembers: _import,
                  newMembersActive: _active,
                  sendInvitations: _invite,
                ),
              ),
        child: Text(_import ? 'Import' : 'Review invitations'),
      ),
    ],
  );
}
