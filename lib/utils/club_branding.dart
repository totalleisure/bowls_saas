class ClubBranding {
  final int brandingSetNo;
  final String? primaryColour;
  final String? secondaryColour;

  const ClubBranding({
    required this.brandingSetNo,
    this.primaryColour,
    this.secondaryColour,
  });

  factory ClubBranding.fromClubMap(Map<String, dynamic>? club) {
    return ClubBranding(
      brandingSetNo: int.tryParse('${club?['branding_set_no'] ?? 0}') ?? 0,
      primaryColour: club?['primary_colour']?.toString(),
      secondaryColour: club?['secondary_colour']?.toString(),
    );
  }

  String get authPhone => 'assets/images/auth_bg_phone_$brandingSetNo.png';
  String get authTablet => 'assets/images/auth_bg_tablet_$brandingSetNo.png';
  String get authDesktop => 'assets/images/auth_bg_desktop_$brandingSetNo.png';

  String get blankPhone => 'assets/images/blank_bg_phone_$brandingSetNo.png';
  String get blankTablet => 'assets/images/blank_bg_tablet_$brandingSetNo.png';
  String get blankDesktop =>
      'assets/images/blank_bg_desktop_$brandingSetNo.png';
}
