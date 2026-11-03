import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Alternating, flushed generations retain the last good save if writing fails.
class LocalScorecardStore {
  LocalScorecardStore({this.directory});
  final Directory? directory;
  String? readWarning;
  Future<Directory> _dir() async {
    final d =
        directory ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}/electronic_scorecards',
        );
    await d.create(recursive: true);
    return d;
  }

  Future<Map<String, dynamic>?> _read() async {
    final d = await _dir();
    final candidates = <Map<String, dynamic>>[];
    bool exists = false;
    var unreadable = false;
    readWarning = null;
    for (final slot in [0, 1]) {
      final f = File('${d.path}/cards-$slot.json');
      if (!await f.exists()) continue;
      exists = true;
      try {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        if (j['generation'] is int && j['cards'] is List) {
          candidates.add(j);
        } else {
          unreadable = true;
        }
      } catch (_) {
        unreadable = true;
        /* Try the other complete generation. */
      }
    }
    if (exists && candidates.isEmpty) {
      throw const FormatException(
        'Local scorecard files could not be read. Your files have been preserved; do not create replacement cards until recovered.',
      );
    }
    candidates.sort(
      (a, b) => (b['generation'] as int).compareTo(a['generation'] as int),
    );
    if (unreadable && candidates.isNotEmpty) {
      readWarning =
          'Recovered a previous local save after an unreadable file. Check the most recent end before continuing.';
    }
    return candidates.isEmpty ? null : candidates.first;
  }

  Future<List<dynamic>> read() async =>
      (await _read())?['cards'] as List? ?? [];
  Future<void> write(List<dynamic> cards) async {
    final current = await _read();
    final generation = (current?['generation'] as int? ?? 0) + 1;
    final d = await _dir();
    final target = File('${d.path}/cards-${generation % 2}.json');
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(
      jsonEncode({'generation': generation, 'cards': cards}),
      flush: true,
    );
    // Only the older slot is replaced; the latest committed generation stays intact.
    if (await target.exists()) await target.delete();
    await temp.rename(target.path);
  }
}
