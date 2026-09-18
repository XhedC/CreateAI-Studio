import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum GenerationStatus {
  pending('pending', 'Pending', Icons.schedule_rounded, AppColors.warning),
  processing('processing', 'Processing', Icons.autorenew_rounded, AppColors.info),
  completed('completed', 'Completed', Icons.check_circle_rounded, AppColors.success),
  failed('failed', 'Failed', Icons.error_rounded, AppColors.danger),
  cancelled('cancelled', 'Cancelled', Icons.cancel_rounded, Colors.grey);

  const GenerationStatus(this.value, this.label, this.icon, this.color);

  final String value;
  final String label;
  final IconData icon;
  final Color color;

  static GenerationStatus fromValue(String value) =>
      GenerationStatus.values.firstWhere(
        (s) => s.value == value,
        orElse: () => GenerationStatus.pending,
      );
}
