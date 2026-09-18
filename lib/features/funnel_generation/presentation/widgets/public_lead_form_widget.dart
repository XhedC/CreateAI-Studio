import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/validators.dart';
import '../providers/funnel_providers.dart';

/// The fully public, unauthenticated counterpart to [LeadFormWidget] -
/// rendered on the public funnel view for a truly anonymous visitor.
/// Submits via [publicLeadFormControllerProvider] (the
/// `submit_funnel_lead` RPC), never a direct table insert. See
/// docs/PHASE_7_PUBLISHING.md "Public lead form" / "Lead success state".
class PublicLeadFormWidget extends ConsumerStatefulWidget {
  const PublicLeadFormWidget({super.key, required this.slug, this.submitLabel = 'Submit'});

  final String slug;
  final String submitLabel;

  @override
  ConsumerState<PublicLeadFormWidget> createState() => _PublicLeadFormWidgetState();
}

class _PublicLeadFormWidgetState extends ConsumerState<PublicLeadFormWidget> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _messageController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    // The controller itself no-ops on a second call while already
    // submitting, so a double-tap (or a slow network making the button
    // look unresponsive) can never fire two requests - see
    // docs/PHASE_7_PUBLISHING.md "Lead success state".
    final ok = await ref.read(publicLeadFormControllerProvider.notifier).submit(
          slug: widget.slug,
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          phone: _phoneController.text.trim(),
          message: _messageController.text.trim(),
        );
    if (ok) {
      _nameController.clear();
      _emailController.clear();
      _phoneController.clear();
      _messageController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(publicLeadFormControllerProvider);
    final isSubmitting = state.status == LeadFormStatus.submitting;

    if (state.status == LeadFormStatus.success) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.onPrimaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Thank you! Your information has been submitted successfully.',
                style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer),
              ),
            ),
            TextButton(
              onPressed: () => ref.read(publicLeadFormControllerProvider.notifier).reset(),
              child: const Text('Submit another'),
            ),
          ],
        ),
      );
    }

    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _nameController,
            enabled: !isSubmitting,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _emailController,
            enabled: !isSubmitting,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
            validator: (v) => Validators.leadEmail(v, hasPhone: _phoneController.text.trim().isNotEmpty),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _phoneController,
            enabled: !isSubmitting,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone'),
            validator: (v) => Validators.leadPhone(v, hasEmail: _emailController.text.trim().isNotEmpty),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _messageController,
            enabled: !isSubmitting,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Message (optional)'),
          ),
          const SizedBox(height: 14),
          if (state.status == LeadFormStatus.error && state.errorMessage != null) ...[
            Text(
              state.errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 10),
          ],
          FilledButton(
            onPressed: isSubmitting ? null : _submit,
            child: isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(widget.submitLabel),
          ),
        ],
      ),
    );
  }
}
