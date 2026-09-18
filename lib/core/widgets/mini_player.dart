import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../audio/audio_player_controller.dart';

/// A slim now-playing bar shown just above the bottom navigation whenever a
/// track is loaded (playing or paused) - lets the user control playback
/// without leaving whatever screen they're on. Disappears entirely (no
/// layout reservation) when nothing is loaded, so it never disturbs the
/// existing bottom navigation bar.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nowPlaying = ref.watch(audioPlayerControllerProvider);
    if (nowPlaying == null) return const SizedBox.shrink();

    final controller = ref.read(audioPlayerControllerProvider.notifier);
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: colors.surfaceContainerHigh,
      child: InkWell(
        onTap: () {}, // Reserved for a future "expand to full player" action.
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.music_note_rounded, size: 18, color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  nowPlaying.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              StreamBuilder<PlayerState>(
                stream: controller.player.playerStateStream,
                builder: (context, snapshot) {
                  final playing = snapshot.data?.playing ?? false;
                  return IconButton(
                    icon: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: colors.onSurface,
                    ),
                    onPressed: () => playing ? controller.pause() : controller.resume(),
                  );
                },
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: colors.onSurfaceVariant),
                onPressed: controller.stop,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
