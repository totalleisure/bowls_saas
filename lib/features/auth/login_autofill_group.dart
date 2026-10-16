import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

/// Observes platform AutoFill, never ordinary typing/controller changes.
class LoginAutofillGroup extends AutofillGroup {
  const LoginAutofillGroup({
    super.key,
    required super.child,
    required this.onAutofilled,
    this.shouldSaveOnDispose,
    super.onDisposeAction = AutofillContextAction.cancel,
  });
  final void Function(Set<String> hints) onAutofilled;

  /// Read the verified result at disposal, even if the auth event removes this
  /// widget before another build. Do not retain credentials in this callback.
  final bool Function()? shouldSaveOnDispose;

  @override
  AutofillContextAction get onDisposeAction => shouldSaveOnDispose == null
      ? super.onDisposeAction
      : (shouldSaveOnDispose!()
          ? AutofillContextAction.commit
          : AutofillContextAction.cancel);

  @override
  AutofillGroupState createState() => _LoginAutofillGroupState();
}

class _LoginAutofillGroupState extends AutofillGroupState {
  final _hints = <String>{};
  bool _scheduled = false;

  void _filled(AutofillClient client) {
    _hints.addAll(
      client.textInputConfiguration.autofillConfiguration.autofillHints,
    );
    if (_scheduled) return;
    _scheduled = true;
    // Flutter applies every tagged field before the next frame. Submit only
    // after the paired fields have reached their controllers.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final hints = Set<String>.of(_hints);
      _hints.clear();
      (widget as LoginAutofillGroup).onAutofilled(hints);
    });
  }

  @override
  AutofillClient? getAutofillClient(String autofillId) {
    final client = super.getAutofillClient(autofillId);
    return client == null
        ? null
        : _ObservedAutofillClient(client, () => _filled(client));
  }
}

class _ObservedAutofillClient implements AutofillClient {
  _ObservedAutofillClient(this.client, this.onFilled);
  final AutofillClient client;
  final VoidCallback onFilled;
  @override
  String get autofillId => client.autofillId;
  @override
  TextInputConfiguration get textInputConfiguration =>
      client.textInputConfiguration;
  @override
  void autofill(TextEditingValue value) {
    client.autofill(value);
    onFilled();
  }
}
