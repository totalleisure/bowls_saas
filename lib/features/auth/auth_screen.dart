import 'package:intl/intl.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../clubs/my_clubs_screen.dart';
import '../../core/utils/date_format.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;

  List<Map<String, dynamic>> _debugUsers = [];
  bool _loadingDebugUsers = false;
  String? _debugError;

  String _debugSearch = '';

  static const String _debugPassword = 'password';

  @override
  void initState() {
    super.initState();
    debugPrint('kDebugMode: $kDebugMode');
    debugPrint('kProfileMode: $kProfileMode');
    debugPrint('kReleaseMode: $kReleaseMode');    
    if (kDebugMode) {
      _loadDebugUsers();
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _loadDebugUsers() async {
    if (!kDebugMode) return;

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Quick sign in error: $e')),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign up error: $e')),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign in error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildDebugQuickLoginList() {
    if (!kDebugMode) return const SizedBox.shrink();

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
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            if (_loading) const CircularProgressIndicator(),
            if (!_loading) ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _signIn,
                      child: const Text('Sign in'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _signUp,
                      child: const Text('Sign up'),
                    ),
                  ),
                ],
              ),
              _buildDebugQuickLoginList(),
            ],
          ],
        ),
      ),
    );
  }
}


