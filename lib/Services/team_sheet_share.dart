import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'open_file_helpers.dart';

Future<File> _writePdfToDownloads(Uint8List bytes, {required String filename}) async {
  // On Windows this usually resolves to the user's Downloads folder
  final baseDir = await getDownloadsDirectory()
      ?? await getApplicationDocumentsDirectory();

  final outDir = Directory('${baseDir.path}${Platform.pathSeparator}Bowls Team Sheets');
  if (!await outDir.exists()) {
    await outDir.create(recursive: true);
  }

  final file = File('${outDir.path}${Platform.pathSeparator}$filename');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

/// Returns saved file path.
/// On Windows: opens folder (safe) instead of invoking flaky share sheet.
Future<String> shareTeamSheetPdf(
  Uint8List pdfBytes, {
  required String message,
  String filename = 'team_sheet.pdf',
}) async {
  // Save location depends on platform
  final File file;
  if (Platform.isWindows) {
    file = await _writePdfToDownloads(pdfBytes, filename: filename);
  } else {
    file = await _writeTempPdf(pdfBytes, filename: filename); // <-- use temp on Android/iOS
  }

  final len = await file.length();
  debugPrint('TEAM_SHEET: saved ${file.path} (${len} bytes)');

  if (Platform.isWindows) {
    await revealFileInExplorer(file.path);
    return file.path;
  }

  final xfile = XFile(file.path, mimeType: 'application/pdf', name: filename);

  await SharePlus.instance.share(
    ShareParams(text: message, files: [xfile]),
  );

  return file.path;
}

Future<void> revealFileInExplorer(String filePath) async {
  if (Platform.isWindows) {
    // Note: "/select," must be part of the same argument
    await Process.run('explorer.exe', ['/select,${filePath.replaceAll('/', r'\')}']);
    return;
  }

  if (Platform.isMacOS) {
    await Process.run('open', ['-R', filePath]);
    return;
  }

  if (Platform.isLinux) {
    await Process.run('xdg-open', [File(filePath).parent.path]);
    return;
  }
}

Future<File> _writeTempPdf(Uint8List bytes, {required String filename}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}${Platform.pathSeparator}$filename');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}