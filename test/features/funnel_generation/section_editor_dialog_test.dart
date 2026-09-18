import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:createai_studio/features/funnel_generation/data/models/funnel_schema.dart';
import 'package:createai_studio/features/funnel_generation/presentation/widgets/section_editor_dialog.dart';

void main() {
  testWidgets('shows a text field per editable string content value, pre-filled', (tester) async {
    const section = FunnelSection(
      id: 'hero-1',
      type: 'hero',
      content: {'headline': 'Original headline', 'subheadline': 'Original subheadline'},
    );

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => SectionEditorDialog.show(context, section),
            child: const Text('Open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Hero'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Original headline'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Original subheadline'), findsOneWidget);
  });

  testWidgets('returns the edited field values on Save', (tester) async {
    const section = FunnelSection(id: 'hero-1', type: 'hero', content: {'headline': 'Old'});
    Map<String, dynamic>? result;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              result = await SectionEditorDialog.show(context, section);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'New headline');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(result, {'headline': 'New headline'});
  });

  testWidgets('returns null on Cancel', (tester) async {
    const section = FunnelSection(id: 'hero-1', type: 'hero', content: {'headline': 'Old'});
    Map<String, dynamic>? result = const {'unset': true};

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              result = await SectionEditorDialog.show(context, section);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets('notes non-string fields as not editable yet, without dropping them', (tester) async {
    const section = FunnelSection(
      id: 'faq-1',
      type: 'faq',
      content: {
        'title': 'FAQ',
        'items': [
          {'question': 'Q', 'answer': 'A'},
        ],
      },
    );

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => SectionEditorDialog.show(context, section),
            child: const Text('Open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'FAQ'), findsOneWidget);
    expect(find.textContaining("aren't editable yet"), findsOneWidget);
  });
}
