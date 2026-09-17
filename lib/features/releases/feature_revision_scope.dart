import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'feature_revision_controller.dart';

class FeatureRevisionScope
    extends InheritedNotifier<FeatureRevisionController> {
  const FeatureRevisionScope({
    super.key,
    required FeatureRevisionController controller,
    required super.child,
  }) : super(notifier: controller);
  static FeatureRevisionController of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<FeatureRevisionScope>()!
      .notifier!;
}

class FeatureRevisionHost extends StatefulWidget {
  const FeatureRevisionHost({super.key, required this.child});
  final Widget child;
  @override
  State<FeatureRevisionHost> createState() => _FeatureRevisionHostState();
}

class _FeatureRevisionHostState extends State<FeatureRevisionHost>
    with WidgetsBindingObserver {
  late final FeatureRevisionController _controller;
  StreamSubscription<AuthState>? _auth;
  final _client = Supabase.instance.client;
  @override
  void initState() {
    super.initState();
    _controller = FeatureRevisionController(
      loadRevision: () async {
        final row = await _client
            .from('feature_revision_policy')
            .select('enabled_revision')
            .eq('id', true)
            .single();
        return row['enabled_revision'] as int;
      },
    );
    WidgetsBinding.instance.addObserver(this);
    _auth = _client.auth.onAuthStateChange.listen((_) => _refresh());
    _refresh();
  }

  void _refresh() {
    if (_client.auth.currentSession == null) {
      _controller.clear();
    } else {
      unawaited(_controller.refresh());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
    if (state == AppLifecycleState.paused) _controller.clear();
  }

  @override
  void dispose() {
    _auth?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FeatureRevisionScope(controller: _controller, child: widget.child);
}

/// UI convenience only. Every corresponding server operation must also check.
class FeatureRevisionGate extends StatelessWidget {
  const FeatureRevisionGate({
    super.key,
    required this.revision,
    required this.child,
    this.fallback = const SizedBox.shrink(),
  });
  final int revision;
  final Widget child;
  final Widget fallback;
  @override
  Widget build(BuildContext context) =>
      FeatureRevisionScope.of(context).allows(revision) ? child : fallback;
}
