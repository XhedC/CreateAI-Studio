import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gal/gal.dart';

/// Saves a generated image to wherever "downloads" means on the current
/// platform, behind one call site - see docs/CROSS_PLATFORM_ARCHITECTURE.md
/// "Downloads". `gal` only supports Android/iOS (there is no macOS/Windows/
/// Linux implementation), so desktop falls back to the same save-dialog
/// path already used for video/music downloads ([FilePicker.saveFile]).
///
/// Returns `true` if the image was saved, `false` if the user cancelled a
/// desktop save dialog. Throws on a genuine I/O failure either way, exactly
/// like the mobile `Gal.putImageBytes` path already did.
class MediaSaveService {
  const MediaSaveService();

  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  Future<bool> saveImageBytes(
    Uint8List bytes, {
    required String album,
    String fileName = 'createai-studio-image.png',
  }) async {
    if (_isDesktop) {
      final path = await FilePicker.saveFile(
        fileName: fileName,
        bytes: bytes,
        type: FileType.image,
      );
      return path != null;
    }
    await Gal.putImageBytes(bytes, album: album);
    return true;
  }
}
