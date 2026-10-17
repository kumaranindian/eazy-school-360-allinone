import 'package:flutter/material.dart';

import '../../../../shared/layouts/hero_scope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/permissions/user_role.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../attendance/domain/attendance_date.dart';
import '../../../fees/presentation/pages/parent_fees_page.dart'
    show linkedChildrenProvider;
import '../../../staff/domain/staff.dart';
import '../../../staff/presentation/providers/staff_providers.dart';
import '../../../students/domain/student.dart';
import '../../domain/leave_application.dart';
import '../../domain/leave_balance.dart';
import '../../domain/leave_enums.dart';
import '../../domain/leave_units.dart';
import '../providers/leave_providers.dart';
import '../widgets/leave_widgets.dart';

/// `/my-leave` — a staff member's own leave, or a parent's children's leave.
/// Everything shown is read through `firestore.rules`: a parent sees only
/// children with an ACTIVE, portal-enabled link; staff see only their own.
class MyLeavePage extends ConsumerWidget {
  const MyLeavePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: pageAppBar(
        context,
        title: const Text('My leave'),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.go('/my-leave/notifications'),
          ),
        ],
      ),
      body: AsyncValueWidget<TenantContext?>(
        value: ref.watch(tenantContextProvider),
        data: (tenant) {
          final school = tenant?.school;
          if (tenant == null || school == null) {
            return const EmptyView(
              icon: Icons.beach_access_outlined,
              message: 'No school found for your account.',
            );
          }
          return tenant.role == UserRole.parent
              ? _ParentLeave(tenant: tenant, schoolId: school.schoolId)
              : _StaffLeave(tenant: tenant, schoolId: school.schoolId);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- parent

class _ParentLeave extends ConsumerStatefulWidget {
  final TenantContext tenant;
  final String schoolId;

  const _ParentLeave({required this.tenant, required this.schoolId});

  @override
  ConsumerState<_ParentLeave> createState() => _ParentLeaveState();
}

class _ParentLeaveState extends ConsumerState<_ParentLeave> {
  String? _childId;

  @override
  Widget build(BuildContext context) {
    final parentId = widget.tenant.user.linkedParentId;
    if (parentId == null) {
      return const EmptyView(
        icon: Icons.link_off,
        message:
            "Your account isn't linked to a parent record yet. Please contact the school office.",
      );
    }
    final children = ref.watch(
      linkedChildrenProvider((schoolId: widget.schoolId, parentId: parentId)),
    );
    return children.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
        message: userMessageFor(e),
        onRetry: () => ref.invalidate(linkedChildrenProvider),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyView(
            icon: Icons.child_care_outlined,
            message: 'No children are linked to your account yet.',
          );
        }
        final child = list.firstWhere(
          (c) => c.studentId == _childId,
          orElse: () => list.first,
        );
        return _ChildLeave(
          tenant: widget.tenant,
          schoolId: widget.schoolId,
          children: list,
          child: child,
          onSelect: (id) => setState(() => _childId = id),
        );
      },
    );
  }
}

class _ChildLeave extends ConsumerWidget {
  final TenantContext tenant;
  final String schoolId;
  final List<Student> children;
  final Student child;
  final ValueChanged<String> onSelect;

  const _ChildLeave({
    required this.tenant,
    required this.schoolId,
    required this.children,
    required this.child,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (
      schoolId: schoolId,
      branchId: child.branchId,
      kind: LeaveKind.student,
      subjectId: child.studentId,
    );
    final applications = ref.watch(subjectLeaveProvider(key));
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (children.length > 1)
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final c in children)
                ChoiceChip(
                  label: Text(c.displayName),
                  selected: c.studentId == child.studentId,
                  onSelected: (_) => onSelect(c.studentId),
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: Text(
                'Leave for ${child.displayName}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            FilledButton.icon(
              onPressed: () => context.go(
                '/my-leave/apply?studentId=${child.studentId}&b=${child.branchId}',
              ),
              icon: const Icon(Icons.add),
              label: const Text('Apply for leave'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        applications.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => ErrorView(
            message: userMessageFor(e),
            onRetry: () => ref.invalidate(subjectLeaveProvider(key)),
          ),
          data: (list) => _ApplicationList(
            applications: list,
            branchId: child.branchId,
            emptyMessage: 'No leave applications yet for ${child.firstName}.',
          ),
        ),
      ],
    );
  }
}

class _ApplicationList extends StatelessWidget {
  final List<LeaveApplication> applications;
  final String branchId;
  final String emptyMessage;

