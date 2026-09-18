import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/image_generation_settings.dart';
import '../providers/image_generation_providers.dart';

/// The expandable "Image Settings" section: aspect ratio, quality, style,
/// and number of images. Every option here is a real, provider-agnostic
/// setting - see docs/image-generation.md for how each one maps (or is
/// gracefully ignored) per AI provider.
class ImageSettingsPanel extends ConsumerStatefulWidget {
  const ImageSettingsPanel({super.key});

  @override
  ConsumerState<ImageSettingsPanel> createState() => _ImageSettingsPanelState();
}

class _ImageSettingsPanelState extends ConsumerState<ImageSettingsPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(imageSettingsProvider);
    final notifier = ref.read(imageSettingsProvider.notifier);

    return ExpansionTile(
      title: const Text('Image Settings'),
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
            for (final ratio in ImageAspectRatio.values)
              ChoiceChip(
                label: Text('${ratio.label} (${ratio.value})'),
                selected: settings.aspectRatio == ratio,
                onSelected: (_) => notifier.setAspectRatio(ratio),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _SectionLabel('Quality'),
        SegmentedButton<ImageQuality>(
          segments: [
            for (final quality in ImageQuality.values)
              ButtonSegment(value: quality, label: Text(quality.label)),
          ],
          selected: {settings.quality},
          onSelectionChanged: (selection) =>
              notifier.setQuality(selection.first),
        ),
        const SizedBox(height: 16),
        _SectionLabel('Style'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final style in ImageStyle.values)
              ChoiceChip(
                label: Text(style.label),
                selected: settings.style == style,
                onSelected: (_) => notifier.setStyle(style),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _SectionLabel('Number of images'),
        Row(
          children: [
            for (var i = ImageGenerationSettings.minImages;
                i <= ImageGenerationSettings.maxImages;
                i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text('$i'),
                  selected: settings.numberOfImages == i,
                  onSelected: (_) => notifier.setNumberOfImages(i),
                ),
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
