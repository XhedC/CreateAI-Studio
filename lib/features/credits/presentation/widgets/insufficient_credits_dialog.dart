import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';

/// Shown when a generation request is rejected server-side with
/// `INSUFFICIENT_CREDITS`, instead of the generic error snackbar every other
/// failure gets - the user needs a clear next step (view plans), not just
/// "something went wrong". See docs/PHASE_6_CREDITS_SUBSCRIPTIONS.md.
Future<void> showInsufficientCreditsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.bolt_outlined),
      title: const Text('Not enough credits'),
      content: const Text(
        "You don't have enough credits for this generation. "
        'Upgrade your plan or wait for your next monthly credit grant.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            context.push(RoutePaths.plans);
          },
          child: const Text('View plans'),
        ),
      ],
    ),
  );
}
