import 'package:flutter/material.dart';

/// Convenience accessors over the active [TextTheme] so widgets don't repeat
/// `Theme.of(context).textTheme.*` everywhere.
extension AppTextStylesX on BuildContext {
  TextTheme get textStyles => Theme.of(this).textTheme;
  ColorScheme get colors => Theme.of(this).colorScheme;
}
