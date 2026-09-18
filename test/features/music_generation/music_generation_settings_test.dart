import 'package:flutter_test/flutter_test.dart';
import 'package:createai_studio/features/music_generation/data/models/music_generation_settings.dart';

void main() {
  group('MusicGenerationSettings.copyWith', () {
    test('leaves other fields untouched when only one changes', () {
      const settings = MusicGenerationSettings(mood: MusicMood.happy);
      final updated = settings.copyWith(genre: MusicGenre.jazz);
      expect(updated.mood, MusicMood.happy);
      expect(updated.genre, MusicGenre.jazz);
    });
  });

  group('MusicGenerationSettings.isInstrumental', () {
    test('is true when vocalType is instrumental', () {
      const settings = MusicGenerationSettings(vocalType: MusicVocalType.instrumental);
      expect(settings.isInstrumental, isTrue);
    });

    test('is false when vocalType is male or female', () {
      const male = MusicGenerationSettings(vocalType: MusicVocalType.male);
      const female = MusicGenerationSettings(vocalType: MusicVocalType.female);
      expect(male.isInstrumental, isFalse);
      expect(female.isInstrumental, isFalse);
    });
  });

  group('MusicGenerationSettings.toJson / fromMetadata', () {
    test('round-trips through JSON', () {
      const settings = MusicGenerationSettings(
        genre: MusicGenre.acoustic,
        mood: MusicMood.inspirational,
        vocalType: MusicVocalType.female,
        language: MusicLanguage.filipino,
        duration: MusicDuration.long,
        tempo: MusicTempo.slow,
      );

      final restored = MusicGenerationSettings.fromMetadata(settings.toJson());

      expect(restored, settings);
    });

    test('falls back to sensible defaults for unknown/missing values', () {
      final restored = MusicGenerationSettings.fromMetadata({
        'genre': 'not-a-real-genre',
        'vocalType': 'robot',
      });

      expect(restored.genre, MusicGenre.none);
      expect(restored.vocalType, MusicVocalType.instrumental);
      expect(restored.mood, MusicMood.none);
      expect(restored.language, MusicLanguage.english);
      expect(restored.duration, MusicDuration.medium);
      expect(restored.tempo, MusicTempo.none);
    });

    test('toJson sets instrumental=true when vocalType is instrumental', () {
      const settings = MusicGenerationSettings(vocalType: MusicVocalType.instrumental);
      expect(settings.toJson()['instrumental'], isTrue);
    });

    test('toJson sets instrumental=false when vocalType is male/female', () {
      const settings = MusicGenerationSettings(vocalType: MusicVocalType.male);
      expect(settings.toJson()['instrumental'], isFalse);
    });
  });
}
