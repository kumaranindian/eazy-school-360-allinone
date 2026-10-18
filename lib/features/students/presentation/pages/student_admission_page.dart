import '../../../../core/regional/school_time.dart';
import 'package:flutter/material.dart';
import '../../../../shared/branding/acting_branch_banner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/activation_status.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../core/validators/validators.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../domain/blood_group.dart';
import '../../domain/gender.dart';
import '../../domain/parent.dart';
import '../../domain/relationship_type.dart';
import '../../domain/admission_outcome.dart';
import '../../domain/student.dart';
import '../../domain/student_status.dart';
import '../providers/parent_providers.dart';
import '../providers/student_providers.dart';

enum _ParentMode { skip, existing, newParent }

/// The admission wizard (brief §13): Basic Information → Parent/Guardian
/// (optional at this stage — a student is never left half-created waiting
/// on a parent) → Academic Placement (year/class/section condensed into
/// one step, a reasonable simplification of the brief's 3-step diagram —
/// see `docs/milestone-3-student-parent-management.md`) → Review.
class StudentAdmissionPage extends ConsumerStatefulWidget {
  const StudentAdmissionPage({super.key});

  @override
  ConsumerState<StudentAdmissionPage> createState() =>
      _StudentAdmissionPageState();
}

class _StudentAdmissionPageState extends ConsumerState<StudentAdmissionPage> {
  int _step = 0;
  final _basicFormKey = GlobalKey<FormState>();

  final _firstName = TextEditingController();
  final _middleName = TextEditingController();
  final _lastName = TextEditingController();
  final _admissionNumber = TextEditingController();
  DateTime? _dateOfBirth;
  Gender _gender = Gender.male;
  BloodGroup? _bloodGroup;
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _addressLine1 = TextEditingController();
  final _city = TextEditingController();
  DateTime _admissionDate = SchoolTime.wallNow();

  _ParentMode _parentMode = _ParentMode.skip;
  final _parentSearchController = TextEditingController();
  List<Parent> _parentSearchResults = const [];
  Parent? _selectedParent;
  final _newParentFirstName = TextEditingController();
  final _newParentLastName = TextEditingController();
  final _newParentPhone = TextEditingController();
  RelationshipType _relationshipType = RelationshipType.guardian;
  bool _isPrimary = true;
  bool _isEmergencyContact = true;

  String? _academicYearId;
  String? _classId;
  String? _sectionId;
  final _rollNumber = TextEditingController();

  bool _saving = false;

  int _parentSearchGeneration = 0;

  Future<void> _searchParents(
    String schoolId,
    String branchId,
    String query,
  ) async {
    // An older search that answers late must not replace a newer one.
    final generation = ++_parentSearchGeneration;
    if (query.trim().isEmpty) {
      setState(() => _parentSearchResults = const []);
      return;
    }
    try {
      final page = await ref
          .read(parentRepositoryProvider)
          .searchParentsByName(
            schoolId: schoolId,
            branchId: branchId,
            query: query.trim(),
          );
      if (mounted && generation == _parentSearchGeneration) {
        setState(() => _parentSearchResults = page.items);
      }
    } catch (_) {
      if (mounted && generation == _parentSearchGeneration) {
        setState(() => _parentSearchResults = const []);
      }
    }
  }

  bool get _canGoToParentStep =>
      _basicFormKey.currentState?.validate() ?? false;

  bool get _canGoToPlacementStep {
    if (_parentMode == _ParentMode.existing && _selectedParent == null) {
      return false;
    }
    if (_parentMode == _ParentMode.newParent &&
        (_newParentFirstName.text.trim().isEmpty ||
            _newParentLastName.text.trim().isEmpty ||
            _newParentPhone.text.trim().isEmpty)) {
      return false;
    }
    return true;
  }

  bool get _canReview =>
      _academicYearId != null && _classId != null && _sectionId != null;

