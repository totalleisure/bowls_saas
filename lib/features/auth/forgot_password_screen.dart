import 'recovery_password_form.dart';
import 'password_recovery_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;

  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

enum _RecoveryStep { requestCode, verifyCode, choosePassword }

String recoveryRateLimitMessage(String code) {
  if (code == 'over_email_send_rate_limit') {
    return 'The email service has reached its hourly sending limit. '
        'Please try again later; it may take up to an hour for capacity to become available.';
  }
  if (code == 'over_request_rate_limit') {
    return 'A code was requested too recently. Please wait at least a minute before trying again.';
  }
  return 'Too many requests have been made. Please wait and try again later.';
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _email;
  final _code = TextEditingController();

  _RecoveryStep _step = _RecoveryStep.requestCode;
  bool _working = false;
  String _requestedEmail = '';

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail.trim());
    _restoreProgress();
  }

  Future<void> _restoreProgress() async {
    final progress = await PasswordRecoveryProgress.read();
    if (!mounted || progress == null || _working) return;
    setState(() {
      _requestedEmail = progress['email'] as String;
      _email.text = _requestedEmail;
      _step = _RecoveryStep.verifyCode;
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
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

    final code = error is AuthException ? error.code : null;
    if (code == 'over_email_send_rate_limit' ||
        text.contains('over_email_send_rate_limit') ||
        text.contains('email rate limit exceeded')) {
      return recoveryRateLimitMessage('over_email_send_rate_limit');
    }
    if (code == 'over_request_rate_limit' ||
        text.contains('over_request_rate_limit')) {
      return recoveryRateLimitMessage('over_request_rate_limit');
    }
    if (text.contains('rate limit') ||
        (error is AuthException && error.statusCode == '429')) {
      return recoveryRateLimitMessage('unknown');
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
      await PasswordRecoveryProgress.save(email);

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
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
      // OTP verification emits an auth event before this future completes.
      // Mark the flow first so that event cannot skip password choice.
      await PasswordRecoveryProgress.save(_requestedEmail, verified: true);
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _startAgain() {
    PasswordRecoveryProgress.clear();
    setState(() {
      _step = _RecoveryStep.requestCode;
      _requestedEmail = '';
      _code.clear();
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
          autofillHints: const [AutofillHints.oneTimeCode],
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
    return RecoveryPasswordForm(
      email: _requestedEmail,
      onBusyChanged: (busy) {
        if (mounted) setState(() => _working = busy);
      },
      onComplete: () =>
          Navigator.of(context).popUntil((route) => route.isFirst),
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

    return PopScope(
      canPop: !_working,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) PasswordRecoveryProgress.clear();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Reset password · Step ${_step.index + 1} of 3'),
        ),
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
      ),
    );
  }
}
