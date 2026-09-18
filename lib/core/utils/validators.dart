class Validators {
  const Validators._();

  static final RegExp _emailRegex =
      RegExp(r'^[\w\.\-\+]+@[\w\-]+\.[a-zA-Z]{2,}$');

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Email is required.';
    if (!_emailRegex.hasMatch(v)) return 'Enter a valid email address.';
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required.';
    if (v.length < 8) return 'Password must be at least 8 characters.';
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(v);
    final hasDigit = RegExp(r'\d').hasMatch(v);
    if (!hasLetter || !hasDigit) {
      return 'Password must contain letters and numbers.';
    }
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if (value != original) return 'Passwords do not match.';
    return null;
  }

  static String? fullName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Full name is required.';
    if (v.length < 2) return 'Enter your full name.';
    return null;
  }

  static String? required(String? value, {String field = 'This field'}) {
    if ((value ?? '').trim().isEmpty) return '$field is required.';
    return null;
  }

  /// Maximum characters accepted for an image-generation prompt - mirrors
  /// the limit enforced server-side by the generate-image Edge Function.
  static const int maxImagePromptLength = 2000;

  static String? imagePrompt(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Please enter a description for your image.';
    if (v.length > maxImagePromptLength) {
      return 'Your description is too long (max $maxImagePromptLength characters).';
    }
    return null;
  }

  /// Mirrors the limits enforced server-side by the generate-music Edge
  /// Function.
  static const int maxMusicPromptLength = 2000;
  static const int maxLyricsLength = 5000;

  static String? musicPrompt(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Please describe the music you want to create.';
    if (v.length > maxMusicPromptLength) {
      return 'Your description is too long (max $maxMusicPromptLength characters).';
    }
    return null;
  }

  /// Lyrics are always optional, so an empty value is valid - this only
  /// catches an over-length value.
  static String? lyrics(String? value) {
    final v = (value ?? '').trim();
    if (v.length > maxLyricsLength) {
      return 'Lyrics are too long (max $maxLyricsLength characters).';
    }
    return null;
  }

  /// Mirrors the limit enforced server-side by the generate-video Edge
  /// Function.
  static const int maxVideoPromptLength = 2000;

  /// Video supports Text->Video, Image->Video, and Image+Prompt->Video, so
  /// an empty prompt is only invalid when there's also no reference image -
  /// unlike [imagePrompt]/[musicPrompt], which are always required.
  static String? videoPrompt(String? value, {required bool hasReferenceImage}) {
    final v = (value ?? '').trim();
    if (v.isEmpty && !hasReferenceImage) {
      return 'Please describe the video you want to create or upload a reference image.';
    }
    if (v.length > maxVideoPromptLength) {
      return 'Your description is too long (max $maxVideoPromptLength characters).';
    }
    return null;
  }

  /// Mirrors the limit enforced server-side by the generate-funnel Edge
  /// Function.
  static const int maxFunnelPromptLength = 2000;

  static String? funnelPrompt(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Please describe the funnel you want to create.';
    if (v.length > maxFunnelPromptLength) {
      return 'Your description is too long (max $maxFunnelPromptLength characters).';
    }
    return null;
  }

  /// Business name is optional on the Funnel Generator form (the prompt
  /// alone is enough to generate), so this only catches an over-length
  /// value - unlike [fullName], an empty business name is valid.
  static String? businessName(String? value) {
    final v = (value ?? '').trim();
    if (v.length > 200) return 'Business name is too long (max 200 characters).';
    return null;
  }

  /// Lead Form validation: at least one contact method (email or phone) is
  /// required, matching the `funnel_leads_has_contact` database constraint -
  /// this lets the client show a friendly message before ever hitting that
  /// constraint.
  static String? leadEmail(String? value, {required bool hasPhone}) {
    final v = (value ?? '').trim();
    if (v.isEmpty) {
      return hasPhone ? null : 'Please provide an email or phone number.';
    }
    return email(v);
  }

  static String? leadPhone(String? value, {required bool hasEmail}) {
    final v = (value ?? '').trim();
    if (v.isEmpty && !hasEmail) return 'Please provide an email or phone number.';
    return null;
  }
}
