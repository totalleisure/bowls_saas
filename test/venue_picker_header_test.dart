import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/fixtures/widgets/venue_picker_header.dart';

void main() {
  for (final size in [const Size(393, 852), const Size(852, 393)]) {
    for (final scale in [1.0, 1.8]) {
      testWidgets('venue header at $size and text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(12),
                  child: VenuePickerHeader(
                    title: 'Select opponent',
                    actions: [
                      TextButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.radar),
                        label: const Text('Find local clubs'),
                      ),
                      TextButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.add),
                        label: const Text('Add external venue'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        final title = tester.getRect(find.text('Select opponent'));
        expect(title.width, greaterThan(140));
        expect(title.height, lessThan(120));
        if (size.width < 600) {
          expect(
            tester.getTopLeft(find.text('Find local clubs')).dy,
            greaterThan(title.top),
          );
        }
      });
    }
  }
}
