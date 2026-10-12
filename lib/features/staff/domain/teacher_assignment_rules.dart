import '../../../core/constants/activation_status.dart';
import '../../academic_setup/domain/academic_year_status.dart';
import 'staff_status.dart';

/// The business checks behind creating or ending a teacher assignment, as
/// pure functions of already-fetched facts: each returns a user-readable
/// reason the action is refused, or null when it is fine. The repository
/// fetches the documents and calls these; `firestore.rules` independently
/// re-enforces the same references server-side.
abstract final class TeacherAssignmentRules {
  static String? checkTeacher({
    required bool exists,
    bool isTeacher = false,
    StaffStatus? status,
  }) {
    if (!exists) return 'This staff member could not be found.';
    if (!isTeacher) {
      return 'This staff member does not have teaching responsibility.';
    }
    if (status == null || !status.canReceiveAssignments) {
      return 'A ${status?.displayName.toLowerCase() ?? 'non-active'} staff member cannot receive new assignments.';
    }
    return null;
  }

  static String? checkAcademicYear({
    required bool exists,
    AcademicYearStatus? status,
  }) {
    if (!exists) return 'The selected academic year does not exist.';
    if (status == AcademicYearStatus.closed) {
      return 'This academic year is closed. Assignments can no longer be added to it.';
    }
    return null;
  }

  /// The section is looked up *under* the chosen class and year, so
  /// "exists" also proves it belongs to them.
  static String? checkSection({
    required bool exists,
    ActivationStatus? status,
  }) {
    if (!exists) {
      return 'The selected section does not belong to the selected class and academic year.';
    }
    if (status != ActivationStatus.active) {
      return 'The selected section is inactive.';
    }
    return null;
  }

  /// A class-teacher assignment needs no subject; a subject assignment needs
  /// one that is linked to the class (Milestone 2's class-subject link).
  static String? checkSubject({
    required bool isClassTeacher,
    required String? subjectId,
    required bool linkedToClass,
  }) {
    if (isClassTeacher) return null;
    if (subjectId == null) {
      return 'Choose a subject, or assign the teacher as class teacher.';
    }
    if (!linkedToClass) {
      return 'That subject is not configured for the selected class.';
    }
    return null;
  }

  /// [holderStaffId] is the teacher currently holding the slot, if any.
  static String? checkSlotFree({
    required bool isClassTeacher,
    required String teacherStaffId,
    required String? holderStaffId,
  }) {
    if (holderStaffId == null) return null;
    if (holderStaffId == teacherStaffId) {
      return isClassTeacher
          ? 'This teacher is already the class teacher of this section.'
          : 'This teacher already teaches this subject in this section.';
    }
    return isClassTeacher
        ? 'This section already has a class teacher. End that assignment first.'
        : 'This subject is already assigned to another teacher in this section. End that assignment first.';
  }

  static String? checkEnd({
    required bool isActive,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    if (!isActive) return 'This assignment has already ended.';
    final startDay = DateTime(startDate.year, startDate.month, startDate.day);
    if (endDate.isBefore(startDay)) {
      return 'The end date cannot be before the start date.';
    }
    return null;
  }
}
