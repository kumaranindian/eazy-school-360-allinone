import '../../../academic_setup/presentation/widgets/year_scope_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../academic_setup/domain/academic_year.dart';
import '../../../academic_setup/domain/academic_year_status.dart';
import '../../../academic_setup/presentation/providers/academic_setup_keys.dart';
import '../../../../core/regional/regional_providers.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../../domain/fee_repositories.dart';

/// What a fees screen works in: the signed-in user, the branch, the chosen
/// academic year, and the school details that get frozen into invoices.
class FeeContext {
  final TenantContext tenant;
  final String schoolId;
  final String branchId;
  final AcademicYear year;
  final InvoiceSchoolInfo info;

  const FeeContext({
    required this.tenant,
    required this.schoolId,
    required this.branchId,
    required this.year,
    required this.info,
  });

  String get currency => info.currency;
  String get userId => tenant.user.userId;
  String get userName => tenant.user.name;
  ({String schoolId, String branchId, String academicYearId}) get yearKey => (
    schoolId: schoolId,
    branchId: branchId,
    academicYearId: year.academicYearId,
  );
}

/// Resolves branch (the staff branch switcher), academic year (a dropdown,
/// defaulting to the active year) and school info, then hands a [FeeContext]
/// to [builder]. Fees are always scoped to one branch and one academic year.
class FeeScope extends ConsumerStatefulWidget {
  final Widget Function(BuildContext context, FeeContext fee) builder;

  /// Hide the year dropdown on screens that do not need it.
  final bool showYearSelector;

  const FeeScope({
    super.key,
    required this.builder,
    this.showYearSelector = true,
  });

  @override
  ConsumerState<FeeScope> createState() => _FeeScopeState();
}

class _FeeScopeState extends ConsumerState<FeeScope> {
  String? _yearId;

  @override
  Widget build(BuildContext context) {
    return StaffBranchScope(
      // The year picker sits in the branch picker's row, not a row of its own.
      scopeControl: widget.showYearSelector
          ? (context, schoolId, branchId) => YearScopeControl(
              schoolId: schoolId,
              branchId: branchId,
              selectedId: _yearId,
              onChanged: (v) => setState(() => _yearId = v),
            )
          : null,
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
            message: 'Create an academic year in Settings before using fees.',
          );
        }
        final selected = years.firstWhere(
          (y) => y.academicYearId == _yearId,
          orElse: () => years.firstWhere(
            (y) => y.status == AcademicYearStatus.active,
            orElse: () => years.first,
          ),
        );
        // One currency for the whole school (Regional settings).
        final currency = ref.watch(regionalSettingsProvider).currency;
        final info = InvoiceSchoolInfo(
          schoolName: tenant.school?.name ?? '',
          branchName: tenant.branch?.name ?? '',
          academicYearName: selected.name,
          academicYearStartYear: selected.startDate.year,
          currency: currency,
        );
        final fee = FeeContext(
          tenant: tenant,
          schoolId: schoolId,
          branchId: branchId,
          year: selected,
          info: info,
        );

        return Column(
          children: [
            Expanded(
              child: KeyedSubtree(
                key: ValueKey('${selected.academicYearId}/$branchId'),
                child: widget.builder(context, fee),
              ),
            ),
          ],
        );
      },
    );
  }
}
