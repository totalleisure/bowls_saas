import 'package:flutter/material.dart';

enum RinkAvailabilityStatus { available, selected, booked, unavailable }

class RinkAvailabilitySlot {
  const RinkAvailabilitySlot({
    required this.rinkLabel,
    required this.status,
    this.note,
  });

  final String rinkLabel;
  final RinkAvailabilityStatus status;
  final String? note;

  bool get canSelect =>
      status == RinkAvailabilityStatus.available ||
      status == RinkAvailabilityStatus.selected;
}

class RinkAvailabilityPanel extends StatelessWidget {
  const RinkAvailabilityPanel({
    super.key,
    required this.title,
    required this.slots,
    required this.rinksRequired,
    required this.selectedRinkLabels,
    required this.onSelectionChanged,
    this.readOnly = false,
  });

  final String title;
  final List<RinkAvailabilitySlot> slots;
  final int rinksRequired;
  final Set<String> selectedRinkLabels;
  final ValueChanged<Set<String>> onSelectionChanged;
  final bool readOnly;

  int get availableCount => slots
      .where(
        (s) =>
            s.status == RinkAvailabilityStatus.available ||
            s.status == RinkAvailabilityStatus.selected,
      )
      .length;

  bool get hasEnoughRinks => availableCount >= rinksRequired;

  @override
  Widget build(BuildContext context) {
    final selectedCount = selectedRinkLabels.length;

    return Card(
      color: hasEnoughRinks ? Colors.green.shade50 : Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),

            Text(
              hasEnoughRinks
                  ? '$availableCount rink${availableCount == 1 ? '' : 's'} available. '
                        '$selectedCount of $rinksRequired selected.'
                  : 'Only $availableCount rink${availableCount == 1 ? '' : 's'} available. '
                        '$rinksRequired required.',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: hasEnoughRinks
                    ? Colors.green.shade900
                    : Colors.red.shade900,
              ),
            ),

            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: slots.map((slot) {
                return _RinkChip(
                  slot: slot,
                  selected: selectedRinkLabels.contains(slot.rinkLabel),
                  readOnly: readOnly,
                  onTap: () {
                    if (readOnly || !slot.canSelect) return;

                    final next = Set<String>.from(selectedRinkLabels);

                    if (next.contains(slot.rinkLabel)) {
                      next.remove(slot.rinkLabel);
                    } else {
                      if (next.length >= rinksRequired) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'You only need $rinksRequired rink${rinksRequired == 1 ? '' : 's'}.',
                            ),
                          ),
                        );
                        return;
                      }

                      next.add(slot.rinkLabel);
                    }

                    onSelectionChanged(next);
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _RinkChip extends StatelessWidget {
  const _RinkChip({
    required this.slot,
    required this.selected,
    required this.readOnly,
    required this.onTap,
  });

  final RinkAvailabilitySlot slot;
  final bool selected;
  final bool readOnly;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;
    final IconData icon;

    if (selected) {
      background = Colors.green.shade700;
      foreground = Colors.white;
      icon = Icons.check_circle;
    } else {
      switch (slot.status) {
        case RinkAvailabilityStatus.available:
          background = Colors.white;
          foreground = Colors.green.shade900;
          icon = Icons.radio_button_unchecked;
          break;
        case RinkAvailabilityStatus.selected:
          background = Colors.green.shade700;
          foreground = Colors.white;
          icon = Icons.check_circle;
          break;
        case RinkAvailabilityStatus.booked:
          background = Colors.grey.shade300;
          foreground = Colors.grey.shade800;
          icon = Icons.lock;
          break;
        case RinkAvailabilityStatus.unavailable:
          background = Colors.red.shade100;
          foreground = Colors.red.shade900;
          icon = Icons.block;
          break;
      }
    }

    return Tooltip(
      message: slot.note ?? '',
      child: InkWell(
        onTap: readOnly ? null : onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? Colors.green.shade800 : Colors.grey.shade400,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: 6),
              Text(
                slot.rinkLabel,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
