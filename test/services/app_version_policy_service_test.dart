import 'package:flutter_test/flutter_test.dart';

import 'package:bowls_saas/services/app_version_policy_service.dart';

AppVersionPolicyService serviceFor({
  required int installed,
  required int minimum,
  String platform = 'ios',
  String? updateUrl,
  String? updateMessage,
  void Function(String platform)? onPlatform,
}) {
  return AppVersionPolicyService(
    platform: platform,
    installedBuildLoader: () async => '$installed',
    rowLoader: (selectedPlatform) async {
      onPlatform?.call(selectedPlatform);
      return {
        'minimum_build': minimum,
        'latest_build': minimum,
        'update_url': updateUrl,
        'update_message': updateMessage,
      };
    },
  );
}

void main() {
  test('build 16 is blocked when the minimum is 17', () async {
    final policy = await serviceFor(installed: 16, minimum: 17).load();
    expect(policy.blocked, isTrue);
    expect(policy.installedBuild, 16);
    expect(policy.minimumBuild, 17);
  });

  test('build 17 is allowed when the minimum is 17', () async {
    final policy = await serviceFor(installed: 17, minimum: 17).load();
    expect(policy.blocked, isFalse);
  });

  test('build 18 is allowed when the minimum is 17', () async {
    final policy = await serviceFor(installed: 18, minimum: 17).load();
    expect(policy.blocked, isFalse);
  });

  test('the requested platform policy is selected', () async {
    String? selectedPlatform;
    await serviceFor(
      installed: 16,
      minimum: 17,
      platform: 'android',
      onPlatform: (value) => selectedPlatform = value,
    ).load();
    expect(selectedPlatform, 'android');
  });

  test('only approved update URL schemes are accepted', () {
    expect(
      AppVersionPolicyService.validUpdateUri(
        'https://testflight.apple.com/join/example',
      ),
      isNotNull,
    );
    expect(
      AppVersionPolicyService.validUpdateUri(
        'itms-apps://itunes.apple.com/app/id123',
      ),
      isNotNull,
    );
    expect(
      AppVersionPolicyService.validUpdateUri('javascript:alert(1)'),
      isNull,
    );
    expect(AppVersionPolicyService.validUpdateUri('file:///unsafe'), isNull);
  });

  test('policy loading failure deliberately fails open', () async {
    final service = AppVersionPolicyService(
      platform: 'windows',
      installedBuildLoader: () async => '16',
      rowLoader: (_) async => throw Exception('network unavailable'),
    );

    final policy = await service.load();
    expect(policy.blocked, isFalse);
    expect(policy.installedBuild, 16);
  });
}
