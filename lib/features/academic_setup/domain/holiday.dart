import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/activation_status.dart';
import '../../../core/constants/firestore_fields.dart';
import 'holiday_type.dart';

/// A `.../academicYears/{yearId}/holidays/{id}` document. [date] is stored
/// at midnight UTC so "same calendar day" comparisons (duplicate-date
/// prevention) don't depend on time-of-day or timezone drift.
class Holiday {
  final String holidayId;
  final String schoolId;
  final String branchId;
  final String academicYearId;

  /// First day (and the only day of a single-day holiday).
  final DateTime date;

  /// Last day of a multi-day holiday or vacation (UTC midnight, on or after
  /// [date]). Null for a single-day holiday — which is how every holiday
  /// recorded before ranges existed reads.
  final DateTime? endDate;
  final String name;
  final HolidayType type;
  final String? description;
  final ActivationStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const Holiday({
    required this.holidayId,
    required this.schoolId,
    required this.branchId,
    required this.academicYearId,
    required this.date,
    this.endDate,
    required this.name,
    required this.type,
    this.description,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  /// Midnight-UTC normalization used both when writing [date] and when
  /// checking for an existing holiday on the same calendar day.
  static DateTime normalizeDate(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day);

  /// The last day covered (the start for a single-day holiday).
  DateTime get lastDate => endDate ?? date;

  bool get isRange => endDate != null && !_sameCivilDay(endDate!, date);

  /// Number of days covered (inclusive).
  int get dayCount => _civil(lastDate).difference(_civil(date)).inDays + 1;

  /// Whether the civil date [day] (its own year/month/day fields) is covered.
  /// Stored dates are UTC midnight of the civil date, so the comparison is on
  /// year/month/day numbers — never on instants — and cannot shift a day.
  bool covers(DateTime day) {
    final d = DateTime.utc(day.year, day.month, day.day);
    return !d.isBefore(_civil(date)) && !d.isAfter(_civil(lastDate));
  }

  bool overlaps(Holiday other) =>
      !_civil(other.lastDate).isBefore(_civil(date)) &&
      !_civil(lastDate).isBefore(_civil(other.date));

  static DateTime _civil(DateTime d) {
    final u = d.toUtc();
    return DateTime.utc(u.year, u.month, u.day);
  }

  static bool _sameCivilDay(DateTime a, DateTime b) => _civil(a) == _civil(b);

  factory Holiday.fromFirestore(
    String schoolId,
    String branchId,
    String academicYearId,
    String id,
    Map<String, dynamic> data,
  ) {
    return Holiday(
      holidayId: id,
      schoolId: schoolId,
      branchId: branchId,
      academicYearId: academicYearId,
      date: (data['date'] as Timestamp).toDate(),
      endDate: (data['endDate'] as Timestamp?)?.toDate(),
      name: data[FirestoreFields.name] as String? ?? '',
      type: HolidayType.fromWireValue(data['type'] as String),
      description: data['description'] as String?,
      status: ActivationStatus.fromWireValue(
        data[FirestoreFields.status] as String,
      ),
      createdAt: (data[FirestoreFields.createdAt] as Timestamp?)?.toDate(),
      updatedAt: (data[FirestoreFields.updatedAt] as Timestamp?)?.toDate(),
      createdBy: data[FirestoreFields.createdBy] as String?,
      updatedBy: data[FirestoreFields.updatedBy] as String?,
    );
  }

  /// Stored only for a real range; a single day carries no end date.
  Timestamp? get _endForWrite =>
      isRange ? Timestamp.fromDate(normalizeDate(endDate!)) : null;

  Map<String, dynamic> toFirestoreCreate({required String createdBy}) {
    return {
      FirestoreFields.schoolId: schoolId,
      FirestoreFields.branchId: branchId,
      'academicYearId': academicYearId,
      'date': Timestamp.fromDate(normalizeDate(date)),
      'endDate': _endForWrite,
      FirestoreFields.name: name,
      'type': type.wireValue,
      'description': description,
      FirestoreFields.status: status.wireValue,
      FirestoreFields.createdAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.createdBy: createdBy,
      FirestoreFields.updatedBy: createdBy,
    };
  }

  Map<String, dynamic> toFirestoreUpdate({required String updatedBy}) {
    return {
      'date': Timestamp.fromDate(normalizeDate(date)),
      'endDate': _endForWrite,
      FirestoreFields.name: name,
      'type': type.wireValue,
      'description': description,
      FirestoreFields.status: status.wireValue,
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedBy: updatedBy,
    };
  }
}
