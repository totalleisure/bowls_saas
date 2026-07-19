import 'dart:io';

Future<void> openContainingFolder(String filePath) async {
  if (Platform.isWindows) {
    // Opens Explorer and selects the file
    await Process.run('explorer.exe', ['/select,', filePath]);
  } else if (Platform.isMacOS) {
    await Process.run('open', ['-R', filePath]);
  } else if (Platform.isLinux) {
    // Best-effort (may vary by distro)
    await Process.run('xdg-open', [File(filePath).parent.path]);
  }
}
