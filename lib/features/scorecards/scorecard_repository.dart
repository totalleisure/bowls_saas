import 'local_scorecard_store.dart';
import 'scorecard.dart';

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
}