  Future<void> _save(
    String schoolId,
    String branchId,
    String currentUserId,
  ) async {
    setState(() => _saving = true);

    final student = Student(
      studentId: '',
      schoolId: schoolId,
      branchId: branchId,
      admissionNumber: _admissionNumber.text.trim(),
      studentCode: '',
      firstName: _firstName.text.trim(),
      middleName: _middleName.text.trim().isEmpty
          ? null
          : _middleName.text.trim(),
      lastName: _lastName.text.trim(),
      dateOfBirth: _dateOfBirth!,
      gender: _gender,
      bloodGroup: _bloodGroup,
      email: _email.text.trim().isEmpty ? null : _email.text.trim(),
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      addressLine1: _addressLine1.text.trim().isEmpty
          ? null
          : _addressLine1.text.trim(),
      city: _city.text.trim().isEmpty ? null : _city.text.trim(),
      admissionDate: _admissionDate,
      status: StudentStatus.active,
    );

    final newStudentId = await ref
        .read(studentWriteControllerProvider.notifier)
        .admitStudent(
          student: student,
          academicYearId: _academicYearId!,
          classId: _classId!,
          sectionId: _sectionId!,
          rollNumber: _rollNumber.text.trim().isEmpty
              ? null
              : _rollNumber.text.trim(),
          createdBy: currentUserId,
        );

    if (newStudentId == null) {
      if (!mounted) return;
      setState(() => _saving = false);
      final error = ref.read(studentWriteControllerProvider).error;
      context.showSnackBar(
        error == null ? 'Unable to admit this student.' : userMessageFor(error),
        isError: true,
      );
      return;
    }

    var guardianLinked = true;
    Object? guardianError;
    if (_parentMode != _ParentMode.skip) {
      var parentId = _selectedParent?.parentId;
      if (_parentMode == _ParentMode.newParent) {
        final newParent = Parent(
          parentId: '',
          schoolId: schoolId,
          branchId: branchId,
          firstName: _newParentFirstName.text.trim(),
          lastName: _newParentLastName.text.trim(),
          phone: _newParentPhone.text.trim(),
          status: ActivationStatus.active,
        );
        parentId = await ref
            .read(parentWriteControllerProvider.notifier)
            .createParent(newParent, createdBy: currentUserId);
        if (parentId == null) {
          guardianLinked = false;
          guardianError = ref.read(parentWriteControllerProvider).error;
        }
      }
      if (parentId != null) {
        guardianLinked = await ref
            .read(studentWriteControllerProvider.notifier)
            .linkParent(
              schoolId: schoolId,
              branchId: branchId,
              studentId: newStudentId,
              parentId: parentId,
              relationshipType: _relationshipType,
              isPrimary: _isPrimary,
              isEmergencyContact: _isEmergencyContact,
              createdBy: currentUserId,
            );
        if (!guardianLinked) {
          guardianError = ref.read(studentWriteControllerProvider).error;
        }
      }
    }

    if (!mounted) return;
    // The student exists either way; say so, and say plainly when the
    // guardian is not linked yet (UI-1) - the profile page can link one.
    context.showSnackBar(
      AdmissionOutcome.message(
        studentName: '${student.firstName} ${student.lastName}',
        guardianLinked: guardianLinked,
        guardianError: guardianError == null
            ? null
            : userMessageFor(guardianError),
      ),
      isError: !guardianLinked,
    );
    context.go('/students/$newStudentId');
  }

