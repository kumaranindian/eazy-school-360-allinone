import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/validators/validators.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../../../core/regional/country.dart';
import '../../../../core/regional/regional_settings.dart';
import '../../../../shared/regional/regional_settings_editor.dart';
import '../providers/create_school_providers.dart';

/// Self-serve onboarding form: a brand-new (profile-less) account becomes
/// the SCHOOL_ADMIN of a new school. See
/// `firebase_school_repository.dart` for the two-phase write this
/// triggers, and FIRESTORE_ARCHITECTURE.md for why it's two phases.
class CreateSchoolForm extends ConsumerStatefulWidget {
  const CreateSchoolForm({super.key});

  @override
  ConsumerState<CreateSchoolForm> createState() => _CreateSchoolFormState();
}

class _CreateSchoolFormState extends ConsumerState<CreateSchoolForm> {
  final _formKey = GlobalKey<FormState>();
  final _schoolNameController = TextEditingController();
  final _schoolEmailController = TextEditingController();
  final _schoolPhoneController = TextEditingController();
  RegionalSettings _regional = RegionalSettings.forCountry(Countries.all.first);

  @override
  void initState() {
    super.initState();
    final currentUser = ref.read(authRepositoryProvider).currentUser;
    _schoolEmailController.text = currentUser?.email ?? '';
  }

  @override
  void dispose() {
    _schoolNameController.dispose();
    _schoolEmailController.dispose();
    _schoolPhoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    await ref
        .read(createSchoolControllerProvider.notifier)
        .createSchool(
          schoolName: _schoolNameController.text.trim(),
          schoolEmail: _schoolEmailController.text.trim(),
          schoolPhone: _schoolPhoneController.text.trim().isEmpty
              ? null
              : _schoolPhoneController.text.trim(),
          regional: _regional,
        );

    final state = ref.read(createSchoolControllerProvider);
    if (!mounted) return;
    if (state.hasError) {
      final error = state.error!;
      final message = userMessageFor(error);

      // Show the error with more detail for debugging
      AppLogger.error(
        'Create school form error: $error (message: $message)',
        tag: 'SchoolCreation',
      );

      context.showSnackBar(message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final createState = ref.watch(createSchoolControllerProvider);
    final isSubmitting = createState.isLoading;

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _schoolNameController,
            enabled: !isSubmitting,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'School name',
              prefixIcon: Icon(Icons.school_outlined),
            ),
            validator: (value) =>
                Validators.required(value, fieldName: 'School name'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _schoolEmailController,
            enabled: !isSubmitting,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'School contact email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: Validators.email,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _schoolPhoneController,
            enabled: !isSubmitting,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'School phone (optional)',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            onFieldSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.md),
          // Country, currency and time zone drive fees, dates and reminders
          // for the whole school; they can be reviewed later in Settings.
          RegionalSettingsEditor(
            value: _regional,
            enabled: !isSubmitting,
            onChanged: (v) => setState(() => _regional = v),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: isSubmitting ? null : _submit,
            child: isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Text('Create school'),
          ),
        ],
      ),
    );
  }
}
