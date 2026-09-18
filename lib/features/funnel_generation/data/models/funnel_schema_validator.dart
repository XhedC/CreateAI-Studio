import 'funnel_schema.dart';

/// Thrown when a funnel document cannot be safely corrected into a valid
/// [FunnelSchema] - see [FunnelSchemaValidator.validate]. Never render a
/// funnel that failed this validation.
class FunnelValidationException implements Exception {
  const FunnelValidationException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Dart-side mirror of supabase/functions/generate-funnel/schema.ts -
/// defensively re-validates a funnel document read back from the `funnels`
/// table (or produced by hand-editing in the Funnel Editor) before it is
/// ever rendered or saved. The Edge Function already validated the AI's
/// output once server-side; this is defense in depth for the client, and
/// the ONLY path [FunnelEditorController] uses to accept edited content.
///
/// Individually malformed pieces are corrected with sensible fallbacks
/// (never blindly rendered) - only a document with zero usable sections
/// after correction throws, since that's the one thing that can't be
/// safely defaulted.
class FunnelSchemaValidator {
  const FunnelSchemaValidator._();

  static const List<String> validSectionTypes = [
    'hero',
    'navigation',
    'benefits',
    'features',
    'services',
    'products',
    'pricing',
    'testimonials',
    'statistics',
    'about',
    'faq',
    'contact',
    'lead_form',
    'appointment_cta',
    'final_cta',
    'footer',
    'custom',
  ];

  static String _str(dynamic value, [String fallback = '']) {
    if (value is String && value.trim().isNotEmpty) return value;
    return fallback;
  }

  static bool _isMap(dynamic value) => value is Map;

  static FunnelSection? _sanitizeSection(dynamic raw, int index) {
    if (!_isMap(raw)) return null;
    final map = (raw as Map).cast<String, dynamic>();
    final type = _str(map['type']).toLowerCase();
    if (!validSectionTypes.contains(type)) return null;
    final content = _isMap(map['content']) ? (map['content'] as Map).cast<String, dynamic>() : <String, dynamic>{};
    return FunnelSection(
      id: _str(map['id'], '$type-$index'),
      type: type,
      visible: map['visible'] != false,
      content: content,
    );
  }

  /// Validates and safely corrects a raw JSON map (as read from
  /// `funnels.content`, or produced by the editor) into a [FunnelSchema].
  /// Throws [FunnelValidationException] only if there are zero usable
  /// sections after correction.
  static FunnelSchema validate(
    Map<String, dynamic> raw, {
    String fallbackName = 'Untitled Funnel',
    String fallbackType = 'custom',
  }) {
    final name = _str(raw['name'], fallbackName);
    final rawType = _str(raw['type']).toLowerCase();
    final type = FunnelType.values.any((t) => t.value == rawType) ? rawType : fallbackType;

    final rawSections = raw['sections'];
    final sections = <FunnelSection>[];
    if (rawSections is List) {
      for (var i = 0; i < rawSections.length; i++) {
        final section = _sanitizeSection(rawSections[i], i);
        if (section != null) sections.add(section);
      }
    }

    if (sections.isEmpty) {
      throw const FunnelValidationException(
        'This funnel has no valid sections and cannot be displayed.',
      );
    }

    final metadataJson = _isMap(raw['metadata']) ? (raw['metadata'] as Map).cast<String, dynamic>() : null;
    final seoJson = _isMap(raw['seo']) ? (raw['seo'] as Map).cast<String, dynamic>() : null;
    final themeJson = _isMap(raw['theme']) ? (raw['theme'] as Map).cast<String, dynamic>() : null;
    final settingsJson = _isMap(raw['settings']) ? (raw['settings'] as Map).cast<String, dynamic>() : null;

    return FunnelSchema(
      version: (raw['version'] as num?)?.toInt() ?? 1,
      name: name,
      type: type,
      metadata: FunnelMetadataInfo.fromJson(metadataJson),
      theme: FunnelTheme.fromJson(themeJson),
      sections: sections,
      seo: FunnelSeo.fromJson(seoJson, fallbackTitle: name, fallbackDescription: name),
      settings: FunnelSettings.fromJson(settingsJson, sections: sections),
    );
  }
}
