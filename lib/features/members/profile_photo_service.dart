import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class ProfilePhotoService {
  static const enabled = bool.fromEnvironment('PROFILE_PHOTOS_ENABLED');
  static const bucket = 'profile-photos';
  final SupabaseClient client;
  ProfilePhotoService(this.client);
  String get _userId => client.auth.currentUser!.id;

  Future<String?> loadPath() async {
    final row = await client
        .from('account_photos')
        .select('object_path')
        .eq('user_id', _userId)
        .maybeSingle();
    return row?['object_path'] as String?;
  }

  Future<Uint8List?> load(String? path) async =>
      path == null ? null : await client.storage.from(bucket).download(path);

  static Future<Uint8List> prepare(Uint8List input) async {
    if (input.isEmpty || input.length > 5 * 1024 * 1024) {
      throw const FormatException('Choose an image smaller than 5 MB.');
    }
    // Check supported file signatures before handing bytes to the image decoder.
    final png =
        input.length >= 8 &&
        input[0] == 137 &&
        input[1] == 80 &&
        input[2] == 78 &&
        input[3] == 71;
    final jpeg =
        input.length >= 3 &&
        input[0] == 255 &&
        input[1] == 216 &&
        input[2] == 255;
    final webp =
        input.length >= 12 &&
        String.fromCharCodes(input.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(input.sublist(8, 12)) == 'WEBP';
    if (!png && !jpeg && !webp) {
      throw const FormatException('Choose a JPEG, PNG or WebP image.');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(input);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    ui.Picture? picture;
    ui.Image? avatar;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width > 8192 ||
          descriptor.height > 8192 ||
          descriptor.width * descriptor.height > 24000000) {
        throw const FormatException(
          'Choose a smaller image (at most 24 megapixels).',
        );
      }
      final ratio = descriptor.width / descriptor.height;
      codec = await descriptor.instantiateCodec(
        targetWidth: ratio >= 1 ? 1024 : (1024 * ratio).round().clamp(1, 1024),
        targetHeight: ratio >= 1 ? (1024 / ratio).round().clamp(1, 1024) : 1024,
      );
      image = (await codec.getNextFrame()).image;
      final side = image.width < image.height
          ? image.width.toDouble()
          : image.height.toDouble();
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        image,
        ui.Rect.fromLTWH(
          (image.width - side) / 2,
          (image.height - side) / 2,
          side,
          side,
        ),
        const ui.Rect.fromLTWH(0, 0, 512, 512),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      picture = recorder.endRecording();
      avatar = await picture.toImage(512, 512);
      final bytes = await avatar.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        throw const FormatException('Unable to prepare this image.');
      }
      // Re-encoding removes EXIF and other source metadata.
      return bytes.buffer.asUint8List();
    } finally {
      avatar?.dispose();
      picture?.dispose();
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  Future<String> replace(Uint8List bytes, String? previous) async {
    final path = '$_userId/${const Uuid().v4()}.png';
    await client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/png',
            upsert: false,
          ),
        );
    try {
      await client.rpc(
        'set_account_photo',
        params: {'expected_path': previous, 'new_path': path},
      );
    } catch (_) {
      // A lost response could conceal a successful update. Delete only when a
      // read proves this upload is not current; RLS also protects current objects.
      try {
        if (await loadPath() != path) {
          await client.storage.from(bucket).remove([path]);
        }
      } catch (_) {
        /* Retain uncertain object for recovery. */
      }
      rethrow;
    }
    if (previous != null) {
      try {
        await client.storage.from(bucket).remove([previous]);
      } catch (_) {
        /* The new photo is saved; obsolete cleanup can be retried. */
      }
    }
    return path;
  }

  Future<void> remove(String? previous) async {
    if (previous == null) return;
    await client.rpc(
      'set_account_photo',
      params: {'expected_path': previous, 'new_path': null},
    );
    try {
      await client.storage.from(bucket).remove([previous]);
    } catch (_) {
      /* Pointer is cleared; private obsolete object can be retried. */
    }
  }
}
