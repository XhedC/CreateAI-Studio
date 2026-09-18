import 'package:equatable/equatable.dart';

enum VideoAspectRatio {
  widescreen('16:9', 'Widescreen'),
  portrait('9:16', 'Portrait'),
  square('1:1', 'Square');

  const VideoAspectRatio(this.value, this.label);
  final String value;
  final String label;
}

enum VideoResolution {
  hd('720p', '720p'),
  fullHd('1080p', '1080p');

  const VideoResolution(this.value, this.label);
  final String value;
  final String label;
}

enum VideoDuration {
  short('short', 'Short'),
  medium('medium', 'Medium'),
  long('long', 'Long');

  const VideoDuration(this.value, this.label);
  final String value;
  final String label;
}

enum VideoMotion {
  low('low', 'Low'),
  medium('medium', 'Medium'),
  high('high', 'High');

  const VideoMotion(this.value, this.label);
  final String value;
  final String label;
}

enum VideoStyle {
  realistic('realistic', 'Realistic'),
  cinematic('cinematic', 'Cinematic'),
  animation('animation', 'Animation'),
  threeD('3d', '3D'),
  illustration('illustration', 'Illustration'),
  minimalist('minimalist', 'Minimalist');

  const VideoStyle(this.value, this.label);
  final String value;
  final String label;
}

enum VideoFps {
  fps24(24, '24 fps'),
  fps30(30, '30 fps');

  const VideoFps(this.value, this.label);
  final int value;
  final String label;
}

/// The video-specific "advanced options" the Video Generator screen
/// exposes. Sent to the `generate-video` Edge Function as `settings` and
/// mirrored into `generations.metadata`.
///
/// Not every field maps onto a native parameter for every provider - the
/// connected real provider (Stable Video Diffusion) has no aspect
/// ratio/resolution/duration/style/fps parameters at all; see
/// docs/video-generation.md for exactly what is (and isn't) honored.
class VideoGenerationSettings extends Equatable {
  const VideoGenerationSettings({
    this.aspectRatio = VideoAspectRatio.widescreen,
    this.resolution = VideoResolution.hd,
    this.duration = VideoDuration.medium,
    this.motion = VideoMotion.medium,
    this.style = VideoStyle.realistic,
    this.fps = VideoFps.fps24,
  });

  final VideoAspectRatio aspectRatio;
  final VideoResolution resolution;
  final VideoDuration duration;
  final VideoMotion motion;
  final VideoStyle style;
  final VideoFps fps;

  VideoGenerationSettings copyWith({
    VideoAspectRatio? aspectRatio,
    VideoResolution? resolution,
    VideoDuration? duration,
    VideoMotion? motion,
    VideoStyle? style,
    VideoFps? fps,
  }) {
    return VideoGenerationSettings(
      aspectRatio: aspectRatio ?? this.aspectRatio,
      resolution: resolution ?? this.resolution,
      duration: duration ?? this.duration,
      motion: motion ?? this.motion,
      style: style ?? this.style,
      fps: fps ?? this.fps,
    );
  }

  Map<String, dynamic> toJson() => {
        'aspectRatio': aspectRatio.value,
        'resolution': resolution.value,
        'duration': duration.value,
        'motion': motion.value,
        'style': style.value,
        'fps': fps.value,
      };

  factory VideoGenerationSettings.fromMetadata(Map<String, dynamic> metadata) {
    return VideoGenerationSettings(
      aspectRatio: VideoAspectRatio.values.firstWhere(
        (v) => v.value == metadata['aspectRatio'],
        orElse: () => VideoAspectRatio.widescreen,
      ),
      resolution: VideoResolution.values.firstWhere(
        (v) => v.value == metadata['resolution'],
        orElse: () => VideoResolution.hd,
      ),
      duration: VideoDuration.values.firstWhere(
        (v) => v.value == metadata['duration'],
        orElse: () => VideoDuration.medium,
      ),
      motion: VideoMotion.values.firstWhere(
        (v) => v.value == metadata['motion'],
        orElse: () => VideoMotion.medium,
      ),
      style: VideoStyle.values.firstWhere(
        (v) => v.value == metadata['style'],
        orElse: () => VideoStyle.realistic,
      ),
      fps: VideoFps.values.firstWhere(
        (v) => v.value == metadata['fps'],
        orElse: () => VideoFps.fps24,
      ),
    );
  }

  @override
  List<Object?> get props => [aspectRatio, resolution, duration, motion, style, fps];
}
