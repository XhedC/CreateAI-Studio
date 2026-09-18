import 'package:flutter/material.dart';

import '../../../../core/constants/creation_type.dart';
import '../../../../core/widgets/feature_card.dart';

/// Home screen's "Quick Create" row: Image, Music, Video, Funnel.
class QuickCreateRow extends StatelessWidget {
  const QuickCreateRow({super.key, required this.onSelected});

  final ValueChanged<CreationType> onSelected;

  static const _quickTypes = [
    CreationType.image,
    CreationType.music,
    CreationType.video,
    CreationType.funnel,
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final type in _quickTypes)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FeatureCard(
                label: type.label.replaceFirst('AI ', ''),
                icon: type.icon,
                color: type.color,
                onTap: () => onSelected(type),
              ),
            ),
          ),
      ],
    );
  }
}
