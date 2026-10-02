import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/creation_type.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/providers/core_providers.dart';
import '../../../../core/utils/result.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../generation/presentation/providers/generation_providers.dart';
import '../../../generation/services/ai_provider.dart';
import '../../data/models/video_maker_settings.dart';
import '../../data/models/video_segment_model.dart';
import '../../data/models/video_story_model.dart';
import '../../data/repositories/video_story_repository.dart';

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

final videoStoryRepositoryProvider = Provider<VideoStoryRepository>((ref) {
  return SupabaseVideoStoryRepository(ref.watch(supabaseClientProvider));
});

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

class VideoMakerSettingsNotifier extends Notifier<VideoMakerSettings> {
  @override
  VideoMakerSettings build() => const VideoMakerSettings();

  void setInputMode(VideoInputMode mode) =>
      state = state.copyWith(inputMode: mode);
  void setAspectRatio(StoryAspectRatio ratio) =>
      state = state.copyWith(aspectRatio: ratio);
  void setQuality(VideoQuality quality) =>
      state = state.copyWith(quality: quality);
  void setStyle(VideoMakerStyle style) =>
      state = state.copyWith(style: style);
  void setDuration(int seconds) =>
      state = state.copyWith(
        durationSeconds: seconds.clamp(
          VideoMakerSettings.minDuration,
          VideoMakerSettings.maxDuration,
        ),
      );
  void setAutoAdjust(bool value) =>
      state = state.copyWith(autoAdjust: value);
  void setFps(int fps) => state = state.copyWith(fps: fps);
  void reset() => state = const VideoMakerSettings();
}

final videoMakerSettingsProvider =
    NotifierProvider<VideoMakerSettingsNotifier, VideoMakerSettings>(
  VideoMakerSettingsNotifier.new,
);

// ---------------------------------------------------------------------------
// Stories list
// ---------------------------------------------------------------------------

final videoStoriesProvider =
    FutureProvider.autoDispose<List<VideoStoryModel>>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return [];
  final result =
      await ref.read(videoStoryRepositoryProvider).getStories(user.id);
  return result.when(success: (data) => data, failure: (e) => throw e);
});

final videoStoryByIdProvider =
    FutureProvider.autoDispose.family<VideoStoryModel?, String>((ref, id) async {
  final result = await ref.read(videoStoryRepositoryProvider).getStory(id);
  return result.when(success: (s) => s, failure: (_) => null);
});

// ---------------------------------------------------------------------------
// Active story controller (create + add segments + extend)
// ---------------------------------------------------------------------------

class ActiveStoryState {
  const ActiveStoryState({this.story, this.isLoading = false, this.error});

  final VideoStoryModel? story;
  final bool isLoading;
  final AppException? error;

  ActiveStoryState copyWith({
    VideoStoryModel? story,
    bool? isLoading,
    AppException? error,
    bool clearError = false,
  }) =>
      ActiveStoryState(
        story: story ?? this.story,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
      );
}

class ActiveStoryNotifier extends Notifier<ActiveStoryState> {
  @override
  ActiveStoryState build() => const ActiveStoryState();

  VideoStoryRepository get _repo => ref.read(videoStoryRepositoryProvider);

  Future<bool> createStory({
    required String title,
    String? projectId,
  }) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return false;

    final settings = ref.read(videoMakerSettingsProvider);
    state = state.copyWith(isLoading: true, clearError: true);

    final story = VideoStoryModel(
      id: '',
      userId: user.id,
      projectId: projectId,
      title: title,
      aspectRatio: settings.aspectRatio.value,
      quality: settings.quality.value,
      style: settings.style.value,
      fps: settings.fps,
      status: StoryStatus.draft,
      createdAt: DateTime.now(),
    );

