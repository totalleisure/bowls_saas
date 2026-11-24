import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ClubOnboardingProgress {
  const ClubOnboardingProgress({this.step = 0, this.reviewed = false});
  final int step;
  final bool reviewed;

  static String key(String account, String club) =>
      'club_setup_v1_${Uri.encodeComponent(account)}_${Uri.encodeComponent(club)}';

  static Future<ClubOnboardingProgress> load(
    String account,
    String club,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key(account, club));
    if (raw == null) return const ClubOnboardingProgress();
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final step = data['step'];
      return ClubOnboardingProgress(
        step: step is int && step >= 0 && step < 10 ? step : 0,
        reviewed: data['reviewed'] == true,
      );
    } catch (_) {
      return const ClubOnboardingProgress();
    }
  }

  Future<void> save(String account, String club) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      key(account, club),
      jsonEncode({'step': step, 'reviewed': reviewed}),
    )) {
      throw StateError('Progress could not be saved.');
    }
  }
}

class ClubSetupSnapshot {
  const ClubSetupSnapshot({
    required this.clubName,
    required this.homeVenues,
    required this.greens,
    required this.hoursReady,
    required this.fixtureTypes,
    required this.members,
    required this.teams,
  });
  final String clubName;
  final int homeVenues, greens, fixtureTypes, members, teams;
  final bool hoursReady;
  bool get essentialsReady =>
      homeVenues > 0 && greens > 0 && hoursReady && fixtureTypes > 0;
}
