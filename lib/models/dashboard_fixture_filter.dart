class DashboardFixtureFilter {
  final Set<String> sections;
  final Set<String> categories;
  final String period;
  final Set<String> fixtureTypeIds;

  const DashboardFixtureFilter({
    this.sections = const <String>{},
    this.categories = const <String>{},
    this.period = 'all',
    this.fixtureTypeIds = const <String>{},
  });

  static const DashboardFixtureFilter empty = DashboardFixtureFilter();

  bool get isDefault =>
      sections.isEmpty &&
      categories.isEmpty &&
      period == 'all' &&
      fixtureTypeIds.isEmpty;

  bool get isFiltered => !isDefault;

  DashboardFixtureFilter copyWith({
    Set<String>? sections,
    Set<String>? categories,
    String? period,
    Set<String>? fixtureTypeIds,
  }) {
    return DashboardFixtureFilter(
      sections: sections ?? this.sections,
      categories: categories ?? this.categories,
      period: period ?? this.period,
      fixtureTypeIds: fixtureTypeIds ?? this.fixtureTypeIds,
    );
  }

  DashboardFixtureFilter clear() => empty;

  Map<String, dynamic> toJson() {
    return {
      'sections': sections.toList()..sort(),
      'categories': categories.toList()..sort(),
      'period': period,
      'fixtureTypeIds': fixtureTypeIds.toList()..sort(),
    };
  }

  factory DashboardFixtureFilter.fromJson(Map<String, dynamic> json) {
    return DashboardFixtureFilter(
      sections: (json['sections'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toSet(),
      categories: (json['categories'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toSet(),
      period: (json['period'] ?? 'all').toString(),
      fixtureTypeIds: (json['fixtureTypeIds'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toSet(),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is DashboardFixtureFilter &&
            _setEquals(sections, other.sections) &&
            _setEquals(categories, other.categories) &&
            period == other.period &&
            _setEquals(fixtureTypeIds, other.fixtureTypeIds);
  }

  @override
  int get hashCode => Object.hash(
    _setHash(sections),
    _setHash(categories),
    period,
    _setHash(fixtureTypeIds),
  );

  static bool _setEquals(Set<String> a, Set<String> b) {
    return a.length == b.length && a.containsAll(b);
  }

  static int _setHash(Set<String> values) {
    final sorted = values.toList()..sort();
    return Object.hashAll(sorted);
  }

  @override
  String toString() {
    return 'DashboardFixtureFilter('
        'sections: $sections, '
        'categories: $categories, '
        'period: $period, '
        'fixtureTypeIds: $fixtureTypeIds'
        ')';
  }
}
