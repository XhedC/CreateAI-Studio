import 'package:flutter_test/flutter_test.dart';
import 'package:createai_studio/features/video_generation/data/models/video_generation_settings.dart';

void main() {
  group('VideoGenerationSettings.copyWith', () {
    test('leaves other fields untouched when only one changes', () {
      const settings = VideoGenerationSettings(motion: VideoMotion.high);
      final updated = settings.copyWith(style: VideoStyle.cinematic);
      expect(updated.motion, VideoMotion.high);
      expect(updated.style, VideoStyle.cinematic);
    });
  });

  group('VideoGenerationSettings.toJson / fromMetadata', () {
    test('round-trips through JSON', () {
      const settings = VideoGenerationSettings(
        aspectRatio: VideoAspectRatio.portrait,
        resolution: VideoResolution.fullHd,
        duration: VideoDuration.long,
        motion: VideoMotion.low,
        style: VideoStyle.animation,
        fps: VideoFps.fps30,
      );

      final restored = VideoGenerationSettings.fromMetadata(settings.toJson());

      expect(restored, settings);
    });

    test('falls back to sensible defaults for unknown/missing values', () {
      final restored = VideoGenerationSettings.fromMetadata({
        'aspectRatio': 'not-a-real-ratio',
        'fps': 999,
      });

      expect(restored.aspectRatio, VideoAspectRatio.widescreen);
      expect(restored.resolution, VideoResolution.hd);
      expect(restored.duration, VideoDuration.medium);
      expect(restored.motion, VideoMotion.medium);
      expect(restored.style, VideoStyle.realistic);
      expect(restored.fps, VideoFps.fps24);
    });

    test('toJson uses the raw enum values the Edge Function expects', () {
      const settings = VideoGenerationSettings(
        aspectRatio: VideoAspectRatio.square,
        resolution: VideoResolution.fullHd,
      );
      final json = settings.toJson();
      expect(json['aspectRatio'], '1:1');
      expect(json['resolution'], '1080p');
    });
  });
}
