import 'package:equatable/equatable.dart';

enum VideoInputMode {
  text('text', 'Text to Video'),
  photo('photo', 'Photo to Video'),
  voice('voice', 'Voice to Video');

  const VideoInputMode(this.value, this.label);
  final String value;
  final String label;
}

enum StoryAspectRatio {
  landscape('16:9', 'Landscape', 16 / 9),
  portrait('9:16', 'Portrait', 9 / 16),
  square('1:1', 'Square', 1),
  cinematic('21:9', 'Cinematic', 21 / 9),
  vertical('4:5', 'Vertical', 4 / 5);

  const StoryAspectRatio(this.value, this.label, this.ratio);
  final String value;
  final String label;
  final double ratio;
}

enum VideoQuality {
  sd('480p', '480p', 480),
  hd('720p', '720p', 720),
  fullHd('1080p', '1080p', 1080);

  const VideoQuality(this.value, this.label, this.height);
  final String value;
  final String label;
  final int height;
}

enum VideoMakerStyle {
  realistic('realistic', 'Realistic'),
  cinematic('cinematic', 'Cinematic'),
  animation('animation', 'Animation'),
  anime('anime', 'Anime'),
  threeD('3d', '3D'),
  watercolor('watercolor', 'Watercolor'),
  comic('comic', 'Comic'),
  documentary('documentary', 'Documentary');

  const VideoMakerStyle(this.value, this.label);
  final String value;
  final String label;
}

class VideoMakerSettings extends Equatable {
  const VideoMakerSettings({
    this.inputMode = VideoInputMode.text,
    this.aspectRatio = StoryAspectRatio.landscape,
    this.quality = VideoQuality.hd,
    this.style = VideoMakerStyle.cinematic,
    this.durationSeconds = 10,
    this.autoAdjust = true,
    this.fps = 24,
  });

  final VideoInputMode inputMode;
  final StoryAspectRatio aspectRatio;
  final VideoQuality quality;
  final VideoMakerStyle style;

  /// Duration in seconds (5–60).
  final int durationSeconds;

  /// When true, the AI auto-adjusts duration and style based on prompt content.
  final bool autoAdjust;

  final int fps;

  static const int minDuration = 5;
  static const int maxDuration = 60;

  VideoMakerSettings copyWith({
    VideoInputMode? inputMode,
    StoryAspectRatio? aspectRatio,
    VideoQuality? quality,
    VideoMakerStyle? style,
    int? durationSeconds,
    bool? autoAdjust,
    int? fps,
  }) {
    return VideoMakerSettings(
      inputMode: inputMode ?? this.inputMode,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      quality: quality ?? this.quality,
      style: style ?? this.style,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      autoAdjust: autoAdjust ?? this.autoAdjust,
      fps: fps ?? this.fps,
    );
  }

  Map<String, dynamic> toJson() => {
        'inputMode': inputMode.value,
        'aspectRatio': aspectRatio.value,
        'quality': quality.value,
        'style': style.value,
        'durationSeconds': durationSeconds,
        'autoAdjust': autoAdjust,
        'fps': fps,
      };

  factory VideoMakerSettings.fromJson(Map<String, dynamic> json) {
    return VideoMakerSettings(
      inputMode: VideoInputMode.values.firstWhere(
        (v) => v.value == json['inputMode'],
        orElse: () => VideoInputMode.text,
      ),
      aspectRatio: StoryAspectRatio.values.firstWhere(
        (v) => v.value == json['aspectRatio'],
        orElse: () => StoryAspectRatio.landscape,
      ),
      quality: VideoQuality.values.firstWhere(
        (v) => v.value == json['quality'],
        orElse: () => VideoQuality.hd,
      ),
      style: VideoMakerStyle.values.firstWhere(
        (v) => v.value == json['style'],
        orElse: () => VideoMakerStyle.cinematic,
      ),
      durationSeconds: json['durationSeconds'] as int? ?? 10,
      autoAdjust: json['autoAdjust'] as bool? ?? true,
      fps: json['fps'] as int? ?? 24,
    );
  }

  @override
  List<Object?> get props =>
      [inputMode, aspectRatio, quality, style, durationSeconds, autoAdjust, fps];
}
