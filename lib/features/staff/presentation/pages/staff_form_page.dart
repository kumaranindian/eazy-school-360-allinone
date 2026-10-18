import '../../../../core/regional/school_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../core/validators/validators.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../students/domain/blood_group.dart';
import '../../../students/domain/gender.dart';
import '../../domain/employment_type.dart';
import '../../domain/staff.dart';
import '../../domain/staff_status.dart';
import '../providers/staff_providers.dart';
import '../widgets/form_grid.dart';
import '../widgets/staff_branch_scope.dart';

/// Create (`/staff/new`) or edit (`/staff/:id/edit`) a staff member. Teaching
/// responsibility is a switch on the one staff form — there is no separate
/// "teacher" record to create. Status, photo and the app-account link are
/// not edited here; they have their own actions on the profile.
class StaffFormPage extends ConsumerWidget {
  final String? staffId;

  const StaffFormPage({super.key, this.staffId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StaffBranchScope(
      builder: (context, tenant, schoolId, branchId) {
        if (!tenant.can(Permission.manageStaff)) {
          return const EmptyView(
            icon: Icons.lock_outline,
            message: "You don't have permission to manage staff.",
          );
        }
        if (staffId == null) {
          return _StaffForm(
            schoolId: schoolId,
            branchId: branchId,
            userId: tenant.user.userId,
          );
        }
        final staffAsync = ref.watch(
          staffProvider((
            schoolId: schoolId,
            branchId: branchId,
            staffId: staffId!,
          )),
        );
        return AsyncValueWidget(
          value: staffAsync,
          errorMessage: userMessageFor,
          data: (staff) => staff == null
              ? const EmptyView(
                  icon: Icons.person_off_outlined,
                  message: 'This staff member could not be found.',
                )
              : _StaffForm(
                  schoolId: schoolId,
                  branchId: branchId,
                  userId: tenant.user.userId,
                  existing: staff,
                ),
        );
      },
    );
  }
}

class _StaffForm extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;
  final String userId;
  final Staff? existing;

  const _StaffForm({
    required this.schoolId,
    required this.branchId,
    required this.userId,
    this.existing,
  });

  @override
  ConsumerState<_StaffForm> createState() => _StaffFormState();
}

class _StaffFormState extends ConsumerState<_StaffForm> {
  final _formKey = GlobalKey<FormState>();
  late final _employeeCode = TextEditingController(
    text: widget.existing?.employeeCode,
  );
  late final _firstName = TextEditingController(
    text: widget.existing?.firstName,
  );
  late final _middleName = TextEditingController(
    text: widget.existing?.middleName,
  );
  late final _lastName = TextEditingController(text: widget.existing?.lastName);
  late final _phone = TextEditingController(text: widget.existing?.phone);
  late final _alternatePhone = TextEditingController(
    text: widget.existing?.alternatePhone,
  );
  late final _email = TextEditingController(text: widget.existing?.email);
  late final _address = TextEditingController(text: widget.existing?.address);
  late final _city = TextEditingController(text: widget.existing?.city);
  late final _state = TextEditingController(text: widget.existing?.state);
  late final _country = TextEditingController(text: widget.existing?.country);
  late final _postalCode = TextEditingController(
    text: widget.existing?.postalCode,
  );

  late DateTime? _dateOfBirth = widget.existing?.dateOfBirth;
  late DateTime? _joiningDate =
      widget.existing?.joiningDate ?? SchoolTime.wallNow();
  late Gender? _gender = widget.existing?.gender;
  late BloodGroup? _bloodGroup = widget.existing?.bloodGroup;
  late EmploymentType _employmentType =
      widget.existing?.employmentType ?? EmploymentType.fullTime;
  late String? _departmentId = widget.existing?.departmentId;
  late String? _designationId = widget.existing?.designationId;
  late bool _isTeacher = widget.existing?.isTeacher ?? false;

  bool get _isEditing => widget.existing != null;

