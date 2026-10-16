import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/members/profile_photo_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('rejects non-image data and oversized uploads', () async {
    await expectLater(
      ProfilePhotoService.prepare(Uint8List.fromList('<svg></svg>'.codeUnits)),
      throwsFormatException,
    );
    await expectLater(
      ProfilePhotoService.prepare(Uint8List(5 * 1024 * 1024 + 1)),
      throwsFormatException,
    );
  });
  test('valid image becomes bounded square PNG', () async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, 80, 40),
      ui.Paint()..color = const ui.Color(0xff123456),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(80, 40);
    final source = await image.toByteData(format: ui.ImageByteFormat.png);
    final prepared = await ProfilePhotoService.prepare(
      source!.buffer.asUint8List(),
    );
    final codec = await ui.instantiateImageCodec(prepared);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 512);
    expect(frame.image.height, 512);
    frame.image.dispose();
    codec.dispose();
    image.dispose();
    picture.dispose();
  });
}
