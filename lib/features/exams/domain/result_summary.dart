import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../attendance/domain/attendance_tally.dart';
import 'result_calculator.dart';

/// Attendance counted over the academic year up to finalisation, from the
/// existing student attendance records: `(present + late + ½ half-day) ÷
/// marked days × 100` (the attendance module's own definition). A snapshot —
/// a report card never changes when attendance is corrected later.
class AttendanceSnapshot {
  final double attendedDays;
  final int markedDays;
  final double? percentage;
  final String fromKey;
  final String toKey;

  const AttendanceSnapshot({
    required this.attendedDays,
    required this.markedDays,
    this.percentage,
    required this.fromKey,
    required this.toKey,
  });

  /// From the attendance module's own tally, so the percentage means exactly
  /// what it means there: `(present + late + ½ half-day) ÷ marked days`.
  factory AttendanceSnapshot.fromTally(
    AttendanceTally tally, {
    required String fromKey,
    required String toKey,
  }) => AttendanceSnapshot(
    attendedDays: tally.attendedDays,
    markedDays: tally.marked,
    percentage: tally.percentage,
    fromKey: fromKey,
    toKey: toKey,
  );

  Map<String, dynamic> toMap() => {
    'attendedDays': attendedDays,
    'markedDays': markedDays,
    'percentage': percentage,
    'fromKey': fromKey,
    'toKey': toKey,
  };

  factory AttendanceSnapshot.fromMap(Map<String, dynamic> m) =>
      AttendanceSnapshot(
        attendedDays: (m['attendedDays'] as num).toDouble(),
        markedDays: (m['markedDays'] as num).toInt(),
        percentage: (m['percentage'] as num?)?.toDouble(),
        fromKey: m['fromKey'] as String? ?? '',
        toKey: m['toKey'] as String? ?? '',
      );
}

/// A finalised result: immutable and versioned. Parents can read it only
/// while its version is the one in force for a PUBLISHED examination.
class ResultSummary {
  final String examId;
  final String examName;
  final String studentId;
  final int version;
  final String schoolId;
  final String branchId;
  final String academicYearId;
  final String classId;
  final String sectionId;
  final String? classLabel;
  final StudentResult result;
  final Map<String, dynamic> schemeSnapshot;
  final AttendanceSnapshot? attendance;
  final String teacherRemark;
  final String principalRemark;
  final String? calculatedBy;
  final DateTime? calculatedAt;

  const ResultSummary({
    required this.examId,
    required this.examName,
    required this.studentId,
    required this.version,
    required this.schoolId,
    required this.branchId,
    required this.academicYearId,
    required this.classId,
    required this.sectionId,
    this.classLabel,
    required this.result,
    required this.schemeSnapshot,
    this.attendance,
    this.teacherRemark = '',
    this.principalRemark = '',
    this.calculatedBy,
    this.calculatedAt,
  });

  static String idFor(String examId, String studentId, int version) =>
      '${examId}__${studentId}__v$version';

  String get id => idFor(examId, studentId, version);

  factory ResultSummary.fromFirestore(Map<String, dynamic> d) => ResultSummary(
    examId: d['examId'] as String,
    examName: d['examName'] as String? ?? '',
    studentId: d['studentId'] as String,
    version: (d['version'] as num).toInt(),
    schoolId: d[FirestoreFields.schoolId] as String,
    branchId: d[FirestoreFields.branchId] as String,
    academicYearId: d['academicYearId'] as String,
    classId: d['classId'] as String,
    sectionId: d['sectionId'] as String,
    classLabel: d['classLabel'] as String?,
    result: StudentResult.fromMap(
      Map<String, dynamic>.from(d['summary'] as Map),
    ),
    schemeSnapshot: Map<String, dynamic>.from(d['schemeSnapshot'] as Map),
    attendance: d['attendance'] == null
        ? null
        : AttendanceSnapshot.fromMap(
            Map<String, dynamic>.from(d['attendance'] as Map),
          ),
    teacherRemark: d['teacherRemark'] as String? ?? '',
    principalRemark: d['principalRemark'] as String? ?? '',
    calculatedBy: d['calculatedBy'] as String?,
    calculatedAt: (d['calculatedAt'] as Timestamp?)?.toDate(),
  );
}

/// Remarks entered before finalisation and copied into the result.
class ExamRemark {
  final String studentId;
  final String teacherRemark;
  final String principalRemark;

  const ExamRemark({
    required this.studentId,
    this.teacherRemark = '',
    this.principalRemark = '',
  });
}
