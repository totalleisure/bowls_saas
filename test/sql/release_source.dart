import 'dart:io';

// Staging keeps production's historical SQL as non-deployable test references.
// Production checks its actual migration files, so source drift remains visible.
String releaseSource(String path) {
  final actual = File(path);
  final reference = File('test/fixtures/release_history/$path');
  return (actual.existsSync() ? actual : reference).readAsStringSync();
}
