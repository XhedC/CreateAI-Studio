import 'package:flutter/widgets.dart';

/// Centralized responsive breakpoints - Material 3's window-size-class
/// widths (see https://m3.material.io/foundations/layout/applying-layout).
/// One source of truth so "is this a phone/tablet/desktop layout" is never
/// decided ad hoc per screen. See docs/CROSS_PLATFORM_ARCHITECTURE.md
/// "Responsive UI".
enum AppFormFactor { compact, medium, expanded }

class Breakpoints {
  const Breakpoints._();

  static const double medium = 600;
  static const double expanded = 840;

  static AppFormFactor formFactorFor(double width) {
    if (width >= expanded) return AppFormFactor.expanded;
    if (width >= medium) return AppFormFactor.medium;
    return AppFormFactor.compact;
  }

  static AppFormFactor of(BuildContext context) =>
      formFactorFor(MediaQuery.sizeOf(context).width);

  /// True for [AppFormFactor.medium] and [AppFormFactor.expanded] - i.e.
  /// "wide enough for a side nav rail instead of a bottom bar."
  static bool isWide(BuildContext context) => of(context) != AppFormFactor.compact;
}
