import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/regional/school_time.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../core/validators/validators.dart';
import '../../domain/blood_group.dart';
import '../../domain/gender.dart';
import '../../domain/student.dart';
import '../providers/student_providers.dart';

/// Edits a student's profile (identity, contact and address). Status and
/// placement have their own dialogs and are not touched here; the student's
/// code, admission date and photo are left as they are.
class StudentEditDialog extends ConsumerStatefulWidget {
  final Student student;
  final String currentUserId;

  const StudentEditDialog({
    super.key,
    required this.student,
    required this.currentUserId,
  });

  @override
  ConsumerState<StudentEditDialog> createState() => _StudentEditDialogState();
}

class _StudentEditDialogState extends ConsumerState<StudentEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _admissionNumber = TextEditingController(
    text: widget.student.admissionNumber,
  );
  late final _firstName = TextEditingController(text: widget.student.firstName);
  late final _middleName = TextEditingController(
    text: widget.student.middleName ?? '',
  );
  late final _lastName = TextEditingController(text: widget.student.lastName);
  late final _email = TextEditingController(text: widget.student.email ?? '');
  late final _phone = TextEditingController(text: widget.student.phone ?? '');
  late final _address1 = TextEditingController(
    text: widget.student.addressLine1 ?? '',
  );
  late final _address2 = TextEditingController(
    text: widget.student.addressLine2 ?? '',
  );
  late final _city = TextEditingController(text: widget.student.city ?? '');
  late final _state = TextEditingController(text: widget.student.state ?? '');
  late final _country = TextEditingController(
    text: widget.student.country ?? '',
  );
  late final _postal = TextEditingController(
    text: widget.student.postalCode ?? '',
  );
  late DateTime _dob = widget.student.dateOfBirth;
  late Gender _gender = widget.student.gender;
  late BloodGroup? _bloodGroup = widget.student.bloodGroup;
  bool _saving = false;

  List<TextEditingController> get _all => [
    _admissionNumber,
    _firstName,
    _middleName,
    _lastName,
    _email,
    _phone,
    _address1,
    _address2,
    _city,
    _state,
    _country,
    _postal,
  ];

  String? _clean(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _pickDob() async {
    final now = SchoolTime.wallNow();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob.isAfter(now) ? now : _dob,
      firstDate: DateTime(1990),
      lastDate: now,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    final s = widget.student;
    final updated = Student(
      studentId: s.studentId,
      schoolId: s.schoolId,
      branchId: s.branchId,
      admissionNumber: s.admissionNumber,
      studentCode: s.studentCode,
      firstName: _firstName.text.trim(),
      middleName: _clean(_middleName),
      lastName: _lastName.text.trim(),
      dateOfBirth: _dob,
      gender: _gender,
      bloodGroup: _bloodGroup,
      photoUrl: s.photoUrl,
      email: _clean(_email),
      phone: _clean(_phone),
      addressLine1: _clean(_address1),
      addressLine2: _clean(_address2),
      city: _clean(_city),
      state: _clean(_state),
      country: _clean(_country),
      postalCode: _clean(_postal),
      admissionDate: s.admissionDate,
      status: s.status,
      statusChangeReason: s.statusChangeReason,
      statusChangeDate: s.statusChangeDate,
      statusChangeNotes: s.statusChangeNotes,
      currentAcademicYearId: s.currentAcademicYearId,
      currentClassId: s.currentClassId,
      currentSectionId: s.currentSectionId,
      currentRollNumber: s.currentRollNumber,
    );
    setState(() => _saving = true);
    final ok = await ref
        .read(studentWriteControllerProvider.notifier)
        .updateProfile(updated, updatedBy: widget.currentUserId);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _saving = false);
      final error = ref.read(studentWriteControllerProvider).error;
      context.showSnackBar(
        error == null ? 'Unable to save changes.' : userMessageFor(error),
        isError: true,
      );
    }
  }

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the (auto-dispose) write controller alive while a save is running.
    ref.watch(studentWriteControllerProvider);
    const gap = SizedBox(height: AppSpacing.sm);
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Edit student', style: context.textStyles.titleLarge),
          const SizedBox(height: AppSpacing.md),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _admissionNumber,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Admission number',
                      helperText: 'The admission number cannot be changed.',
                      suffixIcon: Icon(Icons.lock_outline, size: 18),
                    ),
                  ),
                  gap,
                  TextFormField(
                    controller: _firstName,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'First name'),
                    validator: (v) =>
                        Validators.required(v, fieldName: 'First name'),
                  ),
                  gap,
                  TextFormField(
                    controller: _middleName,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Middle name (optional)',
                    ),
                  ),
                  gap,
                  TextFormField(
                    controller: _lastName,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Last name'),
                    validator: (v) =>
                        Validators.required(v, fieldName: 'Last name'),
                  ),
                  gap,
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _pickDob,
                    icon: const Icon(Icons.cake_outlined),
                    label: Text('Date of birth: ${formatDisplayDate(_dob)}'),
                  ),
                  gap,
                  DropdownButtonFormField<Gender>(
                    isExpanded: true,
                    value: _gender,
                    decoration: const InputDecoration(labelText: 'Gender'),
                    items: [
                      for (final g in Gender.values)
                        DropdownMenuItem(value: g, child: Text(g.displayName)),
                    ],
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _gender = v ?? _gender),
                  ),
                  gap,
                  DropdownButtonFormField<BloodGroup?>(
                    isExpanded: true,
                    value: _bloodGroup,
                    decoration: const InputDecoration(
                      labelText: 'Blood group (optional)',
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('—')),
                      for (final b in BloodGroup.values)
                        DropdownMenuItem(value: b, child: Text(b.displayName)),
                    ],
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _bloodGroup = v),
                  ),
                  gap,
                  TextFormField(
                    controller: _email,
                    enabled: !_saving,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email (optional)',
                    ),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? null : Validators.email(v),
                  ),
                  gap,
                  TextFormField(
                    controller: _phone,
                    enabled: !_saving,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone (optional)',
                    ),
                    validator: Validators.phone,
                  ),
                  gap,
                  TextFormField(
                    controller: _address1,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Address line 1 (optional)',
                    ),
                  ),
                  gap,
                  TextFormField(
                    controller: _address2,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Address line 2 (optional)',
                    ),
                  ),
                  gap,
                  TextFormField(
                    controller: _city,
                    enabled: !_saving,
                    decoration: const InputDecoration(labelText: 'City'),
                  ),
                  gap,
                  TextFormField(
                    controller: _state,
                    enabled: !_saving,
                    decoration: const InputDecoration(labelText: 'State'),
                  ),
                  gap,
                  TextFormField(
                    controller: _country,
                    enabled: !_saving,
                    decoration: const InputDecoration(labelText: 'Country'),
                  ),
                  gap,
                  TextFormField(
                    controller: _postal,
                    enabled: !_saving,
                    decoration: const InputDecoration(labelText: 'Postal code'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpacing.sm,
            children: [
              TextButton(
                onPressed: _saving
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save changes'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
