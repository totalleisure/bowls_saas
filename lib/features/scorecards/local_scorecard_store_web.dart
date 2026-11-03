import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalScorecardStore {
  String? get readWarning => null;
  Future<List<dynamic>> read() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('standalone_scorecards_v1');
    return raw == null ? [] : jsonDecode(raw) as List;
  }

  Future<void> write(List<dynamic> cards) async {
    final p = await SharedPreferences.getInstance();
    if (!await p.setString('standalone_scorecards_v1', jsonEncode(cards))) {
      throw StateError('Unable to save scorecards in this browser.');
    }
  }
}
