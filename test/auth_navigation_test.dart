import 'dart:async';

import 'package:bowls_saas/features/auth/app_entry_access_service.dart';
import 'package:bowls_saas/features/auth/auth_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const allowed = AppEntryAccess(isSuperuser: false, hasActiveMembership: true);
const denied = AppEntryAccess(isSuperuser: false, hasActiveMembership: false);

Session session({String user = 'member-a', int seconds = 3600}) => Session(
  accessToken: 'test-token',
  tokenType: 'bearer',
  user: User(
    id: user,
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  ),
)..expiresAt = DateTime.now().millisecondsSinceEpoch ~/ 1000 + seconds;

class Harness {
  Session? current;
  final changes = StreamController<AuthState>.broadcast();
  Future<AppEntryAccess> Function() load = () async => allowed;

  void emit(AuthChangeEvent event, Session? value) {
    current = value;
    changes.add(AuthState(event, value));
  }

  Widget build() => AuthNavigationHost(
    readSession: () => current,
    authChanges: changes.stream,
    loadAccess: () => load(),
    onSignOut: () async => emit(AuthChangeEvent.signedOut, null),
    signedOutBuilder: (_) => const Scaffold(
      body: Column(
        children: [
          Text('Sign in'),
          TextField(key: ValueKey('public-form')),
        ],
      ),
    ),
    signedInBuilder: (_) => const _Home(),
    recoveryBuilder: (_, complete) => Scaffold(
      body: Column(
        children: [
          const Text('Recovery only'),
          const TextField(key: ValueKey('recovery-form')),
          TextButton(
            onPressed: complete,
            child: const Text('Complete recovery'),
          ),
        ],
      ),
    ),
  );
}

