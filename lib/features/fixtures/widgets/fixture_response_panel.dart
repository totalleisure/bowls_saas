import 'package:flutter/material.dart';

/// The same clear response choices wherever a player is asked to respond.
class FixtureResponsePanel extends StatefulWidget {
  final bool acceptance;
  final bool embedded;
  final Color foregroundColor;
  final String? status;
  final Future<void> Function(String) onResponse;
  const FixtureResponsePanel({
    super.key,
    this.acceptance = false,
    this.embedded = false,
    this.foregroundColor = Colors.black87,
    required this.status,
    required this.onResponse,
  });

  @override
  State<FixtureResponsePanel> createState() => _FixtureResponsePanelState();
}

class _FixtureResponsePanelState extends State<FixtureResponsePanel> {
  bool _saving = false;
  String? _error;

  Future<void> _respond(String value) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onResponse(value);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not save your response. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final choices = widget.acceptance
        ? {'accepted': 'Accept selection', 'declined': 'Decline selection'}
        : {'yes': 'Available', 'no': 'Not available'};
    final responded = choices.containsKey(widget.status);
    final title = responded
        ? 'Your response: ${widget.acceptance ? (widget.status == 'accepted' ? 'Accepted' : 'Declined') : choices[widget.status]}'
        : widget.acceptance
        ? 'You’ve been selected—please respond'
        : 'Can you play? Availability needed';
    return Semantics(
      container: true,
      child: Container(
        width: double.infinity,
        padding: widget.embedded
            ? const EdgeInsets.symmetric(vertical: 8)
            : const EdgeInsets.all(16),
        margin: widget.embedded
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(vertical: 8),
        decoration: widget.embedded
            ? null
            : BoxDecoration(
                color: responded
                    ? const Color(0xFFE0F2F1)
                    : const Color(0xFFFFF3CD),
                border: Border.all(
                  color: responded
                      ? const Color(0xFF00796B)
                      : const Color(0xFFB45309),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!widget.acceptance) ...[
              SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    responded
                        ? "You've told the Fixture Captain you are:"
                        : 'Let the Fixture Captain know if you are:',
                    maxLines: 1,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: widget.foregroundColor,
                    ),
                  ),
                ),
              ),
              if (widget.status == 'maybe') ...[
                const SizedBox(height: 8),
                Text(
                  'Previously answered Maybe—please update.',
                  style: TextStyle(color: widget.foregroundColor),
                ),
              ],
            ],
            if (widget.acceptance) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    responded
                        ? Icons.check_circle_outline
                        : Icons.notification_important_outlined,
                    color: widget.foregroundColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: widget.foregroundColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                responded
                    ? "You've told the Fixture Captain you are:"
                    : 'Let the Fixture Captain know if you are:',
                style: TextStyle(color: widget.foregroundColor, fontWeight: FontWeight.bold),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final choice in choices.entries)
                  Semantics(
                    selected: widget.status == choice.key,
                    child: FilledButton.tonal(
                      onPressed: _saving ? null : () => _respond(choice.key),
                      style: FilledButton.styleFrom(
                        side: widget.acceptance
                            ? null
                            : const BorderSide(color: Colors.black, width: 1.5),
                        backgroundColor: widget.status == choice.key
                            ? (widget.acceptance
                                  ? const Color(0xFF00695C)
                                  : choice.key == 'no'
                                  ? const Color(0xFFB71C1C)
                                  : const Color(0xFF2E7D32))
                            : Colors.white,
                        foregroundColor: widget.status == choice.key
                            ? Colors.white
                            : Colors.black87,
                      ),
                      child: Text(
                        '${widget.status == choice.key ? '✓ ' : ''}${choice.value}',
                      ),
                    ),
                  ),
              ],
            ),
            if (_saving)
              Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Saving response…',
                  style: TextStyle(color: widget.foregroundColor),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Color(0xFFB71C1C)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
