import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/validators/validators.dart';
import '../../domain/school.dart';
import '../providers/school_profile_providers.dart';
import 'school_logo_picker.dart';

/// Editable form for the three sections the brief asks for — Basic
/// Information, Contact, Address — laid out as two columns on
/// tablet/desktop and one on mobile. [onSaved] lets the page switch back
/// to view mode; [onCancel] discards edits without writing anything.
class SchoolProfileForm extends ConsumerStatefulWidget {
  final School school;
  final String updatedBy;
  final VoidCallback onSaved;
  final VoidCallback onCancel;

  const SchoolProfileForm({
    super.key,
    required this.school,
    required this.updatedBy,
    required this.onSaved,
    required this.onCancel,
  });

  @override
  ConsumerState<SchoolProfileForm> createState() => _SchoolProfileFormState();
}

class _SchoolProfileFormState extends ConsumerState<SchoolProfileForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.school.name);
  late final _shortName = TextEditingController(text: widget.school.shortName);
  late final _code = TextEditingController(text: widget.school.code);
  late final _email = TextEditingController(text: widget.school.email);
  late final _phone = TextEditingController(text: widget.school.phone);
  late final _alternatePhone = TextEditingController(
    text: widget.school.alternatePhone,
  );
  late final _website = TextEditingController(text: widget.school.website);
  late final _addressLine1 = TextEditingController(
    text: widget.school.addressLine1,
  );
  late final _addressLine2 = TextEditingController(
    text: widget.school.addressLine2,
  );
  late final _city = TextEditingController(text: widget.school.city);
  late final _state = TextEditingController(text: widget.school.state);
  late final _country = TextEditingController(text: widget.school.country);
  late final _postalCode = TextEditingController(
    text: widget.school.postalCode,
  );

  @override
  void dispose() {
    for (final c in [
      _name,
      _shortName,
      _code,
      _email,
      _phone,
      _alternatePhone,
      _website,
      _addressLine1,
      _addressLine2,
      _city,
      _state,
      _country,
      _postalCode,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final updated = widget.school.copyWith(
      name: _name.text.trim(),
      shortName: _shortName.text.trim(),
      code: _code.text.trim(),
      email: _email.text.trim(),
      phone: _phone.text.trim(),
      alternatePhone: _alternatePhone.text.trim(),
      website: _website.text.trim(),
      addressLine1: _addressLine1.text.trim(),
      addressLine2: _addressLine2.text.trim(),
      city: _city.text.trim(),
      state: _state.text.trim(),
      country: _country.text.trim(),
      postalCode: _postalCode.text.trim(),
    );

    final success = await ref
        .read(schoolProfileWriteControllerProvider.notifier)
        .updateProfile(updated, updatedBy: widget.updatedBy);

    if (!mounted) return;
    if (success) {
      context.showSnackBar('School profile updated successfully.');
      widget.onSaved();
    } else {
      final error = ref.read(schoolProfileWriteControllerProvider).error;
      context.showSnackBar(
        error == null
            ? 'Unable to update school profile. Please try again.'
            : userMessageFor(error),
        isError: true,
      );
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? Function(String?)? validator,
    int? maxLines,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      validator: validator,
      maxLines: maxLines ?? 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = ref.watch(schoolProfileWriteControllerProvider).isLoading;

    return ResponsiveBuilder(
      builder: (context, screenSize) {
        final columns = screenSize.isMobile ? 1 : 2;
        return Form(
          key: _formKey,
          child: IgnorePointer(
            ignoring: isSaving,
            child: Opacity(
              opacity: isSaving ? 0.6 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Basic Information',
                    style: context.textStyles.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SchoolLogoPicker(
                    schoolId: widget.school.schoolId,
                    logoUrl: widget.school.logoUrl,
                    updatedBy: widget.updatedBy,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ResponsiveFieldGrid(
                    columns: columns,
                    children: [
                      _field(
                        _name,
                        'School name',
                        validator: (v) =>
                            Validators.required(v, fieldName: 'School name'),
                      ),
                      _field(_shortName, 'Short name'),
                      _field(_code, 'School code'),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Contact', style: context.textStyles.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  _ResponsiveFieldGrid(
                    columns: columns,
                    children: [
                      _field(_email, 'Email', validator: Validators.email),
                      _field(_phone, 'Phone'),
                      _field(_alternatePhone, 'Alternate phone'),
                      _field(_website, 'Website'),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Address', style: context.textStyles.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  _ResponsiveFieldGrid(
                    columns: columns,
                    children: [
                      _field(_addressLine1, 'Address line 1'),
                      _field(_addressLine2, 'Address line 2'),
                      _field(_city, 'City'),
                      _field(_state, 'State'),
                      _field(_country, 'Country'),
                      _field(_postalCode, 'Postal code'),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: isSaving ? null : widget.onCancel,
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      FilledButton(
                        onPressed: isSaving ? null : _save,
                        child: isSaving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ResponsiveFieldGrid extends StatelessWidget {
  final int columns;
  final List<Widget> children;

  const _ResponsiveFieldGrid({required this.columns, required this.children});

  @override
  Widget build(BuildContext context) {
    if (columns == 1) {
      return Column(
        children: [
          for (final child in children)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: child,
            ),
        ],
      );
    }
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        for (final child in children)
          SizedBox(width: (560 - AppSpacing.md) / 2, child: child),
      ],
    );
  }
}