  String? _optional(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final base = widget.existing;
    final staff = Staff(
      staffId: base?.staffId ?? '',
      schoolId: widget.schoolId,
      branchId: widget.branchId,
      employeeCode: _employeeCode.text.trim(),
      firstName: _firstName.text.trim(),
      middleName: _optional(_middleName),
      lastName: _lastName.text.trim(),
      photoUrl: base?.photoUrl,
      dateOfBirth: _dateOfBirth!,
      gender: _gender!,
      bloodGroup: _bloodGroup,
      phone: _phone.text.trim(),
      alternatePhone: _optional(_alternatePhone),
      email: _optional(_email),
      address: _optional(_address),
      city: _optional(_city),
      state: _optional(_state),
      country: _optional(_country),
      postalCode: _optional(_postalCode),
      joiningDate: _joiningDate!,
      employmentType: _employmentType,
      departmentId: _departmentId!,
      designationId: _designationId!,
      status: base?.status ?? StaffStatus.active,
      isTeacher: _isTeacher,
    );

    final controller = ref.read(staffWriteControllerProvider.notifier);
    String? savedId;
    if (_isEditing) {
      if (await controller.updateStaff(staff, updatedBy: widget.userId)) {
        savedId = base!.staffId;
      }
    } else {
      savedId = await controller.createStaff(staff, createdBy: widget.userId);
    }

    if (!mounted) return;
    if (savedId != null) {
      context.showSnackBar(
        _isEditing
            ? 'Staff member updated successfully.'
            : 'Staff member created successfully.',
      );
      if (_isEditing) {
        context.pop();
      } else {
        context.pushReplacement('/staff/$savedId');
      }
    } else {
      final error = ref.read(staffWriteControllerProvider).error;
      context.showSnackBar(
        error == null
            ? 'Unable to save this staff member.'
            : userMessageFor(error),
        isError: true,
      );
    }
  }

