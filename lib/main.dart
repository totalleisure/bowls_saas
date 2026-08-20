import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'secrets.dart';
import 'App/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
    debugPrintStack(stackTrace: details.stack, label: 'FLUTTER ERROR STACK');
  };

  await Supabase.initialize(
    url: Secrets.supabaseUrl,
    anonKey: Secrets.supabaseAnonKey,
  );

  final versionPolicy = await _loadVersionPolicy();

  runApp(BowlsVersionGate(versionPolicy: versionPolicy));
}

class AppVersionPolicy {
  final bool blocked;
  final String? message;

  const AppVersionPolicy({required this.blocked, this.message});
}

Future<AppVersionPolicy> _loadVersionPolicy() async {
  try {
    final packageInfo = await PackageInfo.fromPlatform();

    final currentBuild = int.tryParse(packageInfo.buildNumber.trim()) ?? 0;

    final platform = Platform.isIOS
        ? 'ios'
        : Platform.isAndroid
        ? 'android'
        : Platform.isWindows
        ? 'windows'
        : null;

    // Unknown platform: don't block.
    if (platform == null) {
      return const AppVersionPolicy(blocked: false);
    }

    final row = await Supabase.instance.client
        .from('app_version_policy')
        .select('minimum_build, latest_build, force_update_message')
        .eq('platform', platform)
        .maybeSingle();

    // No policy configured: don't block.
    if (row == null) {
      return const AppVersionPolicy(blocked: false);
    }

    final minimumBuild = int.tryParse(row['minimum_build'].toString()) ?? 0;

    final blocked = currentBuild < minimumBuild;

    debugPrint(
      'VERSION CHECK: '
      'platform=$platform '
      'currentBuild=$currentBuild '
      'minimumBuild=$minimumBuild '
      'blocked=$blocked',
    );

    return AppVersionPolicy(
      blocked: blocked,
      message: row['force_update_message']?.toString(),
    );
  } catch (e, stackTrace) {
    // Important: fail open.
    // A temporary Supabase/network problem must not lock users out.
    debugPrint('VERSION CHECK FAILED: $e');
    debugPrintStack(stackTrace: stackTrace);

    return const AppVersionPolicy(blocked: false);
  }
}

class BowlsVersionGate extends StatelessWidget {
  final AppVersionPolicy versionPolicy;

  const BowlsVersionGate({super.key, required this.versionPolicy});

  @override
  Widget build(BuildContext context) {
    if (versionPolicy.blocked) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: UpdateRequiredPage(message: versionPolicy.message),
      );
    }

    return const BowlsApp();
  }
}

class UpdateRequiredPage extends StatelessWidget {
  final String? message;

  const UpdateRequiredPage({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    final displayMessage = message?.trim().isNotEmpty == true
        ? message!.trim()
        : 'This version of the Total Leisure Bowls App is no longer supported. '
              'Please update to the latest version before continuing.';

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.system_update_alt, size: 64),
                const SizedBox(height: 20),
                const Text(
                  'Update required',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text(
                  displayMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
