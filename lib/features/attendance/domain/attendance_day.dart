import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import 'attendance_date.dart';
import 'attendance_status.dart';
import 'attendance_tally.dart';
import 'attendance_calendar.dart';

/// The "register" for one day: whether the entries are still DRAFT or
/// FINALIZED, plus maintained counts so dashboards read one small document
/// instead of every student.
///
/// - Student attendance: one per section per date,
///   `attendanceSessions/{dateKey}__{year}__{class}__{section}`.
/// - Staff attendance: one per branch per date,
///   `staffAttendanceDays/{dateKey}` (the year/class/section are null).
///
/// The counts are computed from the complete register inside the same
/// transaction that writes the records, so they are consistent with the
/// records at that moment; `firestore.rules` checks who may write them and
/// their shape, not the arithmetic.
class AttendanceDay {
  final String dayId;
  final String schoolId;
  final String branchId;
  final String? academicYearId;
  final String? classId;
  final String? sectionId;
  final String dateKey;
  final AttendanceDayStatus status;
  final AttendanceTally tally;
  final CalendarDayKind dayKind;
  final String? overrideReason;
  final int revision;
  final DateTime? finalizedAt;
  final String? finalizedBy;
  final DateTime? updatedAt;
  final String? updatedBy;

  const AttendanceDay({
    required this.dayId,
    required this.schoolId,
    required this.branchId,
    this.academicYearId,
    this.classId,
    this.sectionId,
    required this.dateKey,
    required this.status,
    required this.tally,
    this.dayKind = CalendarDayKind.workingDay,
    this.overrideReason,
    this.revision = 1,
    this.finalizedAt,
    this.finalizedBy,
    this.updatedAt,
    this.updatedBy,
  });

  bool get isFinalized => status == AttendanceDayStatus.finalized;

  static String studentSessionId({
    required String dateKey,
    required String academicYearId,
    required String classId,
    required String sectionId,
  }) => [dateKey, academicYearId, classId, sectionId].join('__');

  static String staffDayId(String dateKey) => dateKey;

  factory AttendanceDay.fromFirestore(
    String schoolId,
    String branchId,
    String id,
    Map<String, dynamic> data,
  ) {
    int n(String key) => (data[key] as num?)?.toInt() ?? 0;
    return AttendanceDay(
      dayId: id,
      schoolId: schoolId,
      branchId: branchId,
      academicYearId: data['academicYearId'] as String?,
      classId: data['classId'] as String?,
      sectionId: data['sectionId'] as String?,
      dateKey: data['dateKey'] as String? ?? '',
      status: AttendanceDayStatus.fromWireValue(
        data[FirestoreFields.status] as String,
      ),
      tally: AttendanceTally(
        present: n('present'),
        absent: n('absent'),
        late: n('late'),
        halfDay: n('halfDay'),
        notMarked: n('notMarked'),
      ),
      dayKind: CalendarDayKind.values.firstWhere(
        (k) => k.name == data['dayKind'],
        orElse: () => CalendarDayKind.workingDay,
      ),
      overrideReason: data['overrideReason'] as String?,
      revision: (data['revision'] as num?)?.toInt() ?? 1,
      finalizedAt: (data['finalizedAt'] as Timestamp?)?.toDate(),
      finalizedBy: data['finalizedBy'] as String?,
      updatedAt: (data[FirestoreFields.updatedAt] as Timestamp?)?.toDate(),
      updatedBy: data[FirestoreFields.updatedBy] as String?,
    );
  }

  Map<String, dynamic> _fields({required String actor}) {
    return {
      'dateKey': dateKey,
      'attendanceDate': AttendanceDate.timestampFor(dateKey),
      FirestoreFields.status: status.wireValue,
      'enrolled': tally.total,
      'present': tally.present,
      'absent': tally.absent,
      'late': tally.late,
      'halfDay': tally.halfDay,
      'notMarked': tally.notMarked,
      'dayKind': dayKind.name,
      'overrideReason': overrideReason,
      'revision': revision,
      'finalizedAt': isFinalized ? FieldValue.serverTimestamp() : null,
      'finalizedBy': isFinalized ? actor : null,
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedBy: actor,
    };
  }

  /// [revision] must be 1 for a create.
  Map<String, dynamic> toFirestoreCreate({required String createdBy}) {
    return {
      FirestoreFields.schoolId: schoolId,
      FirestoreFields.branchId: branchId,
      if (academicYearId != null) 'academicYearId': academicYearId,
      if (classId != null) 'classId': classId,
      if (sectionId != null) 'sectionId': sectionId,
      ..._fields(actor: createdBy),
      FirestoreFields.createdAt: FieldValue.serverTimestamp(),
      FirestoreFields.createdBy: createdBy,
    };
  }

  /// [revision] must already be the new revision.
  Map<String, dynamic> toFirestoreUpdate({required String updatedBy}) =>
      _fields(actor: updatedBy);
}
