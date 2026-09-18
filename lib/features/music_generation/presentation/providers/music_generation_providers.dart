import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/music_generation_settings.dart';

/// Holds the Music Generator screen's current Genre / Mood / Vocal Type /
/// Language / Duration / Tempo selection. Reset per screen instance, not
/// persisted - mirrors `ImageSettingsNotifier`.
class MusicSettingsNotifier extends Notifier<MusicGenerationSettings> {
  @override
  MusicGenerationSettings build() => const MusicGenerationSettings();

  void setGenre(MusicGenre value) => state = state.copyWith(genre: value);
  void setMood(MusicMood value) => state = state.copyWith(mood: value);
  void setVocalType(MusicVocalType value) => state = state.copyWith(vocalType: value);
  void setLanguage(MusicLanguage value) => state = state.copyWith(language: value);
  void setDuration(MusicDuration value) => state = state.copyWith(duration: value);
  void setTempo(MusicTempo value) => state = state.copyWith(tempo: value);
  void reset() => state = const MusicGenerationSettings();
}

final musicSettingsProvider =
    NotifierProvider<MusicSettingsNotifier, MusicGenerationSettings>(
  MusicSettingsNotifier.new,
);
