import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

// Reused as-is from image_generation - the reference-image concept (model
// and validator) isn't image-generation-specific, and a funnel needs TWO
// independent optional image slots (logo, product/reference) rather than
// image/video's single slot, so this is a parameterized sibling of
// ReferenceImagePickerField rather than a second copy of its validation
// logic. See docs/funnel-generation.md.
import '../../../image_generation/data/models/reference_image.dart';
import '../../../image_generation/presentation/providers/image_generation_providers.dart'
    show ReferenceImageNotifier;
import '../../../image_generation/services/reference_image_validator.dart';

/// A logo/product image picker bound to whichever [provider] is passed in -
/// lets the Funnel Generator screen show two of these side by side without
/// them clobbering each other's state.
class FunnelImagePickerField extends ConsumerWidget {
  const FunnelImagePickerField({
    super.key,
    required this.provider,
    required this.label,
  });

  final NotifierProvider<ReferenceImageNotifier, ReferenceImage?> provider;
  final String label;

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

    ref.read(provider.notifier).set(referenceImage);
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
    final referenceImage = ref.watch(provider);
    final colors = Theme.of(context).colorScheme;

    if (referenceImage == null) {
      return OutlinedButton.icon(
        onPressed: () => _showSourceSheet(context, ref),
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: Text(label),
      );
    }

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(referenceImage.file, width: 48, height: 48, fit: BoxFit.cover),
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
          tooltip: 'Remove $label',
          icon: Icon(Icons.close_rounded, color: colors.onSurfaceVariant),
          onPressed: () => ref.read(provider.notifier).clear(),
        ),
      ],
    );
  }
}
