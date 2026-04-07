import 'package:intl/intl.dart';

// lib/core/fixtures/fixture_display.dart

String _s(dynamic v) => (v?.toString() ?? '').trim();

String _mapName(dynamic maybeMap) {
  if (maybeMap is Map) return _s(maybeMap['name']);
  return '';
}

String _greenName(dynamic greenAreas) {
  // Depending on select, green_areas can arrive as a List or Map
  if (greenAreas is List && greenAreas.isNotEmpty) {
    final first = greenAreas.first;
    if (first is Map) return _s(first['name']);
  }
  if (greenAreas is Map) return _s(greenAreas['name']);
  return '';
}

/// Title rules (using your venue_id/opponent_venue_id model):
/// HOME fixtures (is_home=true):
///   venue = my club (location), opponent_venue = opponent
///   HOME — {Team if present} on {Green} vs {opponent_venue.name}
///
/// AWAY fixtures (is_home=false):
///   venue = opponent (location), opponent_venue = my club
///   AWAY — at {venue.name} vs {Team if present else My club}
String fixtureTitleUnified(
  Map<String, dynamic> f, {
  required String myClubName,
}) {
  final isHome = f['is_home'] == true;

  final joinedTeamName = _mapName(f['team']);
  final teamName = joinedTeamName.isNotEmpty ? joinedTeamName : _s(f['team_name']);
  final hasTeam = _s(f['team_id']).isNotEmpty && teamName.isNotEmpty;

  final greenName = _greenName(f['green_areas']);

  // Your model:
  // venue.name = location (host)
  // opponent_venue.name = "other party" (opponent for home, MY club for away)
  final venueName = _mapName(f['venue']);
  final opponentVenueName = _mapName(f['opponent_venue']);

  if (isHome) {
    final g = greenName.isNotEmpty ? greenName : 'Home';
    final opp = opponentVenueName.isNotEmpty ? opponentVenueName : 'Opponent';

    if (hasTeam) return 'HOME — $teamName on $g vs $opp';
    return 'HOME — $g vs $opp';
  } else {
    final where = venueName.isNotEmpty ? venueName : 'Opponent club';
    final vs = hasTeam ? teamName : myClubName;
    return 'AWAY — at $where vs $vs';
  }
}

String formatFixtureWhenLong12h(String isoUtc) {
  final dt = DateTime.parse(isoUtc).toLocal();
  var s = DateFormat("EEEE d MMMM yyyy, h:mm a").format(dt);
  s = s.replaceAll('AM', 'a.m.').replaceAll('PM', 'p.m.');
  return s;
}

String fixtureSubtitleUnified(Map<String, dynamic> f) {
  final startAt = (f['start_at'] ?? '').toString();
  final whenText =
      startAt.isEmpty ? 'Date/time not set' : formatFixtureWhenLong12h(startAt);

  final section = (f['section'] ?? '').toString().trim();

  final parts = <String>[
    whenText,
    if (section.isNotEmpty) section.toUpperCase(),
  ];

  return parts.join(' • ');
}