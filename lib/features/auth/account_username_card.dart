import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'account_username_service.dart';

class AccountUsernameCard extends StatefulWidget {
  const AccountUsernameCard({super.key});
  @override
  State<AccountUsernameCard> createState() => _AccountUsernameCardState();
}

class _AccountUsernameCardState extends State<AccountUsernameCard> {
  final _controller = TextEditingController();
  bool _loading = true;
  bool _failed = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final name = await AccountUsernameService(
        Supabase.instance.client,
      ).load();
      if (mounted) _controller.text = name ?? '';
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = 'Username settings are unavailable. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final name = await AccountUsernameService(
        Supabase.instance.client,
      ).save(_controller.text);
      if (mounted) {
        setState(() {
          _controller.text = name ?? '';
          _message = name == null
              ? 'Username removed. Email login is still available.'
              : 'Username saved.';
        });
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(
          () => _message = error.code == '23505'
              ? 'That username is already taken. Please choose another.'
              : 'Unable to save. Please wait a moment and try again.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Unable to save. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Username (optional)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          const Text(
            'One username for every club connected to your account. You can always sign in with your email.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            enabled: !_loading && !_failed,
            autocorrect: false,
            enableSuggestions: false,
            maxLength: 30,
            decoration: const InputDecoration(
              labelText: 'Username',
              border: OutlineInputBorder(),
              helperText: 'Leave blank to remove your username.',
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_message!, semanticsLabel: _message),
            ),
          if (_failed)
            OutlinedButton(
              onPressed: _loading
                  ? null
                  : () {
                      setState(() {
                        _loading = true;
                        _failed = false;
                        _message = null;
                      });
                      _load();
                    },
              child: const Text('Try again'),
            )
          else
            FilledButton(
              onPressed: _loading ? null : _save,
              child: Text(_loading ? 'Please wait…' : 'Save username'),
            ),
        ],
      ),
    ),
  );
}
