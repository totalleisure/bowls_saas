import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

const maxMailAttachmentBytes = 2 * 1024 * 1024;
const maxMailAttachments = 10;

class MailAttachment {
  final String name;
  final Uint8List bytes;
  MailAttachment(this.name, this.bytes);
  Map<String, String> toJson() => {
    'name': name,
    'contentType': 'application/octet-stream',
    'contentBytes': base64Encode(bytes),
  };
}

Future<List<MailAttachment>> readMailAttachments(
  List<PlatformFile> files,
  List<MailAttachment> existing,
) async {
  if (existing.length + files.length > maxMailAttachments) {
    throw const FormatException('You can attach up to 10 files.');
  }
  var total = existing.fold<int>(0, (sum, item) => sum + item.bytes.length);
  final names = existing.map((e) => e.name.toLowerCase()).toSet();
  final added = <MailAttachment>[];
  for (final file in files) {
    final name = file.name.trim();
    if (name.isEmpty ||
        name.length > 255 ||
        RegExp(r'[\x00-\x1f\x7f/\\]').hasMatch(name)) {
      throw const FormatException(
        'Please choose a file with a valid filename.',
      );
    }
    if (!names.add(name.toLowerCase())) {
      throw FormatException(
        '$name is already attached. Rename it to attach another file with the same name.',
      );
    }
    if (total + file.size > maxMailAttachmentBytes) {
      throw const FormatException('Attachments must total 2 MB or less.');
    }
    final builder = BytesBuilder(copy: false);
    if (file.bytes != null) {
      builder.add(file.bytes!);
    } else if (file.readStream != null) {
      await for (final chunk in file.readStream!) {
        if (total + builder.length + chunk.length > maxMailAttachmentBytes) {
          throw const FormatException('Attachments must total 2 MB or less.');
        }
        builder.add(chunk);
      }
    } else {
      throw FormatException('Could not read $name. Please choose it again.');
    }
    final bytes = builder.takeBytes();
    total += bytes.length;
    if (total > maxMailAttachmentBytes) {
      throw const FormatException('Attachments must total 2 MB or less.');
    }
    if (bytes.isEmpty) throw FormatException('$name is empty.');
    added.add(MailAttachment(name, bytes));
  }
  return [...existing, ...added];
}

class MailAttachmentsField extends StatefulWidget {
  final List<MailAttachment> attachments;
  final bool enabled;
  final ValueChanged<List<MailAttachment>> onChanged;
  final ValueChanged<bool> onBusy;
  const MailAttachmentsField({
    super.key,
    required this.attachments,
    required this.enabled,
    required this.onChanged,
    required this.onBusy,
  });
  @override
  State<MailAttachmentsField> createState() => _MailAttachmentsFieldState();
}

class _MailAttachmentsFieldState extends State<MailAttachmentsField> {
  bool _busy = false;
  String? _error;
  Future<void> _pick() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    widget.onBusy(true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
        withReadStream: true,
      );
      if (result == null || !mounted) return;
      final items = await readMailAttachments(result.files, widget.attachments);
      if (mounted) widget.onChanged(items);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is FormatException
              ? e.message
              : 'Could not read the selected files. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onBusy(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Email attachments',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Text(
            'Up to 10 files, 2 MB total. Sent with email only; not included in app notifications.',
          ),
          for (final item in widget.attachments)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.attach_file),
              title: Text(item.name),
              subtitle: Text(
                '${(item.bytes.length / 1024).toStringAsFixed(1)} KB',
              ),
              trailing: IconButton(
                tooltip: 'Remove ${item.name}',
                onPressed: widget.enabled && !_busy
                    ? () => widget.onChanged(
                        widget.attachments.where((a) => a != item).toList(),
                      )
                    : null,
                icon: const Icon(Icons.close),
              ),
            ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          TextButton.icon(
            onPressed: widget.enabled && !_busy ? _pick : null,
            icon: const Icon(Icons.attach_file),
            label: Text(_busy ? 'Reading files...' : 'Add attachments'),
          ),
        ],
      ),
    ),
  );
}
