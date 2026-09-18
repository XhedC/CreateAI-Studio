import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/models/reference_image.dart';
import '../../services/reference_image_validator.dart';
import '../providers/image_generation_providers.dart';

/// "Reference Image" picker: camera or gallery, with format/size validation
/// and a small preview. Only requests camera access when the user actually
/// taps "Take photo" - image_picker's gallery path uses the Android photo
/// picker, which needs no runtime permission at all on Android 13+.
class ReferenceImagePickerField extends ConsumerWidget {
  const ReferenceImagePickerField({super.key});

  String _mimeTypeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _pick(BuildContext context, WidgetRef ref, ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 90);
    if (picked == null) return;

    final file = File(picked.path);
    final size = await file.length();
    final referenceImage = ReferenceImage(
      file: file,
      fileName: picked.name,
      mimeType: _mimeTypeFor(picked.path),
      fileSizeBytes: size,
    );

    final error = ReferenceImageValidator.validate(referenceImage);
    if (error != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      }
      return;
    }

    ref.read(referenceImageProvider.notifier).set(referenceImage);
  }

  void _showSourceSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pick(context, ref, ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pick(context, ref, ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final referenceImage = ref.watch(referenceImageProvider);
    final colors = Theme.of(context).colorScheme;

    if (referenceImage == null) {
      return OutlinedButton.icon(
        onPressed: () => _showSourceSheet(context, ref),
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Upload Image'),
      );
    }

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            referenceImage.file,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            referenceImage.fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        IconButton(
          tooltip: 'Remove reference image',
          icon: Icon(Icons.close_rounded, color: colors.onSurfaceVariant),
          onPressed: () => ref.read(referenceImageProvider.notifier).clear(),
        ),
      ],
    );
  }
}
