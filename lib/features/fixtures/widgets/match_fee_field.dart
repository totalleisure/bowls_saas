import 'package:flutter/material.dart';

int? parseMatchFeePence(String input) {
  final value = input.trim();
  if (value.isEmpty) return null;
  if (!RegExp(r'^\d{1,7}(\.\d{1,2})?$').hasMatch(value)) {
    throw const FormatException('Enter pounds and pence, for example 7.50.');
  }
  final parts = value.split('.');
  return int.parse(parts[0]) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
}

String matchFeeAmount(int pence) =>
    '${pence ~/ 100}.${(pence % 100).toString().padLeft(2, '0')}';

class MatchFeeEditResult {
  const MatchFeeEditResult(this.pence);
  final int? pence;
}

class MatchFeeDialog extends StatefulWidget {
  const MatchFeeDialog({super.key, this.initialPence});
  final int? initialPence;

  @override
  State<MatchFeeDialog> createState() => _MatchFeeDialogState();
}

class _MatchFeeDialogState extends State<MatchFeeDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _controller = TextEditingController(
    text: widget.initialPence == null
        ? ''
        : matchFeeAmount(widget.initialPence!),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Match fee'),
    content: Form(
      key: _formKey,
      child: MatchFeeField(controller: _controller),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_formKey.currentState!.validate()) {
            Navigator.pop(
              context,
              MatchFeeEditResult(parseMatchFeePence(_controller.text)),
            );
          }
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class MatchFeeField extends StatelessWidget {
  const MatchFeeField({super.key, required this.controller, this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: const InputDecoration(
      labelText: 'Match fee per player (optional)',
      prefixText: '£',
      hintText: '7.50',
      helperText: 'Leave blank if not set. Enter 0 for no charge.',
    ),
    onChanged: onChanged,
    validator: (value) {
      try {
        parseMatchFeePence(value ?? '');
        return null;
      } on FormatException catch (error) {
        return error.message;
      }
    },
  );
}
