import 'dart:async';

import 'package:eazy_school_360/features/academic_setup/domain/school_academic_year.dart';
import 'package:eazy_school_360/features/academic_setup/domain/school_year_repository.dart';

/// In-memory [SchoolYearRepository]. Records what was opened where; a branch
/// listed in [refusing] is denied (like the rules would).
class FakeSchoolYearRepository implements SchoolYearRepository {
  final List<SchoolAcademicYear> years;
  final Map<String, Set<String>> opened; // yearId -> branch ids
  final Set<String> refusing;
  final List<({String yearId, List<String> branches})> openCalls = [];
  final List<SchoolAcademicYear> created = [];
  final List<({String yearId, bool archived})> archiveCalls = [];

  FakeSchoolYearRepository({
    this.years = const [],
    Map<String, Set<String>>? opened,
    this.refusing = const {},
  }) : opened = opened ?? {};

  @override
  Stream<List<SchoolAcademicYear>> watchSchoolYears(String schoolId) =>
      Stream.value(years);

  @override
  Future<String> createSchoolYear(
    SchoolAcademicYear year, {
    required String createdBy,
  }) async {
    created.add(year);
    return 'new-${created.length}';
  }

  @override
  Future<void> setArchived(
    String schoolId,
    String schoolYearId, {
    required bool archived,
    required String updatedBy,
  }) async => archiveCalls.add((yearId: schoolYearId, archived: archived));

  @override
  Future<List<OpenYearResult>> openInBranches(
    SchoolAcademicYear year,
    List<String> branchIds, {
    required String createdBy,
  }) async {
    openCalls.add((yearId: year.schoolYearId, branches: branchIds));
    final out = <OpenYearResult>[];
    for (final b in branchIds) {
      final set = opened.putIfAbsent(year.schoolYearId, () => {});
      if (set.contains(b)) {
        out.add(OpenYearResult(b, OpenYearOutcome.alreadyOpen));
      } else if (refusing.contains(b)) {
        out.add(
          OpenYearResult(b, OpenYearOutcome.failed, 'You do not have access.'),
        );
      } else {
        set.add(b);
        out.add(OpenYearResult(b, OpenYearOutcome.opened));
      }
    }
    return out;
  }

  @override
  Future<Set<String>> openedIn(
    String schoolId,
    String schoolYearId,
    List<String> branchIds,
  ) async => {
    for (final b in branchIds)
      if (opened[schoolYearId]?.contains(b) ?? false) b,
  };
}
