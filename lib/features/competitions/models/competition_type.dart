class ColourScheme {
  final String id;
  final String name;
  final String backgroundHex;
  final String foregroundHex;
  final int? sortOrder;

  ColourScheme({
    required this.id,
    required this.name,
    required this.backgroundHex,
    required this.foregroundHex,
    this.sortOrder,
  });

  factory ColourScheme.fromMap(Map<String, dynamic> map) {
    return ColourScheme(
      id: map['id'].toString(),
      name: (map['name'] ?? '').toString(),
      backgroundHex: (map['background_hex'] ?? '#FFFFFF').toString(),
      foregroundHex: (map['foreground_hex'] ?? '#000000').toString(),
      sortOrder: map['sort_order'] as int?,
    );
  }
}

class CompetitionType {
  final String id;
  final String clubId;
  final String name;  
  final bool isInternal;
  final String section;
  final int? defaultRinksRequired;
  final int? defaultPlayersPerRink;
  final int? defaultDurationMinutes;
  final String? dressCode;
  final bool teamSelectionEnabled;
  final String? selectionMode;
  final bool usesRinks;
  final bool bookableByMembers;
  final bool isActive;
  final ColourScheme? colourScheme;

  const CompetitionType({
    required this.id,
    required this.clubId,
    required this.name,
    required this.isInternal,
    required this.section,
    required this.defaultRinksRequired,
    required this.defaultPlayersPerRink,
    required this.defaultDurationMinutes,
    required this.dressCode,
    required this.teamSelectionEnabled,
    required this.selectionMode,
    required this.usesRinks,
    required this.bookableByMembers,
    required this.isActive,
    required this.colourScheme,
  });

  factory CompetitionType.fromMap(Map<String, dynamic> map) {
    final colour = map['colour_scheme'];

    return CompetitionType(
      id: (map['id'] ?? '').toString(),
      clubId: (map['club_id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      isInternal: map['is_internal'] == true,
      section: (map['section'] ?? '').toString(),
      defaultRinksRequired: map['default_rinks_required'] as int?,
      defaultPlayersPerRink: map['default_players_per_rink'] as int?,
      defaultDurationMinutes: map['default_duration_minutes'] as int?,
      dressCode: map['dress_code']?.toString(),
      teamSelectionEnabled: map['team_selection_enabled'] == true,
      selectionMode: map['selection_mode']?.toString(),
      usesRinks: map['uses_rinks'] != false,
      bookableByMembers: map['bookable_by_members'] == true,      
      isActive: map['is_active'] == true,
      colourScheme: colour is Map<String, dynamic>
          ? ColourScheme.fromMap(colour)
          : null,
    );
  }
}