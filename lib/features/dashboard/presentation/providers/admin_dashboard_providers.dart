import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/activation_status.dart';
import '../../../../core/regional/school_time.dart';
import '../../../academic_setup/domain/academic_year.dart';
import '../../../academic_setup/domain/academic_year_status.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../attendance/domain/attendance_date.dart';
import '../../../attendance/presentation/providers/attendance_providers.dart';
import '../../../fees/presentation/providers/fee_providers.dart';
import '../../../students/domain/student_status.dart';
import '../../../students/presentation/providers/student_keys.dart';
import '../../../students/presentation/providers/student_providers.dart';
import '../../../users/presentation/providers/user_providers.dart';
import '../../data/firebase_parent_counter.dart';
import '../../domain/dashboard_summaries.dart';
import '../../domain/parent_counter.dart';

final parentCounterProvider = Provider<ParentCounter>(
  (ref) => FirebaseParentCounter(ref.watch(firestoreProvider)),
);

/// Active parent records of the branch (a server-side count).
final dashboardParentCountProvider = FutureProvider.autoDispose
    .family<int, BranchKey>(
      (ref, key) => ref
          .watch(parentCounterProvider)
          .countParents(
            schoolId: key.schoolId,
            branchId: key.branchId,
            status: ActivationStatus.active,
          ),
    );

/// Active students of the branch (reuses the roster's count provider).
final dashboardStudentCountProvider = FutureProvider.autoDispose
    .family<int, BranchKey>((ref, key) async {
      final counts = await ref.watch(studentCountsProvider(key).future);
      return counts[StudentStatus.active] ?? 0;
    });

/// The branch's current academic year: the ACTIVE one, else the first.
final dashboardYearProvider = FutureProvider.autoDispose
    .family<AcademicYear?, BranchKey>((ref, key) async {
      final years = await ref.watch(academicYearsProvider(key).future);
      if (years.isEmpty) return null;
      return years.firstWhere(
        (y) => y.status == AcademicYearStatus.active,
        orElse: () => years.first,
      );
    });

/// Today's attendance (school time) from the section registers' stored
/// counts: one small query, no per-student reads.
final attendanceTodayProvider = FutureProvider.autoDispose
    .family<AttendanceToday?, BranchKey>((ref, key) async {
      final year = await ref.watch(dashboardYearProvider(key).future);
      if (year == null) return null;
      final expected = await ref.watch(
        dashboardStudentCountProvider(key).future,
      );
      final registers = await ref
          .watch(studentAttendanceRepositoryProvider)
          .fetchSessions(
            schoolId: key.schoolId,
            branchId: key.branchId,
            academicYearId: year.academicYearId,
            dateKey: SchoolTime.todayKey(),
          );
      return AttendanceToday.from(
        expectedStudents: expected,
        registers: registers,
      );
    });

/// The fee card: this month's collections (school time) and the academic
/// year's outstanding balance and rate, from the existing fee reports.
final feeMonthCardProvider = FutureProvider.autoDispose
    .family<FeeMonthCard?, BranchKey>((ref, key) async {
      final year = await ref.watch(dashboardYearProvider(key).future);
      if (year == null) return null;
      final today = SchoolTime.today();
      final from = AttendanceDate.key(DateTime(today.year, today.month, 1));
      final to = AttendanceDate.key(today);
      final repo = ref.watch(feeReportRepositoryProvider);
      final monthF = repo.loadCollections(
        schoolId: key.schoolId,
        branchId: key.branchId,
        academicYearId: year.academicYearId,
        fromKey: from,
        toKey: to,
      );
      final yearF = repo.loadSummary(
        schoolId: key.schoolId,
        branchId: key.branchId,
        academicYearId: year.academicYearId,
        todayKey: to,
      );
      return FeeMonthCard.from(month: await monthF, year: await yearF);
    });
