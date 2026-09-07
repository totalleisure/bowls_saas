import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef VersionPolicyRowLoader =
    Future<Map<String, dynamic>?> Function(String platform);
typedef InstalledBuildLoader = Future<String> Function();

class AppVersionPolicy {
  const AppVersionPolicy({
    required this.blocked,
    required this.installedBuild,
    required this.minimumBuild,
    this.latestBuild,
    this.updateMessage,
    this.updateUri,
  });

  final bool blocked;
  final int installedBuild;
  final int minimumBuild;
  final int? latestBuild;
  final String? updateMessage;
  final Uri? updateUri;

  static AppVersionPolicy allow({int installedBuild = 0}) {
    return AppVersionPolicy(
      blocked: false,
      installedBuild: installedBuild,
      minimumBuild: 0,
    );
  }
}

class AppVersionPolicyService {
  AppVersionPolicyService({
    required VersionPolicyRowLoader rowLoader,
    required InstalledBuildLoader installedBuildLoader,
    String? platform,
  }) : _rowLoader = rowLoader,
       _installedBuildLoader = installedBuildLoader,
       _platform = platform ?? currentPlatform();

  factory AppVersionPolicyService.supabase({SupabaseClient? client}) {
    final supabase = client ?? Supabase.instance.client;

    return AppVersionPolicyService(
      rowLoader: (platform) async {
        final row = await supabase
            .from('app_version_policy')
            .select(
              'minimum_build, latest_build, force_update_message, '
              'update_url, update_message',
            )
            .eq('platform', platform)
            .maybeSingle();

        return row == null ? null : Map<String, dynamic>.from(row);
      },
      installedBuildLoader: () async {
        final packageInfo = await PackageInfo.fromPlatform();
        return packageInfo.buildNumber;
      },
    );
  }

  final VersionPolicyRowLoader _rowLoader;
  final InstalledBuildLoader _installedBuildLoader;
  final String? _platform;

  static String? currentPlatform() {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    return null;
  }

  static Uri? validUpdateUri(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return null;

    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasAuthority) return null;

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'itms-apps') return null;

    return uri;
  }

  Future<AppVersionPolicy> load() async {
    var installedBuild = 0;

    try {
      installedBuild =
          int.tryParse((await _installedBuildLoader()).trim()) ?? 0;

      final platform = _platform;
      if (platform == null) {
        return AppVersionPolicy.allow(installedBuild: installedBuild);
      }

      final row = await _rowLoader(platform);
      if (row == null) {
        return AppVersionPolicy.allow(installedBuild: installedBuild);
      }

      final minimumBuild =
          int.tryParse((row['minimum_build'] ?? '').toString()) ?? 0;
      final latestBuild = int.tryParse((row['latest_build'] ?? '').toString());
      final updateMessage = _firstNonEmpty([
        row['update_message'],
        row['force_update_message'],
      ]);

      return AppVersionPolicy(
        blocked: installedBuild < minimumBuild,
        installedBuild: installedBuild,
        minimumBuild: minimumBuild,
        latestBuild: latestBuild,
        updateMessage: updateMessage,
        updateUri: validUpdateUri(row['update_url']),
      );
    } catch (_) {
      // Deliberately fail open when package or remote policy loading fails.
      return AppVersionPolicy.allow(installedBuild: installedBuild);
    }
  }

  static String? _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      final text = (value ?? '').toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }
}
