import 'package:flutter/foundation.dart';

/// Only capabilities actually implemented in this app can be enabled remotely.
class FeatureRevisionController extends ChangeNotifier {
  FeatureRevisionController({
    required this.loadRevision,
    this.supportedRevision = 1,
  });
  final Future<int> Function() loadRevision;
  final int supportedRevision;
  int? enabledRevision;
  String? error;
  bool loading = false;
  int _generation = 0;
  bool _disposed = false;

  bool allows(int requiredRevision) =>
      requiredRevision == 0 ||
      (requiredRevision > 0 &&
          requiredRevision <= supportedRevision &&
          enabledRevision != null &&
          enabledRevision! >= requiredRevision);

  void clear() {
    _generation++;
    enabledRevision = null;
    loading = false;
    error = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    final generation = ++_generation;
    enabledRevision = null;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final value = await loadRevision();
      if (_disposed || generation != _generation) return;
      if (value < 0) throw StateError('Invalid revision');
      enabledRevision = value;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      error = 'Could not check feature availability. Please refresh.';
    }
    if (_disposed || generation != _generation) return;
    loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