  const _ApplicationList({
    required this.applications,
    required this.branchId,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (applications.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Center(child: Text(emptyMessage)),
      );
    }
    return Column(
      children: [
        for (final a in applications)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: LeaveApplicationTile(
              application: a,
              showSubject: false,
              onTap: () => context.go(
                '/my-leave/applications/${a.applicationId}?b=$branchId',
              ),
            ),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------------ staff

class _StaffLeave extends ConsumerWidget {
  final TenantContext tenant;
  final String schoolId;

  const _StaffLeave({required this.tenant, required this.schoolId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branchId = tenant.user.branchId ?? tenant.branch?.branchId;
    if (branchId == null) {
      return const EmptyView(
        icon: Icons.beach_access_outlined,
        message: 'No branch found for your account.',
      );
    }
    final own = ref.watch(
      ownStaffProvider((
        schoolId: schoolId,
        branchId: branchId,
        userId: tenant.user.userId,
      )),
    );
    return own.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
        message: userMessageFor(e),
        onRetry: () => ref.invalidate(ownStaffProvider),
      ),
      data: (staff) {
        if (staff == null) {
          return const EmptyView(
            icon: Icons.link_off,
            message:
                "Your account isn't linked to a staff record yet, so leave "
                'cannot be applied for here. Please contact the school office.',
          );
        }
        return _StaffBody(
          tenant: tenant,
          schoolId: schoolId,
          branchId: branchId,
          staff: staff,
        );
      },
    );
  }
}

class _StaffBody extends ConsumerWidget {
  final TenantContext tenant;
  final String schoolId;
  final String branchId;
  final Staff staff;

  const _StaffBody({
    required this.tenant,
    required this.schoolId,
    required this.branchId,
    required this.staff,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final key = (
      schoolId: schoolId,
      branchId: branchId,
      kind: LeaveKind.staff,
      subjectId: staff.staffId,
    );
    final applications = ref.watch(subjectLeaveProvider(key));
    // The active leave year's balances. The year is the academic year the
    // most recent application used, else resolved on the apply page.
    final yearId = applications.value
        ?.map((a) => a.academicYearId)
        .whereType<String>()
        .firstOrNull;
    final balances = yearId == null
        ? const AsyncValue<List<LeaveBalance>>.data([])
        : ref.watch(
            staffLeaveBalancesProvider((
              schoolId: schoolId,
              branchId: branchId,
              staffId: staff.staffId,
              academicYearId: yearId,
            )),
          );
    final types =
        ref
            .watch(
              leaveTypesProvider((
                schoolId: schoolId,
                branchId: branchId,
                kind: LeaveKind.staff,
              )),
            )
            .value ??
        const [];
    final typeNames = {for (final t in types) t.typeId: t.name};
    final today = AttendanceDate.key(DateTime.now());

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                staff.displayName,
                style: theme.textTheme.titleMedium,
              ),
            ),
            FilledButton.icon(
              onPressed: () => context.go('/my-leave/apply'),
              icon: const Icon(Icons.add),
              label: const Text('Apply for leave'),
            ),
          ],
        ),
        if (tenant.can(Permission.viewLeaveCalendar))
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => context.go('/leave/calendar'),
              icon: const Icon(Icons.calendar_month_outlined),
              label: const Text('Leave calendar'),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        Text('Balances', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        balances.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(userMessageFor(e)),
          data: (list) {
            if (list.isEmpty) {
              return Text(
                'No leave balance has been set up for you yet. A balance '
                'appears after your first approved leave, or when the school '
                'office initialises it.',
                style: theme.textTheme.bodySmall,
              );
            }
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final b in list)
                  _BalanceCard(
                    name: typeNames[b.typeId] ?? b.typeId,
                    figures: LeaveBalanceMath.figures(
                      balance: b,
                      todayKey: today,
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        Text('My applications', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        applications.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorView(
            message: userMessageFor(e),
            onRetry: () => ref.invalidate(subjectLeaveProvider(key)),
          ),
          data: (list) => _ApplicationList(
            applications: list,
            branchId: branchId,
            emptyMessage: 'You have not applied for leave yet.',
          ),
        ),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final String name;
  final LeaveBalanceFigures figures;

  const _BalanceCard({required this.name, required this.figures});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 220,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                LeaveUnits.formatDays(figures.available),
                style: theme.textTheme.headlineSmall,
              ),
              Text('available', style: theme.textTheme.bodySmall),
              const Divider(),
              Text(
                'Granted ${LeaveUnits.format(figures.accrued + figures.carryForward + figures.adjustments)} · '
                'Used ${LeaveUnits.format(figures.consumed)}'
                '${figures.pending > 0 ? ' · Pending ${LeaveUnits.format(figures.pending)}' : ''}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
