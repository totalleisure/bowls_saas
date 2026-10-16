import 'dart:convert';
import 'package:bowls_saas/features/auth/auth_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:bowls_saas/features/auth/login_autofill_group.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var accept = true;
  const savedLoginChannel = MethodChannel('bowls/saved_login');
  final savedCalls = <MethodCall>[];
  var authRequests = 0;
  String? pickerError;
  setUp(() async {
    savedCalls.clear();
    authRequests = 0;
    pickerError = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(savedLoginChannel, (call) async {
          savedCalls.add(call);
          if (call.method == 'get') {
            if (pickerError != null) {
              throw PlatformException(code: pickerError!);
            }
            return {
              'identifier': 'saved@example.test',
              'password': 'saved-test-password',
            };
          }
          return true;
        });
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'test',
      packageName: 'test',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    );
    accept = true;
    await Supabase.initialize(
      url: 'https://test.invalid',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        authRequests++;
        if (!accept) {
          return http.Response(
            jsonEncode({
              'error_code': 'invalid_credentials',
              'msg': 'Invalid login credentials',
            }),
            400,
          );
        }
        final expires = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
        String part(Object value) => base64Url
            .encode(utf8.encode(jsonEncode(value)))
            .replaceAll('=', '');
        return http.Response(
          jsonEncode({
            'access_token':
                '${part({'alg': 'HS256'})}.${part({'exp': expires, 'sub': 'test-user'})}.signature',
            'refresh_token': 'test-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': 'test-user',
              'app_metadata': {},
              'user_metadata': {},
              'aud': 'authenticated',
              'created_at': '2026-01-01T00:00:00Z',
            },
          }),
          200,
        );
      }),
    );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(savedLoginChannel, null);
    await Supabase.instance.dispose();
  });

  Future<void> showLogin(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: StreamBuilder<AuthState>(
          stream: Supabase.instance.client.auth.onAuthStateChange,
          builder: (context, state) => state.data?.session == null
              ? const AuthScreen()
              : const Scaffold(body: Text('Signed in')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
  }

  testWidgets('Windows manual sign-in offers saving only after success', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await showLogin(tester);
    await tester.enterText(find.byType(TextField).first, 'member@example.test');
    await tester.enterText(find.byType(TextField).last, 'new-test-password');
    expect(savedCalls, isEmpty);
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();
    expect(find.text('Signed in'), findsOneWidget);
    expect(savedCalls, hasLength(1));
    expect(savedCalls.single.method, 'save');
    expect(savedCalls.single.arguments['resource'], isNotEmpty);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows rejected sign-in never saves', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    accept = false;
    await showLogin(tester);
    await tester.enterText(find.byType(TextField).first, 'member@example.test');
    await tester.enterText(find.byType(TextField).last, 'wrong-password');
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();
    expect(savedCalls, isEmpty);
    expect(find.byType(AlertDialog), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows saved login signs in without another save offer', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await showLogin(tester);
    await tester.tap(find.text('Use saved login'));
    await tester.pumpAndSettle();
    expect(find.text('Signed in'), findsOneWidget);
    expect(savedCalls, hasLength(1));
    expect(savedCalls.single.method, 'get');
    expect(savedCalls.single.arguments['resource'], isNotEmpty);
    debugDefaultTargetPlatformOverride = null;
  });

  bool saveRequested(WidgetTester tester) => tester.testTextInput.log.any(
    (call) =>
        call.method == 'TextInput.finishAutofillContext' &&
        call.arguments == true,
  );

  void appleFill(WidgetTester tester, {bool passwordOnly = false}) {
    final fields = tester.testTextInput.setClientArgs!['fields'] as List;
    final scope = tester.state<AutofillGroupState>(
      find.byType(LoginAutofillGroup),
    );
    for (var i = passwordOnly ? 1 : 0; i < fields.length; i++) {
      final id = (fields[i] as Map)['autofill']['uniqueIdentifier'] as String;
      scope
          .getAutofillClient(id)!
          .autofill(
            TextEditingValue(
              text: i == 0 ? 'apple@example.test' : 'apple-saved-password',
            ),
          );
    }
  }

  testWidgets('Apple manual login commits once without a later cancellation', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await showLogin(tester);
    await tester.enterText(find.byType(TextField).first, 'first@example.test');
    await tester.enterText(find.byType(TextField).last, 'first-test-password');
    tester.testTextInput.log.clear();
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();
    expect(find.text('Signed in'), findsOneWidget);
    final finishes = tester.testTextInput.log
        .where((call) => call.method == 'TextInput.finishAutofillContext')
        .map((call) => call.arguments).toList();
    expect(finishes, equals([true]), reason: 'Successful manual login must not cancel the native save request during disposal.');

    expect(finishes.where((value) => value == true), hasLength(1));
    expect(savedCalls, isEmpty, reason: 'Apple uses system AutoFill, not the Android bridge.');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Apple rejected login cancels on exit without saving', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    accept = false;
    await showLogin(tester);
    await tester.enterText(find.byType(TextField).first, 'failed@example.test');
    await tester.enterText(find.byType(TextField).last, 'wrong-password');
    tester.testTextInput.log.clear();
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(saveRequested(tester), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final finishes = tester.testTextInput.log
        .where((call) => call.method == 'TextInput.finishAutofillContext')
        .map((call) => call.arguments).toList();
    expect(finishes, equals([false]));
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('Apple paired AutoFill signs in once; typing does not', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await showLogin(tester);
    await tester.enterText(find.byType(TextField).first, 'manual@example.test');
    await tester.enterText(find.byType(TextField).last, 'manual-password');
    await tester.pumpAndSettle();
    expect(authRequests, 0);
    appleFill(tester);
    await tester.pumpAndSettle();
    expect(authRequests, 1);
    expect(find.text('Signed in'), findsOneWidget);
    expect(saveRequested(tester), isFalse);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'Apple incomplete fill remains manual; failed full fill can be corrected',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      accept = false;
      await showLogin(tester);
      appleFill(tester, passwordOnly: true);
      await tester.pumpAndSettle();
      expect(authRequests, 0);
      appleFill(tester);
      await tester.pumpAndSettle();
      expect(authRequests, 1);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextButton),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'corrected-apple-password',
      );
      await tester.pumpAndSettle();
      expect(authRequests, 1);
      accept = true;
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();
      expect(authRequests, 2);
      expect(find.text('Signed in'), findsOneWidget);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'platform sees paired login fields and saves only after successful login',
    (tester) async {
      await showLogin(tester);
      final configuration = tester.testTextInput.setClientArgs!;
      final fields = configuration['fields'] as List;
      expect(fields.length, 2);
      final hints = fields
          .map((field) => (field as Map)['autofill']['hints'] as List)
          .toList();
      expect(hints[0], contains(AutofillHints.username));
      expect(hints[1], contains(AutofillHints.password));
      await tester.enterText(
        find.byType(TextField).first,
        'tester@example.test',
      );
      await tester.enterText(find.byType(TextField).last, 'test-only-password');
      tester.testTextInput.log.clear();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Signed in'), findsOneWidget);
      expect(savedCalls.where((call) => call.method == 'save').length, 1);
      expect(
        (savedCalls.last.arguments as Map)['identifier'],
        'tester@example.test',
      );
      expect(saveRequested(tester), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed login and leaving the form do not request password saving',
    (tester) async {
      accept = false;
      await showLogin(tester);
      await tester.enterText(
        find.byType(TextField).first,
        'tester@example.test',
      );
      await tester.enterText(
        find.byType(TextField).last,
        'wrong-test-password',
      );
      tester.testTextInput.log.clear();
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();
      expect(saveRequested(tester), isFalse);
      expect(savedCalls.where((call) => call.method == 'save'), isEmpty);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      expect(saveRequested(tester), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('saved-login selection signs in once without resaving', (
    tester,
  ) async {
    await showLogin(tester);
    await tester.tap(find.text('Use saved login'));
    await tester.pumpAndSettle();
    expect(authRequests, 1);
    expect(find.text('Signed in'), findsOneWidget);
    expect(savedCalls.where((call) => call.method == 'save'), isEmpty);
    expect(saveRequested(tester), isFalse);
  });

  testWidgets('failed saved password permits corrected manual sign in', (
    tester,
  ) async {
    accept = false;
    await showLogin(tester);
    await tester.tap(find.text('Use saved login'));
    await tester.pumpAndSettle();
    expect(authRequests, 1);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(savedCalls.where((call) => call.method == 'save'), isEmpty);
    await tester.tap(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextButton),
          )
          .first,
    );
    await tester.pumpAndSettle();
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields.first.controller!.text, 'saved@example.test');
    expect(fields.last.obscureText, isTrue);
    await tester.enterText(find.byType(TextField).last, 'corrected-password');
    accept = true;
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();
    expect(authRequests, 2);
    expect(find.text('Signed in'), findsOneWidget);
    expect(savedCalls.where((call) => call.method == 'save').length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cancelled picker retains manual entries and never submits login',
    (tester) async {
      await showLogin(tester);
      await tester.enterText(
        find.byType(TextField).first,
        'manual@example.test',
      );
      pickerError = 'cancelled';
      await tester.tap(find.text('Use saved login'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'manual@example.test',
      );
      expect(authRequests, 0);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets('no matching login explains manual save and keeps login usable', (
    tester,
  ) async {
    await showLogin(tester);
    pickerError = 'no_credentials';
    await tester.tap(find.text('Use saved login'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No saved login matched'), findsOneWidget);
    expect(authRequests, 0);
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Sign In'),
          )
          .onPressed,
      isNotNull,
    );
  });
}
