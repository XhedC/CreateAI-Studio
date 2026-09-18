import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:createai_studio/features/funnel_generation/data/models/funnel_schema.dart';
import 'package:createai_studio/features/funnel_generation/presentation/widgets/funnel_renderer.dart';

FunnelSchema _schema(List<FunnelSection> sections) => FunnelSchema(
      name: 'Test Funnel',
      type: 'custom',
      metadata: const FunnelMetadataInfo(),
      theme: const FunnelTheme(),
      sections: sections,
      seo: const FunnelSeo(title: 'Test', description: 'Test', ogTitle: 'Test', ogDescription: 'Test'),
      settings: const FunnelSettings(),
    );

Future<void> _pump(WidgetTester tester, FunnelSchema schema, {bool onlyVisible = true}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: FunnelRenderer(schema: schema, onlyVisible: onlyVisible),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders a hero section headline, subheadline, and CTA', (tester) async {
    await _pump(
      tester,
      _schema(const [
        FunnelSection(
          id: 'hero-1',
          type: 'hero',
          content: {'headline': 'Fast medicine delivery', 'subheadline': 'Right to your door', 'cta': 'Order Now'},
        ),
      ]),
    );

    expect(find.text('Fast medicine delivery'), findsOneWidget);
    expect(find.text('Right to your door'), findsOneWidget);
    expect(find.text('Order Now'), findsOneWidget);
  });

  testWidgets('does not render a hidden section when onlyVisible is true', (tester) async {
    await _pump(
      tester,
      _schema(const [
        FunnelSection(id: 'hero-1', type: 'hero', content: {'headline': 'Visible hero'}),
        FunnelSection(id: 'faq-1', type: 'faq', visible: false, content: {'title': 'Hidden FAQ'}),
      ]),
    );

    expect(find.text('Visible hero'), findsOneWidget);
    expect(find.text('Hidden FAQ'), findsNothing);
  });

  testWidgets('renders a hidden section when onlyVisible is false', (tester) async {
    await _pump(
      tester,
      _schema(const [
        FunnelSection(id: 'faq-1', type: 'faq', visible: false, content: {'title': 'Hidden FAQ'}),
      ]),
      onlyVisible: false,
    );

    expect(find.text('Hidden FAQ'), findsOneWidget);
  });

  testWidgets('falls back to a generic card for an unrecognized section type', (tester) async {
    await _pump(
      tester,
      _schema(const [
        FunnelSection(id: 'x-1', type: 'not_a_real_type', content: {'title': 'Mystery section'}),
      ]),
    );

    expect(find.text('Mystery section'), findsOneWidget);
  });

  testWidgets('renders FAQ items as expandable tiles', (tester) async {
    await _pump(
      tester,
      _schema(const [
        FunnelSection(
          id: 'faq-1',
          type: 'faq',
          content: {
            'title': 'FAQ',
            'items': [
              {'question': 'Do you deliver?', 'answer': 'Yes, same day.'},
            ],
          },
        ),
      ]),
    );

    expect(find.text('Do you deliver?'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsOneWidget);
  });
}