    final result = await _repo.createStory(story);
    return result.when(
      success: (created) {
        state = ActiveStoryState(story: created);
        ref.invalidate(videoStoriesProvider);
        return true;
      },
      failure: (error) {
        state = state.copyWith(isLoading: false, error: error);
        return false;
      },
    );
  }

  Future<bool> loadStory(String storyId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    final result = await _repo.getStory(storyId);
    return result.when(
      success: (story) {
        state = ActiveStoryState(story: story);
        return true;
      },
      failure: (error) {
        state = state.copyWith(isLoading: false, error: error);
        return false;
      },
    );
  }

  Future<bool> addSegment({
    required String prompt,
    required SegmentInputType inputType,
    required int durationSeconds,
    String? photoUrl,
    String? voiceUrl,
  }) async {
    final story = state.story;
    if (story == null) return false;

    final user = ref.read(authStateProvider).value;
    if (user == null) return false;

    state = state.copyWith(isLoading: true, clearError: true);

    final segment = VideoSegmentModel(
      id: '',
      storyId: story.id,
      userId: user.id,
      orderIndex: story.segments.length,
      inputType: inputType,
      prompt: prompt,
      photoUrl: photoUrl,
      voiceUrl: voiceUrl,
      durationSeconds: durationSeconds,
      status: SegmentStatus.pending,
      createdAt: DateTime.now(),
    );

    final result = await _repo.addSegment(segment);
    return result.when(
      success: (created) async {
        await _refreshStory();
        return true;
      },
      failure: (error) {
        state = state.copyWith(isLoading: false, error: error);
        return false;
      },
    );
  }

  Future<bool> generateSegment(String segmentId) async {
    final story = state.story;
    if (story == null) return false;

    state = state.copyWith(isLoading: true, clearError: true);

    final segmentResult = await _repo.updateSegment(
      segmentId,
      {'status': SegmentStatus.processing.value},
    );

    return segmentResult.when(
      success: (segment) async {
        final orchestrator = ref.read(generationOrchestratorProvider);
        final user = ref.read(authStateProvider).value!;

        final attachments = <String>[];
        if (segment.photoUrl != null) attachments.add(segment.photoUrl!);
        if (segment.voiceUrl != null) attachments.add(segment.voiceUrl!);

        final genResult = await orchestrator.generate(
          userId: user.id,
          projectId: story.projectId,
          type: CreationType.video,
          prompt: segment.prompt,
          attachmentUrls: attachments,
          options: {
            'aspectRatio': story.aspectRatio,
            'quality': story.quality,
            'style': story.style,
            'fps': story.fps,
            'durationSeconds': segment.durationSeconds,
            'inputType': segment.inputType.value,
            'storyId': story.id,
            'segmentId': segmentId,
          },
        );

        genResult.when(
          success: (generation) async {
            await _repo.updateSegment(segmentId, {
              'generation_id': generation.id,
              'status': generation.status == 'completed'
                  ? SegmentStatus.completed.value
                  : SegmentStatus.processing.value,
              if (generation.resultUrl != null) 'video_url': generation.resultUrl,
              if (generation.thumbnailUrl != null)
                'thumbnail_url': generation.thumbnailUrl,
            });
          },
          failure: (error) async {
            await _repo.updateSegment(segmentId, {
              'status': SegmentStatus.failed.value,
              'error_message': error.message,
            });
          },
        );

        await _refreshStory();
        return true;
      },
      failure: (error) {
        state = state.copyWith(isLoading: false, error: error);
        return false;
      },
    );
  }

  Future<bool> retrySegment(String segmentId) async {
    await _repo.updateSegment(segmentId, {
      'status': SegmentStatus.pending.value,
      'error_message': null,
    });
    return generateSegment(segmentId);
  }

  Future<bool> deleteSegment(String segmentId) async {
    final result = await _repo.deleteSegment(segmentId);
    return result.when(
      success: (_) async {
        await _refreshStory();
        return true;
      },
      failure: (error) {
        state = state.copyWith(error: error);
        return false;
      },
    );
  }

  Future<bool> reorderSegments(List<String> segmentIds) async {
    final story = state.story;
    if (story == null) return false;

    final result = await _repo.reorderSegments(story.id, segmentIds);
    return result.when(
      success: (_) async {
        await _refreshStory();
        return true;
      },
      failure: (error) {
        state = state.copyWith(error: error);
        return false;
      },
    );
  }

  Future<bool> updateStoryStatus(StoryStatus status) async {
    final story = state.story;
    if (story == null) return false;

    final result = await _repo.updateStory(story.id, {'status': status.value});
    return result.when(
      success: (updated) {
        state = ActiveStoryState(story: updated);
        ref.invalidate(videoStoriesProvider);
        return true;
      },
      failure: (error) {
        state = state.copyWith(error: error);
        return false;
      },
    );
  }

  Future<void> _refreshStory() async {
    final story = state.story;
    if (story == null) return;
    final result = await _repo.getStory(story.id);
    result.when(
      success: (refreshed) {
        state = ActiveStoryState(story: refreshed);
      },
      failure: (_) {
        state = state.copyWith(isLoading: false);
      },
    );
    ref.invalidate(videoStoriesProvider);
  }

  void clear() => state = const ActiveStoryState();
}

final activeStoryProvider =
    NotifierProvider<ActiveStoryNotifier, ActiveStoryState>(
  ActiveStoryNotifier.new,
);

// ---------------------------------------------------------------------------
// Segment polling (checks processing segments for completion)
// ---------------------------------------------------------------------------

final segmentPollingProvider =
    StreamProvider.autoDispose.family<VideoSegmentModel, String>(
        (ref, segmentId) async* {
  final repo = ref.read(videoStoryRepositoryProvider);
  while (true) {
    await Future<void>.delayed(const Duration(seconds: 5));
    final segments = await repo.getSegments(
      ref.read(activeStoryProvider).story?.id ?? '',
    );
    final segment = segments.dataOrNull?.where((s) => s.id == segmentId).firstOrNull;
    if (segment != null) {
      yield segment;
      if (segment.isCompleted || segment.isFailed) break;
    }
  }
});
