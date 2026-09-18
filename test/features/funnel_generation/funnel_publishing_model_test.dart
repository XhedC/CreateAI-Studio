import 'package:flutter_test/flutter_test.dart';
import 'package:createai_studio/core/config/env_config.dart';
import 'package:createai_studio/features/funnel_generation/data/models/funnel_model.dart';
import 'package:createai_studio/features/funnel_generation/data/models/public_funnel_view.dart';

Map<String, dynamic> _row({
  bool published = false,
  String? publishedAt,
  String? unpublishedAt,
  String? publicSlug,
  int publishedVersion = 0,
  String updatedAt = '2025-01-01T00:00:00.000Z',
}) => {
      'id': 'funnel-1',
      'user_id': 'user-1',
      'generation_id': 'gen-1',
      'name': 'Test Funnel',
      'funnel_type': 'custom',
      'status': 'draft',
      'schema_version': 1,
      'content': {
        'name': 'Test Funnel',
        'type': 'custom',
        'sections': [
          {'id': 'hero-1', 'type': 'hero', 'content': {'headline': 'Hi'}},
        ],
      },
      'created_at': '2025-01-01T00:00:00.000Z',
      'updated_at': updatedAt,
      'published': published,
      if (publishedAt != null) 'published_at': publishedAt,
      if (unpublishedAt != null) 'unpublished_at': unpublishedAt,
      if (publicSlug != null) 'public_slug': publicSlug,
      'published_version': publishedVersion,
    };

void main() {
  group('FunnelModel publishing fields', () {
    test('fromJson defaults to unpublished/draft when publishing columns are absent', () {
      final funnel = FunnelModel.fromJson(_row());

      expect(funnel.published, isFalse);
      expect(funnel.publishedAt, isNull);
      expect(funnel.unpublishedAt, isNull);
      expect(funnel.publicSlug, isNull);
      expect(funnel.publishedVersion, 0);
      expect(funnel.hasUnpublishedChanges, isFalse);
    });

    test('fromJson parses a fully published row', () {
      final funnel = FunnelModel.fromJson(_row(
        published: true,
        publishedAt: '2025-01-02T00:00:00.000Z',
        publicSlug: 'test-funnel',
        publishedVersion: 3,
        updatedAt: '2025-01-02T00:00:00.000Z',
      ));

      expect(funnel.published, isTrue);
      expect(funnel.publishedAt, DateTime.parse('2025-01-02T00:00:00.000Z'));
      expect(funnel.publicSlug, 'test-funnel');
      expect(funnel.publishedVersion, 3);
    });

    test('hasUnpublishedChanges is true once the draft is edited after the last publish', () {
      final funnel = FunnelModel.fromJson(_row(
        published: true,
        publishedAt: '2025-01-02T00:00:00.000Z',
        publicSlug: 'test-funnel',
        publishedVersion: 1,
        updatedAt: '2025-01-03T00:00:00.000Z', // edited AFTER publish
      ));

      expect(funnel.hasUnpublishedChanges, isTrue);
    });

    test('hasUnpublishedChanges is false immediately after publishing (same timestamp)', () {
      final funnel = FunnelModel.fromJson(_row(
        published: true,
        publishedAt: '2025-01-02T00:00:00.000Z',
        publicSlug: 'test-funnel',
        publishedVersion: 1,
        updatedAt: '2025-01-02T00:00:00.000Z',
      ));

      expect(funnel.hasUnpublishedChanges, isFalse);
    });

    test('hasUnpublishedChanges is always false once unpublished, even with a stale edit', () {
      final funnel = FunnelModel.fromJson(_row(
        published: false,
        publishedAt: '2025-01-02T00:00:00.000Z',
        publicSlug: 'test-funnel',
        publishedVersion: 1,
        updatedAt: '2025-01-05T00:00:00.000Z',
      ));

      expect(funnel.hasUnpublishedChanges, isFalse);
    });

    test('copyWith preserves publishing fields not explicitly overridden', () {
      final original = FunnelModel.fromJson(_row(
        published: true,
        publishedAt: '2025-01-02T00:00:00.000Z',
        publicSlug: 'test-funnel',
        publishedVersion: 2,
      ));

      final copy = original.copyWith(name: 'Renamed');

      expect(copy.name, 'Renamed');
      expect(copy.published, isTrue);
      expect(copy.publicSlug, 'test-funnel');
      expect(copy.publishedVersion, 2);
    });
  });

  group('PublicFunnelView.fromJson', () {
    test('parses the sanitized shape returned by get_public_funnel', () {
      final view = PublicFunnelView.fromJson({
        'name': 'Test Funnel',
        'funnelType': 'custom',
        'content': {
          'name': 'Test Funnel',
          'type': 'custom',
          'sections': [
            {'id': 'hero-1', 'type': 'hero', 'content': {'headline': 'Hi'}},
          ],
        },
        'publicSlug': 'test-funnel',
        'publishedAt': '2025-01-02T00:00:00.000Z',
        'publishedVersion': 2,
      });

      expect(view.name, 'Test Funnel');
      expect(view.publicSlug, 'test-funnel');
      expect(view.publishedVersion, 2);
      expect(view.content.sections, hasLength(1));
    });
  });

  group('EnvConfig.publicFunnelUrl', () {
    test('falls back to a relative path when PUBLIC_APP_URL is unconfigured', () {
      // The test build never sets --dart-define=PUBLIC_APP_URL, so this
      // exercises the real default - never a fake production-looking URL.
      expect(EnvConfig.publicFunnelUrl('my-slug'), '/f/my-slug');
    });
  });
}
