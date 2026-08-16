import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/utils/date_format.dart';

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

  final selectionMode = _s(
    competitionType?['selection_mode'],
  ).toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');

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
    final opponent = opponentVenueName.isNotEmpty
        ? opponentVenueName
        : 'opponent to be confirmed';

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
  final dt = parseClubTime(isoUtc);
  var s = DateFormat("EEEE d MMMM yyyy, h:mm a").format(dt);
  s = s.replaceAll('AM', 'a.m.').replaceAll('PM', 'p.m.');
  return s;
}

String fixtureSubtitleUnified(Map<String, dynamic> f) {
  final startAt = (f['start_at'] ?? '').toString();
  final whenText = startAt.isEmpty
      ? 'Date/time not set'
      : formatFixtureWhenLong12h(startAt);

  final competitionType = f['competition_type'] as Map<String, dynamic>?;
  final fixtureTypeName = _s(competitionType?['name']);

  final rawUsesRinks = competitionType?['uses_rinks'];
  final usesRinks = rawUsesRinks == null ? true : rawUsesRinks == true;

  final selectionMode = _s(
    competitionType?['selection_mode'],
  ).toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');

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

class UnifiedFixtureCard extends StatelessWidget {
  const UnifiedFixtureCard({
    super.key,
    required this.fixture,
    required this.myClubName,
    required this.onTap,
    this.actionHint,
    this.trailing,
    this.margin = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  });

  final Map<String, dynamic> fixture;
  final String myClubName;
  final VoidCallback onTap;
  final String? actionHint;
  final Widget? trailing;
  final EdgeInsetsGeometry margin;

  Color _colourFromHex(String? hex, Color fallback) {
    if (hex == null || hex.trim().isEmpty) return fallback;

    final clean = hex.replaceAll('#', '').trim();

    if (clean.length != 6) return fallback;

    return Color(int.parse('FF$clean', radix: 16));
  }

  String _formatLabel() {
    String? formatCode;

    final fixtureRinks = fixture['fixture_rinks'];

    if (fixtureRinks is List && fixtureRinks.isNotEmpty) {
      final first = fixtureRinks.first;

      if (first is Map) {
        formatCode = first['format']?.toString().trim().toLowerCase();
      }
    }

    switch (formatCode) {
      case 'singles':
        return 'Singles';
      case 'pairs':
        return 'Pairs';
      case 'aussie_pairs':
        return 'Aussie Pairs';
      case 'triples':
        return 'Triples';
      case 'fours':
      case 'rinks':
        return 'Fours';
    }

    final playersPerRink = fixture['players_per_rink'];

    if (playersPerRink == 1) return 'Singles';
    if (playersPerRink == 2) return 'Pairs';
    if (playersPerRink == 3) return 'Triples';
    if (playersPerRink == 4) return 'Fours';

    return '';
  }

  @override
  Widget build(BuildContext context) {
    final isCancelled = fixture['cancelled_at'] != null;
    final isHome = fixture['is_home'] == true;

    final title = fixtureTitleUnified(fixture, myClubName: myClubName);

    final whenText = formatWhenLocal(fixture['start_at'].toString());

    final section = (fixture['section'] ?? '').toString().trim();
    final rinks = fixture['rinks_required'] as int? ?? 0;
    final orientation = fixture['orientation']?.toString();

    final competitionType =
        fixture['competition_type'] as Map<String, dynamic>?;

    final competitionTypeName = (competitionType?['name'] ?? '')
        .toString()
        .trim();

    final colourScheme =
        competitionType?['colour_scheme'] as Map<String, dynamic>?;

    final greenArea = fixture['green_areas'] as Map<String, dynamic>?;

    final discipline = greenArea?['discipline']?.toString().toLowerCase();

    final orientationMode = greenArea?['orientation_mode']
        ?.toString()
        .toLowerCase();

    final showOrientation =
        isHome &&
        discipline == 'outdoor' &&
        orientationMode != 'not_applicable';

    final formatLabel = _formatLabel();

    final normalBackground = _colourFromHex(
      colourScheme?['background_hex']?.toString(),
      Theme.of(context).colorScheme.surface,
    );

    final normalForeground = _colourFromHex(
      colourScheme?['foreground_hex']?.toString(),
      Theme.of(context).colorScheme.onSurface,
    );

    final background = isCancelled ? Colors.grey.shade300 : normalBackground;

    final foreground = isCancelled ? Colors.grey.shade800 : normalForeground;

    final detailParts = <String>[
      whenText,
      if (section.isNotEmpty) section,
      if (formatLabel.isNotEmpty) formatLabel,
      if (rinks > 0) '$rinks rinks',
      if (showOrientation) 'orient: ${orientation ?? 'not set'}',
    ];

    return Card(
      margin: margin,
      color: background,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isCancelled) ...[
                Text(
                  'CANCELLED',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.grey.shade900,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
              ],

              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isCancelled
                          ? Colors.grey.shade400
                          : foreground.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isCancelled
                            ? Colors.grey.shade600
                            : foreground.withOpacity(0.28),
                      ),
                    ),
                    child: Text(
                      isHome ? 'HOME' : 'AWAY',
                      style: TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),

              if (competitionTypeName.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  competitionTypeName,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],

              const SizedBox(height: 3),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      detailParts.join(' • '),
                      style: TextStyle(color: foreground),
                    ),
                  ),
                  const SizedBox(width: 8),
                  trailing ?? Icon(Icons.chevron_right, color: foreground),
                ],
              ),

              if (actionHint != null && actionHint!.trim().isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  actionHint!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
