import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import 'attendance_date.dart';
import 'attendance_status.dart';

/// A `.../branches/{branchId}/staffAttendance/{dateKey}_{staffId}`
/// document: one staff member's attendance for one civil date. Same
/// deterministic-id, revision and history design as [StudentAttendance];
/// no class/section/year because staff attendance is per branch and day.
/// It deliberately carries no shift, overtime or pay fields.
class StaffAttendance {
  final String attendanceId;
  final String schoolId;
  final String branchId;
  final String dateKey;
  final String staffId;
  final AttendanceStatus status;
  final String? remarks;
  final int revision;
  final String? lastChangeReason;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const StaffAttendance({
    required this.attendanceId,
    required this.schoolId,
    required this.branchId,
    required this.dateKey,
    required this.staffId,
    required this.status,
    this.remarks,
    this.revision = 1,
    this.lastChangeReason,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  static String idFor(String dateKey, String staffId) => '${dateKey}_$staffId';

  factory StaffAttendance.fromFirestore(
    String schoolId,
    String branchId,
    String id,
    Map<String, dynamic> data,
  ) {
    return StaffAttendance(
      attendanceId: id,
      schoolId: schoolId,
      branchId: branchId,
      dateKey: data['dateKey'] as String? ?? '',
      staffId: data['staffId'] as String? ?? '',
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
      'dateKey': dateKey,
      'attendanceDate': AttendanceDate.timestampFor(dateKey),
      'staffId': staffId,
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
