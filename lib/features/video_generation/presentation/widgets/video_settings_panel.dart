import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/video_generation_settings.dart';
import '../providers/video_generation_providers.dart';

/// The expandable "Video Settings" section. Collapsed by default with
/// sensible defaults already applied, mirroring
/// ImageSettingsPanel/MusicSettingsPanel.
class VideoSettingsPanel extends ConsumerStatefulWidget {
  const VideoSettingsPanel({super.key});

  @override
  ConsumerState<VideoSettingsPanel> createState() => _VideoSettingsPanelState();
}

class _VideoSettingsPanelState extends ConsumerState<VideoSettingsPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(videoSettingsProvider);
    final notifier = ref.read(videoSettingsProvider.notifier);

    return ExpansionTile(
      title: const Text('Video Settings'),
      initiallyExpanded: _expanded,
      onExpansionChanged: (v) => setState(() => _expanded = v),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 16),
      children: [
        _SectionLabel('Aspect ratio'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final ratio in VideoAspectRatio.values)
              ChoiceChip(
                label: Text('${ratio.label} (${ratio.value})'),
                selected: settings.aspectRatio == ratio,
                onSelected: (_) => notifier.setAspectRatio(ratio),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _SectionLabel('Resolution'),
        SegmentedButton<VideoResolution>(
          segments: [
            for (final resolution in VideoResolution.values)
              ButtonSegment(value: resolution, label: Text(resolution.label)),
          ],
          selected: {settings.resolution},
          onSelectionChanged: (selection) => notifier.setResolution(selection.first),
        ),
        const SizedBox(height: 16),
        _SectionLabel('Duration'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final duration in VideoDuration.values)
              ChoiceChip(
                label: Text(duration.label),
                selected: settings.duration == duration,
                onSelected: (_) => notifier.setDuration(duration),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _SectionLabel('Motion'),
        SegmentedButton<VideoMotion>(
          segments: [
            for (final motion in VideoMotion.values)
              ButtonSegment(value: motion, label: Text(motion.label)),
          ],
          selected: {settings.motion},
          onSelectionChanged: (selection) => notifier.setMotion(selection.first),
        ),
        const SizedBox(height: 16),
        _SectionLabel('Style'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final style in VideoStyle.values)
              ChoiceChip(
                label: Text(style.label),
                selected: settings.style == style,
                onSelected: (_) => notifier.setStyle(style),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _SectionLabel('Frame rate'),
        SegmentedButton<VideoFps>(
          segments: [
            for (final fps in VideoFps.values) ButtonSegment(value: fps, label: Text(fps.label)),
          ],
          selected: {settings.fps},
          onSelectionChanged: (selection) => notifier.setFps(selection.first),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}
