import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import 'weekday.dart';

/// The `.../branches/{branchId}/settings/workingDays` singleton document.
/// One document per branch (not per academic year — a branch's weekly
/// pattern rarely changes year to year, and the brief doesn't ask for
/// year-scoping here), holding a working/holiday flag per [Weekday] so
/// every day is represented explicitly — never an assumed Mon-Fri default.
class WorkingDays {
  final String schoolId;
  final String branchId;
  final Map<Weekday, bool> isWorkingDay;
  final DateTime? updatedAt;
  final String? updatedBy;

  const WorkingDays({
    required this.schoolId,
    required this.branchId,
    required this.isWorkingDay,
    this.updatedAt,
    this.updatedBy,
  });

  static Map<Weekday, bool> defaultPattern() => {
    for (final day in Weekday.values)
      day: day != Weekday.saturday && day != Weekday.sunday,
  };

  factory WorkingDays.defaults({
    required String schoolId,
    required String branchId,
  }) {
    return WorkingDays(
      schoolId: schoolId,
      branchId: branchId,
      isWorkingDay: defaultPattern(),
    );
  }

  WorkingDays copyWith(Weekday day, bool isWorking) {
    return WorkingDays(
      schoolId: schoolId,
      branchId: branchId,
      isWorkingDay: {...isWorkingDay, day: isWorking},
      updatedAt: updatedAt,
      updatedBy: updatedBy,
    );
  }

  factory WorkingDays.fromFirestore(
    String schoolId,
    String branchId,
    Map<String, dynamic> data,
  ) {
    final raw = (data['isWorkingDay'] as Map<String, dynamic>?) ?? const {};
    return WorkingDays(
      schoolId: schoolId,
      branchId: branchId,
      isWorkingDay: {
        for (final day in Weekday.values)
          day: raw[day.wireValue] as bool? ?? defaultPattern()[day]!,
      },
      updatedAt: (data[FirestoreFields.updatedAt] as Timestamp?)?.toDate(),
      updatedBy: data[FirestoreFields.updatedBy] as String?,
    );
  }

  Map<String, dynamic> toFirestore({required String updatedBy}) {
    return {
      FirestoreFields.schoolId: schoolId,
      FirestoreFields.branchId: branchId,
      'isWorkingDay': {
        for (final entry in isWorkingDay.entries)
          entry.key.wireValue: entry.value,
      },
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedBy: updatedBy,
    };
  }
}
