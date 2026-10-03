class DashboardFixtureFilter {
  final Set<String> sections;
  final Set<String> categories;
  final String period;
  final Set<String> fixtureTypeIds;

  /// Distinguishes an explicit empty selection (None) from legacy All.
  final bool explicitTypes;
  final bool explicitSections;

  const DashboardFixtureFilter({
    this.sections = const <String>{},
    this.categories = const <String>{},
    this.period = 'all',
    this.explicitTypes = false,
    this.explicitSections = false,
    this.fixtureTypeIds = const <String>{},
  });

  static const DashboardFixtureFilter empty = DashboardFixtureFilter();

  bool get isDefault =>
      !explicitTypes &&
      !explicitSections &&
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
    bool? explicitTypes,
    bool? explicitSections,
  }) {
    return DashboardFixtureFilter(
      explicitTypes: explicitTypes ?? this.explicitTypes,
      explicitSections: explicitSections ?? this.explicitSections,
      sections: sections ?? this.sections,
      categories: categories ?? this.categories,
      period: period ?? this.period,
      fixtureTypeIds: fixtureTypeIds ?? this.fixtureTypeIds,
    );
  }

  bool get allSectionsSelected => !explicitSections && sections.isEmpty;

  bool matchesSection(String? value) {
    if (allSectionsSelected) return true;
    final raw = (value ?? '').trim().toLowerCase();
    return sections.contains(raw.isEmpty ? 'open' : raw);
  }

  // Both arguments are club calendar dates, irrespective of device timezone.
  DateTime? periodEnd(DateTime now) {
    switch (period) {
      case 'this_month':
        return DateTime.utc(now.year, now.month + 1);
      case 'next_month':
        return DateTime.utc(now.year, now.month + 2);
      case 'three_months':
        final lastDay = DateTime.utc(now.year, now.month + 4, 0).day;
        final day = now.day > lastDay ? lastDay : now.day;
        return DateTime.utc(now.year, now.month + 3, day + 1);
      default:
        return null;
    }
  }

  DateTime periodStart(DateTime now) => period == 'next_month'
      ? DateTime.utc(now.year, now.month + 1)
      : DateTime.utc(now.year, now.month, now.day);

  bool matchesPeriod(DateTime date, DateTime now) {
    final day = DateTime.utc(date.year, date.month, date.day);
    final end = periodEnd(now);
    return !day.isBefore(periodStart(now)) &&
        (end == null || day.isBefore(end));
  }

  bool get allTypesSelected =>
      !explicitTypes && categories.isEmpty && fixtureTypeIds.isEmpty;

  static bool matchesTag(Map<String, dynamic> type, String tag) {
    if (tag == 'internal') return type['is_internal'] == true;
    if (tag == 'event') return type['uses_rinks'] == false;
    if (tag == 'open_session') return type['selection_mode'] == 'open';
    return (type['tags'] as List<dynamic>? ?? const []).any(
      (value) => value.toString().trim().toLowerCase() == tag,
    );
  }

  bool includesType(String id, Map<String, dynamic> type) {
    if (explicitTypes) return fixtureTypeIds.contains(id);
    // Preserve the meaning of filters saved before explicit selection existed.
    if (fixtureTypeIds.isNotEmpty && !fixtureTypeIds.contains(id)) return false;
    if (categories.isEmpty) return true;
    return categories.any(
      (tag) => tag == 'internal'
          ? type['is_internal'] == true
          : (type['tags'] as List<dynamic>? ?? const []).any(
              (value) => value.toString().trim().toLowerCase() == tag,
            ),
    );
  }

  Set<String> selectedIds(List<Map<String, dynamic>> types) => {
    for (final type in types)
      if (includesType(type['id'].toString(), type)) type['id'].toString(),
  };

  DashboardFixtureFilter selectTypes(Set<String> ids) =>
      copyWith(fixtureTypeIds: ids, categories: {}, explicitTypes: true);

  DashboardFixtureFilter selectAllTypes() =>
      copyWith(fixtureTypeIds: {}, categories: {}, explicitTypes: false);

  DashboardFixtureFilter toggleType(
    String id,
    List<Map<String, dynamic>> types,
  ) {
    final ids = selectedIds(types);
    ids.contains(id) ? ids.remove(id) : ids.add(id);
    return selectTypes(ids);
  }

  DashboardFixtureFilter toggleTag(
    String tag,
    List<Map<String, dynamic>> types,
  ) {
    final group = {
      for (final type in types)
        if (matchesTag(type, tag)) type['id'].toString(),
    };
    if (group.isEmpty) return this;
    // The first shortcut narrows All. Subsequent shortcuts add groups;
    // clicking a fully selected group removes it.
    final ids = allTypesSelected ? <String>{} : selectedIds(types);
    if (ids.containsAll(group)) {
      ids.removeAll(group);
    } else {
      ids.addAll(group);
    }
    return selectTypes(ids);
  }

  DashboardFixtureFilter clear() => empty;

  Map<String, dynamic> toJson() {
    return {
      'explicitTypes': explicitTypes,
      'explicitSections': explicitSections,
      'sections': sections.toList()..sort(),
      'categories': categories.toList()..sort(),
      'period': period,
      'fixtureTypeIds': fixtureTypeIds.toList()..sort(),
    };
  }

  factory DashboardFixtureFilter.fromJson(Map<String, dynamic> json) {
    return DashboardFixtureFilter(
      explicitTypes: json['explicitTypes'] == true,
      explicitSections: json['explicitSections'] == true,
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
            explicitTypes == other.explicitTypes &&
            explicitSections == other.explicitSections &&
            period == other.period &&
            _setEquals(fixtureTypeIds, other.fixtureTypeIds);
  }

  @override
  int get hashCode => Object.hash(
    explicitTypes,
    explicitSections,
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
