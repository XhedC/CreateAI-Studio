import '../data/models/reference_image.dart';

/// Validates a picked reference image before it's uploaded, per
/// docs/image-generation.md's supported-formats/size-limit rules.
class ReferenceImageValidator {
  const ReferenceImageValidator._();

  static const int maxFileSizeBytes = 10 * 1024 * 1024; // 10 MB

  static const Map<String, String> supportedMimeTypes = {
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/webp': 'webp',
  };

  /// Returns a friendly error message, or null if the image is valid.
  static String? validate(ReferenceImage image) {
    if (!supportedMimeTypes.containsKey(image.mimeType)) {
      return 'Unsupported image format.';
    }
    if (image.fileSizeBytes > maxFileSizeBytes) {
      return 'Image is too large.';
    }
    if (image.fileSizeBytes <= 0) {
      return 'That image could not be read. Please choose another one.';
    }
    return null;
  }
}
