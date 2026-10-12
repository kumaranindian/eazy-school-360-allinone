import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../academic_setup/domain/academic_year.dart';
import '../../../academic_setup/domain/academic_year_status.dart';
import '../../../academic_setup/presentation/providers/academic_setup_keys.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../attendance/domain/attendance_date.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';

/// What a leave screen works in: the signed-in user, the branch and the leave
/// year (= academic year).
class LeaveContext {
  final TenantContext tenant;
  final String schoolId;
  final String branchId;
  final AcademicYear year;

  const LeaveContext({
    required this.tenant,
    required this.schoolId,
    required this.branchId,
    required this.year,
  });

  String get userId => tenant.user.userId;
  String get userName => tenant.user.name;
  String get yearStartKey => AttendanceDate.key(year.startDate.toUtc());
  String get yearEndKey => AttendanceDate.key(year.endDate.toUtc());
  AcademicYearKey get yearKey => (
    schoolId: schoolId,
    branchId: branchId,
    academicYearId: year.academicYearId,
  );
  BranchKey get branchKey => (schoolId: schoolId, branchId: branchId);
}

/// Resolves branch (the staff branch switcher) and academic year (dropdown,
/// defaulting to the active year) and hands a [LeaveContext] to [builder].
class LeaveScope extends ConsumerStatefulWidget {
  final Widget Function(BuildContext context, LeaveContext leave) builder;
  final bool showYearSelector;

  const LeaveScope({
    super.key,
    required this.builder,
    this.showYearSelector = true,
  });

  @override
  ConsumerState<LeaveScope> createState() => _LeaveScopeState();
}

class _LeaveScopeState extends ConsumerState<LeaveScope> {
  String? _yearId;

  @override
  Widget build(BuildContext context) {
    return StaffBranchScope(
      builder: (context, tenant, schoolId, branchId) {
        final BranchKey branchKey = (schoolId: schoolId, branchId: branchId);
        final yearsAsync = ref.watch(academicYearsProvider(branchKey));
        if (yearsAsync.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (yearsAsync.hasError) {
          return ErrorView(
            message: userMessageFor(yearsAsync.error!),
            onRetry: () => ref.invalidate(academicYearsProvider(branchKey)),
          );
        }
        final years = yearsAsync.value ?? const <AcademicYear>[];
        if (years.isEmpty) {
          return const EmptyView(
            icon: Icons.event_outlined,
            message: 'Create an academic year in Settings before using leave.',
          );
        }
        final selected = years.firstWhere(
          (y) => y.academicYearId == _yearId,
          orElse: () => years.firstWhere(
            (y) => y.status == AcademicYearStatus.active,
            orElse: () => years.first,
          ),
        );
        final leave = LeaveContext(
          tenant: tenant,
          schoolId: schoolId,
          branchId: branchId,
          year: selected,
        );
        return Column(
          children: [
            if (widget.showYearSelector)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  0,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: DropdownButtonFormField<String>(
                      value: selected.academicYearId,
                      decoration: const InputDecoration(
                        labelText: 'Academic year',
                        isDense: true,
                      ),
                      items: [
                        for (final y in years)
                          DropdownMenuItem(
                            value: y.academicYearId,
                            child: Text(y.name),
                          ),
                      ],
                      onChanged: (v) => setState(() => _yearId = v),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: KeyedSubtree(
                key: ValueKey('${selected.academicYearId}/$branchId'),
                child: widget.builder(context, leave),
              ),
            ),
          ],
        );
      },
    );
  }
}
