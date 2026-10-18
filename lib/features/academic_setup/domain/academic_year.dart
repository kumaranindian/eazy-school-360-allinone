import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../attendance/domain/attendance_date.dart';
import 'academic_year_status.dart';

/// A `/schools/{schoolId}/branches/{branchId}/academicYears/{id}` document,
/// e.g. "2026-2027". Classes, sections, subjects, and holidays all nest
/// under a specific academic year — see FIRESTORE_ARCHITECTURE.md.
/// Academic-year dates are *civil dates*, not instants (a year starts on
/// 1 April wherever the viewer is). They are stored as a UTC-midnight
/// [Timestamp] plus a `yyyy-MM-dd` key, exactly like holidays and attendance.
/// Older documents hold the local-midnight instant of whoever picked the date;
/// [AcademicDates.read] recovers the intended civil date from either shape.
abstract final class AcademicDates {
  /// The civil date (as UTC midnight) of a stored year boundary.
  ///
  /// * a valid [key] wins;
  /// * an instant that is exactly UTC midnight is already a civil date;
  /// * otherwise it is a legacy local-midnight pick: take its date in the
  ///   zone it was picked in ([localOffset] — the device zone by default,
  ///   which is right for the usual single-zone school).
  static DateTime read(Timestamp stored, String? key, {Duration? localOffset}) {
    if (key != null && AttendanceDate.keyPattern.hasMatch(key)) {
      return AttendanceDate.parse(key);
    }
    final utc = stored.toDate().toUtc();
    final atUtcMidnight =
        utc.hour == 0 &&
        utc.minute == 0 &&
        utc.second == 0 &&
        utc.millisecond == 0;
    final instant = atUtcMidnight
        ? utc
        : (localOffset == null
              ? stored.toDate().toLocal()
              : utc.add(localOffset));
    return DateTime.utc(instant.year, instant.month, instant.day);
  }

  /// UTC midnight of [date]'s own year/month/day (what is written).
  static DateTime civil(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day);

  static String key(DateTime date) => AttendanceDate.key(civil(date));
}

class AcademicYear {
  final String academicYearId;
  final String schoolId;
  final String branchId;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final AcademicYearStatus status;

  /// The school-wide year (`/schools/{s}/academicYears/{id}`) this branch year
  /// was opened from; its id equals this document's id. Null for older
  /// branch-only years. A linked year keeps the school's name and dates.
  final String? schoolYearId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const AcademicYear({
    required this.academicYearId,
    required this.schoolId,
    required this.branchId,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.schoolYearId,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  factory AcademicYear.fromFirestore(
    String schoolId,
    String branchId,
    String id,
    Map<String, dynamic> data,
  ) {
    return AcademicYear(
      academicYearId: id,
      schoolId: schoolId,
      branchId: branchId,
      name: data[FirestoreFields.name] as String? ?? '',
      startDate: AcademicDates.read(
        data['startDate'] as Timestamp,
        data['startDateKey'] as String?,
      ),
      endDate: AcademicDates.read(
        data['endDate'] as Timestamp,
        data['endDateKey'] as String?,
      ),
      status: AcademicYearStatus.fromWireValue(
        data[FirestoreFields.status] as String,
      ),
      schoolYearId: data['schoolYearId'] as String?,
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
      FirestoreFields.name: name,
      ..._dateFields(),
      FirestoreFields.status: status.wireValue,
      'schoolYearId': ?schoolYearId,
      FirestoreFields.createdAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.createdBy: createdBy,
      FirestoreFields.updatedBy: createdBy,
    };
  }

  Map<String, dynamic> toFirestoreUpdate({required String updatedBy}) {
    return {
      FirestoreFields.name: name,
      ..._dateFields(),
      FirestoreFields.status: status.wireValue,
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedBy: updatedBy,
    };
  }

  /// Boundaries as civil dates: UTC-midnight timestamps plus date keys.
  Map<String, dynamic> _dateFields() => {
    'startDate': Timestamp.fromDate(AcademicDates.civil(startDate)),
    'endDate': Timestamp.fromDate(AcademicDates.civil(endDate)),
    'startDateKey': AcademicDates.key(startDate),
    'endDateKey': AcademicDates.key(endDate),
  };
}
