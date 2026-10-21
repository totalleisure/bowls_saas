/// Used by individual menus and both bulk reminder actions.
bool canRemindSelectedMember(
  Map<String, dynamic> row, {
  required bool isAllocated,
}) {
  final role = (row['role'] ?? '').toString().trim().toLowerCase();
  final acceptance =
      (row['acceptance'] ?? 'pending').toString().trim().toLowerCase();
  return row['is_selected'] != false &&
      isAllocated &&
      const {'player', 'reserve', 'marker', 'opponent'}.contains(role) &&
      acceptance == 'pending' &&
      row['member_profiles']?['is_captain_managed'] != true;
}
