import 'package:flutter_test/flutter_test.dart';
import 'package:createai_studio/features/funnel_generation/data/models/funnel_model.dart';
import 'package:createai_studio/features/funnel_generation/data/models/funnel_schema_validator.dart';

Map<String, dynamic> _validRaw() => {
      'version': 1,
      'name': 'CrossCare Pharmacy',
      'type': 'pharmacy',
      'metadata': {
        'business_name': 'CrossCare Pharmacy',
        'business_type': 'Pharmacy',
        'target_audience': 'Local residents',
        'goal': 'generate_leads',
        'offer': '10% off first order',
        'cta': 'Order Now',
      },
      'theme': {
        'primaryColor': '#2563EB',
        'secondaryColor': '#0F172A',
        'backgroundColor': '#FFFFFF',
        'textColor': '#0F172A',
        'fontFamily': 'Inter',
      },
      'sections': [
        {
          'id': 'hero-1',
          'type': 'hero',
          'visible': true,
          'content': {'headline': 'Fast, reliable medicine delivery', 'cta': 'Order Now'},
        },
        {
          'id': 'faq-1',
          'type': 'faq',
          'visible': true,
          'content': {
            'title': 'FAQ',
            'items': [
              {'question': 'Do you deliver?', 'answer': 'Yes, same day.'},
            ],
          },
        },
      ],
      'seo': {
        'title': 'CrossCare Pharmacy',
        'description': 'Online consultation and medicine delivery.',
        'ogTitle': 'CrossCare Pharmacy',
        'ogDescription': 'Online consultation and medicine delivery.',
      },
      'settings': {'showNavigation': true, 'enableLeadCapture': false},
    };

void main() {
  group('FunnelSchemaValidator.validate', () {
    test('accepts a fully well-formed document unchanged', () {
      final schema = FunnelSchemaValidator.validate(_validRaw());

      expect(schema.name, 'CrossCare Pharmacy');
      expect(schema.type, 'pharmacy');
      expect(schema.sections, hasLength(2));
      expect(schema.sections.first.type, 'hero');
      expect(schema.theme.primaryColor, '#2563EB');
      expect(schema.metadata.goal, 'generate_leads');
    });

    test('drops a section with an unrecognized type but keeps the rest', () {
      final raw = _validRaw();
      (raw['sections'] as List).add({
        'id': 'weird-1',
        'type': 'not_a_real_section_type',
        'content': {},
      });

      final schema = FunnelSchemaValidator.validate(raw);

      expect(schema.sections, hasLength(2));
      expect(schema.sections.any((s) => s.type == 'not_a_real_section_type'), isFalse);
    });

    test('throws FunnelValidationException when there are zero usable sections', () {
      final raw = _validRaw();
      raw['sections'] = [
        {'id': 'x', 'type': 'not_real', 'content': {}},
      ];

      expect(
        () => FunnelSchemaValidator.validate(raw),
        throwsA(isA<FunnelValidationException>()),
      );
    });

    test('throws FunnelValidationException when sections is missing entirely', () {
      final raw = _validRaw();
      raw.remove('sections');

      expect(
        () => FunnelSchemaValidator.validate(raw),
        throwsA(isA<FunnelValidationException>()),
      );
    });

    test('falls back to a default theme color when given an invalid hex value', () {
      final raw = _validRaw();
      raw['theme'] = {'primaryColor': 'not-a-color', 'fontFamily': 'Inter'};

      final schema = FunnelSchemaValidator.validate(raw);

      expect(schema.theme.primaryColor, '#2563EB');
      expect(schema.theme.fontFamily, 'Inter');
    });

    test('falls back to sensible SEO values when seo is missing', () {
      final raw = _validRaw();
      raw.remove('seo');

      final schema = FunnelSchemaValidator.validate(raw, fallbackName: 'Untitled Funnel');

      expect(schema.seo.title, schema.name);
      expect(schema.seo.ogTitle, schema.seo.title);
    });

    test('falls back to the provided fallback type when type is invalid', () {
      final raw = _validRaw();
      raw['type'] = 'not-a-real-funnel-type';

      final schema = FunnelSchemaValidator.validate(raw, fallbackType: 'custom');

      expect(schema.type, 'custom');
    });

    test('infers enableLeadCapture from a lead_form section when settings is missing', () {
      final raw = _validRaw();
      raw.remove('settings');
      (raw['sections'] as List).add({
        'id': 'lead-1',
        'type': 'lead_form',
        'content': {'title': 'Get in touch'},
      });

      final schema = FunnelSchemaValidator.validate(raw);

      expect(schema.settings.enableLeadCapture, isTrue);
    });
  });

  group('FunnelModel.fromJson', () {
    test('parses a full funnels row, validating content through FunnelSchemaValidator', () {
      final json = {
        'id': 'funnel-1',
        'user_id': 'user-1',
        'project_id': null,
        'generation_id': 'gen-1',
        'name': 'CrossCare Pharmacy',
        'description': null,
        'funnel_type': 'pharmacy',
        'status': 'draft',
        'schema_version': 1,
        'content': _validRaw(),
        'thumbnail_url': null,
        'created_at': '2025-01-01T00:00:00.000Z',
        'updated_at': '2025-01-01T00:00:00.000Z',
      };

      final funnel = FunnelModel.fromJson(json);

      expect(funnel.id, 'funnel-1');
      expect(funnel.generationId, 'gen-1');
      expect(funnel.content.sections, hasLength(2));
    });

    test('recovers with a fallback name/type when content is malformed but has sections', () {
      final json = {
        'id': 'funnel-1',
        'user_id': 'user-1',
        'project_id': null,
        'generation_id': 'gen-1',
        'name': 'My Funnel',
        'description': null,
        'funnel_type': 'custom',
        'status': 'draft',
        'schema_version': 1,
        'content': {
          'sections': [
            {'id': 'hero-1', 'type': 'hero', 'content': {}},
          ],
        },
        'thumbnail_url': null,
        'created_at': '2025-01-01T00:00:00.000Z',
        'updated_at': '2025-01-01T00:00:00.000Z',
      };

      final funnel = FunnelModel.fromJson(json);

      expect(funnel.content.name, 'My Funnel');
      expect(funnel.content.type, 'custom');
    });
  });
}
