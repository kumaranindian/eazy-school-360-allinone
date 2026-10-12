import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../staff/domain/teacher_assignment.dart';
import '../../../staff/presentation/providers/staff_keys.dart';
import '../../../staff/presentation/providers/staff_providers.dart';
import '../../../users/presentation/providers/user_providers.dart';
import '../../data/firebase_staff_attendance_repository.dart';
import '../../data/firebase_student_attendance_repository.dart';
import '../../domain/staff_attendance_repository.dart';
import '../../domain/student_attendance_repository.dart';

final studentAttendanceRepositoryProvider =
    Provider<StudentAttendanceRepository>((ref) {
      return FirebaseStudentAttendanceRepository(ref.watch(firestoreProvider));
    });

final staffAttendanceRepositoryProvider = Provider<StaffAttendanceRepository>((
  ref,
) {
  return FirebaseStaffAttendanceRepository(ref.watch(firestoreProvider));
});

/// The sections the signed-in teacher is **class teacher of** right now —
/// the only sections they may mark (mirrors `isClassTeacherOf` in
/// `firestore.rules`). Empty if their account is not linked to a staff
/// record or they hold no class-teacher assignment.
final classTeacherAssignmentsProvider = FutureProvider.autoDispose
    .family<List<TeacherAssignment>, OwnStaffKey>((ref, key) async {
      final staff = await ref.watch(ownStaffProvider(key).future);
      if (staff == null) return const [];
      final assignments = await ref.watch(
        teacherAssignmentsProvider((
          schoolId: key.schoolId,
          branchId: key.branchId,
          staffId: staff.staffId,
        )).future,
      );
      return assignments.where((a) => a.isActive && a.isClassTeacher).toList();
    });
