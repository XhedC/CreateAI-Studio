import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/validators.dart';
import '../providers/funnel_providers.dart';

/// Reusable Name/Email/Phone/Message lead-capture form, rendered wherever a
/// funnel includes a `lead_form` section. Submits into `funnel_leads`
/// (scoped to the funnel owner's own session in Phase 5 - see
/// docs/funnel-generation.md for why there is no public/unauthenticated
/// submission path yet). Never sends lead data to any third-party service.
class LeadFormWidget extends ConsumerStatefulWidget {
  const LeadFormWidget({super.key, required this.funnelId, this.submitLabel = 'Submit'});

  final String funnelId;
  final String submitLabel;

  @override
  ConsumerState<LeadFormWidget> createState() => _LeadFormWidgetState();
}

class _LeadFormWidgetState extends ConsumerState<LeadFormWidget> {
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
    final ok = await ref.read(leadFormControllerProvider.notifier).submit(
          funnelId: widget.funnelId,
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
    final state = ref.watch(leadFormControllerProvider);
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
                "Thank you! We've received your submission.",
                style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer),
              ),
            ),
            TextButton(
              onPressed: () => ref.read(leadFormControllerProvider.notifier).reset(),
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