  @override
  void dispose() {
    for (final c in [
      _firstName,
      _middleName,
      _lastName,
      _admissionNumber,
      _email,
      _phone,
      _addressLine1,
      _city,
      _parentSearchController,
      _newParentFirstName,
      _newParentLastName,
      _newParentPhone,
      _rollNumber,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tenantState = ref.watch(tenantContextProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Admit student')),
      body: AsyncValueWidget(
        value: tenantState,
        data: (tenant) {
          if (tenant?.school == null || tenant?.branch == null) {
            return const EmptyView(
              icon: Icons.person_add_alt_1_outlined,
              message: 'No branch found for your account.',
            );
          }
          final schoolId = tenant!.school!.schoolId;
          final branchId = tenant.branch!.branchId;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  0,
                ),
                child: ActingBranchBanner(),
              ),
              Expanded(
                child: Stepper(
                  currentStep: _step,
                  onStepContinue: () {
                    if (_step == 0 && !_canGoToParentStep) return;
                    if (_step == 1 && !_canGoToParentStep) return;
                    if (_step == 1 && !_canGoToPlacementStep) {
                      context.showSnackBar(
                        'Please complete the parent details or choose to skip.',
                        isError: true,
                      );
                      return;
                    }
                    if (_step == 2 && !_canReview) {
                      context.showSnackBar(
                        'Please choose an academic year, class, and section.',
                        isError: true,
                      );
                      return;
                    }
                    if (_step == 3) {
                      _save(schoolId, branchId, tenant.user.userId);
                      return;
                    }
                    setState(() => _step += 1);
                  },
                  onStepCancel: _step == 0
                      ? null
                      : () => setState(() => _step -= 1),
                  controlsBuilder: (context, details) => Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: Row(
                      children: [
                        FilledButton(
                          onPressed: _saving ? null : details.onStepContinue,
                          child: _saving
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(_step == 3 ? 'Admit student' : 'Next'),
                        ),
                        if (details.onStepCancel != null) ...[
                          const SizedBox(width: AppSpacing.sm),
                          TextButton(
                            onPressed: _saving ? null : details.onStepCancel,
                            child: const Text('Back'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  steps: [
                    Step(
                      title: const Text('Basic information'),
                      isActive: _step >= 0,
                      state: _step > 0 ? StepState.complete : StepState.indexed,
                      content: Form(
                        key: _basicFormKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _firstName,
                              decoration: const InputDecoration(
                                labelText: 'First name',
                              ),
                              validator: (v) => Validators.required(
                                v,
                                fieldName: 'First name',
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            TextFormField(
                              controller: _middleName,
                              decoration: const InputDecoration(
                                labelText: 'Middle name (optional)',
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            TextFormField(
                              controller: _lastName,
                              decoration: const InputDecoration(
                                labelText: 'Last name',
                              ),
                              validator: (v) => Validators.required(
                                v,
                                fieldName: 'Last name',
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            TextFormField(
                              controller: _admissionNumber,
                              decoration: const InputDecoration(
                                labelText: 'Admission number',
                                hintText: 'e.g. ADM-2026-001',
                              ),
                              validator: (v) => Validators.required(
                                v,
                                fieldName: 'Admission number',
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            OutlinedButton(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate:
                                      _dateOfBirth ??
                                      DateTime(SchoolTime.wallNow().year - 10),
                                  firstDate: DateTime(1990),
                                  lastDate: SchoolTime.wallNow(),
                                );
                                if (picked != null) {
                                  setState(() => _dateOfBirth = picked);
                                }
                              },
                              child: Text(
                                _dateOfBirth == null
                                    ? 'Date of birth'
                                    : formatDisplayDate(_dateOfBirth!),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            DropdownButtonFormField<Gender>(
                              isExpanded: true,
                              value: _gender,
                              decoration: const InputDecoration(
                                labelText: 'Gender',
                              ),
                              items: [
                                for (final g in Gender.values)
                                  DropdownMenuItem(
                                    value: g,
                                    child: Text(g.displayName),
                                  ),
                              ],
                              onChanged: (v) =>
                                  setState(() => _gender = v ?? _gender),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            DropdownButtonFormField<BloodGroup?>(
                              isExpanded: true,
                              value: _bloodGroup,
                              decoration: const InputDecoration(
                                labelText: 'Blood group (optional)',
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('Unknown'),
                                ),
                                for (final b in BloodGroup.values)
                                  DropdownMenuItem(
                                    value: b,
                                    child: Text(b.displayName),
                                  ),
                              ],
                              onChanged: (v) => setState(() => _bloodGroup = v),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            TextFormField(
                              controller: _email,
                              decoration: const InputDecoration(
                                labelText: 'Email (optional)',
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            TextFormField(
                              controller: _phone,
                              decoration: const InputDecoration(
                                labelText: 'Phone (optional)',
                              ),
                              validator: Validators.phone,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            TextFormField(
                              controller: _addressLine1,
                              decoration: const InputDecoration(
                                labelText: 'Address (optional)',
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            TextFormField(
                              controller: _city,
                              decoration: const InputDecoration(
                                labelText: 'City (optional)',
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            OutlinedButton(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _admissionDate,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null) {
                                  setState(() => _admissionDate = picked);
                                }
                              },
                              child: Text(
                                'Admission date: ${formatDisplayDate(_admissionDate)}',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Step(
                      title: const Text('Parent / guardian'),
                      isActive: _step >= 1,
                      state: _step > 1 ? StepState.complete : StepState.indexed,
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SegmentedButton<_ParentMode>(
                            segments: const [
                              ButtonSegment(
                                value: _ParentMode.skip,
                                label: Text('Add later'),
                              ),
                              ButtonSegment(
                                value: _ParentMode.existing,
                                label: Text('Existing'),
                              ),
                              ButtonSegment(
                                value: _ParentMode.newParent,
                                label: Text('New'),
                              ),
                            ],
                            selected: {_parentMode},
                            onSelectionChanged: (s) =>
                                setState(() => _parentMode = s.first),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          if (_parentMode == _ParentMode.existing) ...[
                            TextField(
                              controller: _parentSearchController,
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.search),
                                hintText: 'Search parents by name',
                              ),
                              onChanged: (v) =>
                                  _searchParents(schoolId, branchId, v),
                            ),
                            for (final parent in _parentSearchResults)
                              RadioListTile<Parent>(
                                value: parent,
                                groupValue: _selectedParent,
                                onChanged: (p) =>
                                    setState(() => _selectedParent = p),
                                title: Text(parent.displayName),
                                subtitle: Text(parent.phone),
                              ),
                          ],
                          if (_parentMode == _ParentMode.newParent) ...[
                            TextField(
                              controller: _newParentFirstName,
                              decoration: const InputDecoration(
                                labelText: 'First name',
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            TextField(
                              controller: _newParentLastName,
                              decoration: const InputDecoration(
                                labelText: 'Last name',
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            TextField(
                              controller: _newParentPhone,
                              decoration: const InputDecoration(
                                labelText: 'Phone',
                              ),
                              keyboardType: TextInputType.phone,
                            ),
                          ],
                          if (_parentMode != _ParentMode.skip) ...[
                            const SizedBox(height: AppSpacing.sm),
                            DropdownButtonFormField<RelationshipType>(
                              isExpanded: true,
                              value: _relationshipType,
                              decoration: const InputDecoration(
                                labelText: 'Relationship',
                              ),
                              items: [
                                for (final t in RelationshipType.values)
                                  DropdownMenuItem(
                                    value: t,
                                    child: Text(t.displayName),
                                  ),
                              ],
                              onChanged: (v) => setState(
                                () =>
                                    _relationshipType = v ?? _relationshipType,
                              ),
                            ),
                            CheckboxListTile(
                              value: _isPrimary,
                              onChanged: (v) =>
                                  setState(() => _isPrimary = v ?? false),
                              title: const Text('Primary contact'),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                            CheckboxListTile(
                              value: _isEmergencyContact,
                              onChanged: (v) => setState(
                                () => _isEmergencyContact = v ?? false,
                              ),
                              title: const Text('Emergency contact'),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                          ],
                        ],
                      ),
                    ),
                    Step(
                      title: const Text('Academic placement'),
                      isActive: _step >= 2,
                      state: _step > 2 ? StepState.complete : StepState.indexed,
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Consumer(
                            builder: (context, ref, _) {
                              final yearsAsync = ref.watch(
                                academicYearsProvider((
                                  schoolId: schoolId,
                                  branchId: branchId,
                                )),
                              );
                              return yearsAsync.when(
                                data: (years) =>
                                    DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      value:
                                          years.any(
                                            (y) =>
                                                y.academicYearId ==
                                                _academicYearId,
                                          )
                                          ? _academicYearId
                                          : null,
                                      decoration: const InputDecoration(
                                        labelText: 'Academic year',
                                      ),
                                      items: [
                                        for (final y in years)
                                          DropdownMenuItem(
                                            value: y.academicYearId,
                                            child: Text(y.name),
                                          ),
                                      ],
                                      onChanged: (v) => setState(() {
                                        _academicYearId = v;
                                        _classId = null;
                                        _sectionId = null;
                                      }),
                                    ),
                                loading: () => const LinearProgressIndicator(),
                                error: (_, __) => const Text(
                                  'Unable to load academic years. Add one under Settings first.',
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          if (_academicYearId != null)
                            Consumer(
                              builder: (context, ref, _) {
                                final classesAsync = ref.watch(
                                  classesProvider((
                                    schoolId: schoolId,
                                    branchId: branchId,
                                    academicYearId: _academicYearId!,
                                  )),
                                );
                                return classesAsync.when(
                                  data: (classes) =>
                                      DropdownButtonFormField<String>(
                                        isExpanded: true,
                                        value:
                                            classes.any(
                                              (c) => c.classId == _classId,
                                            )
                                            ? _classId
                                            : null,
                                        decoration: const InputDecoration(
                                          labelText: 'Class',
                                        ),
                                        items: [
                                          for (final c in classes)
                                            DropdownMenuItem(
                                              value: c.classId,
                                              child: Text(c.name),
                                            ),
                                        ],
                                        onChanged: (v) => setState(() {
                                          _classId = v;
                                          _sectionId = null;
                                        }),
                                      ),
                                  loading: () =>
                                      const LinearProgressIndicator(),
                                  error: (_, __) =>
                                      const Text('Unable to load classes.'),
                                );
                              },
                            ),
                          const SizedBox(height: AppSpacing.sm),
                          if (_academicYearId != null && _classId != null)
                            Consumer(
                              builder: (context, ref, _) {
                                final sectionsAsync = ref.watch(
                                  sectionsProvider((
                                    schoolId: schoolId,
                                    branchId: branchId,
                                    academicYearId: _academicYearId!,
                                    classId: _classId!,
                                  )),
                                );
                                return sectionsAsync.when(
                                  data: (sections) =>
                                      DropdownButtonFormField<String>(
                                        isExpanded: true,
                                        value:
                                            sections.any(
                                              (s) => s.sectionId == _sectionId,
                                            )
                                            ? _sectionId
                                            : null,
                                        decoration: const InputDecoration(
                                          labelText: 'Section',
                                        ),
                                        items: [
                                          for (final s in sections)
                                            DropdownMenuItem(
                                              value: s.sectionId,
                                              child: Text(s.name),
                                            ),
                                        ],
                                        onChanged: (v) =>
                                            setState(() => _sectionId = v),
                                      ),
                                  loading: () =>
                                      const LinearProgressIndicator(),
                                  error: (_, __) =>
                                      const Text('Unable to load sections.'),
                                );
                              },
                            ),
                          const SizedBox(height: AppSpacing.sm),
                          TextField(
                            controller: _rollNumber,
                            decoration: const InputDecoration(
                              labelText: 'Roll number (optional)',
                            ),
                          ),
                        ],
                      ),
                    ),
                    Step(
                      title: const Text('Review'),
                      isActive: _step >= 3,
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_firstName.text} ${_lastName.text}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text('Admission number: ${_admissionNumber.text}'),
                          Text(
                            'Parent/guardian: ${_parentMode == _ParentMode.skip
                                ? 'To be added later'
                                : _parentMode == _ParentMode.existing
                                ? (_selectedParent?.displayName ?? '—')
                                : '${_newParentFirstName.text} ${_newParentLastName.text}'}',
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          const Text(
                            'Review the details above, then admit this student.',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
