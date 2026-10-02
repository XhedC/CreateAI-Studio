import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../credits/presentation/providers/credits_providers.dart';
import '../../../credits/presentation/widgets/generation_cost_label.dart';
import '../../../credits/presentation/widgets/insufficient_credits_dialog.dart';
import '../../../image_generation/presentation/providers/image_generation_providers.dart'
    show referenceImageProvider;
import '../../../image_generation/presentation/widgets/reference_image_picker_field.dart';
import '../../data/models/video_maker_settings.dart';
import '../../data/models/video_segment_model.dart';
import '../providers/video_maker_providers.dart';
import '../widgets/input_mode_tab_bar.dart';
import '../widgets/video_maker_settings_panel.dart';
import '../widgets/voice_recorder_widget.dart';

class VideoMakerScreen extends ConsumerStatefulWidget {
  const VideoMakerScreen({super.key});

  @override
  ConsumerState<VideoMakerScreen> createState() => _VideoMakerScreenState();
}

class _VideoMakerScreenState extends ConsumerState<VideoMakerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _promptController = TextEditingController();
  final _titleController = TextEditingController();
  String? _voiceRecordingPath;
  bool _isGenerating = false;

  @override
  void dispose() {
    _promptController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _createAndGenerate() async {
    final settings = ref.read(videoMakerSettingsProvider);
    final inputMode = settings.inputMode;

    if (inputMode != VideoInputMode.voice &&
        !_formKey.currentState!.validate()) {
      return;
    }

    if (inputMode == VideoInputMode.voice && _voiceRecordingPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please record your voice narration first.')),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isGenerating = true);

    final storyNotifier = ref.read(activeStoryProvider.notifier);

    final title = _titleController.text.trim().isNotEmpty
        ? _titleController.text.trim()
        : 'Video Story ${DateTime.now().millisecondsSinceEpoch % 10000}';

    final created = await storyNotifier.createStory(title: title);
    if (!created || !mounted) {
      setState(() => _isGenerating = false);
      return;
    }

    final prompt = inputMode == VideoInputMode.voice
        ? 'Voice narration video'
        : _promptController.text.trim();

    final segmentAdded = await storyNotifier.addSegment(
      prompt: prompt,
      inputType: SegmentInputType.values.firstWhere(
        (s) => s.value == inputMode.value,
      ),
      durationSeconds: settings.durationSeconds,
      photoUrl: inputMode == VideoInputMode.photo
          ? ref.read(referenceImageProvider)?.file.path
          : null,
      voiceUrl: inputMode == VideoInputMode.voice ? _voiceRecordingPath : null,
    );

    if (!segmentAdded || !mounted) {
      setState(() => _isGenerating = false);
      return;
    }

    final storyState = ref.read(activeStoryProvider);
    final firstSegment = storyState.story?.segments.firstOrNull;
    if (firstSegment != null) {
      await storyNotifier.generateSegment(firstSegment.id);
    }

    setState(() => _isGenerating = false);

    if (!mounted) return;
    final storyId = ref.read(activeStoryProvider).story?.id;
    if (storyId != null) {
      context.push(RoutePaths.videoStoryEditor(storyId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(videoMakerSettingsProvider);
    final settingsNotifier = ref.read(videoMakerSettingsProvider.notifier);
    final creditsAsync = ref.watch(creditSummaryProvider);
    final colors = Theme.of(context).colorScheme;

    ref.listen(activeStoryProvider, (previous, next) {
      if (next.error != null) {
        final error = next.error!;
        if (error.code == 'INSUFFICIENT_CREDITS') {
          showInsufficientCreditsDialog(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.message)),
          );
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Video Maker'),
        actions: [
          TextButton.icon(
            onPressed: () => context.push(RoutePaths.videoStories),
            icon: const Icon(Icons.video_library_outlined, size: 20),
            label: const Text('My Stories'),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Credits banner
              creditsAsync.maybeWhen(
                data: (summary) => summary.creditsRemaining <= 0
                    ? _LowCreditsBanner(planName: summary.planName)
                    : const SizedBox.shrink(),
                orElse: () => const SizedBox.shrink(),
              ),

              // Title
              TextFormField(
                controller: _titleController,
                enabled: !_isGenerating,
                decoration: const InputDecoration(
                  labelText: 'Story Title (optional)',
                  hintText: 'My awesome video...',
                  prefixIcon: Icon(Icons.movie_outlined),
                ),
              ),
              const SizedBox(height: 20),

              // Input mode selector
              Text(
                'How would you like to create?',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 10),
              InputModeTabBar(
                selected: settings.inputMode,
                onSelected: settingsNotifier.setInputMode,
              ),
              const SizedBox(height: 20),

              // Mode-specific input
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _buildInputSection(settings.inputMode),
              ),
              const SizedBox(height: 16),

              // Settings
              VideoMakerSettingsPanel(enabled: !_isGenerating),
              const SizedBox(height: 16),

              // Cost label
              const GenerationCostLabel(generationType: 'video'),
              const SizedBox(height: 8),

              // Generate button
              AppButton(
                label: 'Create Video',
                icon: Icons.auto_awesome_rounded,
                isLoading: _isGenerating,
                onPressed: _createAndGenerate,
              ),
              if (_isGenerating) ...[
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    'Creating your video story...',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputSection(VideoInputMode mode) {
    return switch (mode) {
      VideoInputMode.text => _TextInputSection(
          key: const ValueKey('text'),
          controller: _promptController,
          enabled: !_isGenerating,
        ),
      VideoInputMode.photo => _PhotoInputSection(
          key: const ValueKey('photo'),
          controller: _promptController,
          enabled: !_isGenerating,
        ),
      VideoInputMode.voice => _VoiceInputSection(
          key: const ValueKey('voice'),
          onRecordingComplete: (path) {
            setState(() => _voiceRecordingPath = path);
          },
          enabled: !_isGenerating,
        ),
    };
  }
}

class _TextInputSection extends StatelessWidget {
  const _TextInputSection({
    super.key,
    required this.controller,
    required this.enabled,
  });

  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Describe your video scene',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Be specific about visuals, camera movement, mood, and action.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: controller,
          maxLines: 5,
          minLines: 3,
          maxLength: 1000,
          enabled: enabled,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please describe the video you want to create.';
            }
            return null;
          },
          decoration: const InputDecoration(
            hintText:
                'e.g. A cinematic drone shot over a misty mountain range at sunrise, '
                'slowly revealing a hidden valley with a winding river...',
          ),
        ),
      ],
    );
  }
}

class _PhotoInputSection extends StatelessWidget {
  const _PhotoInputSection({
    super.key,
    required this.controller,
    required this.enabled,
  });

  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Upload a photo to animate',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'The AI will bring your still image to life with motion.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 10),
        const ReferenceImagePickerField(),
        const SizedBox(height: 12),
        TextFormField(
          controller: controller,
          maxLines: 3,
          minLines: 2,
          maxLength: 500,
          enabled: enabled,
          decoration: const InputDecoration(
            labelText: 'Motion description (optional)',
            hintText:
                'e.g. Camera slowly zooms in while leaves gently sway in the wind...',
          ),
        ),
      ],
    );
  }
}

class _VoiceInputSection extends StatelessWidget {
  const _VoiceInputSection({
    super.key,
    required this.onRecordingComplete,
    required this.enabled,
  });

  final ValueChanged<String?> onRecordingComplete;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Record your narration',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Speak your story and the AI will create matching visuals.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 10),
        VoiceRecorderWidget(
          onRecordingComplete: onRecordingComplete,
          enabled: enabled,
        ),
      ],
    );
  }
}

class _LowCreditsBanner extends StatelessWidget {
  const _LowCreditsBanner({required this.planName});

  final String planName;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.bolt_outlined, color: colors.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "You're out of credits on the $planName plan. "
              'Generation may be blocked until more are available.',
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
