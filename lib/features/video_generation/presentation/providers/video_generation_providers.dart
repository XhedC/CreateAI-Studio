import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/video_generation_settings.dart';

/// Holds the Video Generator screen's current Aspect Ratio / Resolution /
/// Duration / Motion / Style / FPS selection. Mirrors
/// `ImageSettingsNotifier`/`MusicSettingsNotifier`.
class VideoSettingsNotifier extends Notifier<VideoGenerationSettings> {
  @override
  VideoGenerationSettings build() => const VideoGenerationSettings();

  void setAspectRatio(VideoAspectRatio value) => state = state.copyWith(aspectRatio: value);
  void setResolution(VideoResolution value) => state = state.copyWith(resolution: value);
  void setDuration(VideoDuration value) => state = state.copyWith(duration: value);
  void setMotion(VideoMotion value) => state = state.copyWith(motion: value);
  void setStyle(VideoStyle value) => state = state.copyWith(style: value);
  void setFps(VideoFps value) => state = state.copyWith(fps: value);
  void reset() => state = const VideoGenerationSettings();
}

final videoSettingsProvider =
    NotifierProvider<VideoSettingsNotifier, VideoGenerationSettings>(
  VideoSettingsNotifier.new,
);
