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
  final teamName =
      joinedTeamName.isNotEmpty ? joinedTeamName : _s(f['team_name']);
  final hasTeam = _s(f['team_id']).isNotEmpty && teamName.isNotEmpty;

  final venueName = _mapName(f['venue']);
  final opponentVenueName = _mapName(f['opponent_venue']);

  final competitionType = f['competition_type'] as Map<String, dynamic>?;
  final fixtureTypeName = _s(competitionType?['name']);
  final isInternal = competitionType?['is_internal'] == true;

  if (isInternal) {
    final internalLabel =
        fixtureTypeName.isNotEmpty ? fixtureTypeName : 'Internal fixture';
    return '${isHome ? 'Home' : 'Away'} - $internalLabel';
  }

  if (isHome) {
    final opponent =
        opponentVenueName.isNotEmpty ? opponentVenueName : 'Opponent';

    if (hasTeam) {
      return 'Home $teamName v $opponent';
    }
    return 'Home against $opponent';
  } else {
    final opponent = venueName.isNotEmpty ? venueName : 'Opponent';

    if (hasTeam) {
      return 'Away at $opponent v $teamName';
    }
    return 'Away at $opponent';
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