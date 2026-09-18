import 'package:flutter/material.dart';

import '../../../../core/constants/creation_type.dart';

/// Horizontal chip selector for choosing which AI category to generate with.
class CreationTypeSelector extends StatelessWidget {
  const CreationTypeSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final CreationType selected;
  final ValueChanged<CreationType> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: CreationType.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final type = CreationType.values[index];
          final isSelected = type == selected;
          return ChoiceChip(
            label: Text(type.label),
            avatar: Icon(
              type.icon,
              size: 18,
              color: isSelected ? Colors.white : type.color,
            ),
            selected: isSelected,
            selectedColor: type.color,
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : null,
              fontWeight: FontWeight.w600,
            ),
            onSelected: (_) => onSelected(type),
          );
        },
      ),
    );
  }
}
