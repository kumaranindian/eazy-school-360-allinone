import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/user_role.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../academic_setup/domain/academic_year.dart';
import '../../../academic_setup/domain/academic_year_status.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../fees/presentation/pages/parent_fees_page.dart'
    show linkedChildrenProvider;
import '../../../staff/presentation/providers/staff_providers.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../../../students/domain/student.dart';
import '../../../students/presentation/providers/student_providers.dart';
import '../../domain/leave_application.dart';
import '../../domain/leave_enums.dart';
import '../../domain/leave_repositories.dart';
import '../widgets/leave_apply_form.dart';

AcademicYear? _pickYear(List<AcademicYear> years, String? preferredId) {
  if (years.isEmpty) return null;
  return years.firstWhere(
    (y) => y.academicYearId == preferredId,
    orElse: () => years.firstWhere(
      (y) => y.status == AcademicYearStatus.active,
      orElse: () => years.first,
    ),
  );
}

class _ApplyShell extends StatelessWidget {
  final String title;
  final Widget child;

  const _ApplyShell({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: BackButton(onPressed: () => context.go('/my-leave')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// `/my-leave/apply` — a parent applies for a linked child
/// (`?studentId=&b=`), or a staff member for themselves. The child comes from
/// the parent's own linked-children list, never from the URL alone: an id
/// that is not in that list is refused here, and `firestore.rules` refuses
/// it again at write time.
class MyLeaveApplyPage extends ConsumerWidget {
  final String? studentId;
  final String? branchId;

  const MyLeaveApplyPage({super.key, this.studentId, this.branchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueWidget<TenantContext?>(
      value: ref.watch(tenantContextProvider),
      data: (tenant) {
        final schoolId = tenant?.school?.schoolId;
        if (tenant == null || schoolId == null) {
          return const _ApplyShell(
            title: 'Apply for leave',
            child: EmptyView(
              icon: Icons.beach_access_outlined,
              message: 'No school found for your account.',
            ),
          );
        }
        return tenant.role == UserRole.parent
            ? _ParentApply(
                tenant: tenant,
                schoolId: schoolId,
                studentId: studentId,
              )
            : _StaffApply(tenant: tenant, schoolId: schoolId);
      },
    );
  }
}

class _ParentApply extends ConsumerWidget {
  final TenantContext tenant;
  final String schoolId;
  final String? studentId;

  const _ParentApply({
    required this.tenant,
    required this.schoolId,
    required this.studentId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parentId = tenant.user.linkedParentId;
    final children = parentId == null
        ? const AsyncValue<List<Student>>.data([])
        : ref.watch(
            linkedChildrenProvider((schoolId: schoolId, parentId: parentId)),
          );
    return _ApplyShell(
      title: 'Apply for leave',
      child: children.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(message: userMessageFor(e)),
        data: (list) {
          final child = list.where((c) => c.studentId == studentId).firstOrNull;
          if (child == null) {
            return const EmptyView(
              icon: Icons.child_care_outlined,
              message:
                  'Choose one of your linked children from the My leave page.',
            );
          }
          return _StudentForm(
            tenant: tenant,
            schoolId: schoolId,
            student: child,
            relation: ApplicantRelation.parent,
            onDone: () => context.go('/my-leave'),
          );
        },
      ),
    );
  }
}

class _StudentForm extends ConsumerWidget {
  final TenantContext tenant;
  final String schoolId;
  final Student student;
  final ApplicantRelation relation;
  final VoidCallback onDone;

  const _StudentForm({
    required this.tenant,
    required this.schoolId,
    required this.student,
    required this.relation,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final years = ref.watch(
      academicYearsProvider((schoolId: schoolId, branchId: student.branchId)),
    );
    return years.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: userMessageFor(e)),
      data: (list) {
        final year = _pickYear(list, student.currentAcademicYearId);
        if (year == null) {
          return const EmptyView(
            icon: Icons.event_outlined,
            message: 'The school has not set up an academic year yet.',
          );
        }
        final classes = ref
            .watch(
              classesProvider((
                schoolId: schoolId,
                branchId: student.branchId,
                academicYearId: year.academicYearId,
              )),
            )
            .value;
        final className = classes
            ?.where((c) => c.classId == student.currentClassId)
            .firstOrNull
            ?.name;
        final sections = student.currentClassId == null
            ? null
            : ref
                  .watch(
                    sectionsProvider((
                      schoolId: schoolId,
                      branchId: student.branchId,
                      academicYearId: year.academicYearId,
                      classId: student.currentClassId!,
                    )),
                  )
                  .value;
        final sectionName = sections
            ?.where((s) => s.sectionId == student.currentSectionId)
            .firstOrNull
            ?.name;
        return LeaveApplyForm(
          schoolId: schoolId,
          branchId: student.branchId,
          year: year,
          subject: LeaveSubject(
            kind: LeaveKind.student,
            id: student.studentId,
            name: student.displayName,
            code: student.admissionNumber,
            classId: student.currentClassId,
            className: className,
            sectionId: student.currentSectionId,
            sectionName: sectionName,
          ),
          actor: LeaveActor(userId: tenant.user.userId, name: tenant.user.name),
          applicantRole: tenant.role.wireValue,
          relation: relation,
          onDone: onDone,
        );
      },
    );
  }
}

class _StaffApply extends ConsumerWidget {
  final TenantContext tenant;
  final String schoolId;

  const _StaffApply({required this.tenant, required this.schoolId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branchId = tenant.user.branchId ?? tenant.branch?.branchId;
    if (branchId == null) {
      return const _ApplyShell(
        title: 'Apply for leave',
        child: EmptyView(
          icon: Icons.beach_access_outlined,
          message: 'No branch found for your account.',
        ),
      );
    }
    final own = ref.watch(
      ownStaffProvider((
        schoolId: schoolId,
        branchId: branchId,
        userId: tenant.user.userId,
      )),
    );
    final years = ref.watch(
      academicYearsProvider((schoolId: schoolId, branchId: branchId)),
    );
    return _ApplyShell(
      title: 'Apply for leave',
      child: own.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(message: userMessageFor(e)),
        data: (staff) {
          if (staff == null) {
            return const EmptyView(
              icon: Icons.link_off,
              message:
                  "Your account isn't linked to a staff record, so leave "
                  'cannot be applied for here.',
            );
          }
          final year = _pickYear(years.value ?? const [], null);
          if (year == null) {
            return const EmptyView(
              icon: Icons.event_outlined,
              message: 'The school has not set up an academic year yet.',
            );
          }
          return LeaveApplyForm(
            schoolId: schoolId,
            branchId: branchId,
            year: year,
            subject: LeaveSubject(
              kind: LeaveKind.staff,
              id: staff.staffId,
              name: staff.displayName,
              code: staff.employeeCode,
            ),
            actor: LeaveActor(
              userId: tenant.user.userId,
              name: tenant.user.name,
            ),
            applicantRole: tenant.role.wireValue,
            relation: ApplicantRelation.self,
            employmentType: staff.employmentType.wireValue,
            onDone: () => context.go('/my-leave'),
          );
        },
      ),
    );
  }
}

/// `/leave/apply` — a reviewer files a **student's** leave on their behalf.
/// Offered only when the branch policy allows it (the setting is checked by
/// `firestore.rules` too; with it off the write is refused).
class AdminApplyPage extends ConsumerStatefulWidget {
  const AdminApplyPage({super.key});

  @override
  ConsumerState<AdminApplyPage> createState() => _AdminApplyPageState();
}

class _AdminApplyPageState extends ConsumerState<AdminApplyPage> {
  final _query = TextEditingController();
  Student? _student;
  List<Student>? _results;
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search(String schoolId, String branchId) async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(studentRepositoryProvider)
          .searchStudentsByAdmissionNumber(
            schoolId: schoolId,
            branchId: branchId,
            query: q,
          );
      if (mounted) setState(() => _results = page.items);
    } catch (e) {
      if (mounted) setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Apply for leave on behalf'),
        leading: BackButton(onPressed: () => context.go('/leave/applications')),
      ),
      body: StaffBranchScope(
        builder: (context, tenant, schoolId, branchId) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Find the student by admission number. This is available '
                      'only when the school has allowed office staff to file '
                      'leave on behalf of families.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _query,
                            decoration: const InputDecoration(
                              labelText: 'Admission number',
                            ),
                            onSubmitted: (_) => _search(schoolId, branchId),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        FilledButton(
                          onPressed: _searching
                              ? null
                              : () => _search(schoolId, branchId),
                          child: const Text('Find'),
                        ),
                      ],
                    ),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (_results != null && _student == null) ...[
                      const SizedBox(height: AppSpacing.md),
                      if (_results!.isEmpty)
                        const Text('No student found with that number.'),
                      for (final s in _results!)
                        ListTile(
                          title: Text(s.displayName),
                          subtitle: Text(s.admissionNumber),
                          onTap: () => setState(() => _student = s),
                        ),
                    ],
                    if (_student != null) ...[
                      const Divider(height: AppSpacing.xl),
                      _StudentForm(
                        tenant: tenant,
                        schoolId: schoolId,
                        student: _student!,
                        relation: ApplicantRelation.admin,
                        onDone: () => context.go('/leave/applications'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
