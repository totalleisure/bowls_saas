import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../diary/diary_involvement.dart';
import 'fixture_details_page.dart';
import 'next_fixture_reminder.dart';

/// Loads personal commitments independently of the visible diary date/filter.
class NextFixtureReminderButton extends StatefulWidget {
  final String clubId;
  final String clubName;
  final bool showOnOpen;
  /// Lets the owning screen consume its entry reminder before async loading.
  /// The screen survives header reconstruction during a diary refresh.
  final VoidCallback? onAutomaticOpen;
  final Future<Map<String, dynamic>?> Function()? loader;
  final DateTime Function()? now;
  final Future<void> Function(String)? openFixture;
  const NextFixtureReminderButton({
    super.key,
    required this.clubId,
    required this.clubName,
    this.showOnOpen = false,
    this.onAutomaticOpen,
    this.loader,
    this.now,
    this.openFixture,
  });

  @override
  State<NextFixtureReminderButton> createState() =>
      _NextFixtureReminderButtonState();
}

class _NextFixtureReminderButtonState extends State<NextFixtureReminderButton> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.showOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) {
          widget.onAutomaticOpen?.call();
          _show(automatic: true);
        }
      });
    }
  }

  Future<void> _show({bool automatic = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final fixtures = widget.loader != null
          ? [?await widget.loader!()]
          : await DiaryInvolvementRepository(
              Supabase.instance.client,
              widget.clubId,
            ).reminders((widget.now?.call() ?? DateTime.now()).toUtc());
      if (!mounted) return;
      if (automatic && (fixtures.isEmpty || !(ModalRoute.of(context)?.isCurrent ?? true))) return;
      await NextFixtureReminder(
        context: context,
        clubName: widget.clubName,
        nextMatch: null,
        fixtures: fixtures,
        now: widget.now,
        openFixture:
            widget.openFixture ??
            (id) async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FixtureDetailsPage(fixtureId: id),
                ),
              );
            },
      ).show();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load your next match. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Next match',
    onPressed: _busy ? null : () => _show(),
    icon: const Icon(Icons.info_outline),
  );
}
