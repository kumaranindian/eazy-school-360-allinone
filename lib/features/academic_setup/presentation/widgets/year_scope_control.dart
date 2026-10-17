import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/academic_year.dart';
import '../../domain/academic_year_status.dart';
import '../providers/academic_structure_providers.dart';
import 'academic_year_selector.dart';

/// The academic-year picker of a scoped page (Fees, Leave, Timetable), meant
/// for the shared scope row beside the branch picker. It reads the branch's
/// years itself and chooses the same default as the scopes do: the chosen
/// year, else the active one, else the first.
class YearScopeControl extends ConsumerWidget {
  final String schoolId;
  final String branchId;
  final String? selectedId;
  final ValueChanged<String> onChanged;

  const YearScopeControl({
    super.key,
    required this.schoolId,
    required this.branchId,
    required this.selectedId,
    required this.onChanged,
  });

  /// The year a scope shows: [id] if it exists, else the active one, else the
  /// first. Shared so the picker and the page below it always agree.
  static AcademicYear pick(List<AcademicYear> years, String? id) =>
      years.firstWhere(
        (y) => y.academicYearId == id,
        orElse: () => years.firstWhere(
          (y) => y.status == AcademicYearStatus.active,
          orElse: () => years.first,
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final years =
        ref
            .watch(
              academicYearsProvider((schoolId: schoolId, branchId: branchId)),
            )
            .value ??
        const <AcademicYear>[];
    if (years.isEmpty) return const SizedBox.shrink();
    return AcademicYearSelector(
      years: years,
      selectedId: pick(years, selectedId).academicYearId,
      onChanged: onChanged,
    );
  }
}
