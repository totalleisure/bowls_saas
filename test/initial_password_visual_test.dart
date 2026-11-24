import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/auth/initial_password_gate.dart';

void main() {
  testWidgets('colourful password choices fit and produce a review preview', (
    t,
  ) async {
    t.view.physicalSize = const Size(760, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.runAsync(() async {
      for (final font in [
        ('PreviewUI', 'C:/Windows/Fonts/segoeui.ttf'),
        (
          'MaterialIcons',
          'C:/src/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ),
      ]) {
        if (!File(font.$2).existsSync()) continue;
        final bytes = File(font.$2).readAsBytesSync();
        await (FontLoader(
          font.$1,
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
    });
    final key = GlobalKey();
    await t.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(useMaterial3: true, fontFamily: 'PreviewUI'),
          home: InitialPasswordGate(
            email: 'test@example.invalid',
            loadChoice: () async => true,
            decide: (_) async {},
            child: const SizedBox(),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Change my password').hitTestable(), findsOneWidget);
    expect(
      find.text('Keep this password and continue').hitTestable(),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
    await t.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('tmp').create(recursive: true);
      final output =
          'tmp/password-choice-preview-${DateTime.now().microsecondsSinceEpoch}.png';
      await File(output).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
      print(output);
    });
  });
}
