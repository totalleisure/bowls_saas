import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'profile_photo_service.dart';

class ProfilePhotoAvatar extends StatefulWidget {
  final String initials;
  const ProfilePhotoAvatar({super.key, required this.initials});
  @override
  State<ProfilePhotoAvatar> createState() => _ProfilePhotoAvatarState();
}

class _ProfilePhotoAvatarState extends State<ProfilePhotoAvatar> {
  Uint8List? _image;
  String? _path;
  bool _busy = true;
  bool _loaded = false;
  late final _service = ProfilePhotoService(Supabase.instance.client);
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final path = await _service.loadPath();
      final bytes = await _service.load(path);
      if (mounted) {
        setState(() {
          _path = path;
          _image = bytes;
          _loaded = true;
        });
      }
    } catch (_) {
      _message('Unable to load your photo. Tap to try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<void> _edit() async {
    if (!_loaded) {
      setState(() => _busy = true);
      await _load();
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(
                _path == null
                    ? 'Choose profile photo'
                    : 'Replace profile photo',
              ),
              onTap: () => Navigator.pop(context, 'choose'),
            ),
            if (_path != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove profile photo'),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Optional. Your photo is visible only to you.'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    setState(() => _busy = true);
    try {
      if (action == 'remove') {
        await _service.remove(_path);
        if (mounted) {
          setState(() {
            _path = null;
            _image = null;
          });
        }
      } else {
        final files = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
          withData: true,
        );
        if (files == null || !mounted) return;
        if (files.files.single.size > 5 * 1024 * 1024) {
          throw const FormatException('Choose an image smaller than 5 MB.');
        }
        final input = files.files.single.bytes;
        if (input == null) {
          throw const FormatException('Unable to read this image.');
        }
        final prepared = await ProfilePhotoService.prepare(input);
        if (!mounted) return;
        final approved = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Preview profile photo'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipOval(
                  child: Image.memory(prepared, width: 200, height: 200),
                ),
                const SizedBox(height: 12),
                const Text(
                  'A square centre crop will be saved. Choose another photo if needed.',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save photo'),
              ),
            ],
          ),
        );
        if (approved != true) return;
        final path = await _service.replace(prepared, _path);
        if (mounted) {
          setState(() {
            _path = path;
            _image = prepared;
          });
        }
      }
    } on FormatException catch (error) {
      _message(error.message);
    } catch (_) {
      _message('Unable to change your photo. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: _busy ? 'Loading profile photo' : 'Change profile photo',
    onPressed: _busy ? null : _edit,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 64, minHeight: 64),
    icon: CircleAvatar(
      radius: 32,
      backgroundColor: const Color(0xFFDCFCE7),
      foregroundColor: const Color(0xFF14532D),
      backgroundImage: _image == null ? null : MemoryImage(_image!),
      child: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(),
            )
          : _image == null
          ? Text(
              widget.initials.isEmpty ? '?' : widget.initials,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            )
          : null,
    ),
  );
}
