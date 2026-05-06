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

  final competitionType = f['competition_type'] as Map<String, dynamic>?;
  final fixtureTypeName = _s(competitionType?['name']);
  final isInternal = competitionType?['is_internal'] == true;

  final rawUsesRinks = competitionType?['uses_rinks'];
  final usesRinks = rawUsesRinks == null ? true : rawUsesRinks == true;

  final selectionMode = _s(competitionType?['selection_mode'])
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');

  final joinedTeamName = _mapName(f['team']);
  final fixtureLabel = _s(f['team_name']);
  final teamName = joinedTeamName.isNotEmpty ? joinedTeamName : fixtureLabel;
  final hasTeam = _s(f['team_id']).isNotEmpty && teamName.isNotEmpty;

  final venueName = _mapName(f['venue']);
  final opponentVenueName = _mapName(f['opponent_venue']);

  // Events / meetings / parties: no green or rink interaction.
  // Prefer the user-facing label, then the fixture type.
  if (!usesRinks) {
    if (fixtureLabel.isNotEmpty) return fixtureLabel;
    if (fixtureTypeName.isNotEmpty) return fixtureTypeName;
    return 'Event';
  }

  // Open sessions / roll-ups / rink-only items.
  // Prefer label, then fixture type. No "Home against Opponent".
  if (selectionMode == 'open' || selectionMode == 'no_players') {
    if (fixtureLabel.isNotEmpty) return fixtureLabel;
    if (fixtureTypeName.isNotEmpty) return fixtureTypeName;
    return 'Open Session';
  }

  if (isInternal) {
    if (fixtureLabel.isNotEmpty) return fixtureLabel;
    if (fixtureTypeName.isNotEmpty) return fixtureTypeName;
    return 'Internal Fixture';
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

  final competitionType = f['competition_type'] as Map<String, dynamic>?;
  final fixtureTypeName = _s(competitionType?['name']);

  final rawUsesRinks = competitionType?['uses_rinks'];
  final usesRinks = rawUsesRinks == null ? true : rawUsesRinks == true;

  final selectionMode = _s(competitionType?['selection_mode'])
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');

  final section = _s(f['section']);

  final parts = <String>[whenText];

  if (!usesRinks) {
    if (fixtureTypeName.isNotEmpty) parts.add(fixtureTypeName);
    return parts.join(' • ');
  }

  if (selectionMode == 'open' || selectionMode == 'no_players') {
    if (fixtureTypeName.isNotEmpty) {
      parts.add(fixtureTypeName);
    } else if (section.isNotEmpty) {
      parts.add(section.toUpperCase());
    }
    return parts.join(' • ');
  }

  if (section.isNotEmpty) parts.add(section.toUpperCase());

  return parts.join(' • ');
}