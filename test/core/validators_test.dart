import 'package:flutter_test/flutter_test.dart';
import 'package:createai_studio/core/utils/validators.dart';

void main() {
  group('Validators.email', () {
    test('rejects empty input', () {
      expect(Validators.email(''), isNotNull);
    });

    test('rejects malformed addresses', () {
      expect(Validators.email('not-an-email'), isNotNull);
    });

    test('accepts a valid address', () {
      expect(Validators.email('user@example.com'), isNull);
    });
  });

  group('Validators.password', () {
    test('rejects short passwords', () {
      expect(Validators.password('abc1'), isNotNull);
    });

    test('rejects letters-only passwords', () {
      expect(Validators.password('abcdefgh'), isNotNull);
    });

    test('accepts a strong password', () {
      expect(Validators.password('password123'), isNull);
    });
  });

  group('Validators.confirmPassword', () {
    test('rejects mismatched confirmation', () {
      expect(Validators.confirmPassword('abc', 'def'), isNotNull);
    });

    test('accepts a matching confirmation', () {
      expect(Validators.confirmPassword('abc', 'abc'), isNull);
    });
  });

  group('Validators.imagePrompt', () {
    test('rejects an empty prompt', () {
      expect(Validators.imagePrompt(''), isNotNull);
    });

    test('rejects a whitespace-only prompt', () {
      expect(Validators.imagePrompt('   '), isNotNull);
    });

    test('rejects a prompt over the max length', () {
      final tooLong = 'a' * (Validators.maxImagePromptLength + 1);
      expect(Validators.imagePrompt(tooLong), isNotNull);
    });

    test('accepts a prompt at exactly the max length', () {
      final atLimit = 'a' * Validators.maxImagePromptLength;
      expect(Validators.imagePrompt(atLimit), isNull);
    });

    test('accepts a normal prompt', () {
      expect(
        Validators.imagePrompt('A modern advertisement for a pharmacy'),
        isNull,
      );
    });
  });

  group('Validators.musicPrompt', () {
    test('rejects an empty prompt', () {
      expect(Validators.musicPrompt(''), isNotNull);
    });

    test('rejects a whitespace-only prompt', () {
      expect(Validators.musicPrompt('   '), isNotNull);
    });

    test('rejects a prompt over the max length', () {
      final tooLong = 'a' * (Validators.maxMusicPromptLength + 1);
      expect(Validators.musicPrompt(tooLong), isNotNull);
    });

    test('accepts a normal prompt', () {
      expect(
        Validators.musicPrompt('An uplifting acoustic worship song about hope'),
        isNull,
      );
    });
  });

  group('Validators.videoPrompt', () {
    test('rejects an empty prompt with no reference image', () {
      expect(Validators.videoPrompt('', hasReferenceImage: false), isNotNull);
    });

    test('rejects a whitespace-only prompt with no reference image', () {
      expect(Validators.videoPrompt('   ', hasReferenceImage: false), isNotNull);
    });

    test('accepts an empty prompt when a reference image is attached (Image -> Video)', () {
      expect(Validators.videoPrompt('', hasReferenceImage: true), isNull);
    });

    test('rejects a prompt over the max length even with a reference image', () {
      final tooLong = 'a' * (Validators.maxVideoPromptLength + 1);
      expect(Validators.videoPrompt(tooLong, hasReferenceImage: true), isNotNull);
    });

    test('accepts a normal prompt', () {
      expect(
        Validators.videoPrompt(
          'A cinematic advertisement for a modern pharmacy',
          hasReferenceImage: false,
        ),
        isNull,
      );
    });
  });

  group('Validators.funnelPrompt', () {
    test('rejects an empty prompt', () {
      expect(Validators.funnelPrompt(''), isNotNull);
    });

    test('rejects a whitespace-only prompt', () {
      expect(Validators.funnelPrompt('   '), isNotNull);
    });

    test('rejects a prompt over the max length', () {
      final tooLong = 'a' * (Validators.maxFunnelPromptLength + 1);
      expect(Validators.funnelPrompt(tooLong), isNotNull);
    });

    test('accepts a normal prompt', () {
      expect(
        Validators.funnelPrompt(
          'Create a landing page for a pharmacy offering online consultation.',
        ),
        isNull,
      );
    });
  });

  group('Validators.businessName', () {
    test('accepts an empty value (business name is optional)', () {
      expect(Validators.businessName(''), isNull);
      expect(Validators.businessName(null), isNull);
    });

    test('rejects a name over the max length', () {
      final tooLong = 'a' * 201;
      expect(Validators.businessName(tooLong), isNotNull);
    });

    test('accepts a normal business name', () {
      expect(Validators.businessName('CrossCare Pharmacy'), isNull);
    });
  });

  group('Validators.leadEmail / leadPhone', () {
    test('rejects an empty email when there is also no phone', () {
      expect(Validators.leadEmail('', hasPhone: false), isNotNull);
    });

    test('accepts an empty email when a phone is provided', () {
      expect(Validators.leadEmail('', hasPhone: true), isNull);
    });

    test('rejects a malformed email even when a phone is provided', () {
      expect(Validators.leadEmail('not-an-email', hasPhone: true), isNotNull);
    });

    test('accepts a valid email', () {
      expect(Validators.leadEmail('lead@example.com', hasPhone: false), isNull);
    });

    test('rejects an empty phone when there is also no email', () {
      expect(Validators.leadPhone('', hasEmail: false), isNotNull);
    });

    test('accepts an empty phone when an email is provided', () {
      expect(Validators.leadPhone('', hasEmail: true), isNull);
    });
  });

  group('Validators.lyrics', () {
    test('accepts an empty value (lyrics are always optional)', () {
      expect(Validators.lyrics(''), isNull);
      expect(Validators.lyrics(null), isNull);
    });

    test('rejects lyrics over the max length', () {
      final tooLong = 'a' * (Validators.maxLyricsLength + 1);
      expect(Validators.lyrics(tooLong), isNotNull);
    });

    test('accepts normal lyrics', () {
      expect(Validators.lyrics('Verse one\nChorus\nVerse two'), isNull);
    });
  });
}
