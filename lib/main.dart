import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'secrets.dart';
import 'App/app.dart';
import 'services/app_version_policy_service.dart';

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

  final policyService = AppVersionPolicyService.supabase();
  final versionPolicy = await policyService.load();

  runApp(
    BowlsVersionGate(
      versionPolicy: versionPolicy,
      reloadPolicy: policyService.load,
    ),
  );
}

class BowlsVersionGate extends StatefulWidget {
  final AppVersionPolicy versionPolicy;
  final Future<AppVersionPolicy> Function()? reloadPolicy;
  final Future<bool> Function(Uri uri)? launchExternal;

  const BowlsVersionGate({
    super.key,
    required this.versionPolicy,
    this.reloadPolicy,
    this.launchExternal,
  });

  @override
  State<BowlsVersionGate> createState() => _BowlsVersionGateState();
}

class _BowlsVersionGateState extends State<BowlsVersionGate> {
  late AppVersionPolicy _policy;
  bool _reloading = false;
  String? _launchError;

  @override
  void initState() {
    super.initState();
    _policy = widget.versionPolicy;
  }

  Future<void> _reload() async {
    final loader = widget.reloadPolicy;
    if (loader == null || _reloading) return;

    setState(() {
      _reloading = true;
      _launchError = null;
    });

    final policy = await loader();
    if (!mounted) return;

    setState(() {
      _policy = policy;
      _reloading = false;
    });
  }

  Future<void> _openUpdate() async {
    final uri = _policy.updateUri;
    if (uri == null ||
        AppVersionPolicyService.validUpdateUri(uri.toString()) == null) {
      return;
    }

    setState(() => _launchError = null);

    try {
      final launched =
          await (widget.launchExternal?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.externalApplication));
      if (!launched && mounted) {
        setState(() {
          _launchError =
              'The update page could not be opened. Please try again.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _launchError =
              'The update page could not be opened. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_policy.blocked) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: UpdateRequiredPage(
          policy: _policy,
          reloading: _reloading,
          launchError: _launchError,
          onUpdate: _policy.updateUri == null ? null : _openUpdate,
          onTryAgain: widget.reloadPolicy == null ? null : _reload,
        ),
      );
    }

    return const BowlsApp();
  }
}

class UpdateRequiredPage extends StatelessWidget {
  final AppVersionPolicy policy;
  final bool reloading;
  final String? launchError;
  final VoidCallback? onUpdate;
  final VoidCallback? onTryAgain;

  const UpdateRequiredPage({
    super.key,
    required this.policy,
    this.reloading = false,
    this.launchError,
    this.onUpdate,
    this.onTryAgain,
  });

  @override
  Widget build(BuildContext context) {
    final displayMessage = policy.updateMessage?.trim().isNotEmpty == true
        ? policy.updateMessage!.trim()
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
                const SizedBox(height: 16),
                Text(
                  'Installed build: ${policy.installedBuild}\n'
                  'Required build: ${policy.minimumBuild}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                if (onUpdate != null)
                  FilledButton.icon(
                    onPressed: onUpdate,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Update now'),
                  )
                else
                  const Text(
                    'An update download link is not available yet. '
                    'Please contact your club administrator for assistance.',
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: reloading ? null : onTryAgain,
                  icon: reloading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
                if (launchError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    launchError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
