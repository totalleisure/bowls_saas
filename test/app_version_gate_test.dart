import 'package:flutter_test/flutter_test.dart';

import 'package:bowls_saas/main.dart';
import 'package:bowls_saas/services/app_version_policy_service.dart';

AppVersionPolicy blockedPolicy({Uri? updateUri, int installed = 16}) {
  return AppVersionPolicy(
    blocked: true,
    installedBuild: installed,
    minimumBuild: 17,
    updateMessage: 'A tested update is required.',
    updateUri: updateUri,
  );
}

void main() {
  testWidgets('valid URL shows the Update now button', (tester) async {
    await tester.pumpWidget(
      BowlsVersionGate(
        versionPolicy: blockedPolicy(
          updateUri: Uri.parse('https://example.test/update'),
        ),
        launchExternal: (_) async => true,
      ),
    );

    expect(find.text('Update now'), findsOneWidget);
    expect(
      find.text('Installed build: 16\nRequired build: 17'),
      findsOneWidget,
    );
  });

  testWidgets('missing URL shows safe guidance without an update button', (
    tester,
  ) async {
    await tester.pumpWidget(BowlsVersionGate(versionPolicy: blockedPolicy()));

    expect(find.text('Update now'), findsNothing);
    expect(find.textContaining('not available yet'), findsOneWidget);
  });

  testWidgets('invalid URL is removed before the screen is built', (
    tester,
  ) async {
    final service = AppVersionPolicyService(
      platform: 'android',
      installedBuildLoader: () async => '16',
      rowLoader: (_) async => {
        'minimum_build': 17,
        'update_url': 'javascript:alert(1)',
      },
    );
    final policy = await service.load();

    await tester.pumpWidget(BowlsVersionGate(versionPolicy: policy));

    expect(find.text('Update now'), findsNothing);
  });

  testWidgets('Try again reloads the remote policy', (tester) async {
    var reloads = 0;
    await tester.pumpWidget(
      BowlsVersionGate(
        versionPolicy: blockedPolicy(),
        reloadPolicy: () async {
          reloads++;
          return blockedPolicy(installed: 17);
        },
      ),
    );

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(reloads, 1);
    expect(
      find.text('Installed build: 17\nRequired build: 17'),
      findsOneWidget,
    );
  });

  testWidgets('launch failure does not bypass the gate', (tester) async {
    await tester.pumpWidget(
      BowlsVersionGate(
        versionPolicy: blockedPolicy(
          updateUri: Uri.parse('https://example.test/update'),
        ),
        launchExternal: (_) async => false,
      ),
    );

    await tester.tap(find.text('Update now'));
    await tester.pumpAndSettle();

    expect(find.text('Update required'), findsOneWidget);
    expect(find.textContaining('could not be opened'), findsOneWidget);
  });
}
