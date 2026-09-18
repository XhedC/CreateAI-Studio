import 'package:equatable/equatable.dart';

enum ImageAspectRatio {
  square('1:1', 'Square'),
  widescreen('16:9', 'Widescreen'),
  portrait('9:16', 'Portrait'),
  standard('4:3', 'Standard');

  const ImageAspectRatio(this.value, this.label);
  final String value;
  final String label;
}

enum ImageQuality {
  standard('standard', 'Standard'),
  high('high', 'High');

  const ImageQuality(this.value, this.label);
  final String value;
  final String label;
}

enum ImageStyle {
  none('none', 'None'),
  realistic('realistic', 'Realistic'),
  cinematic('cinematic', 'Cinematic'),
  illustration('illustration', 'Illustration'),
  threeD('3d', '3D'),
  anime('anime', 'Anime'),
  minimalist('minimalist', 'Minimalist');

  const ImageStyle(this.value, this.label);
  final String value;
  final String label;
}

/// The image-specific "advanced options" the Image Generator screen exposes.
/// Sent to the `generate-image` Edge Function as `settings` and mirrored
/// into `generations.metadata` for history/regeneration - see
/// docs/image-generation.md for how each option maps (or gracefully doesn't
/// map) onto a given AI provider.
class ImageGenerationSettings extends Equatable {
  const ImageGenerationSettings({
    this.aspectRatio = ImageAspectRatio.square,
    this.quality = ImageQuality.standard,
    this.style = ImageStyle.none,
    this.numberOfImages = 1,
  });

  final ImageAspectRatio aspectRatio;
  final ImageQuality quality;
  final ImageStyle style;
  final int numberOfImages;

  static const int minImages = 1;
  static const int maxImages = 4;

  ImageGenerationSettings copyWith({
    ImageAspectRatio? aspectRatio,
    ImageQuality? quality,
    ImageStyle? style,
    int? numberOfImages,
  }) {
    return ImageGenerationSettings(
      aspectRatio: aspectRatio ?? this.aspectRatio,
      quality: quality ?? this.quality,
      style: style ?? this.style,
      numberOfImages:
          (numberOfImages ?? this.numberOfImages).clamp(minImages, maxImages),
    );
  }

  /// The wire format sent to the Edge Function and stored in
  /// `generations.metadata`.
  Map<String, dynamic> toJson() => {
        'aspectRatio': aspectRatio.value,
        'quality': quality.value,
        'style': style.value,
        'numberOfImages': numberOfImages,
      };

  factory ImageGenerationSettings.fromMetadata(Map<String, dynamic> metadata) {
    return ImageGenerationSettings(
      aspectRatio: ImageAspectRatio.values.firstWhere(
        (v) => v.value == metadata['aspectRatio'],
        orElse: () => ImageAspectRatio.square,
      ),
      quality: ImageQuality.values.firstWhere(
        (v) => v.value == metadata['quality'],
        orElse: () => ImageQuality.standard,
      ),
      style: ImageStyle.values.firstWhere(
        (v) => v.value == metadata['style'],
        orElse: () => ImageStyle.none,
      ),
      numberOfImages:
          ((metadata['numberOfImages'] as num?)?.toInt() ?? 1)
              .clamp(minImages, maxImages),
    );
  }

  @override
  List<Object?> get props => [aspectRatio, quality, style, numberOfImages];
}
