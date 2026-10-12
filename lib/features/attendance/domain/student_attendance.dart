import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import 'attendance_date.dart';
import 'attendance_status.dart';

/// A `.../branches/{branchId}/studentAttendance/{dateKey}_{studentId}`
/// document: one student's attendance for one civil date.
///
/// The id is deterministic, so a student has **at most one authoritative
/// record per date per branch** — a double-click, a retry, a re-opened
/// screen or two teachers marking at once all target the same document and
/// cannot create a duplicate. [classId], [sectionId], [academicYearId] and
/// [academicRecordId] are a snapshot of the placement the student was in
/// *when it was recorded* and never change afterwards, so a later transfer
/// does not rewrite history.
///
/// [revision] starts at 1 and grows by exactly 1 on every change (enforced
/// by `firestore.rules`); the save transaction compares it with the value
/// the user loaded, which is how a concurrent edit is detected instead of
/// being silently overwritten. Every change also writes a `history` entry.
class StudentAttendance {
  final String attendanceId;
  final String schoolId;
  final String branchId;
  final String academicYearId;
  final String dateKey;
  final String studentId;
  final String academicRecordId;
  final String classId;
  final String sectionId;
  final AttendanceStatus status;
  final String? remarks;
  final int revision;
  final String? lastChangeReason;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const StudentAttendance({
    required this.attendanceId,
    required this.schoolId,
    required this.branchId,
    required this.academicYearId,
    required this.dateKey,
    required this.studentId,
    required this.academicRecordId,
    required this.classId,
    required this.sectionId,
    required this.status,
    this.remarks,
    this.revision = 1,
    this.lastChangeReason,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  static String idFor(String dateKey, String studentId) =>
      '${dateKey}_$studentId';

  factory StudentAttendance.fromFirestore(
    String schoolId,
    String branchId,
    String id,
    Map<String, dynamic> data,
  ) {
    return StudentAttendance(
      attendanceId: id,
      schoolId: schoolId,
      branchId: branchId,
      academicYearId: data['academicYearId'] as String? ?? '',
      dateKey: data['dateKey'] as String? ?? '',
      studentId: data['studentId'] as String? ?? '',
      academicRecordId: data['academicRecordId'] as String? ?? '',
      classId: data['classId'] as String? ?? '',
      sectionId: data['sectionId'] as String? ?? '',
      status: AttendanceStatus.fromWireValue(
        data[FirestoreFields.status] as String,
      ),
      remarks: data['remarks'] as String?,
      revision: (data['revision'] as num?)?.toInt() ?? 1,
      lastChangeReason: data['lastChangeReason'] as String?,
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
      'dateKey': dateKey,
      'attendanceDate': AttendanceDate.timestampFor(dateKey),
      'studentId': studentId,
      'academicRecordId': academicRecordId,
      'classId': classId,
      'sectionId': sectionId,
      FirestoreFields.status: status.wireValue,
      'remarks': remarks,
      'revision': 1,
      'lastChangeReason': lastChangeReason,
      FirestoreFields.createdAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.createdBy: createdBy,
      FirestoreFields.updatedBy: createdBy,
    };
  }

  /// Only the mutable fields; identity, tenant and placement are untouched.
  /// [revision] on this instance must already be the *new* revision.
  Map<String, dynamic> toFirestoreUpdate({required String updatedBy}) {
    return {
      FirestoreFields.status: status.wireValue,
      'remarks': remarks,
      'revision': revision,
      'lastChangeReason': lastChangeReason,
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedBy: updatedBy,
    };
  }
}
