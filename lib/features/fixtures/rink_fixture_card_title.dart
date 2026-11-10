/// Keep the fixture type/opponent and add a distinct user-entered label.
String rinkFixtureCardTitle(Map<String, dynamic> fixture) {
  final type = fixture['competition_types'] as Map<String, dynamic>?;
  final typeName = (type?['name'] ?? '').toString().trim();
  final opponent = (fixture['opponent_name'] ?? '').toString().trim();
  final label = (fixture['team_name'] ?? '').toString().trim();
  final title = type?['is_internal'] == true
      ? (typeName.isEmpty ? 'Internal Fixture' : typeName)
      : opponent.isNotEmpty
      ? opponent
      : typeName.isEmpty
      ? 'Fixture'
      : typeName;
  String normal(String s) =>
      s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  return label.isNotEmpty &&
          normal(label) != normal(typeName) &&
          normal(label) != normal(title)
      ? '$title\n$label'
      : title;
}