class _Home extends StatelessWidget {
  const _Home();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        const Text('Member home'),
        TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (pageContext) => Scaffold(
                body: Column(
                  children: [
                    const Text('Private fixture'),
                    const TextField(key: ValueKey('fixture-edit')),
                    TextButton(
                      onPressed: () => showDialog<void>(
                        context: pageContext,
                        builder: (_) =>
                            const AlertDialog(content: Text('Private dialog')),
                      ),
                      child: const Text('Open dialog'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          child: const Text('Open fixture'),
        ),
      ],
    ),
  );
}

void main() {
  late Harness h;
  setUp(() => h = Harness());
  tearDown(() => h.changes.close());

  testWidgets('public and recovery forms survive returning from email', (
    t,
  ) async {
    await t.pumpWidget(h.build());
    await t.enterText(
      find.byKey(const ValueKey('public-form')),
      'member@example.com',
    );
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(find.text('member@example.com'), findsOneWidget);
    h.emit(AuthChangeEvent.passwordRecovery, session());
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('recovery-form')),
      'new-password',
    );
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(find.text('new-password'), findsOneWidget);
    expect(find.text('Member home'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('signed-out and expired sessions cannot mount member pages', (
    t,
  ) async {
    await t.pumpWidget(h.build());
    await t.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
    h.emit(AuthChangeEvent.initialSession, session(seconds: -1));
    await t.pumpAndSettle();
    expect(find.text('Member home'), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('sign-out removes pushed pages and dialogs; login starts fresh', (
    t,
  ) async {
    h.current = session();
    await t.pumpWidget(h.build());
    await t.pumpAndSettle();
    await t.tap(find.text('Open fixture'));
    await t.pumpAndSettle();
    await t.tap(find.text('Open dialog'));
    await t.pumpAndSettle();
    h.emit(AuthChangeEvent.signedOut, null);
    await t.pumpAndSettle();
    expect(find.text('Private dialog'), findsNothing);
    expect(find.text('Private fixture'), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
    h.emit(AuthChangeEvent.signedIn, session());
    await t.pumpAndSettle();
    expect(find.text('Member home'), findsOneWidget);
    expect(find.text('Private fixture'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('switching accounts clears the previous navigation stack', (
    t,
  ) async {
    h.current = session();
    await t.pumpWidget(h.build());
    await t.pumpAndSettle();
    await t.tap(find.text('Open fixture'));
    await t.pumpAndSettle();
    h.emit(AuthChangeEvent.signedIn, session(user: 'member-b'));
    await t.pumpAndSettle();
    expect(find.text('Private fixture'), findsNothing);
    expect(find.text('Member home'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('refresh preserves navigation and stream errors are handled', (
    t,
  ) async {
    h.current = session();
    await t.pumpWidget(h.build());
    await t.pumpAndSettle();
    await t.tap(find.text('Open fixture'));
    await t.pumpAndSettle();
    h.emit(AuthChangeEvent.tokenRefreshed, session(seconds: 7200));
    h.changes.addError(StateError('offline'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('Private fixture'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('expiry removes protected routes without another auth event', (
    t,
  ) async {
    h.current = session(seconds: 5);
    await t.pumpWidget(h.build());
    await t.pumpAndSettle();
    await t.tap(find.text('Open fixture'));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 6));
    await t.pumpAndSettle();
    expect(find.text('Private fixture'), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('membership denial blocks every member page and supports retry', (
    t,
  ) async {
    h.current = session();
    h.load = () async => denied;
    await t.pumpWidget(h.build());
    await t.pumpAndSettle();
    expect(find.text('Membership inactive'), findsOneWidget);
    expect(find.text('Member home'), findsNothing);
    h.load = () async => allowed;
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(find.text('Member home'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('membership failures fail closed and allow sign-out', (t) async {
    h.current = session();
    h.load = () async => throw StateError('offline');
    await t.pumpWidget(h.build());
    await t.pumpAndSettle();
    expect(find.text('Unable to verify membership'), findsOneWidget);
    expect(find.text('Member home'), findsNothing);
    await t.tap(find.text('Sign out'));
    await t.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('late membership response cannot restore signed-out access', (
    t,
  ) async {
    h.current = session();
    final pending = Completer<AppEntryAccess>();
    h.load = () => pending.future;
    await t.pumpWidget(h.build());
    await t.pump();
    h.emit(AuthChangeEvent.signedOut, null);
    await t.pumpAndSettle();
    pending.complete(allowed);
    await t.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Member home'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('recovery stays isolated until explicitly completed', (t) async {
    await t.pumpWidget(h.build());
    h.emit(AuthChangeEvent.passwordRecovery, session());
    await t.pumpAndSettle();
    expect(find.text('Recovery only'), findsOneWidget);
    expect(find.text('Member home'), findsNothing);
    h.emit(AuthChangeEvent.tokenRefreshed, session());
    h.emit(AuthChangeEvent.userUpdated, session());
    await t.pumpAndSettle();
    expect(find.text('Recovery only'), findsOneWidget);
    await t.tap(find.text('Complete recovery'));
    await t.pumpAndSettle();
    expect(find.text('Member home'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'focus return preserves routes, edits and dialogs after access check',
    (t) async {
      h.current = session();
      await t.pumpWidget(h.build());
      await t.pumpAndSettle();
      await t.tap(find.text('Open fixture'));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('fixture-edit')),
        'unsaved team edit',
      );
      await t.tap(find.text('Open dialog'));
      await t.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        final pending = Completer<AppEntryAccess>();
        var checks = 0;
        h.load = () {
          checks++;
          return pending.future;
        };
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await t.pump();
        expect(checks, 1);
        expect(find.text('Private dialog'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        pending.complete(allowed);
        await t.pumpAndSettle();
        expect(find.text('Private dialog'), findsOneWidget);
      }
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();
      expect(find.text('Private fixture'), findsOneWidget);
      expect(find.text('unsaved team edit'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('failed resume check removes routes and retry starts fresh', (
    t,
  ) async {
    h.current = session();
    await t.pumpWidget(h.build());
    await t.pumpAndSettle();
    await t.tap(find.text('Open fixture'));
    await t.pumpAndSettle();
    h.load = () async => throw StateError('offline');
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(find.text('Unable to verify membership'), findsOneWidget);
    expect(find.text('Private fixture', skipOffstage: false), findsNothing);
    h.load = () async => allowed;
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(find.text('Member home'), findsOneWidget);
    expect(find.text('Private fixture'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('resume rechecks membership before rebuilding protected pages', (
    t,
  ) async {
    h.current = session();
    await t.pumpWidget(h.build());
    await t.pumpAndSettle();
    await t.tap(find.text('Open fixture'));
    await t.pumpAndSettle();
    h.load = () async => denied;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(find.text('Private fixture'), findsNothing);
    expect(find.text('Membership inactive'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
