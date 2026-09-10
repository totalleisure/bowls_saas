import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_screen.dart';
import '../clubs/my_clubs_screen.dart';
import 'app_entry_access_service.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) return const AuthScreen();
        return AuthenticatedMembershipBoundary(
          key: ValueKey(session.accessToken),
          loadAccess: AppEntryAccessService().load,
          onSignOut: Supabase.instance.client.auth.signOut,
          child: const MyClubsScreen(),
        );
      },
    );
  }
}

class AuthenticatedMembershipBoundary extends StatefulWidget {
  final Future<AppEntryAccess> Function() loadAccess;
  final Future<void> Function() onSignOut;
  final Widget child;

  const AuthenticatedMembershipBoundary({
    super.key,
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

  @override
  void initState() {
    super.initState();
    _access = widget.loadAccess();
  }

  void _retry() {
    setState(() => _access = widget.loadAccess());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppEntryAccess>(
      future: _access,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return _AccessMessagePage(
            title: 'Unable to verify membership',
            message: 'Your membership could not be checked. Please try again.',
            onRetry: _retry,
            onSignOut: widget.onSignOut,
          );
        }

        if (snapshot.data?.allowed != true) {
          return _AccessMessagePage(
            title: 'Membership inactive',
            message:
                'Your membership is inactive. Please contact your club administrator.',
            onRetry: _retry,
            onSignOut: widget.onSignOut,
          );
        }

        return widget.child;
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
