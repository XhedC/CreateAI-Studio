import 'package:equatable/equatable.dart';

/// The kinds of funnel a user can pick when generating - mirrors
/// `VALID_FUNNEL_TYPES` in supabase/functions/generate-funnel/schema.ts and
/// the `funnels.funnel_type` check constraint. Keep both in sync.
enum FunnelType {
  leadGeneration('lead_generation', 'Lead Generation'),
  productSales('product_sales', 'Product Sales'),
  serviceBusiness('service_business', 'Service Business'),
  appointmentBooking('appointment_booking', 'Appointment Booking'),
  eventRegistration('event_registration', 'Event Registration'),
  restaurant('restaurant', 'Restaurant'),
  pharmacy('pharmacy', 'Pharmacy'),
  healthcare('healthcare', 'Healthcare'),
  realEstate('real_estate', 'Real Estate'),
  personalBrand('personal_brand', 'Personal Brand'),
  agency('agency', 'Agency'),
  ecommerce('ecommerce', 'E-commerce'),
  course('course', 'Course'),
  portfolio('portfolio', 'Portfolio'),
  custom('custom', 'Custom');

  const FunnelType(this.value, this.label);
  final String value;
  final String label;

  static FunnelType fromValue(String? value) => FunnelType.values.firstWhere(
        (t) => t.value == value,
        orElse: () => FunnelType.custom,
      );
}

/// The business goal a funnel is built around - stored in
/// `funnels.content.metadata.goal` and used to decide which sections a
/// generated funnel should include.
enum FunnelGoal {
  generateLeads('generate_leads', 'Generate Leads'),
  sellProduct('sell_product', 'Sell Product'),
  bookAppointment('book_appointment', 'Book Appointment'),
  collectContactInfo('collect_contact_info', 'Collect Contact Information'),
  promoteService('promote_service', 'Promote Service'),
  buildBrandAwareness('build_brand_awareness', 'Build Brand Awareness'),
  eventRegistration('event_registration', 'Event Registration'),
  custom('custom', 'Custom');

  const FunnelGoal(this.value, this.label);
  final String value;
  final String label;

  static FunnelGoal fromValue(String? value) => FunnelGoal.values.firstWhere(
        (g) => g.value == value,
        orElse: () => FunnelGoal.custom,
      );
}

/// Every section type [FunnelRenderer] knows how to draw - mirrors
/// `VALID_SECTION_TYPES` in the Edge Function's schema.ts.
enum FunnelSectionType {
  hero('hero', 'Hero'),
  navigation('navigation', 'Navigation'),
  benefits('benefits', 'Benefits'),
  features('features', 'Features'),
  services('services', 'Services'),
  products('products', 'Products'),
  pricing('pricing', 'Pricing'),
  testimonials('testimonials', 'Testimonials'),
  statistics('statistics', 'Statistics'),
  about('about', 'About'),
  faq('faq', 'FAQ'),
  contact('contact', 'Contact'),
  leadForm('lead_form', 'Lead Form'),
  appointmentCta('appointment_cta', 'Appointment CTA'),
  finalCta('final_cta', 'Final CTA'),
  footer('footer', 'Footer'),
  custom('custom', 'Custom');

  const FunnelSectionType(this.value, this.label);
  final String value;
  final String label;

  static FunnelSectionType? fromValue(String? value) {
    for (final t in FunnelSectionType.values) {
      if (t.value == value) return t;
    }
    return null;
  }
}

class FunnelTheme extends Equatable {
  const FunnelTheme({
    this.primaryColor = '#2563EB',
    this.secondaryColor = '#0F172A',
    this.backgroundColor = '#FFFFFF',
    this.textColor = '#0F172A',
    this.fontFamily = 'Inter',
    this.logoUrl,
  });

  final String primaryColor;
  final String secondaryColor;
  final String backgroundColor;
  final String textColor;
  final String fontFamily;
  final String? logoUrl;

  static final RegExp _hexColor = RegExp(r'^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$');

  static String _color(dynamic value, String fallback) {
    if (value is String && _hexColor.hasMatch(value)) return value;
    return fallback;
  }

