import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/image_generation_settings.dart';
import '../../data/models/reference_image.dart';

/// Holds the Image Generator screen's current Aspect Ratio / Quality /
/// Style / Number-of-images selection while the user is composing a
/// request. Reset per screen instance (not persisted) - each new visit to
/// the screen starts from sensible defaults.
class ImageSettingsNotifier extends Notifier<ImageGenerationSettings> {
  @override
  ImageGenerationSettings build() => const ImageGenerationSettings();

  void setAspectRatio(ImageAspectRatio value) =>
      state = state.copyWith(aspectRatio: value);
  void setQuality(ImageQuality value) => state = state.copyWith(quality: value);
  void setStyle(ImageStyle value) => state = state.copyWith(style: value);
  void setNumberOfImages(int value) =>
      state = state.copyWith(numberOfImages: value);
  void reset() => state = const ImageGenerationSettings();
}

final imageSettingsProvider =
    NotifierProvider<ImageSettingsNotifier, ImageGenerationSettings>(
  ImageSettingsNotifier.new,
);

/// The optional reference image the user picked (camera or gallery), before
/// upload. Cleared once consumed (submitted or removed).
class ReferenceImageNotifier extends Notifier<ReferenceImage?> {
  @override
  ReferenceImage? build() => null;

  void set(ReferenceImage? image) => state = image;
  void clear() => state = null;
}

final referenceImageProvider =
    NotifierProvider<ReferenceImageNotifier, ReferenceImage?>(
  ReferenceImageNotifier.new,
);
