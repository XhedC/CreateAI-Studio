import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/creation_type.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/router/route_paths.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../projects/presentation/providers/project_providers.dart';
import '../../services/file_upload_service.dart';
import '../providers/generation_providers.dart';
import '../widgets/creation_type_selector.dart';
import '../widgets/upload_attachments_field.dart';

class CreateScreen extends ConsumerStatefulWidget {
  const CreateScreen({super.key});

  @override
  ConsumerState<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends ConsumerState<CreateScreen> {
  CreationType _selectedType = CreationType.text;
  String? _selectedProjectId;
  final _promptController = TextEditingController();
  List<UploadedFile> _attachments = [];
  bool _advancedExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = ref.read(pendingCreationTypeProvider);
      if (pending != null && mounted) {
        setState(() => _selectedType = pending);
        ref.read(pendingCreationTypeProvider.notifier).set(null);
      }
    });
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_promptController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe what you would like to create.')),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    final controller = ref.read(createGenerationControllerProvider.notifier);
    final ok = await controller.submit(
      type: _selectedType,
      prompt: _promptController.text,
      projectId: _selectedProjectId,
      attachmentUrls: _attachments.map((f) => f.publicUrl).toList(),
    );

    if (!mounted) return;

    if (ok) {
      final generation = ref.read(createGenerationControllerProvider).value;
      _promptController.clear();
      setState(() => _attachments = []);
      controller.reset();
      if (generation != null) {
        context.push(RoutePaths.generationDetail(generation.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final createState = ref.watch(createGenerationControllerProvider);
    final isGenerating = createState.isLoading;
    final projectsAsync = ref.watch(projectsProvider);

    ref.listen(createGenerationControllerProvider, (previous, next) {
      if (next is AsyncError && next.error is AppException) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text((next.error as AppException).message)),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Create')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Choose creation type',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            CreationTypeSelector(
              selected: _selectedType,
              onSelected: (type) {
                if (type == CreationType.image) {
                  // Image/Music/Video generation each have their own
                  // dedicated, richer screens rather than the generic
                  // inline flow below.
                  context.push(RoutePaths.createImage);
                  return;
                }
                if (type == CreationType.music) {
                  context.push(RoutePaths.createMusic);
                  return;
                }
                if (type == CreationType.video) {
                  context.push(RoutePaths.createVideo);
                  return;
                }
                if (type == CreationType.funnel) {
                  context.push(RoutePaths.createFunnel);
                  return;
                }
                setState(() => _selectedType = type);
              },
            ),
            const SizedBox(height: 20),
            Text(
              'What would you like to create?',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _promptController,
              maxLines: 5,
              minLines: 3,
              decoration: InputDecoration(
                hintText: switch (_selectedType) {
                  CreationType.text => 'Ask anything or describe what to write...',
                  CreationType.image => 'e.g. A modern advertisement for a pharmacy',
                  CreationType.music => 'e.g. An upbeat corporate jingle, 30 seconds',
                  CreationType.video => 'e.g. A 10-second product teaser video',
                  CreationType.funnel => 'e.g. A landing page for a new fitness app',
                },
              ),
            ),
            const SizedBox(height: 16),
            UploadAttachmentsField(
              onChanged: (files) => setState(() => _attachments = files),
            ),
            const SizedBox(height: 16),
            projectsAsync.maybeWhen(
              data: (projects) => projects.isEmpty
                  ? const SizedBox.shrink()
                  : DropdownButtonFormField<String?>(
                      value: _selectedProjectId,
                      decoration: const InputDecoration(labelText: 'Add to project (optional)'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('None')),
                        for (final project in projects)
                          DropdownMenuItem(value: project.id, child: Text(project.name)),
                      ],
                      onChanged: (value) => setState(() => _selectedProjectId = value),
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              title: const Text('Advanced options'),
              initiallyExpanded: _advancedExpanded,
              onExpansionChanged: (v) => setState(() => _advancedExpanded = v),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 12),
              children: const [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.tune_rounded),
                  title: Text('Style, tone & format controls'),
                  subtitle: Text('Coming soon with real AI provider integrations.'),
                  enabled: false,
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppButton(
              label: 'Generate',
              icon: Icons.auto_awesome_rounded,
              isLoading: isGenerating,
              onPressed: _generate,
            ),
          ],
        ),
      ),
    );
  }
}
