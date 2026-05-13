import 'package:flutter/material.dart';

import 'package:bowls_saas/core/widgets/club_member_picker_page.dart';

Future<void> pickFixtureSlotMember({
  required BuildContext context,
  required String clubId,
  required String title,
  required String bucket,
  required String key,
  required Map<String, String?> selections,
  required Future<void> Function(String message) showError,
  required bool Function({
    required String memberProfileId,
    required String targetBucket,
    required String targetKey,
  }) memberAlreadySelectedElsewhere,
  String? fixtureId,
  bool useFixtureSection = true,
  MemberPickerSectionFilter initialSectionFilter =
      MemberPickerSectionFilter.mixed,
}) async {
  final current = selections[key];

  final selectedList = await Navigator.of(context).push<List<String>?>(
    MaterialPageRoute(
      builder: (_) => ClubMemberPickerPage(
        clubId: clubId,
        title: title,
        fixtureId: fixtureId,
        useFixtureSection: useFixtureSection,
        initialSectionFilter: initialSectionFilter,
        allowMultiple: false,
        initialSelectedIds: {
          if (current != null && current.isNotEmpty) current,
        },
      ),
    ),
  );

  if (selectedList == null) return;

  final selected = selectedList.isEmpty ? null : selectedList.first;

  if (selected != null &&
      memberAlreadySelectedElsewhere(
        memberProfileId: selected,
        targetBucket: bucket,
        targetKey: key,
      )) {
    await showError(
      'This member has already been selected elsewhere in this fixture.',
    );
    return;
  }

  selections[key] = selected;
}