import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../releases/feature_revision_scope.dart';

class FeatureRevisionScreen extends StatefulWidget {
  const FeatureRevisionScreen({super.key});
  @override
  State<FeatureRevisionScreen> createState() => _FeatureRevisionScreenState();
}

class _FeatureRevisionScreenState extends State<FeatureRevisionScreen> {
  bool _busy = false;
  String? _message;
  late final Future<bool> _allowed;
  @override
  void initState() {
    super.initState();
    _allowed = Supabase.instance.client
        .rpc('is_app_superuser')
        .then((v) => v == true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FeatureRevisionScope.of(context).refresh();
    });
  }

  Future<void> _change(int revision) async {
    final controller = FeatureRevisionScope.of(context);
    final previous = controller.enabledRevision;
    if (_busy || previous == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await Supabase.instance.client.rpc(
        'set_feature_revision',
        params: {'p_revision': revision, 'p_expected_revision': previous},
      );
      if (mounted) {
        setState(() => _message = 'Feature revision changed to $revision.');
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Could not change revision: $e');
    } finally {
      if (mounted) await controller.refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _demo() async {
    final controller = FeatureRevisionScope.of(context);
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final message = await Supabase.instance.client.rpc(
        'feature_revision_demo',
      );
      if (mounted) setState(() => _message = message.toString());
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'The demonstration is unavailable. Refreshing feature status.',
        );
      }
    } finally {
      if (mounted) await controller.refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = FeatureRevisionScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feature releases'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy || controller.loading
                ? null
                : () async {
                    setState(() => _message = null);
                    await controller.refresh();
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<bool>(
        future: _allowed,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data != true) {
            return const Center(child: Text('Superuser access required.'));
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Enabled feature revision: ${controller.enabledRevision ?? "unavailable"}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'Revision 0 keeps existing features available. Revision 1 also enables the demonstration below. This does not change the minimum app version or send messages.',
              ),
              const SizedBox(height: 16),
              if (controller.loading) const LinearProgressIndicator(),
              if (controller.error != null) Text(controller.error!),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton(
                    onPressed:
                        _busy ||
                            controller.enabledRevision == null ||
                            controller.enabledRevision == 0
                        ? null
                        : () => _change(0),
                    child: const Text('Set revision 0'),
                  ),
                  FilledButton(
                    onPressed:
                        _busy ||
                            controller.enabledRevision == null ||
                            controller.enabledRevision == 1
                        ? null
                        : () => _change(1),
                    child: const Text('Set revision 1'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              FeatureRevisionGate(
                revision: 1,
                fallback: const Text(
                  'Demonstration disabled. Requires feature revision 1.',
                ),
                child: FilledButton.icon(
                  onPressed: _busy ? null : _demo,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Test enabled feature'),
                ),
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Text(_message!),
                ),
            ],
          );
        },
      ),
    );
  }
}
