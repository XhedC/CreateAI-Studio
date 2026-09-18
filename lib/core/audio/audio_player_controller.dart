import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

/// Identifies the track currently loaded into the shared player, so a
/// screen can tell "is *my* track the one playing" (e.g. to highlight a
/// history card) without coupling to music-generation-specific types.
class NowPlayingTrack {
  const NowPlayingTrack({
    required this.generationId,
    required this.title,
    required this.url,
  });

  final String generationId;
  final String title;
  final String url;
}

/// A single, app-wide audio player - reused by the Music Detail screen's
/// full player and the mini-player shown in [AppShell] - so playback
/// continues uninterrupted while the user navigates between screens.
///
/// Wraps `just_audio`, the standard maintained Flutter package for this
/// (play/pause/seek/duration/position streams out of the box) rather than
/// hand-rolling playback.
class AudioPlayerController extends Notifier<NowPlayingTrack?> {
  late final AudioPlayer _player;

  @override
  NowPlayingTrack? build() {
    _player = AudioPlayer();
    ref.onDispose(_player.dispose);
    return null;
  }

  AudioPlayer get player => _player;

  Future<void> play(NowPlayingTrack track) async {
    if (state?.generationId != track.generationId) {
      state = track;
      await _player.setUrl(track.url);
    }
    await _player.play();
  }

  Future<void> pause() => _player.pause();

  Future<void> resume() => _player.play();

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> stop() async {
    await _player.stop();
    state = null;
  }
}

final audioPlayerControllerProvider =
    NotifierProvider<AudioPlayerController, NowPlayingTrack?>(
  AudioPlayerController.new,
);
