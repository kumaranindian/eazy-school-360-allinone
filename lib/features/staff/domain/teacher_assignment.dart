import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import 'teacher_assignment_status.dart';

/// A `.../branches/{branchId}/teacherAssignments/{assignmentId}` document:
/// "[teacherStaffId] teaches [subjectId] to [classId]-[sectionId] in
/// [academicYearId]" — or, when [isClassTeacher], "is the class teacher of
/// [classId]-[sectionId]" (then [subjectId] is null).
///
/// One row per teacher × section × subject × year, never overwritten with
/// a new placement: changing what someone teaches ends the old row
/// ([TeacherAssignmentStatus.ended] + [endDate]) and creates a new one, so
/// "who taught Class 5-A Maths in 2026-27" stays answerable forever.
///
/// Uniqueness lives in `assignmentSlots` (doc id = [slotKeyFor]) — at most
/// one ACTIVE teacher per section+subject+year and one class teacher per
/// section+year, enforced atomically by `firestore.rules` rather than by a
/// racy client-side query. The IDs here is a reference, never a copy of
/// the class/subject names, so renaming a class doesn't rewrite history.
class TeacherAssignment {
  final String assignmentId;
  final String schoolId;
  final String branchId;
  final String academicYearId;
  final String teacherStaffId;
  final String classId;
  final String sectionId;
  final String? subjectId;
  final bool isClassTeacher;
  final DateTime startDate;
  final DateTime? endDate;
  final TeacherAssignmentStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const TeacherAssignment({
    required this.assignmentId,
    required this.schoolId,
    required this.branchId,
    required this.academicYearId,
    required this.teacherStaffId,
    required this.classId,
    required this.sectionId,
    this.subjectId,
    required this.isClassTeacher,
    required this.startDate,
    this.endDate,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  /// Doc id of the `assignmentSlots` reservation guarding this
  /// assignment's uniqueness. `CLASS_TEACHER` cannot collide with a
  /// subject id (Firestore auto ids contain no underscore).
  static String slotKeyFor({
    required String academicYearId,
    required String classId,
    required String sectionId,
    String? subjectId,
  }) {
    return [
      academicYearId,
      classId,
      sectionId,
      subjectId ?? classTeacherSlotName,
    ].join('__');
  }

  static const String classTeacherSlotName = 'CLASS_TEACHER';

  String get slotKey => slotKeyFor(
    academicYearId: academicYearId,
    classId: classId,
    sectionId: sectionId,
    subjectId: isClassTeacher ? null : subjectId,
  );

  bool get isActive => status == TeacherAssignmentStatus.active;

  factory TeacherAssignment.fromFirestore(
    String schoolId,
    String branchId,
    String id,
    Map<String, dynamic> data,
  ) {
    return TeacherAssignment(
      assignmentId: id,
      schoolId: schoolId,
      branchId: branchId,
      academicYearId: data['academicYearId'] as String? ?? '',
      teacherStaffId: data['teacherStaffId'] as String? ?? '',
      classId: data['classId'] as String? ?? '',
      sectionId: data['sectionId'] as String? ?? '',
      subjectId: data['subjectId'] as String?,
      isClassTeacher: data['isClassTeacher'] as bool? ?? false,
      startDate: (data['startDate'] as Timestamp).toDate(),
      endDate: (data['endDate'] as Timestamp?)?.toDate(),
      status: TeacherAssignmentStatus.fromWireValue(
        data[FirestoreFields.status] as String,
      ),
      createdAt: (data[FirestoreFields.createdAt] as Timestamp?)?.toDate(),
      updatedAt: (data[FirestoreFields.updatedAt] as Timestamp?)?.toDate(),
      createdBy: data[FirestoreFields.createdBy] as String?,
      updatedBy: data[FirestoreFields.updatedBy] as String?,
    );
  }

  Map<String, dynamic> toFirestoreCreate({required String createdBy}) {
    return {
      FirestoreFields.schoolId: schoolId,
      FirestoreFields.branchId: branchId,
      'academicYearId': academicYearId,
      'teacherStaffId': teacherStaffId,
      'classId': classId,
      'sectionId': sectionId,
      'subjectId': isClassTeacher ? null : subjectId,
      'isClassTeacher': isClassTeacher,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': null,
      FirestoreFields.status: TeacherAssignmentStatus.active.wireValue,
      FirestoreFields.createdAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.createdBy: createdBy,
      FirestoreFields.updatedBy: createdBy,
    };
  }

  /// The slot reservation written alongside the assignment.
  Map<String, dynamic> toSlotData({required String createdBy}) {
    return {
      FirestoreFields.schoolId: schoolId,
      FirestoreFields.branchId: branchId,
      'assignmentId': assignmentId,
      'teacherStaffId': teacherStaffId,
      FirestoreFields.createdAt: FieldValue.serverTimestamp(),
      FirestoreFields.createdBy: createdBy,
    };
  }

  static Map<String, dynamic> firestoreEnd({
    required DateTime endDate,
    required String updatedBy,
  }) {
    return {
      FirestoreFields.status: TeacherAssignmentStatus.ended.wireValue,
      'endDate': Timestamp.fromDate(endDate),
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedBy: updatedBy,
    };
  }
}
