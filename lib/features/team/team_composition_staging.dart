List<Map<String, dynamic>> buildConfirmedTeamMembers(
  Iterable<Map<String, dynamic>> selected,
) {
  return selected
      .where((row) {
        final role = (row['role'] ?? '').toString().toLowerCase();
        return row['is_selected'] == true &&
            (role == 'player' || role == 'reserve');
      })
      .map(
        (row) => {
          'member_profile_id': row['member_profile_id']?.toString(),
          'role': (row['role'] ?? '').toString().toLowerCase(),
          'is_selected': true,
        },
      )
      .toList();
}

void stageSelectedMemberRoleChange({
  required List<Map<String, dynamic>> selected,
  required Map<String, Map<int, Map<String, dynamic>>> assignmentsByRink,
  required String memberProfileId,
  required String newRole,
}) {
  final normalizedRole = newRole.toLowerCase().trim();

  for (final row in selected) {
    if (row['member_profile_id']?.toString() == memberProfileId) {
      row['role'] = normalizedRole;
      row['is_selected'] = true;
      break;
    }
  }

  if (normalizedRole == 'reserve') {
    for (final byPosition in assignmentsByRink.values) {
      byPosition.removeWhere(
        (_, row) => row['member_profile_id']?.toString() == memberProfileId,
      );
    }
    assignmentsByRink.removeWhere((_, byPosition) => byPosition.isEmpty);
  }
}
