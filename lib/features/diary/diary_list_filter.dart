import '../../models/dashboard_fixture_filter.dart';
import '../../core/utils/date_format.dart';

class DiaryListFilter {
  final DashboardFixtureFilter fixtures;
  final String location;
  final String team;
  const DiaryListFilter({
    this.fixtures = DashboardFixtureFilter.empty,
    this.location = 'all',
    this.team = 'all',
  });
  bool get isFiltered =>
      fixtures.isFiltered || location != 'all' || team != 'all';
  DiaryListFilter copyWith({
    DashboardFixtureFilter? fixtures,
    String? location,
    String? team,
  }) => DiaryListFilter(
    fixtures: fixtures ?? this.fixtures,
    location: location ?? this.location,
    team: team ?? this.team,
  );
  bool matches(Map<String, dynamic> entry, DateTime now) {
    final type = Map<String, dynamic>.from(
      entry['competition_type'] as Map? ?? {},
    );
    final start = parseClubTime(entry['start_at'] as String);
    final end = entry['_maintenance'] == true
        ? parseClubTime(entry['end_at'] as String)
        : start;
    if (!fixtures.matchesSection(entry['section'] as String?)) return false;
    if (!fixtures.includesType(
      entry['competition_type_id']?.toString() ?? '',
      type,
    )) {
      return false;
    }
    if (fixtures.period != 'all') {
      final first = fixtures.periodStart(now);
      final last = fixtures.periodEnd(now);
      final startDay = DateTime.utc(start.year, start.month, start.day);
      final endDay = DateTime.utc(
        end.year,
        end.month,
        end.day,
        end.hour,
        end.minute,
        end.second,
      );
      if (entry['_maintenance'] == true && !endDay.isAfter(first)) return false;
      if (endDay.isBefore(first) ||
          (last != null && !startDay.isBefore(last))) {
        return false;
      }
    }
    if (location == 'home' && entry['is_home'] != true) return false;
    if (location == 'away' && entry['is_home'] != false) return false;
    final teamId = entry['team_id']?.toString() ?? '';
    if (team == 'unassigned' && teamId.isNotEmpty) return false;
    if (team != 'all' && team != 'unassigned' && teamId != team) return false;
    return true;
  }

  Map<String, dynamic> toJson() => {
    'fixtures': fixtures.toJson(),
    'location': location,
    'team': team,
  };
  factory DiaryListFilter.fromJson(Map<String, dynamic> json) =>
      DiaryListFilter(
        fixtures: DashboardFixtureFilter.fromJson(
          Map<String, dynamic>.from(json['fixtures'] as Map? ?? {}),
        ),
        location: json['location'] as String? ?? 'all',
        team: json['team'] as String? ?? 'all',
      );
  static String storageKey(String userId, String clubId) =>
      'diary.list.filters.v1.$userId.$clubId';
}

/// Search descriptive fields only, never hidden player or membership data.
bool diaryEntryMatchesSearch(Map<String, dynamic> entry, String query) {
  final words = query
      .toLowerCase()
      .trim()
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty);
  if (words.isEmpty) return true;
  final type = entry['competition_type'] as Map? ?? {};
  final text = [
    entry['team_name'],
    entry['opponent_name'],
    entry['reason'],
    type['name'],
    (entry['team'] as Map?)?['name'],
    (entry['venue'] as Map?)?['name'],
    (entry['opponent_venue'] as Map?)?['name'],
    (entry['green_areas'] as Map?)?['name'],
  ].whereType<String>().join(' ').toLowerCase();
  return words.every(text.contains);
}
