import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/loading_widget.dart';
import '../../../../core/widgets/video_player_widget.dart';
import '../../data/models/video_maker_settings.dart';
import '../../data/models/video_segment_model.dart';
import '../../data/models/video_story_model.dart';
import '../providers/video_maker_providers.dart';
import '../widgets/input_mode_tab_bar.dart';
import '../widgets/segment_card.dart';
import '../widgets/video_timeline_widget.dart';
import '../widgets/voice_recorder_widget.dart';

class VideoStoryEditorScreen extends ConsumerStatefulWidget {
  const VideoStoryEditorScreen({super.key, required this.storyId});

  final String storyId;

  @override
  ConsumerState<VideoStoryEditorScreen> createState() =>
      _VideoStoryEditorScreenState();
}

class _VideoStoryEditorScreenState
    extends ConsumerState<VideoStoryEditorScreen> {
  int? _selectedSegmentIndex;
  bool _showAddSegment = false;
  VideoInputMode _newSegmentMode = VideoInputMode.text;
  final _newPromptController = TextEditingController();
  int _newSegmentDuration = 10;
  String? _voiceRecordingPath;
  bool _isAdding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(activeStoryProvider.notifier).loadStory(widget.storyId);
    });
  }

  @override
  void dispose() {
    _newPromptController.dispose();
    super.dispose();
  }

  Future<void> _addSegment() async {
    final prompt = _newSegmentMode == VideoInputMode.voice
        ? 'Voice narration segment'
        : _newPromptController.text.trim();

    if (_newSegmentMode != VideoInputMode.voice && prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe the new segment.')),
      );
      return;
    }

    if (_newSegmentMode == VideoInputMode.voice &&
        _voiceRecordingPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please record your voice first.')),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isAdding = true);

    final notifier = ref.read(activeStoryProvider.notifier);
    final added = await notifier.addSegment(
      prompt: prompt,
      inputType: SegmentInputType.values.firstWhere(
        (s) => s.value == _newSegmentMode.value,
      ),
      durationSeconds: _newSegmentDuration,
      voiceUrl:
          _newSegmentMode == VideoInputMode.voice ? _voiceRecordingPath : null,
    );

    if (added && mounted) {
      final story = ref.read(activeStoryProvider).story;
      final lastSegment = story?.segments.lastOrNull;
      if (lastSegment != null) {
        await notifier.generateSegment(lastSegment.id);
      }
      _newPromptController.clear();
      _voiceRecordingPath = null;
      setState(() {
        _showAddSegment = false;
        _isAdding = false;
      });
    } else {
      setState(() => _isAdding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final storyState = ref.watch(activeStoryProvider);
    final story = storyState.story;
    final colors = Theme.of(context).colorScheme;

    if (story == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Video Story')),
        body: storyState.isLoading
            ? const LoadingWidget()
            : Center(
                child: Text(
                  storyState.error?.message ?? 'Story not found.',
                  style: TextStyle(color: colors.error),
                ),
              ),
      );
    }

    final selectedSegment = _selectedSegmentIndex != null &&
            _selectedSegmentIndex! < story.segments.length
        ? story.segments[_selectedSegmentIndex!]
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(story.title),
        actions: [
          if (story.allSegmentsCompleted)
            TextButton.icon(
              onPressed: () => _exportStory(story),
              icon: const Icon(Icons.download_rounded, size: 20),
              label: const Text('Export'),
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'rename') _renameStory(story);
              if (value == 'delete') _deleteStory(story);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              const PopupMenuItem(value: 'delete', child: Text('Delete Story')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Video preview
            if (selectedSegment?.videoUrl != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: VideoPlayerWidget(url: selectedSegment!.videoUrl!),
              )
            else
              Container(
                margin: const EdgeInsets.all(16),
                height: 200,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        story.hasProcessingSegments
                            ? Icons.hourglass_top_rounded
                            : Icons.movie_creation_outlined,
                        size: 48,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        story.hasProcessingSegments
                            ? 'Generating your video...'
                            : 'Select a completed segment to preview',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ),

            // Timeline
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: VideoTimelineWidget(
                story: story,
                selectedSegmentIndex: _selectedSegmentIndex,
                onSegmentTap: (i) {
                  setState(() => _selectedSegmentIndex = i);
                },
              ),
            ),
            const SizedBox(height: 8),

            // Segment list
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (int i = 0; i < story.segments.length; i++)
                    SegmentCard(
                      segment: story.segments[i],
                      index: i,
                      onTap: () =>
                          setState(() => _selectedSegmentIndex = i),
                      onDelete: () => _confirmDeleteSegment(story.segments[i]),
                      onRetry: story.segments[i].isFailed
                          ? () => ref
                              .read(activeStoryProvider.notifier)
                              .retrySegment(story.segments[i].id)
                          : null,
                    ),

                  // "Add segment" section
                  if (_showAddSegment) ...[
                    const Divider(height: 24),
                    _AddSegmentForm(
                      mode: _newSegmentMode,
                      onModeChanged: (m) =>
                          setState(() => _newSegmentMode = m),
                      promptController: _newPromptController,
                      duration: _newSegmentDuration,
                      onDurationChanged: (d) =>
                          setState(() => _newSegmentDuration = d),
                      onVoiceRecording: (path) =>
                          setState(() => _voiceRecordingPath = path),
                      isLoading: _isAdding,
                      onSubmit: _addSegment,
                      onCancel: () =>
                          setState(() => _showAddSegment = false),
                    ),
                  ],

                  const SizedBox(height: 80),
                ],
              ),
            ),
          ],
        ),
      ),
      // FAB to add new segment (continue editing)
      floatingActionButton: _showAddSegment
          ? null
          : FloatingActionButton.extended(
              onPressed: () => setState(() => _showAddSegment = true),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Continue Story'),
            ),
    );
  }

  void _confirmDeleteSegment(VideoSegmentModel segment) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Segment?'),
        content: const Text(
          'This will permanently remove this segment from your story.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(activeStoryProvider.notifier).deleteSegment(segment.id);
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _renameStory(VideoStoryModel story) {
    final controller = TextEditingController(text: story.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Story'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Title'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(videoStoryRepositoryProvider).updateStory(
                story.id,
                {'title': controller.text.trim()},
              );
              ref.read(activeStoryProvider.notifier).loadStory(story.id);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _deleteStory(VideoStoryModel story) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Story?'),
        content: const Text(
          'This will permanently delete this story and all its segments.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(videoStoryRepositoryProvider).deleteStory(story.id);
              ref.read(activeStoryProvider.notifier).clear();
              ref.invalidate(videoStoriesProvider);
              context.pop();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _exportStory(VideoStoryModel story) {
    ref
        .read(activeStoryProvider.notifier)
        .updateStoryStatus(StoryStatus.exported);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Story export started. You will be notified when ready.'),
      ),
    );
  }
}

class _AddSegmentForm extends StatelessWidget {
  const _AddSegmentForm({
    required this.mode,
    required this.onModeChanged,
    required this.promptController,
    required this.duration,
    required this.onDurationChanged,
    required this.onVoiceRecording,
    required this.isLoading,
    required this.onSubmit,
    required this.onCancel,
  });

  final VideoInputMode mode;
  final ValueChanged<VideoInputMode> onModeChanged;
  final TextEditingController promptController;
  final int duration;
  final ValueChanged<int> onDurationChanged;
  final ValueChanged<String?> onVoiceRecording;
  final bool isLoading;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Add New Segment',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: onCancel,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          InputModeTabBar(
            selected: mode,
            onSelected: onModeChanged,
          ),
          const SizedBox(height: 12),
          if (mode == VideoInputMode.voice)
            VoiceRecorderWidget(
              onRecordingComplete: onVoiceRecording,
              enabled: !isLoading,
            )
          else
            TextFormField(
              controller: promptController,
              maxLines: 3,
              minLines: 2,
              enabled: !isLoading,
              decoration: InputDecoration(
                hintText: mode == VideoInputMode.photo
                    ? 'Describe the motion for this photo...'
                    : 'Describe the next scene in your story...',
              ),
            ),
          const SizedBox(height: 12),
          // Duration picker
          Row(
            children: [
              Text(
                'Duration: ${duration}s',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Slider(
                  value: duration.toDouble(),
                  min: 5,
                  max: 60,
                  divisions: 11,
                  onChanged: isLoading
                      ? null
                      : (v) => onDurationChanged(v.round()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppButton(
            label: 'Generate Segment',
            icon: Icons.auto_awesome_rounded,
            isLoading: isLoading,
            onPressed: onSubmit,
          ),
        ],
      ),
    );
  }
}
