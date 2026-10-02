import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/video_maker_settings.dart';
import '../providers/video_maker_providers.dart';
import 'aspect_ratio_picker.dart';
import 'duration_slider_widget.dart';

class VideoMakerSettingsPanel extends ConsumerStatefulWidget {
  const VideoMakerSettingsPanel({super.key, this.enabled = true});

  final bool enabled;

  @override
  ConsumerState<VideoMakerSettingsPanel> createState() =>
      _VideoMakerSettingsPanelState();
}

class _VideoMakerSettingsPanelState
    extends ConsumerState<VideoMakerSettingsPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(videoMakerSettingsProvider);
    final notifier = ref.read(videoMakerSettingsProvider.notifier);
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Duration slider (always visible)
        DurationSliderWidget(
          value: settings.durationSeconds,
          onChanged: notifier.setDuration,
          enabled: widget.enabled,
        ),
        const SizedBox(height: 16),
        // Aspect ratio picker (always visible)
        AspectRatioPicker(
          selected: settings.aspectRatio,
          onSelected: notifier.setAspectRatio,
          enabled: widget.enabled,
        ),
        const SizedBox(height: 8),
        // Auto-adjust toggle
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Auto-adjust from prompt'),
          subtitle: Text(
            'AI optimizes duration and style based on your description',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
          ),
          value: settings.autoAdjust,
          onChanged: widget.enabled ? notifier.setAutoAdjust : null,
        ),
        // Advanced settings
        ExpansionTile(
          title: const Text('Advanced Settings'),
          initiallyExpanded: _expanded,
          onExpansionChanged: (v) => setState(() => _expanded = v),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 16),
          children: [
            // Quality
            _SectionLabel('Quality'),
            SegmentedButton<VideoQuality>(
              segments: [
                for (final q in VideoQuality.values)
                  ButtonSegment(value: q, label: Text(q.label)),
              ],
              selected: {settings.quality},
              onSelectionChanged: widget.enabled
                  ? (s) => notifier.setQuality(s.first)
                  : null,
            ),
            const SizedBox(height: 16),
            // Style
            _SectionLabel('Style'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final style in VideoMakerStyle.values)
                  ChoiceChip(
                    label: Text(style.label),
                    selected: settings.style == style,
                    onSelected: widget.enabled
                        ? (_) => notifier.setStyle(style)
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // FPS
            _SectionLabel('Frame Rate'),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 24, label: Text('24 fps')),
                ButtonSegment(value: 30, label: Text('30 fps')),
              ],
              selected: {settings.fps},
              onSelectionChanged: widget.enabled
                  ? (s) => notifier.setFps(s.first)
                  : null,
            ),
          ],
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
