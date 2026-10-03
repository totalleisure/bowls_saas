import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_screen.dart';
import 'reset_password_screen.dart';
import '../clubs/my_clubs_screen.dart';
import 'app_entry_access_service.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    return AuthNavigationHost(
      readSession: () => client.auth.currentSession,
      authChanges: client.auth.onAuthStateChange,
      loadAccess: AppEntryAccessService(client).load,
      onSignOut: client.auth.signOut,
      signedOutBuilder: (_) => const AuthScreen(),
      signedInBuilder: (_) => const MyClubsScreen(),
      recoveryBuilder: (_, complete) =>
          ResetPasswordScreen(onComplete: complete),
    );
  }
}

/// Owns the entire Navigator, including pushed pages and dialogs. Database
/// authorization remains enforced by Supabase RLS and server-side checks.
class AuthNavigationHost extends StatefulWidget {
  const AuthNavigationHost({
    super.key,
    required this.readSession,
    required this.authChanges,
    required this.loadAccess,
    required this.onSignOut,
    required this.signedOutBuilder,
    required this.signedInBuilder,
    required this.recoveryBuilder,
  });

  final Session? Function() readSession;
  final Stream<AuthState> authChanges;
  final Future<AppEntryAccess> Function() loadAccess;
  final Future<void> Function() onSignOut;
  final WidgetBuilder signedOutBuilder;
  final WidgetBuilder signedInBuilder;
  final Widget Function(BuildContext, VoidCallback) recoveryBuilder;

  @override
  State<AuthNavigationHost> createState() => _AuthNavigationHostState();
}

