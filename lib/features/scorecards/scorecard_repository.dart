import 'local_scorecard_store.dart';
import 'scorecard.dart';
import 'shared_scorecard_api.dart';

class ScorecardRepository {
  ScorecardRepository({LocalScorecardStore? store})
    : _store = store ?? LocalScorecardStore();
  static final instance = ScorecardRepository();
  final LocalScorecardStore _store;
  String? get recoveryNotice => _store.readWarning;
  Future<void> _tail = Future.value();
  Future<List<Scorecard>> load() async {
    await _tail;
    return (await _store.read())
        .map((j) => Scorecard.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList();
  }

  Future<void> save(Scorecard card) {
    final result = _tail.then((_) async {
      final cards = (await _store.read())
          .map((j) => Map<String, dynamic>.from(j as Map))
          .toList();
      final index = cards.indexWhere((j) => j['id'] == card.id);
      if (index >= 0 &&
          (cards[index]['fixtureLink'] as Map?)?['sharedConfirmed'] == true &&
          !card.resultConfirmed) {
        throw StateError(
          'Admin confirmed this result. Reopen the saved card to view it.',
        );
      }
      if (index >= 0 &&
          (cards[index]['saveVersion'] as int? ?? 0) != card.saveVersion) {
        throw StateError(
          'This card was saved from another open screen. Reopen the latest saved card before editing.',
        );
      }
      final saved = card.toJson()..['saveVersion'] = card.saveVersion + 1;
      if (index < 0) {
        cards.insert(0, saved);
      } else {
        cards[index] = saved;
      }
      await _store.write(cards);
      card.saveVersion++;
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// Cache signature evidence only against the matching uploaded local revision.
  Future<void> rememberSignatures(Map<String, dynamic> shared) {
    if (shared['id'] == null || shared['document'] is! Map)
      return Future.value();
    final result = _tail.then((_) async {
      final rows = (await _store.read())
          .map((j) => Map<String, dynamic>.from(j as Map))
          .toList();
      final document = shared['document'] as Map;
      for (final row in rows) {
        if ((row['fixtureLink'] as Map?)?['sharedCardId'] != shared['id'])
          continue;
        // Never attach signatures to unsynchronised local corrections.
        if (row['revision'] != document['revision'] ||
            row['finishedAt'] != document['finishedAt'] ||
            row['saveVersion'] != shared['sequence'])
          continue;
        row['signatureA'] = document['signatureA'];
        row['signatureB'] = document['signatureB'];
      }
      await _store.write(rows);
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// Cache server confirmation without changing scores or the upload sequence.
  Future<void> rememberConfirmation(Map<String, dynamic> shared) {
    final metadata = SharedScorecardApi.confirmationMetadata(shared);
    if (metadata.isEmpty || shared['id'] == null) return Future.value();
    final result = _tail.then((_) async {
      final rows = (await _store.read())
          .map((j) => Map<String, dynamic>.from(j as Map))
          .toList();
      var changed = false;
      for (final row in rows) {
        final link = Map<String, dynamic>.from(
          row['fixtureLink'] as Map? ?? {},
        );
        if (link['sharedCardId'] != shared['id']) continue;
        if (metadata.entries.every((e) => link[e.key] == e.value)) continue;
        row['fixtureLink'] = {...link, ...metadata};
        changed = true;
      }
      if (changed) await _store.write(rows);
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
