import 'package:equatable/equatable.dart';

enum MusicGenre {
  none('none', 'None'),
  pop('pop', 'Pop'),
  rock('rock', 'Rock'),
  acoustic('acoustic', 'Acoustic'),
  hipHop('hip-hop', 'Hip-Hop'),
  rnb('r&b', 'R&B'),
  jazz('jazz', 'Jazz'),
  classical('classical', 'Classical'),
  electronic('electronic', 'Electronic'),
  lofi('lo-fi', 'Lo-fi'),
  cinematic('cinematic', 'Cinematic'),
  worship('worship', 'Worship');

  const MusicGenre(this.value, this.label);
  final String value;
  final String label;
}

enum MusicMood {
  none('none', 'None'),
  happy('happy', 'Happy'),
  sad('sad', 'Sad'),
  calm('calm', 'Calm'),
  energetic('energetic', 'Energetic'),
  romantic('romantic', 'Romantic'),
  inspirational('inspirational', 'Inspirational'),
  epic('epic', 'Epic'),
  peaceful('peaceful', 'Peaceful');

  const MusicMood(this.value, this.label);
  final String value;
  final String label;
}

enum MusicVocalType {
  instrumental('instrumental', 'Instrumental'),
  male('male', 'Male'),
  female('female', 'Female');

  const MusicVocalType(this.value, this.label);
  final String value;
  final String label;
}

enum MusicLanguage {
  english('English', 'English'),
  filipino('Filipino', 'Filipino'),
  tagalog('Tagalog', 'Tagalog'),
  spanish('Spanish', 'Spanish'),
  other('Other', 'Other');

  const MusicLanguage(this.value, this.label);
  final String value;
  final String label;
}

enum MusicDuration {
  short('short', 'Short', '~30s'),
  medium('medium', 'Medium', '~90s'),
  long('long', 'Long', '~3min');

  const MusicDuration(this.value, this.label, this.approxLength);
  final String value;
  final String label;
  final String approxLength;
}

enum MusicTempo {
  none('none', 'None'),
  slow('slow', 'Slow'),
  moderate('moderate', 'Moderate'),
  fast('fast', 'Fast');

  const MusicTempo(this.value, this.label);
  final String value;
  final String label;
}

/// The music-specific "advanced options" the Music Generator screen
/// exposes. Sent to the `generate-music` Edge Function as `settings` and
/// mirrored into `generations.metadata` for history/regeneration.
///
/// Not every field maps onto a native parameter for every provider (the
/// mock and Stable Audio providers both fold genre/mood/tempo into the
/// prompt text rather than a real API field) - see
/// docs/music-generation.md. Unsupported-by-provider preferences are still
/// stored here so they survive into metadata and a future/different
/// provider can honor them natively.
class MusicGenerationSettings extends Equatable {
  const MusicGenerationSettings({
    this.genre = MusicGenre.none,
    this.mood = MusicMood.none,
    this.vocalType = MusicVocalType.instrumental,
    this.language = MusicLanguage.english,
    this.duration = MusicDuration.medium,
    this.tempo = MusicTempo.none,
  });

  final MusicGenre genre;
  final MusicMood mood;
  final MusicVocalType vocalType;
  final MusicLanguage language;
  final MusicDuration duration;
  final MusicTempo tempo;

  bool get isInstrumental => vocalType == MusicVocalType.instrumental;

  MusicGenerationSettings copyWith({
    MusicGenre? genre,
    MusicMood? mood,
    MusicVocalType? vocalType,
    MusicLanguage? language,
    MusicDuration? duration,
    MusicTempo? tempo,
  }) {
    return MusicGenerationSettings(
      genre: genre ?? this.genre,
      mood: mood ?? this.mood,
      vocalType: vocalType ?? this.vocalType,
      language: language ?? this.language,
      duration: duration ?? this.duration,
      tempo: tempo ?? this.tempo,
    );
  }

  Map<String, dynamic> toJson() => {
        'genre': genre.value,
        'mood': mood.value,
        'vocalType': vocalType.value,
        'language': language.value,
        'duration': duration.value,
        'tempo': tempo.value,
        'instrumental': isInstrumental,
      };

  factory MusicGenerationSettings.fromMetadata(Map<String, dynamic> metadata) {
    return MusicGenerationSettings(
      genre: MusicGenre.values.firstWhere(
        (v) => v.value == metadata['genre'],
        orElse: () => MusicGenre.none,
      ),
      mood: MusicMood.values.firstWhere(
        (v) => v.value == metadata['mood'],
        orElse: () => MusicMood.none,
      ),
      vocalType: MusicVocalType.values.firstWhere(
        (v) => v.value == metadata['vocalType'],
        orElse: () => MusicVocalType.instrumental,
      ),
      language: MusicLanguage.values.firstWhere(
        (v) => v.value == metadata['language'],
        orElse: () => MusicLanguage.english,
      ),
      duration: MusicDuration.values.firstWhere(
        (v) => v.value == metadata['duration'],
        orElse: () => MusicDuration.medium,
      ),
      tempo: MusicTempo.values.firstWhere(
        (v) => v.value == metadata['tempo'],
        orElse: () => MusicTempo.none,
      ),
    );
  }

  @override
  List<Object?> get props => [genre, mood, vocalType, language, duration, tempo];
}
