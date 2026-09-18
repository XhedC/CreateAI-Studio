import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/core_providers.dart';
import '../../services/video_status_checker.dart';
import 'generation_providers.dart';

final videoStatusCheckerProvider = Provider<VideoStatusChecker>((ref) {
  return VideoStatusChecker(ref.watch(supabaseClientProvider));
});

/// How often to poll `video-status` while a generation is processing.
const _pollInterval = Duration(seconds: 4);

/// Give up after this many polls (~2.7 minutes) and mark the generation
/// failed with a friendly "taking longer than expected" message, rather
/// than polling forever if a provider job is stuck.
const _maxPollAttempts = 40;

/// True while this generation is being actively polled - drives the
/// "Processing..." / Cancel UI on the video detail screen. One instance per
/// generationId (Riverpod family), so navigating away and back doesn't
/// start a second concurrent poller for the same generation.
class VideoPollingController extends Notifier<bool> {
  VideoPollingController(this.generationId);

  final String generationId;
  Timer? _timer;
  int _attemptsLeft = _maxPollAttempts;

  @override
  bool build() {
    ref.onDispose(() {
      _timer?.cancel();
    });
    return false;
  }

  /// Starts polling for [jobId] if not already running. Safe to call every
  /// time the detail screen builds - a no-op if already polling.
  void start(String jobId) {
    if (state) return;
    _attemptsLeft = _maxPollAttempts;
    state = true;
    _poll(jobId);
  }

  Future<void> _poll(String jobId) async {
    if (!state) return; // cancelled while this was scheduled

    final result = await ref
        .read(videoStatusCheckerProvider)
        .check(generationId: generationId, jobId: jobId);

    if (!state) return; // cancelled while awaiting the network call

    if (result.isCompleted) {
      await ref.read(generationRepositoryProvider).updateGeneration(
            generationId,
            status: 'completed',
            resultUrl: result.videoUrl,
            thumbnailUrl: result.thumbnailUrl,
            metadata: {
              ...result.metadata,
              if (result.videoStoragePath != null) 'storagePath': result.videoStoragePath,
              if (result.thumbnailStoragePath != null)
                'thumbnailStoragePath': result.thumbnailStoragePath,
            },
            completedAt: DateTime.now(),
          );
      _finish();
      return;
    }

    if (result.isFailed) {
      await ref.read(generationRepositoryProvider).updateGeneration(
            generationId,
            status: 'failed',
            errorMessage: result.error,
            completedAt: DateTime.now(),
          );
      _finish();
      return;
    }

    _attemptsLeft--;
    if (_attemptsLeft <= 0) {
      await ref.read(generationRepositoryProvider).updateGeneration(
            generationId,
            status: 'failed',
            errorMessage:
                'This video is taking longer than expected. Please try regenerating.',
            completedAt: DateTime.now(),
          );
      _finish();
      return;
    }

    _timer = Timer(_pollInterval, () => _poll(jobId));
  }

  /// Stops polling without changing the generation's status - used when the
  /// user navigates away. The generation stays "processing" and can resume
  /// being polled next time its detail screen opens.
  void stop() {
    _timer?.cancel();
    state = false;
  }

  /// User-initiated cancel: stops polling AND marks the generation
  /// cancelled. Does not (cannot, without confirmed provider support) tell
  /// the AI provider to stop its job - see docs/video-generation.md.
  Future<void> cancel() async {
    _timer?.cancel();
    state = false;
    await ref.read(generationRepositoryProvider).updateGeneration(
          generationId,
          status: 'cancelled',
          completedAt: DateTime.now(),
        );
    _finish();
  }

  void _finish() {
    state = false;
    ref.invalidate(generationByIdProvider(generationId));
    ref.invalidate(generationsProvider);
    ref.invalidate(recentGenerationsProvider);
  }
}

final videoPollingProvider = NotifierProvider.family<VideoPollingController, bool, String>(
  VideoPollingController.new,
);
