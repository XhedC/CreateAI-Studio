import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../../../../core/widgets/loading_widget.dart';
import '../../data/models/funnel_schema.dart';
import '../providers/funnel_providers.dart';
import '../widgets/section_editor_dialog.dart';

/// A basic, stable structured funnel editor - not a full website builder.
/// Users can edit each section's simple text fields, reorder sections
/// (drag-and-drop via [ReorderableListView], with Move Up/Down buttons as
/// an always-available fallback per the brief), hide/show, delete, and add
/// new sections, then Save. See docs/funnel-generation.md.
class FunnelEditorScreen extends ConsumerStatefulWidget {
  const FunnelEditorScreen({super.key, required this.funnelId});

  final String funnelId;

  @override
  ConsumerState<FunnelEditorScreen> createState() => _FunnelEditorScreenState();
}

class _FunnelEditorScreenState extends ConsumerState<FunnelEditorScreen> {
  bool _isSaving = false;

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final ok = await ref.read(funnelEditorProvider(widget.funnelId).notifier).save();
    if (!mounted) return;
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Funnel saved.' : 'Unable to save the funnel. Please try again.')),
    );
  }

  Future<void> _editSection(FunnelSection section) async {
    final changes = await SectionEditorDialog.show(context, section);
    if (changes == null || !mounted) return;
    ref.read(funnelEditorProvider(widget.funnelId).notifier).updateSectionContent(
          section.id,
          changes,
        );
  }

  void _confirmDeleteSection(FunnelSection section) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this section?'),
        content: const Text('This will remove the section from your funnel.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(funnelEditorProvider(widget.funnelId).notifier).removeSection(section.id);
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showAddSectionSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Add section', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            for (final type in FunnelSectionType.values)
              ListTile(
                title: Text(type.label),
                onTap: () {
                  ref.read(funnelEditorProvider(widget.funnelId).notifier).addSection(type);
                  Navigator.of(sheetContext).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final funnelAsync = ref.watch(funnelEditorProvider(widget.funnelId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Funnel'),
        actions: [
          IconButton(
            tooltip: 'Preview',
            icon: const Icon(Icons.visibility_outlined),
            onPressed: () => context.push(RoutePaths.funnelPreview(widget.funnelId)),
          ),
          IconButton(
            tooltip: 'Save',
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            onPressed: _isSaving ? null : _save,
          ),
        ],
      ),
      body: funnelAsync.when(
        loading: () => const LoadingWidget(),
        error: (_, __) => const AppErrorWidget(),
        data: (funnel) {
          final sections = funnel.content.sections;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextFormField(
                  key: ValueKey(funnel.content.name),
                  initialValue: funnel.content.name,
                  decoration: const InputDecoration(labelText: 'Funnel name'),
                  onChanged: (value) =>
                      ref.read(funnelEditorProvider(widget.funnelId).notifier).updateName(value),
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 90),
                  itemCount: sections.length,
                  onReorder: (oldIndex, newIndex) => ref
                      .read(funnelEditorProvider(widget.funnelId).notifier)
                      .reorderSections(oldIndex, newIndex),
                  itemBuilder: (context, index) {
                    final section = sections[index];
                    final type = FunnelSectionType.fromValue(section.type);
                    final preview = (section.content['headline'] ??
                            section.content['title'] ??
                            section.content['businessName'] ??
                            '') as String? ??
                        '';
                    return Card(
                      key: ValueKey(section.id),
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        leading: ReorderableDragStartListener(
                          index: index,
                          child: const Icon(Icons.drag_indicator_rounded),
                        ),
                        title: Text(type?.label ?? section.type),
                        subtitle: preview.isNotEmpty ? Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Move up',
                              icon: const Icon(Icons.arrow_upward_rounded),
                              onPressed: index == 0
                                  ? null
                                  : () => ref
                                      .read(funnelEditorProvider(widget.funnelId).notifier)
                                      .moveSectionUp(section.id),
                            ),
                            IconButton(
                              tooltip: 'Move down',
                              icon: const Icon(Icons.arrow_downward_rounded),
                              onPressed: index == sections.length - 1
                                  ? null
                                  : () => ref
                                      .read(funnelEditorProvider(widget.funnelId).notifier)
                                      .moveSectionDown(section.id),
                            ),
                            Switch(
                              value: section.visible,
                              onChanged: (value) => ref
                                  .read(funnelEditorProvider(widget.funnelId).notifier)
                                  .setSectionVisible(section.id, value),
                            ),
                            IconButton(
                              tooltip: 'Edit section',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _editSection(section),
                            ),
                            IconButton(
                              tooltip: 'Delete section',
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () => _confirmDeleteSection(section),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSectionSheet,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Section'),
      ),
    );
  }
}
