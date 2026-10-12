import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';

/// The `.../branches/{branchId}/settings/academic` singleton document —
/// the small set of branch-wide values future modules (Attendance,
/// Reports, ...) will read instead of re-deriving. Deliberately minimal:
/// each field exists because something in this milestone or a clearly
/// upcoming one needs it, not because it "might be useful."
///
/// `schoolWorkingDays` is *not* duplicated here — that's
/// [WorkingDays]' own document; storing it twice would just be two
/// sources of truth that can disagree.
class AcademicSettings {
  final String schoolId;
  final String branchId;
  final String? currentAcademicYearId;
  final String? attendanceCutoffTime;
  final String timezone;
  final String dateFormat;
  final String currency;
  final DateTime? updatedAt;
  final String? updatedBy;

  const AcademicSettings({
    required this.schoolId,
    required this.branchId,
    this.currentAcademicYearId,
    this.attendanceCutoffTime,
    this.timezone = 'Asia/Kolkata',
    this.dateFormat = 'dd/MM/yyyy',
    this.currency = 'INR',
    this.updatedAt,
    this.updatedBy,
  });

  AcademicSettings copyWith({
    String? currentAcademicYearId,
    String? attendanceCutoffTime,
    String? timezone,
    String? dateFormat,
    String? currency,
  }) {
    return AcademicSettings(
      schoolId: schoolId,
      branchId: branchId,
      currentAcademicYearId:
          currentAcademicYearId ?? this.currentAcademicYearId,
      attendanceCutoffTime: attendanceCutoffTime ?? this.attendanceCutoffTime,
      timezone: timezone ?? this.timezone,
      dateFormat: dateFormat ?? this.dateFormat,
      currency: currency ?? this.currency,
    );
  }

  factory AcademicSettings.fromFirestore(
    String schoolId,
    String branchId,
    Map<String, dynamic> data,
  ) {
    return AcademicSettings(
      schoolId: schoolId,
      branchId: branchId,
      currentAcademicYearId: data['currentAcademicYearId'] as String?,
      attendanceCutoffTime: data['attendanceCutoffTime'] as String?,
      timezone: data['timezone'] as String? ?? 'Asia/Kolkata',
      dateFormat: data['dateFormat'] as String? ?? 'dd/MM/yyyy',
      currency: data['currency'] as String? ?? 'INR',
      updatedAt: (data[FirestoreFields.updatedAt] as Timestamp?)?.toDate(),
      updatedBy: data[FirestoreFields.updatedBy] as String?,
    );
  }

  Map<String, dynamic> toFirestore({required String updatedBy}) {
    return {
      FirestoreFields.schoolId: schoolId,
      FirestoreFields.branchId: branchId,
      'currentAcademicYearId': currentAcademicYearId,
      'attendanceCutoffTime': attendanceCutoffTime,
      'timezone': timezone,
      'dateFormat': dateFormat,
      'currency': currency,
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedBy: updatedBy,
    };
  }
}
