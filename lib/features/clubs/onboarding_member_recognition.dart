import 'onboarding_member_import.dart';

typedef OnboardingMemberLookup =
    Future<List<Map<String, dynamic>>> Function(List<OnboardingMember> members);

String recognisedClubs(List<dynamic>? clubs) => (clubs ?? [])
    .map((c) {
      final row = Map<String, dynamic>.from(c as Map);
      return '${row['name']} (${row['active'] == true ? 'active' : 'inactive'})';
    })
    .join('; ');

String recognitionNote(Map<String, dynamic> match) {
  if (match['status'] == 'ambiguous') {
    return 'More than one existing record uses this email. Please check before linking.';
  }
  if (match['status'] != 'matched') {
    return 'No existing profile was found for this email. They will start inactive in this club. '
        'You can send their invitation after club setup.';
  }
  final clubs = recognisedClubs(match['clubs'] as List?);
  final membership = match['attached'] == true
      ? 'Membership here is ${match['active_here'] == true ? 'active' : 'inactive'}; existing memberships stay unchanged.'
      : clubs.isNotEmpty
      ? 'They will join this club as an inactive Member. Their other club memberships stay unchanged.'
      : 'They will start as an inactive Member of this club.';
  return 'Existing record: ${match['display_name'] ?? ''}. '
      '${clubs.isEmpty ? 'No other club membership found.' : 'Found at: $clubs.'} $membership';
}
