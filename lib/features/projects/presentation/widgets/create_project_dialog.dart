import 'package:flutter/material.dart';

import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';

/// Shows the create/rename project dialog and returns the entered name, or
/// null if cancelled. Pass [initialName] to reuse this for renaming.
Future<String?> showProjectNameDialog(
  BuildContext context, {
  String title = 'New project',
  String? initialName,
}) {
  final controller = TextEditingController(text: initialName);
  final formKey = GlobalKey<FormState>();

  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: AppTextField(
          label: 'Project name',
          controller: controller,
          validator: (v) => Validators.required(v, field: 'Project name'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        AppButton(
          label: 'Save',
          fullWidth: false,
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.of(context).pop(controller.text.trim());
            }
          },
        ),
      ],
    ),
  );
}
