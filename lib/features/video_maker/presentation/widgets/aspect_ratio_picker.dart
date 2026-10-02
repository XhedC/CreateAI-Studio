import 'package:flutter/material.dart';

import '../../data/models/video_maker_settings.dart';

class AspectRatioPicker extends StatelessWidget {
  const AspectRatioPicker({
    super.key,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
  });

  final StoryAspectRatio selected;
  final ValueChanged<StoryAspectRatio> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Screen Ratio',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final ratio in StoryAspectRatio.values) ...[
              if (ratio != StoryAspectRatio.values.first) const SizedBox(width: 8),
              Expanded(
                child: _RatioCard(
                  ratio: ratio,
                  isSelected: selected == ratio,
                  onTap: enabled ? () => onSelected(ratio) : null,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _RatioCard extends StatelessWidget {
  const _RatioCard({
    required this.ratio,
    required this.isSelected,
    this.onTap,
  });

  final StoryAspectRatio ratio;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final previewRatio = ratio.ratio.clamp(0.5, 2.0);
    final previewWidth = 28.0;
    final previewHeight = previewWidth / previewRatio;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? colors.primaryContainer : colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? colors.primary : colors.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: previewWidth,
              height: previewHeight.clamp(14.0, 40.0),
              decoration: BoxDecoration(
                color: isSelected
                    ? colors.onPrimaryContainer.withValues(alpha: 0.2)
                    : colors.onSurface.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: isSelected
                      ? colors.onPrimaryContainer.withValues(alpha: 0.4)
                      : colors.onSurface.withValues(alpha: 0.2),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              ratio.value,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? colors.onPrimaryContainer
                        : colors.onSurfaceVariant,
                    fontSize: 10,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
