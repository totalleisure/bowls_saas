import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/Services/arrival_guidance.dart';
void main() {
  test('default arrival only without captain arrival guidance', () {
    for (final text in [null, '', 'Wear greys and bring your bowls.', 'Match fee £2']) {
      expect(defaultArrivalGuidance(text), contains('30 minutes'));
    }
    for (final text in ['Please arrive 45 minutes before.', 'Meet at 9:00', 'Arrival: 09:30', 'Report to the captain at 10', 'Check-in at 9', 'Be there early']) {
      expect(defaultArrivalGuidance(text), isNull, reason: text);
    }
  });
}
