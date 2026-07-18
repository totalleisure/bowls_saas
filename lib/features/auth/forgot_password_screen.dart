import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;

  const ForgotPasswordScreen({
    super.key,
    this.initialEmail = '',
  });

  @override
  State<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

enum _RecoveryStep {
  requestCode,
  verifyCode,
  choosePassword,
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _email;
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  _RecoveryStep _step = _RecoveryStep.requestCode;
  bool _working = false;
  bool _showPassword = false;
  String _requestedEmail = '';

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail.trim());
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  bool _looksLikeEmail(String value) {
    final text = value.trim();
    final at = text.indexOf('@');
    final dot = text.lastIndexOf('.');
    return at > 0 && dot > at + 1 && dot < text.length - 1;
  }

  bool _looksLikeConnectionFailure(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('failed host lookup') ||
        text.contains('socketexception') ||
        text.contains('network is unreachable') ||
        text.contains('failed to fetch') ||
        text.contains('clientexception');
  }

  String _friendlyError(Object error) {
    final text = error.toString().toLowerCase();

    if (_looksLikeConnectionFailure(error)) {
      return 'The app could not contact the Bowls Club service. '
          'Please check your internet connection and try again.';
    }

    if (text.contains('rate limit') || text.contains('over_email_send_rate_limit')) {
      return 'A code was requested too recently. Please wait a minute and try again.';
    }

    if (text.contains('expired') ||
        text.contains('invalid') ||
        text.contains('otp')) {
      return 'That code is invalid or has expired. Please check it carefully or request a new code.';
    }

    return 'The request could not be completed. Please try again.';
  }

  Future<void> _sendCode({bool resend = false}) async {
    final email = resend ? _requestedEmail : _email.text.trim();

    if (!_looksLikeEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address.')),
      );
      return;
    }

    setState(() => _working = true);

    try {
      // No redirect URL is supplied. The recovery email contains a numeric
      // code, so there is no browser, deep-link or email-scanner dependency.
      await Supabase.instance.client.auth.resetPasswordForEmail(email);

      if (!mounted) return;

      setState(() {
        _requestedEmail = email;
        _code.clear();
        _step = _RecoveryStep.verifyCode;
      });

      if (resend) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A new recovery code has been sent.')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(error))),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _verifyCode() async {
    final code = _code.text.trim();

    if (code.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the code from the email.')),
      );
      return;
    }

    setState(() => _working = true);

    try {
      final response = await Supabase.instance.client.auth.verifyOTP(
        email: _requestedEmail,
        token: code,
        type: OtpType.recovery,
      );

      if (response.session == null) {
        throw Exception('The recovery code did not create a session.');
      }

      if (!mounted) return;
      setState(() => _step = _RecoveryStep.choosePassword);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(error))),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _savePassword() async {
    final password = _password.text;
    final confirmation = _confirmPassword.text;

    if (password.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please use a password of at least 8 characters.'),
        ),
      );
      return;
    }

    if (password != confirmation) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The two passwords do not match.')),
      );
      return;
    }

    setState(() => _working = true);

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password),
      );

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(
            Icons.check_circle_outline,
            color: Colors.green.shade700,
            size: 48,
          ),
          title: const Text('Password updated'),
          content: const Text(
            'Your new password has been saved. You are now signed in.',
            textAlign: TextAlign.center,
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Continue'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password could not be updated: $error')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _startAgain() {
    setState(() {
      _step = _RecoveryStep.requestCode;
      _requestedEmail = '';
      _code.clear();
      _password.clear();
      _confirmPassword.clear();
    });
  }

  Widget _requestCodeCard() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Forgotten your password?',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const Text(
          'Enter the email address you use to sign in. We will email you a one-time recovery code.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _email,
          enabled: !_working,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Email address',
            prefixIcon: Icon(Icons.email_outlined),
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) {
            if (!_working) _sendCode();
          },
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _working ? null : _sendCode,
          icon: _working
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.password_outlined),
          label: Text(_working ? 'Sending…' : 'Send recovery code'),
        ),
      ],
    );
  }

  Widget _verifyCodeCard() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.mark_email_read_outlined,
          size: 56,
          color: Colors.green.shade700,
        ),
        const SizedBox(height: 16),
        Text(
          'Enter your recovery code',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'If an account exists for $_requestedEmail, a recovery code has been sent. Copy the code from the email and enter it below. Do not click a link.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _code,
          enabled: !_working,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          decoration: const InputDecoration(
            labelText: 'Recovery code',
            prefixIcon: Icon(Icons.pin_outlined),
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) {
            if (!_working) _verifyCode();
          },
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _working ? null : _verifyCode,
          icon: _working
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.verified_outlined),
          label: Text(_working ? 'Checking…' : 'Check code'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _working ? null : () => _sendCode(resend: true),
          child: const Text('Send another code'),
        ),
        TextButton(
          onPressed: _working ? null : _startAgain,
          child: const Text('Use a different email address'),
        ),
      ],
    );
  }

  Widget _choosePasswordCard() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Choose a new password',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const Text(
          'The code has been accepted. Enter and confirm the password you want to use from now on.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _password,
          enabled: !_working,
          obscureText: !_showPassword,
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: 'New password',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: _showPassword ? 'Hide password' : 'Show password',
              onPressed: () {
                setState(() => _showPassword = !_showPassword);
              },
              icon: Icon(
                _showPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _confirmPassword,
          enabled: !_working,
          obscureText: !_showPassword,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.newPassword],
          decoration: const InputDecoration(
            labelText: 'Confirm new password',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) {
            if (!_working) _savePassword();
          },
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _working ? null : _savePassword,
          icon: _working
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.lock_reset_outlined),
          label: Text(_working ? 'Saving…' : 'Save new password'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget contents;
    switch (_step) {
      case _RecoveryStep.requestCode:
        contents = _requestCodeCard();
        break;
      case _RecoveryStep.verifyCode:
        contents = _verifyCodeCard();
        break;
      case _RecoveryStep.choosePassword:
        contents = _choosePasswordCard();
        break;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: contents,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
