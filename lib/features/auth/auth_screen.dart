import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../help/player_help_screen.dart';

import '../clubs/my_clubs_screen.dart';
import '../../core/utils/date_format.dart';

import 'register_screen.dart';

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
  bool _loading = false;
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
    TextInputType? keyboardType,
    double height = 50,
  }) {
    return SizedBox(
      height: height,
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        style: const TextStyle(
          color: Color(0xFF0D47A1),
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: hintText,
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
      if (!mounted) return;
      setState(() {
        _loadingDebugUsers = false;
      });
    }
  }

  Future<void> _quickSignIn(String email) async {
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: _debugPassword,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Quick sign in error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Sign up error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signIn() async {
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Sign in error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildOverlayField(
                            controller: _email,
                            hintText: 'Username',
                            keyboardType: TextInputType.emailAddress,
                            height: fieldHeight,
                          ),
                          const SizedBox(height: 12),
                          _buildOverlayField(
                            controller: _password,
                            hintText: 'Password',
                            obscureText: true,
                            height: fieldHeight,
                          ),
                          const SizedBox(height: 14),
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
                          const SizedBox(height: 10),
                          Center(
                            child: TextButton(
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
                                'Need Help?',
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