  factory FunnelTheme.fromJson(Map<String, dynamic>? json) {
    const fallback = FunnelTheme();
    final j = json ?? const {};
    return FunnelTheme(
      primaryColor: _color(j['primaryColor'], fallback.primaryColor),
      secondaryColor: _color(j['secondaryColor'], fallback.secondaryColor),
      backgroundColor: _color(j['backgroundColor'], fallback.backgroundColor),
      textColor: _color(j['textColor'], fallback.textColor),
      fontFamily: (j['fontFamily'] as String?)?.trim().isNotEmpty == true
          ? j['fontFamily'] as String
          : fallback.fontFamily,
      logoUrl: j['logoUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'primaryColor': primaryColor,
        'secondaryColor': secondaryColor,
        'backgroundColor': backgroundColor,
        'textColor': textColor,
        'fontFamily': fontFamily,
        if (logoUrl != null) 'logoUrl': logoUrl,
      };

  FunnelTheme copyWith({
    String? primaryColor,
    String? secondaryColor,
    String? backgroundColor,
    String? textColor,
    String? fontFamily,
    String? logoUrl,
  }) =>
      FunnelTheme(
        primaryColor: primaryColor ?? this.primaryColor,
        secondaryColor: secondaryColor ?? this.secondaryColor,
        backgroundColor: backgroundColor ?? this.backgroundColor,
        textColor: textColor ?? this.textColor,
        fontFamily: fontFamily ?? this.fontFamily,
        logoUrl: logoUrl ?? this.logoUrl,
      );

  @override
  List<Object?> get props =>
      [primaryColor, secondaryColor, backgroundColor, textColor, fontFamily, logoUrl];
}

class FunnelSeo extends Equatable {
  const FunnelSeo({
    required this.title,
    required this.description,
    required this.ogTitle,
    required this.ogDescription,
  });

  final String title;
  final String description;
  final String ogTitle;
  final String ogDescription;

  factory FunnelSeo.fromJson(
    Map<String, dynamic>? json, {
    required String fallbackTitle,
    required String fallbackDescription,
  }) {
    final j = json ?? const {};
    final title = (j['title'] as String?)?.trim().isNotEmpty == true
        ? j['title'] as String
        : fallbackTitle;
    final description = (j['description'] as String?)?.trim().isNotEmpty == true
        ? j['description'] as String
        : fallbackDescription;
    return FunnelSeo(
      title: title,
      description: description,
      ogTitle: (j['ogTitle'] as String?)?.trim().isNotEmpty == true ? j['ogTitle'] as String : title,
      ogDescription: (j['ogDescription'] as String?)?.trim().isNotEmpty == true
          ? j['ogDescription'] as String
          : description,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'ogTitle': ogTitle,
        'ogDescription': ogDescription,
      };

  FunnelSeo copyWith({String? title, String? description, String? ogTitle, String? ogDescription}) =>
      FunnelSeo(
        title: title ?? this.title,
        description: description ?? this.description,
        ogTitle: ogTitle ?? this.ogTitle,
        ogDescription: ogDescription ?? this.ogDescription,
      );

  @override
  List<Object?> get props => [title, description, ogTitle, ogDescription];
}

class FunnelSettings extends Equatable {
  const FunnelSettings({this.showNavigation = true, this.enableLeadCapture = false});

  final bool showNavigation;
  final bool enableLeadCapture;

  factory FunnelSettings.fromJson(Map<String, dynamic>? json, {required List<FunnelSection> sections}) {
    final j = json ?? const {};
    return FunnelSettings(
      showNavigation: j['showNavigation'] as bool? ??
          sections.any((s) => s.type == FunnelSectionType.navigation.value),
      enableLeadCapture: j['enableLeadCapture'] as bool? ??
          sections.any((s) => s.type == FunnelSectionType.leadForm.value),
    );
  }

  Map<String, dynamic> toJson() => {
        'showNavigation': showNavigation,
        'enableLeadCapture': enableLeadCapture,
      };

  FunnelSettings copyWith({bool? showNavigation, bool? enableLeadCapture}) => FunnelSettings(
        showNavigation: showNavigation ?? this.showNavigation,
        enableLeadCapture: enableLeadCapture ?? this.enableLeadCapture,
      );

  @override
  List<Object?> get props => [showNavigation, enableLeadCapture];
}

class FunnelMetadataInfo extends Equatable {
  const FunnelMetadataInfo({
    this.businessName = '',
    this.businessType = '',
    this.targetAudience = '',
    this.goal = 'custom',
    this.offer = '',
    this.cta = '',
  });

  final String businessName;
  final String businessType;
  final String targetAudience;
  final String goal;
  final String offer;
  final String cta;

  factory FunnelMetadataInfo.fromJson(Map<String, dynamic>? json) {
    final j = json ?? const {};
    return FunnelMetadataInfo(
      businessName: (j['business_name'] as String?) ?? '',
      businessType: (j['business_type'] as String?) ?? '',
      targetAudience: (j['target_audience'] as String?) ?? '',
      goal: (j['goal'] as String?) ?? 'custom',
      offer: (j['offer'] as String?) ?? '',
      cta: (j['cta'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'business_name': businessName,
        'business_type': businessType,
        'target_audience': targetAudience,
        'goal': goal,
        'offer': offer,
        'cta': cta,
      };

  @override
  List<Object?> get props => [businessName, businessType, targetAudience, goal, offer, cta];
}

class FunnelSection extends Equatable {
  const FunnelSection({
    required this.id,
    required this.type,
    this.visible = true,
    this.content = const {},
  });

  final String id;

  /// Raw string matching [FunnelSectionType.value] - kept as a string
  /// (rather than the enum itself) so an unrecognized-but-otherwise-valid
  /// section from a future schema version doesn't crash parsing; the
  /// renderer falls back to a generic card for anything it doesn't
  /// recognize instead of throwing.
  final String type;
  final bool visible;
  final Map<String, dynamic> content;

  factory FunnelSection.fromJson(Map<String, dynamic> json) => FunnelSection(
        id: (json['id'] as String?) ?? '',
        type: (json['type'] as String?) ?? '',
        visible: json['visible'] as bool? ?? true,
        content: (json['content'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'visible': visible,
        'content': content,
      };

  FunnelSection copyWith({String? id, String? type, bool? visible, Map<String, dynamic>? content}) =>
      FunnelSection(
        id: id ?? this.id,
        type: type ?? this.type,
        visible: visible ?? this.visible,
        content: content ?? this.content,
      );

  @override
  List<Object?> get props => [id, type, visible, content];
}

/// The validated, versioned funnel document - the Dart mirror of
/// `FunnelSchema` in supabase/functions/generate-funnel/types.ts. Always
/// construct this via [FunnelSchemaValidator.validate] rather than calling
/// [fromJson] directly on untrusted data - see funnel_schema_validator.dart.
class FunnelSchema extends Equatable {
  const FunnelSchema({
    this.version = 1,
    required this.name,
    required this.type,
    required this.metadata,
    required this.theme,
    required this.sections,
    required this.seo,
    required this.settings,
  });

  final int version;
  final String name;
  final String type;
  final FunnelMetadataInfo metadata;
  final FunnelTheme theme;
  final List<FunnelSection> sections;
  final FunnelSeo seo;
  final FunnelSettings settings;

  Map<String, dynamic> toJson() => {
        'version': version,
        'name': name,
        'type': type,
        'metadata': metadata.toJson(),
        'theme': theme.toJson(),
        'sections': sections.map((s) => s.toJson()).toList(),
        'seo': seo.toJson(),
        'settings': settings.toJson(),
      };

  FunnelSchema copyWith({
    String? name,
    String? type,
    FunnelMetadataInfo? metadata,
    FunnelTheme? theme,
    List<FunnelSection>? sections,
    FunnelSeo? seo,
    FunnelSettings? settings,
  }) =>
      FunnelSchema(
        version: version,
        name: name ?? this.name,
        type: type ?? this.type,
        metadata: metadata ?? this.metadata,
        theme: theme ?? this.theme,
        sections: sections ?? this.sections,
        seo: seo ?? this.seo,
        settings: settings ?? this.settings,
      );

  @override
  List<Object?> get props => [version, name, type, metadata, theme, sections, seo, settings];
}