class _AuthNavigationHostState extends State<AuthNavigationHost>
    with WidgetsBindingObserver {
  late final StreamSubscription<AuthState> _subscription;
  Timer? _expiryTimer;
  Session? _session;
  bool _expired = true;
  bool _recovering = false;
  int _navigationGeneration = 0;
  int _membershipRevision = 0;

  String get _identity => _session == null || _expired
      ? 'signed-out'
      : '${_session!.user.id}:${_recovering ? 'recovery' : 'member'}';

  @override
  void initState() {
    super.initState();
    _session = widget.readSession();
    _scheduleExpiry();
    WidgetsBinding.instance.addObserver(this);
    _subscription = widget.authChanges.listen(
      _onAuthChange,
      // A transient refresh failure must not crash the app. The expiry timer
      // still removes protected navigation if no valid token arrives.
      onError: (Object error, StackTrace stack) {
        if (!mounted) return;
        setState(() {
          final previous = _identity;
          _scheduleExpiry();
          if (previous != _identity) _navigationGeneration++;
        });
      },
    );
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    final expiresAt = _session?.expiresAt;
    final remaining = expiresAt == null
        ? Duration.zero
        : DateTime.fromMillisecondsSinceEpoch(
            expiresAt * 1000,
          ).difference(DateTime.now());
    _expired = remaining <= Duration.zero;
    if (!_expired) {
      _expiryTimer = Timer(remaining, () {
        if (!mounted) return;
        setState(() {
          _expired = true;
          _navigationGeneration++;
        });
      });
    }
  }

  void _onAuthChange(AuthState state) {
    if (!mounted) return;
    setState(() {
      final previous = _identity;
      final previousUser = _session?.user.id;
      _session = state.event == AuthChangeEvent.signedOut
          ? null
          : state.session;
      if (_session == null ||
          previousUser != _session?.user.id ||
          state.event == AuthChangeEvent.signedIn) {
        _recovering = false;
      }
      if (state.event == AuthChangeEvent.passwordRecovery) _recovering = true;
      _scheduleExpiry();
      if (previous != _identity) _navigationGeneration++;
    });
  }

  void _completeRecovery() {
    setState(() {
      _recovering = false;
      _navigationGeneration++;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    setState(() {
      final previous = _identity;
      _session = widget.readSession();
      _scheduleExpiry();
      // Keep public registration/recovery forms when returning from email.
      if (previous != _identity) {
        _navigationGeneration++;
      } else if (_session != null && !_expired && !_recovering) {
        // Recheck access without destroying the current routes or edits.
        _membershipRevision++;
      }
    });
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _subscription.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authenticated = _session != null && !_expired;
    final protected = authenticated && !_recovering;
    return MaterialApp(
      key: ValueKey(_navigationGeneration),
      debugShowCheckedModeBanner: false,
      title: 'Bowls SaaS',
      theme: ThemeData(useMaterial3: true),
      // Ignore external route names: entry always passes through this gate.
      initialRoute: '/',
      home: Builder(
        builder: (context) {
          if (!authenticated) return widget.signedOutBuilder(context);
          if (_recovering) {
            return widget.recoveryBuilder(context, _completeRecovery);
          }
          return widget.signedInBuilder(context);
        },
      ),
      builder: (context, navigator) {
        if (!protected) return navigator!;
        return AuthenticatedMembershipBoundary(
          revision: _membershipRevision,
          loadAccess: widget.loadAccess,
          onSignOut: widget.onSignOut,
          child: navigator!,
        );
      },
    );
  }
}

class AuthenticatedMembershipBoundary extends StatefulWidget {
  final int revision;
  final Future<AppEntryAccess> Function() loadAccess;
  final Future<void> Function() onSignOut;
  final Widget child;

  const AuthenticatedMembershipBoundary({
    super.key,
    this.revision = 0,
    required this.loadAccess,
    required this.onSignOut,
    required this.child,
  });

  @override
  State<AuthenticatedMembershipBoundary> createState() =>
      _AuthenticatedMembershipBoundaryState();
}

class _AuthenticatedMembershipBoundaryState
    extends State<AuthenticatedMembershipBoundary> {
  late Future<AppEntryAccess> _access;
  bool _retainNavigation = false;

  @override
  void didUpdateWidget(AuthenticatedMembershipBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) {
      _access = widget.loadAccess();
    }
  }

  @override
  void initState() {
    super.initState();
    _access = widget.loadAccess();
  }

  void _retry() {
    setState(() {
      _access = widget.loadAccess();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppEntryAccess>(
      future: _access,
      builder: (context, snapshot) {
        final pending = snapshot.connectionState != ConnectionState.done;
        final allowed =
            !pending && !snapshot.hasError && snapshot.data?.allowed == true;
        if (!pending) _retainNavigation = allowed;

        // Keep the Navigator mounted while checking the same identity. Hide
        // its content and disable focus until access is confirmed. Denial or
        // failure disposes it; identity changes reset it in the parent host.
        return Stack(
          fit: StackFit.expand,
          children: [
            Offstage(
              offstage: !allowed,
              child: ExcludeFocus(
                excluding: !allowed,
                child: TickerMode(
                  enabled: allowed,
                  child: _retainNavigation ? widget.child : const SizedBox(),
                ),
              ),
            ),
            if (pending)
              const Scaffold(body: Center(child: CircularProgressIndicator()))
            else if (snapshot.hasError)
              _AccessMessagePage(
                title: 'Unable to verify membership',
                message:
                    'Your membership could not be checked. Please try again.',
                onRetry: _retry,
                onSignOut: widget.onSignOut,
              )
            else if (!allowed)
              _AccessMessagePage(
                title: 'Membership inactive',
                message:
                    'Your membership is inactive. Please contact your club administrator.',
                onRetry: _retry,
                onSignOut: widget.onSignOut,
              ),
          ],
        );
      },
    );
  }
}

class _AccessMessagePage extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onRetry;
  final Future<void> Function() onSignOut;

  const _AccessMessagePage({
    required this.title,
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 56),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
              TextButton(onPressed: onSignOut, child: const Text('Sign out')),
            ],
          ),
        ),
      ),
    );
  }
}
