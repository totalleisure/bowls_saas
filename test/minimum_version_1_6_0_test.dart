import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/services/app_version_policy_service.dart';
void main() {
 for (final platform in ['ios','android','windows']) {
  for (final build in [17,27,28,29,33]) {
   test('$platform build $build under 1.6.0 minimum', () async {
    final policy = await AppVersionPolicyService(platform:platform,
      installedBuildLoader: () async => '$build',
      rowLoader:(requested) async {expect(requested,platform);return {'minimum_build':28,'latest_build':28,'force_update_message':'Please update to 1.6.0 or later.'};},
    ).load();
    expect(policy.blocked, build<28);
    expect(policy.minimumBuild,28);
   });
  }
 }
}
