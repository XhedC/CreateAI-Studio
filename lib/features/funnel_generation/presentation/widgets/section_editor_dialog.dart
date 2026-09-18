import 'package:flutter/material.dart';

import '../../data/models/funnel_schema.dart';

/// Edits one section's simple (string) content fields - headline,
/// subheadline, CTA, titles, descriptions, and so on. List/nested-map
/// fields (e.g. a benefits section's `items`) aren't item-editable yet in
/// this version - shown as a read-only count instead of silently dropped,
/// per the brief's "focus on a stable structured editor, not a full
/// website builder yet."
class SectionEditorDialog extends StatefulWidget {
  const SectionEditorDialog({super.key, required this.section});

  final FunnelSection section;

  /// Returns the edited field map on Save, or null if cancelled.
  static Future<Map<String, dynamic>?> show(BuildContext context, FunnelSection section) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => SectionEditorDialog(section: section),
    );
  }

  @override
  State<SectionEditorDialog> createState() => _SectionEditorDialogState();
}

class _SectionEditorDialogState extends State<SectionEditorDialog> {
  late final Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final entry in widget.section.content.entries)
        if (entry.value is String) entry.key: TextEditingController(text: entry.value as String),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _labelFor(String key) {
    final spaced = key.replaceAllMapped(
      RegExp('([a-z])([A-Z])'),
      (m) => '${m.group(1)} ${m.group(2)}',
    );
    final withSpaces = spaced.replaceAll('_', ' ');
    return withSpaces[0].toUpperCase() + withSpaces.substring(1);
  }

  bool _isMultiline(String key) {
    final lower = key.toLowerCase();
    return lower.contains('description') || lower.contains('subheadline') || lower == 'tagline';
  }

  @override
  Widget build(BuildContext context) {
    final nonEditableCount =
        widget.section.content.entries.where((e) => e.value is! String).length;
    final type = FunnelSectionType.fromValue(widget.section.type);

    return AlertDialog(
      title: Text('Edit ${type?.label ?? widget.section.type}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_controllers.isEmpty)
              const Text('This section has no editable text fields.')
            else
              for (final entry in _controllers.entries) ...[
                TextField(
                  controller: entry.value,
                  minLines: 1,
                  maxLines: _isMultiline(entry.key) ? 4 : 1,
                  decoration: InputDecoration(labelText: _labelFor(entry.key)),
                ),
                const SizedBox(height: 12),
              ],
            if (nonEditableCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '$nonEditableCount additional field(s) in this section (e.g. lists) '
                  "aren't editable yet in this version.",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop({
            for (final entry in _controllers.entries) entry.key: entry.value.text,
          }),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
