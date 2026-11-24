import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Available on the authenticated setup welcome page, after email verification.
class OnboardingManualDownloads extends StatefulWidget {
  const OnboardingManualDownloads({super.key, this.savePdf});
  final Future<bool> Function(String fileName, Uint8List bytes)? savePdf;

  @override
  State<OnboardingManualDownloads> createState() => _OnboardingManualDownloadsState();
}

class _OnboardingManualDownloadsState extends State<OnboardingManualDownloads> {
  bool _saving = false;
  String? _message;

  Future<void> _download(String name) async {
    setState(() { _saving = true; _message = null; });
    try {
      final data = await rootBundle.load('assets/manuals/$name.pdf');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      bool saved;
      if (widget.savePdf != null) {
        saved = await widget.savePdf!('$name.pdf', bytes);
      } else {
        final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Save your club guide',
          fileName: '$name.pdf',
          type: FileType.custom,
          allowedExtensions: ['pdf'],
          bytes: bytes,
        );
        saved = path != null;
        if (saved && !kIsWeb) await File(path!).writeAsBytes(bytes, flush: true);
      }
      if (mounted && saved) setState(() => _message = 'Your PDF guide has been saved. You can read it now or return to it later.');
    } catch (_) {
      if (mounted) setState(() => _message = 'The guide could not be saved. Please try again. Your club setup is unchanged.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Your guides to getting started', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      const Text('Download these illustrated PDF guides to keep beside you. You can carry on with setup whenever you are ready.'),
      const SizedBox(height: 10),
      Wrap(spacing: 12, runSpacing: 8, children: [
        OutlinedButton.icon(onPressed: _saving ? null : () => _download('Bringing-your-club-online'), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Bringing your club online')),
        OutlinedButton.icon(onPressed: _saving ? null : () => _download('Your-first-Friendly-Match'), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Your first Friendly Match')),
      ]),
      if (_saving) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
      if (_message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_message!, semanticsLabel: _message)),
    ]),
  );
}
