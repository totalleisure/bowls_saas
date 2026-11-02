import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

final clubUsageObserver = RouteObserver<ModalRoute<void>>();

/// One visit per Club/account per process. Token refresh and widget rebuilds
/// do not create visits. Returns from another page do count as screen views.
class ClubUsage {
  static final _visited = <String>{};
  static String get platform => kIsWeb
      ? 'Web'
      : switch (defaultTargetPlatform) {
          TargetPlatform.iOS => 'iOS',
          TargetPlatform.android => 'Android',
          TargetPlatform.windows => 'Windows',
          TargetPlatform.macOS => 'macOS',
          TargetPlatform.linux => 'Linux',
          TargetPlatform.fuchsia => 'Linux',
        };
  static Future<void> screen(String clubId, String screen) async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;
      final visitKey = '${user.id}:$clubId';
      Future<void> send(String kind) async {
        await client
            .rpc(
              'record_club_usage',
              params: {
                'p_club_id': clubId,
                'p_event_id': const Uuid().v4(),
                'p_kind': kind,
                'p_screen': screen,
                'p_platform': platform,
              },
            )
            .timeout(const Duration(seconds: 8));
      }

      if (_visited.add(visitKey)) {
        try {
          await send('app_visit');
        } catch (_) {
          _visited.remove(visitKey);
        }
      }
      await send('screen_view');
    } catch (_) {
      // Reporting must never stop members using the App, including offline.
    }
  }
}

mixin ClubScreenTracking<T extends StatefulWidget> on State<T>
    implements RouteAware {
  String get usageClubId;
  String get usageScreen;
  ModalRoute<void>? _usageRoute;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _usageRoute) {
      clubUsageObserver.unsubscribe(this);
      _usageRoute = route;
      if (route != null) clubUsageObserver.subscribe(this, route);
    }
  }

  @override
  void didPush() => unawaited(ClubUsage.screen(usageClubId, usageScreen));
  @override
  void didPopNext() => unawaited(ClubUsage.screen(usageClubId, usageScreen));
  @override
  void didPop() {}
  @override
  void didPushNext() {}
  @override
  void dispose() {
    clubUsageObserver.unsubscribe(this);
    super.dispose();
  }
}
