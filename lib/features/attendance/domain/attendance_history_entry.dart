import 'package:cloud_firestore/cloud_firestore.dart';

import 'attendance_status.dart';

/// One immutable audit entry in `.../{studentAttendance|staffAttendance}/
/// {id}/history/{revision}`, written in the same transaction as every
/// change: what the status was, what it became, why, by whom and when.
/// Entries are never edited or deleted.
class AttendanceHistoryEntry {
  final int revision;
  final AttendanceStatus? previousStatus;
  final String? previousRemarks;
  final AttendanceStatus newStatus;
  final String? newRemarks;
  final String? reason;
  final String changedBy;
  final DateTime? changedAt;

  const AttendanceHistoryEntry({
    required this.revision,
    this.previousStatus,
    this.previousRemarks,
    required this.newStatus,
    this.newRemarks,
    this.reason,
    required this.changedBy,
    this.changedAt,
  });

  factory AttendanceHistoryEntry.fromFirestore(Map<String, dynamic> data) {
    return AttendanceHistoryEntry(
      revision: (data['revision'] as num?)?.toInt() ?? 1,
      previousStatus: data['previousStatus'] == null
          ? null
          : AttendanceStatus.fromWireValue(data['previousStatus'] as String),
      previousRemarks: data['previousRemarks'] as String?,
      newStatus: AttendanceStatus.fromWireValue(data['newStatus'] as String),
      newRemarks: data['newRemarks'] as String?,
      reason: data['reason'] as String?,
      changedBy: data['changedBy'] as String? ?? '',
      changedAt: (data['changedAt'] as Timestamp?)?.toDate(),
    );
  }
}