  @override
  void dispose() {
    for (final c in [
      _employeeCode,
      _firstName,
      _middleName,
      _lastName,
      _phone,
      _alternatePhone,
      _email,
      _address,
      _city,
      _state,
      _country,
      _postalCode,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
    child: Text(text, style: context.textStyles.titleMedium),
  );

  @override
  Widget build(BuildContext context) {
    final isSaving = ref.watch(staffWriteControllerProvider).isLoading;
    final branchKey = (schoolId: widget.schoolId, branchId: widget.branchId);
    final departments = ref.watch(departmentsProvider(branchKey));
    final designations = ref.watch(designationsProvider(branchKey));

    // Active entries, plus the one already on the record even if it has
    // since been deactivated, so editing never silently drops it.
    final departmentItems = (departments.value ?? const [])
        .where(
          (d) => d.isActive || d.departmentId == widget.existing?.departmentId,
        )
        .toList();
    final designationItems = (designations.value ?? const [])
        .where(
          (d) =>
              d.isActive || d.designationId == widget.existing?.designationId,
        )
        .toList();
    final needsSetup =
        (departments.hasValue && departmentItems.isEmpty) ||
        (designations.hasValue && designationItems.isEmpty);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit staff member' : 'Add staff member'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (needsSetup)
              Card(
                color: context.colors.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline),
                          SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              'Create at least one department and one designation before adding staff.',
                            ),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: AppSpacing.sm,
                        children: [
                          TextButton(
                            onPressed: () => context.push('/staff/departments'),
                            child: const Text('Departments'),
                          ),
                          TextButton(
                            onPressed: () =>
                                context.push('/staff/designations'),
                            child: const Text('Designations'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            _sectionTitle('Basic'),
            FormGrid(
              children: [
                TextFormField(
                  controller: _employeeCode,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Employee code',
                    helperText: 'e.g. EMP-0001 — unique in this branch',
                  ),
                  validator: (v) {
                    final required = Validators.required(
                      v,
                      fieldName: 'Employee code',
                    );
                    if (required != null) return required;
                    return Staff.employeeCodePattern.hasMatch(v!.trim())
                        ? null
                        : '2-20 letters, digits, "-" or "_".';
                  },
                ),
                const SizedBox.shrink(),
                TextFormField(
                  controller: _firstName,
                  decoration: const InputDecoration(labelText: 'First name'),
                  validator: (v) =>
                      Validators.required(v, fieldName: 'First name'),
                ),
                TextFormField(
                  controller: _middleName,
                  decoration: const InputDecoration(
                    labelText: 'Middle name (optional)',
                  ),
                ),
                TextFormField(
                  controller: _lastName,
                  decoration: const InputDecoration(labelText: 'Last name'),
                  validator: (v) =>
                      Validators.required(v, fieldName: 'Last name'),
                ),
                DateFormField(
                  label: 'Date of birth',
                  value: _dateOfBirth,
                  onChanged: (d) => _dateOfBirth = d,
                  format: formatDisplayDate,
                  firstDate: DateTime(1940),
                  lastDate: SchoolTime.wallNow(),
                  initialPickerDate: DateTime(1990),
                ),
                DropdownButtonFormField<Gender>(
                  isExpanded: true,
                  value: _gender,
                  decoration: const InputDecoration(labelText: 'Gender'),
                  items: [
                    for (final g in Gender.values)
                      DropdownMenuItem(value: g, child: Text(g.displayName)),
                  ],
                  onChanged: (v) => setState(() => _gender = v),
                  validator: (v) => v == null ? 'Gender is required.' : null,
                ),
                DropdownButtonFormField<BloodGroup?>(
                  isExpanded: true,
                  value: _bloodGroup,
                  decoration: const InputDecoration(
                    labelText: 'Blood group (optional)',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Not specified'),
                    ),
                    for (final b in BloodGroup.values)
                      DropdownMenuItem(value: b, child: Text(b.displayName)),
                  ],
                  onChanged: (v) => setState(() => _bloodGroup = v),
                ),
              ],
            ),
            _sectionTitle('Contact'),
            FormGrid(
              children: [
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  validator: (v) => Validators.phone(v, required: true),
                ),
                TextFormField(
                  controller: _alternatePhone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Alternate phone (optional)',
                  ),
                  validator: Validators.phone,
                ),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email (optional)',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? null
                      : Validators.email(v),
                ),
              ],
            ),
            _sectionTitle('Address'),
            FormGrid(
              children: [
                FormGrid.full(
                  TextFormField(
                    controller: _address,
                    decoration: const InputDecoration(
                      labelText: 'Address (optional)',
                    ),
                  ),
                ),
                TextFormField(
                  controller: _city,
                  decoration: const InputDecoration(
                    labelText: 'City (optional)',
                  ),
                ),
                TextFormField(
                  controller: _state,
                  decoration: const InputDecoration(
                    labelText: 'State (optional)',
                  ),
                ),
                TextFormField(
                  controller: _country,
                  decoration: const InputDecoration(
                    labelText: 'Country (optional)',
                  ),
                ),
                TextFormField(
                  controller: _postalCode,
                  decoration: const InputDecoration(
                    labelText: 'Postal code (optional)',
                  ),
                ),
              ],
            ),
            _sectionTitle('Employment'),
            FormGrid(
              children: [
                DateFormField(
                  label: 'Joining date',
                  value: _joiningDate,
                  onChanged: (d) => _joiningDate = d,
                  format: formatDisplayDate,
                  firstDate: DateTime(1980),
                  lastDate: SchoolTime.wallNow().add(const Duration(days: 365)),
                ),
                DropdownButtonFormField<EmploymentType>(
                  isExpanded: true,
                  value: _employmentType,
                  decoration: const InputDecoration(
                    labelText: 'Employment type',
                  ),
                  items: [
                    for (final t in EmploymentType.values)
                      DropdownMenuItem(value: t, child: Text(t.displayName)),
                  ],
                  onChanged: (v) =>
                      setState(() => _employmentType = v ?? _employmentType),
                ),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value:
                      departmentItems.any(
                        (d) => d.departmentId == _departmentId,
                      )
                      ? _departmentId
                      : null,
                  decoration: const InputDecoration(labelText: 'Department'),
                  items: [
                    for (final d in departmentItems)
                      DropdownMenuItem(
                        value: d.departmentId,
                        child: Text(d.name),
                      ),
                  ],
                  onChanged: (v) => setState(() => _departmentId = v),
                  validator: (v) =>
                      v == null ? 'Department is required.' : null,
                ),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value:
                      designationItems.any(
                        (d) => d.designationId == _designationId,
                      )
                      ? _designationId
                      : null,
                  decoration: const InputDecoration(labelText: 'Designation'),
                  items: [
                    for (final d in designationItems)
                      DropdownMenuItem(
                        value: d.designationId,
                        child: Text(d.name),
                      ),
                  ],
                  onChanged: (v) => setState(() => _designationId = v),
                  validator: (v) =>
                      v == null ? 'Designation is required.' : null,
                ),
                FormGrid.full(
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Has teaching responsibility'),
                    subtitle: const Text(
                      'Teachers can be assigned classes, sections and subjects. This is separate from their login role.',
                    ),
                    value: _isTeacher,
                    onChanged: isSaving
                        ? null
                        : (v) => setState(() => _isTeacher = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                TextButton(
                  onPressed: isSaving ? null : () => context.pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSaving ? null : _submit,
                  child: isSaving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _isEditing ? 'Save changes' : 'Create staff member',
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
