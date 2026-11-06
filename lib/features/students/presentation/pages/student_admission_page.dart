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
import '../../domain/parent_duplicates.dart';
import '../../domain/relationship_type.dart';
import '../../domain/admission_outcome.dart';
import '../../domain/student.dart';
import '../../domain/student_name_parts.dart';
import '../../domain/student_status.dart';
import '../providers/parent_providers.dart';
import '../providers/student_providers.dart';
import '../widgets/admission_wizard.dart';
import '../widgets/parent_duplicates_dialog.dart';
import '../../../users/domain/login_provisioning.dart';
import '../../../users/presentation/widgets/provision_logins_dialog.dart';

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

  final _fullName = TextEditingController();
  final _dobText = TextEditingController();
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
  final _newParentEmail = TextEditingController();
  final _parentFormKey = GlobalKey<FormState>();

  /// Open "Give login access" for the guardian once the student is saved.
  bool _giveParentLogin = false;
  bool _checkingParent = false;
  RelationshipType _relationshipType = RelationshipType.guardian;
  bool _isPrimary = true;
  bool _isEmergencyContact = true;

  String? _academicYearId;
  String? _classId;
  String? _sectionId;
  final _rollNumber = TextEditingController();

  bool _saving = false;

  /// The admission number is generated (`ADM-0001`), never typed. It is
  /// looked up per branch, and looked up again at save.
  String? _numberKey;
  bool _numberFailed = false;

  int _parentSearchGeneration = 0;

  Future<void> _loadAdmissionNumber(String schoolId, String branchId) async {
    final key = '$schoolId/$branchId';
    _numberKey = key;
    setState(() {
      _numberFailed = false;
      _admissionNumber.clear();
    });
    try {
      final number = await ref
          .read(admissionNumberSourceProvider)
          .nextNumber(schoolId: schoolId, branchId: branchId);
      if (mounted && _numberKey == key) {
        setState(() => _admissionNumber.text = number);
      }
    } catch (_) {
      if (mounted && _numberKey == key) {
        setState(() => _numberFailed = true);
      }
    }
  }

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

  /// The typed full name split into the stored first / middle / last parts.
  StudentNameParts get _name => StudentNameParts.split(_fullName.text);

  bool get _canGoToParentStep =>
      _basicFormKey.currentState?.validate() ?? false;

  bool get _selectedParentHasLogin =>
      _parentMode == _ParentMode.existing &&
      (_selectedParent?.hasPortalAccess ?? false);

  /// Leaving the guardian step: an existing parent must be picked; a new one
  /// must be valid and must not duplicate a parent already in the branch
  /// (same email: refused, as in bulk import; same phone: asked).
  Future<bool> _guardianStepDone(String schoolId, String branchId) async {
    switch (_parentMode) {
      case _ParentMode.skip:
        return true;
      case _ParentMode.existing:
        if (_selectedParent != null) return true;
        context.showSnackBar(
          'Search for the parent and select them, or choose "Add later".',
          isError: true,
        );
        return false;
      case _ParentMode.newParent:
        if (!(_parentFormKey.currentState?.validate() ?? false)) return false;
        setState(() => _checkingParent = true);
        List<ParentMatch> matches;
        try {
          matches = await ref
              .read(parentDuplicateFinderProvider)
              .find(
                schoolId: schoolId,
                branchId: branchId,
                email: _newParentEmail.text,
                phone: _newParentPhone.text,
                displayName:
                    '${_newParentFirstName.text.trim()} '
                    '${_newParentLastName.text.trim()}',
              );
        } catch (error) {
          if (mounted) {
            setState(() => _checkingParent = false);
            context.showSnackBar(
              'Could not check for an existing parent: '
              '${userMessageFor(error)}',
              isError: true,
            );
          }
          return false;
        }
        if (!mounted) return false;
        setState(() => _checkingParent = false);
        if (matches.isEmpty) return true;
        final choice = await showParentDuplicatesDialog(
          context: context,
          matches: matches,
        );
        if (!mounted) return false;
        switch (choice) {
          case UseExistingParent(:final parent):
            setState(() {
              _parentMode = _ParentMode.existing;
              _selectedParent = parent;
              _parentSearchResults = [parent];
              _parentSearchController.text = parent.displayName;
              if (parent.hasPortalAccess) _giveParentLogin = false;
            });
            return true;
          case CreateParentAnyway():
            return true;
          case null:
            return false;
        }
    }
  }

  Future<void> _continue(
    String schoolId,
    String branchId,
    String currentUserId,
  ) async {
    if (_step == 0 && !_canGoToParentStep) return;
    if (_step == 1 && !await _guardianStepDone(schoolId, branchId)) return;
    if (!mounted) return;
    if (_step == 2 && !_canReview) {
      context.showSnackBar(
        'Please choose an academic year, class, and section.',
        isError: true,
      );
      return;
    }
    if (_step == 3) {
      await _save(schoolId, branchId, currentUserId);
      return;
    }
    setState(() => _step += 1);
  }

  bool get _canReview =>
      _academicYearId != null && _classId != null && _sectionId != null;

  Future<void> _save(
    String schoolId,
    String branchId,
    String currentUserId,
  ) async {
    setState(() => _saving = true);

    Student studentWith(String admissionNumber) => Student(
      studentId: '',
      schoolId: schoolId,
      branchId: branchId,
      admissionNumber: admissionNumber,
      studentCode: '',
      firstName: _name.first,
      middleName: _name.middle,
      lastName: _name.last,
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

    // The next number is read again now: another admin may have used the
    // one shown. If it is taken between the read and the write, ask again.
    String? newStudentId;
    Object? admitError;
    Student? student;
    for (var attempt = 0; attempt < 3 && newStudentId == null; attempt++) {
      admitError = null;
      try {
        final number = await ref
            .read(admissionNumberSourceProvider)
            .nextNumber(schoolId: schoolId, branchId: branchId);
        student = studentWith(number);
        newStudentId = await ref
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
          admitError = ref.read(studentWriteControllerProvider).error;
          if (!userMessageFor(admitError ?? '').contains('already in use')) {
            break;
          }
        }
      } catch (error) {
        // Never leave the spinner running on an unexpected failure.
        admitError = error;
        break;
      }
    }

    if (newStudentId == null) {
      if (!mounted) return;
      setState(() => _saving = false);
      final error = admitError;
      context.showSnackBar(
        error == null ? 'Unable to admit this student.' : userMessageFor(error),
        isError: true,
      );
      return;
    }

    var guardianLinked = true;
    Object? guardianError;
    String? parentId;
    if (_parentMode != _ParentMode.skip) {
      try {
        parentId = _selectedParent?.parentId;
        if (_parentMode == _ParentMode.newParent) {
          final newParent = Parent(
            parentId: '',
            schoolId: schoolId,
            branchId: branchId,
            firstName: _newParentFirstName.text.trim(),
            lastName: _newParentLastName.text.trim(),
            phone: _newParentPhone.text.trim(),
            // Lowercase, as bulk import saves it: it becomes the sign-in email.
            email: ParentContact.normalizeEmail(_newParentEmail.text),
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
                // A parent who already signs in (another child) must see this
                // child too; a login given below turns it on anyway.
                canAccessPortal: _selectedParentHasLogin || _giveParentLogin,
                createdBy: currentUserId,
              );
          if (!guardianLinked) {
            guardianError = ref.read(studentWriteControllerProvider).error;
          }
        }
      } catch (error) {
        // The student is already saved; report the guardian step as not
        // done instead of hanging or skipping the message.
        guardianLinked = false;
        guardianError = error;
      }
    }

    if (!mounted) return;

    // Same path as after a bulk import (Parents → Give login access): the
    // server creates or maps the account; nothing privileged runs here.
    var loginNote = '';
    if (guardianLinked && parentId != null && _giveParentLogin) {
      final given = await showProvisionLoginsDialog(
        context: context,
        schoolId: schoolId,
        branchId: branchId,
        kind: LoginKind.parent,
        people: [
          (
            id: parentId,
            name: _parentMode == _ParentMode.newParent
                ? '${_newParentFirstName.text.trim()} '
                      '${_newParentLastName.text.trim()}'
                : _selectedParent!.displayName,
            email: _parentMode == _ParentMode.newParent
                ? ParentContact.normalizeEmail(_newParentEmail.text)
                : _selectedParent!.email,
          ),
        ],
      );
      if (!mounted) return;
      if (given != true) {
        loginNote =
            ' No parent login was given; you can give it later from Parents '
            '(key icon).';
      }
    }

    // The student exists either way; say so, and say plainly when the
    // guardian is not linked yet (UI-1) - the profile page can link one.
    context.showSnackBar(
      AdmissionOutcome.message(
            studentName: '${student!.firstName} ${student.lastName}',
            guardianLinked: guardianLinked,
            guardianError: guardianError == null
                ? null
                : userMessageFor(guardianError),
          ) +
          loginNote,
      isError: !guardianLinked,
    );
    context.go('/students/$newStudentId');
  }

  @override
  void dispose() {
    for (final c in [
      _fullName,
      _dobText,
      _admissionNumber,
      _email,
      _phone,
      _addressLine1,
      _city,
      _parentSearchController,
      _newParentFirstName,
      _newParentLastName,
      _newParentPhone,
      _newParentEmail,
      _rollNumber,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  static const _stepLabels = [
    'Student Details',
    'Parent / Guardian',
    'Academic Placement',
    'Review',
  ];

  Future<void> _pickDateOfBirth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(SchoolTime.wallNow().year - 10),
      firstDate: DateTime(1990),
      lastDate: SchoolTime.wallNow(),
    );
    if (picked != null && mounted) {
      setState(() {
        _dateOfBirth = picked;
        _dobText.text = formatDisplayDate(picked);
      });
    }
  }

  Future<void> _pickAdmissionDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _admissionDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) setState(() => _admissionDate = picked);
  }

  /// Step 1 in the new layout: labelled fields, two columns when wide.
  Widget _studentDetailsStep(
    BuildContext context,
    String schoolId,
    String branchId,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final tint = scheme.primary.withValues(alpha: 0.08);
    const sp = SizedBox(height: AppSpacing.md);
    return Form(
      key: _basicFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdmissionLabeled(
            label: 'Admission Number',
            child: TextFormField(
              controller: _admissionNumber,
              readOnly: true,
              decoration: InputDecoration(
                filled: true,
                fillColor: tint,
                helperText: _numberFailed ? null : 'Generated automatically',
                errorText: _numberFailed
                    ? 'Could not generate the number.'
                    : null,
                suffixIcon: _numberFailed
                    ? IconButton(
                        tooltip: 'Try again',
                        icon: const Icon(Icons.refresh),
                        onPressed: () =>
                            _loadAdmissionNumber(schoolId, branchId),
                      )
                    : const Icon(Icons.lock_outline),
              ),
              validator: (v) => (v ?? '').trim().isEmpty
                  ? 'The admission number is still being generated.'
                  : null,
            ),
          ),
          sp,
          AdmissionFieldRow(
            left: AdmissionLabeled(
              label: 'Full Name',
              required: true,
              child: TextFormField(
                controller: _fullName,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: "Enter student's full name",
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) {
                  final n = StudentNameParts.split(v ?? '');
                  if (n.isEmpty) return 'Full name is required';
                  if (!n.isComplete) return 'Enter the first and last name';
                  return null;
                },
              ),
            ),
            right: AdmissionLabeled(
              label: 'Date of Birth',
              required: true,
              child: TextFormField(
                controller: _dobText,
                readOnly: true,
                onTap: _pickDateOfBirth,
                decoration: const InputDecoration(
                  hintText: 'Select date',
                  prefixIcon: Icon(Icons.calendar_today_outlined),
                ),
                validator: (_) =>
                    _dateOfBirth == null ? 'Select the date of birth' : null,
              ),
            ),
          ),
          sp,
          AdmissionFieldRow(
            left: AdmissionLabeled(
              label: 'Gender',
              required: true,
              child: DropdownButtonFormField<Gender>(
                isExpanded: true,
                value: _gender,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.wc_outlined),
                ),
                items: [
                  for (final g in Gender.values)
                    DropdownMenuItem(value: g, child: Text(g.displayName)),
                ],
                onChanged: (v) => setState(() => _gender = v ?? _gender),
              ),
            ),
            right: AdmissionLabeled(
              label: 'Blood Group',
              child: DropdownButtonFormField<BloodGroup?>(
                isExpanded: true,
                value: _bloodGroup,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.bloodtype_outlined),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Unknown')),
                  for (final b in BloodGroup.values)
                    DropdownMenuItem(value: b, child: Text(b.displayName)),
                ],
                onChanged: (v) => setState(() => _bloodGroup = v),
              ),
            ),
          ),
          sp,
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              hintText: 'Email (optional)',
              prefixIcon: Icon(Icons.mail_outline),
            ),
          ),
          sp,
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              hintText: 'Phone (optional)',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            validator: Validators.phone,
          ),
          sp,
          TextFormField(
            controller: _addressLine1,
            minLines: 2,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Address (optional)',
              prefixIcon: Align(
                widthFactor: 1,
                heightFactor: 1,
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Icon(Icons.location_on_outlined),
                ),
              ),
            ),
          ),
          sp,
          TextFormField(
            controller: _city,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'City (optional)',
              prefixIcon: Icon(Icons.location_city_outlined),
            ),
          ),
          sp,
          Semantics(
            button: true,
            label: 'Admission date ${formatDisplayDate(_admissionDate)}',
            excludeSemantics: true,
            child: InkWell(
              onTap: _pickAdmissionDate,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_month_outlined, color: scheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Admission Date',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            formatDisplayDate(_admissionDate),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.edit_calendar_outlined, color: scheme.primary),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tenantState = ref.watch(tenantContextProvider);
    // Both write controllers are auto-dispose and are only `read` in _save:
    // without a listener Riverpod disposes them while a write is in flight
    // and the save fails with an unmounted-ref error. Keep them alive here.
    ref.watch(studentWriteControllerProvider);
    ref.watch(parentWriteControllerProvider);

    return Scaffold(
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
          if (_numberKey != '$schoolId/$branchId') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _loadAdmissionNumber(schoolId, branchId);
            });
          }

          final busy = _saving || _checkingParent;
          final last = _step == _stepLabels.length - 1;
          final (icon, title, subtitle) = switch (_step) {
            0 => (
              Icons.person_outline,
              'Student Details',
              'Basic information of the student',
            ),
            1 => (
              Icons.family_restroom_outlined,
              'Parent / Guardian',
              'Link a guardian now or add one later',
            ),
            2 => (
              Icons.school_outlined,
              'Academic Placement',
              'Choose the academic year, class and section',
            ),
            _ => (
              Icons.fact_check_outlined,
              'Review',
              'Check the details, then admit the student',
            ),
          };
          final Widget stepContent = switch (_step) {
            0 => _studentDetailsStep(context, schoolId, branchId),
            1 => _parentStep(context, schoolId, branchId),
            2 => _placementStep(context, schoolId, branchId),
            _ => _reviewStep(context),
          };

          final footer = Row(
            children: [
              if (_step > 0)
                OutlinedButton(
                  onPressed: busy ? null : () => setState(() => _step -= 1),
                  child: const Text('Back'),
                ),
              const Spacer(),
              FilledButton(
                onPressed: busy
                    ? null
                    : () => _continue(schoolId, branchId, tenant.user.userId),
                child: busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(last ? 'Admit student' : 'Next'),
                          if (!last) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward, size: 18),
                          ],
                        ],
                      ),
              ),
            ],
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdmissionBanner(
                title: 'Admit Student',
                subtitle: 'Add a new student to the school',
                onBack: () =>
                    context.canPop() ? context.pop() : context.go('/students'),
                action: TextButton.icon(
                  onPressed: busy
                      ? null
                      : () => context.push('/students/import'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    minimumSize: const Size(48, 48),
                    side: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.onPrimary.withValues(alpha: 0.7),
                    ),
                  ),
                  icon: const Icon(Icons.upload_file_outlined, size: 20),
                  label: const Text('Bulk upload'),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 880),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const ActingBranchBanner(),
                          AdmissionStepTracker(
                            labels: _stepLabels,
                            current: _step,
                            onTapStep: busy
                                ? null
                                : (i) => setState(() => _step = i),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          AdmissionStepCard(
                            icon: icon,
                            title: title,
                            subtitle: subtitle,
                            footer: footer,
                            child: stepContent,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // Step 2: the guardian (logic unchanged; only moved out of the build).
  Widget _parentStep(BuildContext context, String schoolId, String branchId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<_ParentMode>(
          segments: const [
            ButtonSegment(value: _ParentMode.skip, label: Text('Add later')),
            ButtonSegment(value: _ParentMode.existing, label: Text('Existing')),
            ButtonSegment(value: _ParentMode.newParent, label: Text('New')),
          ],
          selected: {_parentMode},
          onSelectionChanged: (s) => setState(() => _parentMode = s.first),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_parentMode == _ParentMode.existing) ...[
          TextField(
            controller: _parentSearchController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search parents by name',
            ),
            onChanged: (v) => _searchParents(schoolId, branchId, v),
          ),
          for (final parent in _parentSearchResults)
            RadioListTile<Parent>(
              value: parent,
              groupValue: _selectedParent,
              onChanged: (p) => setState(() => _selectedParent = p),
              title: Text(parent.displayName),
              subtitle: Text(
                [
                  if (parent.phone.isNotEmpty) parent.phone,
                  if (parent.email != null) parent.email!,
                  if (parent.hasPortalAccess) 'Has login',
                ].join(' · '),
              ),
            ),
        ],
        if (_parentMode == _ParentMode.newParent)
          Form(
            key: _parentFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _newParentFirstName,
                  decoration: const InputDecoration(labelText: 'First name'),
                  validator: (v) =>
                      Validators.required(v, fieldName: 'First name'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _newParentLastName,
                  decoration: const InputDecoration(labelText: 'Last name'),
                  validator: (v) =>
                      Validators.required(v, fieldName: 'Last name'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _newParentPhone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  keyboardType: TextInputType.phone,
                  validator: (v) => Validators.phone(v, required: true),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _newParentEmail,
                  decoration: const InputDecoration(
                    labelText: 'Email (optional)',
                    helperText:
                        'Needed for a parent login. One '
                        'email per parent.',
                    helperMaxLines: 3,
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? null : Validators.email(v),
                ),
              ],
            ),
          ),
        if (_parentMode != _ParentMode.skip) ...[
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<RelationshipType>(
            isExpanded: true,
            value: _relationshipType,
            decoration: const InputDecoration(labelText: 'Relationship'),
            items: [
              for (final t in RelationshipType.values)
                DropdownMenuItem(value: t, child: Text(t.displayName)),
            ],
            onChanged: (v) =>
                setState(() => _relationshipType = v ?? _relationshipType),
          ),
          CheckboxListTile(
            value: _isPrimary,
            onChanged: (v) => setState(() => _isPrimary = v ?? false),
            title: const Text('Primary contact'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          CheckboxListTile(
            value: _isEmergencyContact,
            onChanged: (v) => setState(() => _isEmergencyContact = v ?? false),
            title: const Text('Emergency contact'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (_selectedParentHasLogin)
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.verified_user_outlined),
              title: Text(
                'This parent already has a login. They '
                'will see this child in the parent app; '
                'no new login is needed.',
              ),
            )
          else
            CheckboxListTile(
              value: _giveParentLogin,
              onChanged: (v) => setState(() => _giveParentLogin = v ?? false),
              title: const Text('Give this parent a login after admission'),
              subtitle: const Text(
                'You choose how the first password is set. '
                'Needs an email; you can also do this later '
                'from Parents.',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
        ],
      ],
    );
  }

  // Step 3: year, class, section (logic unchanged).
  Widget _placementStep(
    BuildContext context,
    String schoolId,
    String branchId,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Consumer(
          builder: (context, ref, _) {
            final yearsAsync = ref.watch(
              academicYearsProvider((schoolId: schoolId, branchId: branchId)),
            );
            return yearsAsync.when(
              data: (years) => DropdownButtonFormField<String>(
                isExpanded: true,
                value: years.any((y) => y.academicYearId == _academicYearId)
                    ? _academicYearId
                    : null,
                decoration: const InputDecoration(labelText: 'Academic year'),
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
                data: (classes) => DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: classes.any((c) => c.classId == _classId)
                      ? _classId
                      : null,
                  decoration: const InputDecoration(labelText: 'Class'),
                  items: [
                    for (final c in classes)
                      DropdownMenuItem(value: c.classId, child: Text(c.name)),
                  ],
                  onChanged: (v) => setState(() {
                    _classId = v;
                    _sectionId = null;
                  }),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('Unable to load classes.'),
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
                data: (sections) => DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: sections.any((s) => s.sectionId == _sectionId)
                      ? _sectionId
                      : null,
                  decoration: const InputDecoration(labelText: 'Section'),
                  items: [
                    for (final s in sections)
                      DropdownMenuItem(value: s.sectionId, child: Text(s.name)),
                  ],
                  onChanged: (v) => setState(() => _sectionId = v),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('Unable to load sections.'),
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
    );
  }

  // Step 4: review (logic unchanged).
  Widget _reviewStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_name.full, style: Theme.of(context).textTheme.titleMedium),
        Text('Admission number: ${_admissionNumber.text}'),
        Text(
          'Parent/guardian: ${_parentMode == _ParentMode.skip
              ? 'To be added later'
              : _parentMode == _ParentMode.existing
              ? (_selectedParent?.displayName ?? '—')
              : '${_newParentFirstName.text} ${_newParentLastName.text}'}',
        ),
        if (_parentMode != _ParentMode.skip)
          Text(
            'Parent login: ${_selectedParentHasLogin
                ? 'already has one'
                : _giveParentLogin
                ? 'will be set up after admission'
                : 'not now (can be given later from Parents)'}',
          ),
        const SizedBox(height: AppSpacing.sm),
        const Text('Review the details above, then admit this student.'),
      ],
    );
  }
}
