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
  final DateTime date;
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

  Map<String, dynamic> toFirestoreCreate({required String createdBy}) {
    return {
      FirestoreFields.schoolId: schoolId,
      FirestoreFields.branchId: branchId,
      'academicYearId': academicYearId,
      'date': Timestamp.fromDate(normalizeDate(date)),
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
      FirestoreFields.name: name,
      'type': type.wireValue,
      'description': description,
      FirestoreFields.status: status.wireValue,
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedBy: updatedBy,
    };
  }
}
