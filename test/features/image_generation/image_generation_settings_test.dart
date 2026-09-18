import 'package:flutter_test/flutter_test.dart';
import 'package:createai_studio/features/image_generation/data/models/image_generation_settings.dart';

void main() {
  group('ImageGenerationSettings.copyWith', () {
    test('clamps numberOfImages above the max down to 4', () {
      const settings = ImageGenerationSettings();
      final updated = settings.copyWith(numberOfImages: 99);
      expect(updated.numberOfImages, 4);
    });

    test('clamps numberOfImages below the min up to 1', () {
      const settings = ImageGenerationSettings();
      final updated = settings.copyWith(numberOfImages: 0);
      expect(updated.numberOfImages, 1);
    });

    test('leaves other fields untouched when only one changes', () {
      const settings = ImageGenerationSettings(quality: ImageQuality.high);
      final updated = settings.copyWith(aspectRatio: ImageAspectRatio.portrait);
      expect(updated.quality, ImageQuality.high);
      expect(updated.aspectRatio, ImageAspectRatio.portrait);
    });
  });

  group('ImageGenerationSettings.toJson / fromMetadata', () {
    test('round-trips through JSON', () {
      const settings = ImageGenerationSettings(
        aspectRatio: ImageAspectRatio.widescreen,
        quality: ImageQuality.high,
        style: ImageStyle.cinematic,
        numberOfImages: 3,
      );

      final restored = ImageGenerationSettings.fromMetadata(settings.toJson());

      expect(restored, settings);
    });

    test('falls back to sensible defaults for unknown/missing values', () {
      final restored = ImageGenerationSettings.fromMetadata({
        'aspectRatio': 'not-a-real-ratio',
        'quality': 'ultra', // not a supported value
      });

      expect(restored.aspectRatio, ImageAspectRatio.square);
      expect(restored.quality, ImageQuality.standard);
      expect(restored.style, ImageStyle.none);
      expect(restored.numberOfImages, 1);
    });

    test('clamps an out-of-range numberOfImages read from metadata', () {
      final restored = ImageGenerationSettings.fromMetadata({
        'numberOfImages': 50,
      });
      expect(restored.numberOfImages, ImageGenerationSettings.maxImages);
    });
  });
}
