import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../audio/audio_player_controller.dart';

/// Reusable full audio player: play/pause/resume, seek, duration, current
/// position, a progress bar, and loading/error states. Backed by the single
/// app-wide [audioPlayerControllerProvider] so playback (and this widget's
/// displayed state) stays correct even if another screen's mini-player
/// changed it.
class AudioPlayerWidget extends ConsumerStatefulWidget {
  const AudioPlayerWidget({
    super.key,
    required this.generationId,
    required this.title,
    required this.url,
  });

  final String generationId;
  final String title;
  final String url;

  @override
  ConsumerState<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends ConsumerState<AudioPlayerWidget> {
  bool _isLoading = false;
  String? _error;

  bool get _isThisTrack =>
      ref.read(audioPlayerControllerProvider)?.generationId == widget.generationId;

  Future<void> _togglePlayPause() async {
    final controller = ref.read(audioPlayerControllerProvider.notifier);

    if (_isThisTrack) {
      final playing = controller.player.playing;
      await (playing ? controller.pause() : controller.resume());
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await controller.play(NowPlayingTrack(
        generationId: widget.generationId,
        title: widget.title,
        url: widget.url,
      ));
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to play this track. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _format(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(audioPlayerControllerProvider.notifier);
    ref.watch(audioPlayerControllerProvider); // rebuild when the active track changes
    final colors = Theme.of(context).colorScheme;

    if (_error != null) {
      return Row(
        children: [
          Icon(Icons.error_outline_rounded, color: colors.error),
          const SizedBox(width: 8),
          Expanded(child: Text(_error!, style: TextStyle(color: colors.error))),
        ],
      );
    }

    return StreamBuilder<PlayerState>(
      stream: controller.player.playerStateStream,
      builder: (context, snapshot) {
        final isThisTrack = _isThisTrack;
        final playing = isThisTrack && (snapshot.data?.playing ?? false);
        final processingState = isThisTrack ? snapshot.data?.processingState : null;
        final buffering = processingState == ProcessingState.loading ||
            processingState == ProcessingState.buffering;
        final showSpinner = _isLoading || buffering;

        return Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: showSpinner
                      ? const Center(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        )
                      : IconButton(
                          iconSize: 48,
                          padding: EdgeInsets.zero,
                          onPressed: _togglePlayPause,
                          icon: Icon(
                            playing
                                ? Icons.pause_circle_filled_rounded
                                : Icons.play_circle_filled_rounded,
                            color: colors.primary,
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: isThisTrack
                      ? StreamBuilder<Duration>(
                          stream: controller.player.positionStream,
                          builder: (context, positionSnapshot) {
                            final position = positionSnapshot.data ?? Duration.zero;
                            final duration = controller.player.duration ?? Duration.zero;
                            final clampedPosition = position > duration ? duration : position;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 6,
                                    ),
                                  ),
                                  child: Slider(
                                    min: 0,
                                    max: duration.inMilliseconds > 0
                                        ? duration.inMilliseconds.toDouble()
                                        : 1,
                                    value: clampedPosition.inMilliseconds
                                        .clamp(0, duration.inMilliseconds > 0
                                            ? duration.inMilliseconds
                                            : 1)
                                        .toDouble(),
                                    onChanged: duration.inMilliseconds > 0
                                        ? (value) => controller
                                            .seek(Duration(milliseconds: value.round()))
                                        : null,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(_format(clampedPosition),
                                          style: Theme.of(context).textTheme.labelSmall),
                                      Text(_format(duration),
                                          style: Theme.of(context).textTheme.labelSmall),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        )
                      : Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
