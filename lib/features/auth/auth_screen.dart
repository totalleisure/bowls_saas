import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../help/player_help_screen.dart';

import '../clubs/my_clubs_screen.dart';
import '../../core/utils/date_format.dart';

import 'register_screen.dart';
import 'forgot_password_screen.dart';
import 'password_recovery_progress.dart';
import 'auth_failure_policy.dart';
import 'account_username_service.dart';
import 'saved_login_service.dart';
import 'login_autofill_group.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  static const bool kShowDebugQuickLogins = bool.fromEnvironment(
    'QUICK_LOGINS',
    defaultValue: false,
  );

  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  bool _selectingSavedLogin = false;
  bool _selectedSavedLogin = false;
  bool _saveAppleLoginOnDispose = false;
  int _appleLoginGeneration = 0;
  String _version = '';
  String _buildNumber = '';
  int _brandingSetNo = 0;

  List<Map<String, dynamic>> _debugUsers = [];
  bool _loadingDebugUsers = false;
  String? _debugError;

  String _debugSearch = '';

  static const String _debugPassword = 'password';

  String _backgroundImageForWidth(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = size.width;
    final shortestSide = size.shortestSide;

    final requested = _brandingSetNo;

    String fileName;

    if (width >= 1000) {
      fileName = 'auth_bg_desktop_$requested.png';
    } else if (shortestSide >= 600) {
      fileName = 'auth_bg_tablet_$requested.png';
    } else {
      fileName = 'auth_bg_phone_$requested.png';
    }

    final assetPath = 'assets/images/$fileName';

    // TEMPORARY FALLBACKS
    const existingBrandingSets = {0, 2};

    if (!existingBrandingSets.contains(requested)) {
      if (width >= 1000) {
        return 'assets/images/auth_bg_desktop_0.png';
      } else if (shortestSide >= 600) {
        return 'assets/images/auth_bg_tablet_0.png';
      } else {
        return 'assets/images/auth_bg_phone_0.png';
      }
    }

    return assetPath;
  }

  Widget _buildOverlayField({
    required TextEditingController controller,
    required String hintText,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    double height = 50,
    Iterable<String>? autofillHints,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
    bool autofocus = false,
  }) {
    return SizedBox(
      height: height,
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        obscureText: obscureText,
        keyboardType: keyboardType,
        autofillHints: autofillHints,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        onChanged: (_) => _selectedSavedLogin = false,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        style: const TextStyle(
          color: Color(0xFF0D47A1),
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          suffixIcon: suffixIcon,
          hintStyle: TextStyle(
            color: Colors.blue.shade800.withOpacity(0.75),
            fontWeight: FontWeight.w600,
          ),
          filled: true,
          fillColor: Colors.white.withOpacity(0.92),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFBFD8F7), width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFBFD8F7), width: 2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF1565C0), width: 2),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlayButton({
    required String label,
    required VoidCallback? onTap,
    required Color backgroundColor,
    required Color textColor,
    required Color borderColor,
    double height = 52,
  }) {
    return SizedBox(
      height: height,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          elevation: 6,
          backgroundColor: backgroundColor,
          foregroundColor: textColor,
          disabledBackgroundColor: backgroundColor.withOpacity(0.65),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(color: borderColor, width: 3),
          ),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            fontStyle: FontStyle.italic,
          ),
        ),
        child: Text(label),
      ),
    );
  }

  Widget _buildStyledField({
    required TextEditingController controller,
    required String hintText,
    bool obscureText = false,
    TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            blurRadius: 10,
            color: Colors.black26,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          hintText: hintText,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.transparent,
        ),
      ),
    );
  }

  Widget _buildPrimaryActionButton({
    required String label,
    required VoidCallback onTap,
    required Color background,
    required Color foreground,
    required Color borderColor,
  }) {
    return SizedBox(
      height: 64,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          elevation: 6,
          backgroundColor: background,
          foregroundColor: foreground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
            side: BorderSide(color: borderColor, width: 3),
          ),
          textStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            fontStyle: FontStyle.italic,
          ),
        ),
        child: Text(label),
      ),
    );
  }

  Widget _buildSecondaryActionButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 64,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white.withOpacity(0.92),
          foregroundColor: const Color(0xFF0D47A1),
          side: const BorderSide(color: Color(0xFF1565C0), width: 3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
          ),
          textStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            fontStyle: FontStyle.italic,
          ),
        ),
        child: Text(label),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadAppInfo();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resumePasswordRecovery());
    _loadRememberedBranding();
    //    debugPrint('kDebugMode: $kDebugMode');
    //    debugPrint('kProfileMode: $kProfileMode');
    //    debugPrint('kReleaseMode: $kReleaseMode');
    if (!kShowDebugQuickLogins) return;
    _loadDebugUsers();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _loadAppInfo() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _version = info.version;
      _buildNumber = info.buildNumber;
    });
  }

  Future<void> _loadRememberedBranding() async {
    final prefs = await SharedPreferences.getInstance();

    final brandingSetNo = prefs.getInt('last_branding_set_no') ?? 0;

    if (!mounted) return;

    setState(() {
      _brandingSetNo = brandingSetNo;
    });
  }

  Future<void> _loadDebugUsers() async {
    if (!kShowDebugQuickLogins) return;

    setState(() {
      _loadingDebugUsers = true;
      _debugError = null;
    });

    try {
      final rows = await Supabase.instance.client
          .from('debug_login_users')
          .select('display_name, email, sort_order, is_enabled')
          .eq('is_enabled', true)
          .order('sort_order', ascending: true)
          .order('display_name', ascending: true);

      if (!mounted) return;
      setState(() {
        _debugUsers = List<Map<String, dynamic>>.from(rows);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _debugError = '$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingDebugUsers = false;
        });
      }
    }
  }

  bool _looksLikeConnectionFailure(Object error) {
    final text = error.toString().toLowerCase();

    return text.contains('authretryablefetchexception') ||
        text.contains('failed host lookup') ||
        text.contains('socketexception') ||
        text.contains('no address associated with hostname') ||
        text.contains('network is unreachable') ||
        text.contains('connection timed out') ||
        text.contains('connection timeout') ||
        text.contains('connection refused') ||
        text.contains('connection closed') ||
        text.contains('clientexception') ||
        text.contains('failed to fetch');
  }

  String _friendlyAuthMessage(Object error, {required bool signingUp}) {
    final text = error.toString().toLowerCase();

    if (_looksLikeConnectionFailure(error)) {
      return 'The app cannot contact the Bowls Club service. '
          'Please check that Wi-Fi or mobile data is switched on, then try again. '
          'Your account details have not been removed.';
    }

    final invalidCredentials = AuthFailurePolicy.invalidCredentials(error);
    if (invalidCredentials != null) {
      return invalidCredentials.message;
    }

    if (text.contains('email not confirmed')) {
      return 'Your email address has not yet been confirmed. '
          'Please open the confirmation email and follow its link before signing in.';
    }

    if (text.contains('user already registered') ||
        text.contains('already been registered')) {
      return 'An account already exists for this email address. '
          'Please use Sign In instead.';
    }

    if (text.contains('password') &&
        (text.contains('weak') || text.contains('least'))) {
      return 'The password is not strong enough. Please choose a longer password and try again.';
    }

    return signingUp
        ? 'Registration could not be completed. Please check the details and try again.'
        : 'Sign in could not be completed. Please check the details and try again.';
  }

  Future<void> _showAuthFailure({
    required Object error,
    required bool signingUp,
    Future<void> Function()? retry,
  }) async {
    debugPrint('${signingUp ? 'SIGN UP' : 'SIGN IN'} ERROR: $error');

    if (!mounted) return;

    final connectionFailure = _looksLikeConnectionFailure(error);
    final invalidCredentials = AuthFailurePolicy.invalidCredentials(error);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          connectionFailure
              ? Icons.wifi_off_rounded
              : Icons.error_outline_rounded,
          size: 44,
          color: connectionFailure ? Colors.orange.shade800 : Colors.red,
        ),
        title: Text(
          invalidCredentials?.title ??
              (connectionFailure
                  ? 'Unable to connect'
                  : (signingUp
                        ? 'Registration unsuccessful'
                        : 'Sign in unsuccessful')),
        ),
        content: Text(
          _friendlyAuthMessage(error, signingUp: signingUp),
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              invalidCredentials?.actionLabel ??
                  (connectionFailure ? 'Close' : 'Check details'),
            ),
          ),
          if (connectionFailure && retry != null)
            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Future<void>.microtask(retry);
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
        ],
      ),
    );
  }

  Future<void> _quickSignIn(String email) async {
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: _debugPassword,
      );
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      await _showAuthFailure(
        error: e,
        signingUp: false,
        retry: () => _quickSignIn(email),
      );
      return;
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  Future<void> _signUp() async {
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signUp(
        email: _email.text.trim(),
        password: _password.text,
        data: {'display_name': _email.text.trim()},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed up! Now sign in.')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      await _showAuthFailure(error: e, signingUp: true, retry: _signUp);
      return;
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  Future<void> _resumePasswordRecovery() async {
    final progress = await PasswordRecoveryProgress.read();
    if (!mounted || progress == null) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    await _openForgotPassword();
  }

  Future<void> _openForgotPassword() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(
          initialEmail: _email.text.contains('@') ? _email.text.trim() : '',
        ),
      ),
    );
  }

  Future<void> _signIn() async {
    if (_loading || _selectingSavedLogin) return;
    final identifier = _email.text.trim();
    final password = _password.text;
    final appleSavedAttempt = !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS && _selectedSavedLogin;
    setState(() => _loading = true);
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS &&
          !_obscurePassword) {
        // Restore secure native input before authentication can remove this form.
        // Revealing the password changes iOS secureTextEntry; Apple needs the
        // secure field when the verified credential is committed at disposal.
        setState(() => _obscurePassword = true);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }
      await AccountUsernameService(
        Supabase.instance.client,
      ).signIn(identifier, password);
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        // The auth gate removes the login form after success. Finish its native
        // AutoFill context once at disposal; an explicit save followed by the
        // group's cancellation can clear the password while iOS presents it.
        _saveAppleLoginOnDispose = !_selectedSavedLogin;
      } else if (_selectedSavedLogin) {
        TextInput.finishAutofillContext(shouldSave: false);
      } else {
        await SavedLoginService.saveVerified(
          SavedLoginService.windows
              ? Supabase.instance.client.auth.currentUser?.email ?? identifier
              : identifier,
          password,
        );
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      await _showAuthFailure(error: e, signingUp: false, retry: _signIn);
      if (mounted && appleSavedAttempt && e is AuthException &&
          (e.code == 'invalid_credentials' || e.message == 'Invalid login credentials')) {
        // Discard the rejected native credential before the member corrects it.
        // Replacing the group cancels once and gives both fields new native IDs;
        // autofocus then registers a fresh paired context, keeping the username.
        // Never commit the failed password or cancel after a successful commit.
        setState(() {
          _saveAppleLoginOnDispose = false;
          _selectedSavedLogin = false;
          _password.clear();
          _appleLoginGeneration++;
        });
      }
      return;
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  void _appleAutofilled(Set<String> hints) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS ||
        !mounted || _loading || _selectingSavedLogin ||
        ModalRoute.of(context)?.isCurrent != true ||
        !hints.contains(AutofillHints.password) ||
        _password.text.isEmpty) return;
    // iOS may fill only the password when the username is already present.
    // Remember its origin for rejection handling even without auto-submitting.
    _selectedSavedLogin = true;
    if (!hints.contains(AutofillHints.username) || _email.text.trim().isEmpty) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    _signIn();
  }

  Future<void> _useSavedLogin() async {
    if (_loading || _selectingSavedLogin) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _selectingSavedLogin = true);
    var signInWithSelection = false;
    try {
      final login = await SavedLoginService.select();
      if (login == null || !mounted) return;
      setState(() {
        _email.text = login.identifier;
        _password.text = login.password;
        _obscurePassword = true;
        _selectedSavedLogin = true;
      });
      signInWithSelection = true;
    } on PlatformException catch (error) {
      if (mounted && error.code != 'cancelled') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          error.code == 'no_credentials'
              ? 'No saved login matched this app. Sign in manually, then save your login when offered.'
              : 'Your password manager is unavailable. Enter your details manually.')));
      }
    } on MissingPluginException {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Update this app to use the saved-login button.')));
    } finally {
      if (mounted) setState(() => _selectingSavedLogin = false);
    }
    if (signInWithSelection && mounted) await _signIn();
  }

  Widget _buildDebugQuickLoginList() {
    if (!kShowDebugQuickLogins) return const SizedBox.shrink();

    // 👇 filter locally
    final filtered = _debugSearch.trim().isEmpty
        ? _debugUsers
        : _debugUsers.where((u) {
            final name = (u['display_name'] ?? '').toString().toLowerCase();
            final email = (u['email'] ?? '').toString().toLowerCase();
            final q = _debugSearch.toLowerCase();

            return name.contains(q) || email.contains(q);
          }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 12),

        Text(
          'Debug quick login',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        const Text('Tap a member to sign in as them.'),

        const SizedBox(height: 12),

        // 🔍 SEARCH BOX
        TextField(
          decoration: const InputDecoration(
            labelText: 'Search members',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (value) {
            setState(() {
              _debugSearch = value;
            });
          },
        ),

        const SizedBox(height: 12),

        if (_loadingDebugUsers)
          const Center(child: CircularProgressIndicator())
        else if (_debugError != null)
          Text('Error: $_debugError')
        else if (filtered.isEmpty)
          const Text('No matching members.')
        else
          SizedBox(
            height: 260,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final u = filtered[index];

                final name = (u['display_name'] ?? '').toString().trim();
                final email = (u['email'] ?? '').toString().trim();

                return ListTile(
                  dense: true,
                  title: Text(name.isEmpty ? email : name),
                  subtitle: Text(email),
                  trailing: const Icon(Icons.login),
                  onTap: _loading ? null : () => _quickSignIn(email),
                );
              },
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = size.width;
    final height = size.height;

    final isDesktop = width >= 1000;
    final isTablet = width >= 600 && width < 1000;

    final imagePath = _backgroundImageForWidth(context);

    final contentWidth = isDesktop
        ? width * 0.28
        : isTablet
        ? width * 0.62
        : width * 0.82;

    final topOffset = isDesktop
        ? height * 0.58
        : isTablet
        ? height * 0.49
        : height * 0.58;

    final leftOffset = isDesktop ? width * 0.60 : (width - contentWidth) / 2;

    final fieldHeight = isDesktop ? 54.0 : 50.0;
    final buttonHeight = isDesktop ? 56.0 : 52.0;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              imagePath,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),

          Positioned(
            top: 12,
            right: 12,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.28),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'v$_version ($_buildNumber)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              child: SizedBox(
                width: width,
                height: height,
                child: Stack(
                  children: [
                    Positioned(
                      top: topOffset,
                      left: leftOffset,
                      width: contentWidth,
                      child: LoginAutofillGroup(
                        key: ValueKey(_appleLoginGeneration),
                        onAutofilled: _appleAutofilled,
                        shouldSaveOnDispose: () => _saveAppleLoginOnDispose,
                        onDisposeAction: AutofillContextAction.cancel,
                        child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildOverlayField(
                            controller: _email,
                            hintText: AccountUsernameService.enabled
                                ? 'Email or username'
                                : 'Email address',
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.username, AutofillHints.email],
                            textInputAction: TextInputAction.next,
                            height: fieldHeight,
                          ),
                          const SizedBox(height: 12),
                          _buildOverlayField(
                            controller: _password,
                            autofocus: _appleLoginGeneration > 0,
                            hintText: 'Password',
                            obscureText: _obscurePassword,
                            autofillHints: const [AutofillHints.password],
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _signIn(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: _loading ? null : () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            height: fieldHeight,
                          ),
                          const SizedBox(height: 14),
                          if (SavedLoginService.supported) ...[
                            FilledButton.icon(
                              onPressed: _loading || _selectingSavedLogin ? null : _useSavedLogin,
                              icon: const Icon(Icons.key),
                              label: Text(_selectingSavedLogin ? 'Opening password manager…' : 'Use saved login'),
                            ),
                            const SizedBox(height: 12),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: _buildOverlayButton(
                                  label: 'Sign In',
                                  onTap: _loading ? null : _signIn,
                                  backgroundColor: const Color(0xFF0B56C4),
                                  textColor: Colors.white,
                                  borderColor: const Color(0xFF4D8BE6),
                                  height: buttonHeight,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildOverlayButton(
                                  label: 'Register',
                                  onTap: _loading
                                      ? null
                                      : () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const RegisterScreen(),
                                            ),
                                          );
                                        },
                                  backgroundColor: const Color(0xFFF2B600),
                                  textColor: Colors.white,
                                  borderColor: const Color(0xFFFFD54A),
                                  height: buttonHeight,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: _loading
                                    ? null
                                    : _openForgotPassword,
                                child: const Text(
                                  'Forgotten password?',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    shadows: [
                                      Shadow(
                                        blurRadius: 4,
                                        color: Colors.black38,
                                        offset: Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const PlayerHelpScreen(
                                        showAdminGuide: false,
                                      ),
                                    ),
                                  );
                                },
                                child: const Text(
                                  'User Guide',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    shadows: [
                                      Shadow(
                                        blurRadius: 4,
                                        color: Colors.black38,
                                        offset: Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_loading) ...[
                            const SizedBox(height: 12),
                            const Center(child: CircularProgressIndicator()),
                          ],
                          if (kShowDebugQuickLogins) ...[
                            const SizedBox(height: 16),
                            _buildDebugQuickLoginList(),
                          ],
                        ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
