import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import 'academic_year.dart';
import 'academic_year_status.dart';

enum SchoolYearStatus {
  active('ACTIVE', 'Active'),
  archived('ARCHIVED', 'Archived');

  final String wireValue;
  final String label;
  const SchoolYearStatus(this.wireValue, this.label);

  static SchoolYearStatus fromWire(Object? v) =>
      v == 'ARCHIVED' ? archived : active;
}

/// A school-wide academic year: `/schools/{schoolId}/academicYears/{id}`.
///
/// Only the definition (name and dates) lives here. Each branch opens it,
/// which creates that branch's own `academicYears/{sameId}` document; classes,
/// students, fees and results stay branch-owned. Immutable except for
/// archiving (firestore.rules).
class SchoolAcademicYear {
  final String schoolYearId;
  final String schoolId;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final SchoolYearStatus status;

  const SchoolAcademicYear({
    required this.schoolYearId,
    required this.schoolId,
    required this.name,
    required this.startDate,
    required this.endDate,
    this.status = SchoolYearStatus.active,
  });

  bool get isOpenable => status == SchoolYearStatus.active;

  factory SchoolAcademicYear.fromFirestore(
    String schoolId,
    String id,
    Map<String, dynamic> data,
  ) => SchoolAcademicYear(
    schoolYearId: id,
    schoolId: schoolId,
    name: data[FirestoreFields.name] as String? ?? '',
    startDate: (data['startDate'] as Timestamp).toDate(),
    endDate: (data['endDate'] as Timestamp).toDate(),
    status: SchoolYearStatus.fromWire(data[FirestoreFields.status]),
  );

  Map<String, dynamic> toFirestoreCreate({required String createdBy}) => {
    FirestoreFields.schoolId: schoolId,
    FirestoreFields.name: name,
    'startDate': Timestamp.fromDate(startDate),
    'endDate': Timestamp.fromDate(endDate),
    FirestoreFields.status: SchoolYearStatus.active.wireValue,
    FirestoreFields.createdAt: FieldValue.serverTimestamp(),
    FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
    FirestoreFields.createdBy: createdBy,
    FirestoreFields.updatedBy: createdBy,
  };

  /// The branch's copy of this year (what opening creates). Starts as a DRAFT:
  /// the branch decides when it becomes its active year.
  AcademicYear forBranch(String branchId) => AcademicYear(
    academicYearId: schoolYearId,
    schoolId: schoolId,
    branchId: branchId,
    name: name,
    startDate: startDate,
    endDate: endDate,
    status: AcademicYearStatus.draft,
    schoolYearId: schoolYearId,
  );
}

enum OpenYearOutcome { opened, alreadyOpen, failed }

class OpenYearResult {
  final String branchId;
  final OpenYearOutcome outcome;
  final String? message;
  const OpenYearResult(this.branchId, this.outcome, [this.message]);
}

/// Pure checks shared by the form and the repository.
abstract final class SchoolYearRules {
  /// A user-facing problem with a new year definition, or null.
  static String? validate({
    required String name,
    required DateTime? start,
    required DateTime? end,
    required Iterable<String> existingNames,
  }) {
    final n = name.trim();
    if (n.isEmpty) return 'Enter a name, e.g. 2026-2027.';
    if (n.length > 100) return 'The name is too long (100 characters at most).';
    if (start == null || end == null) {
      return 'Choose both a start and an end date.';
    }
    if (!end.isAfter(start)) return 'End date must be after the start date.';
    final lower = n.toLowerCase();
    if (existingNames.any((e) => e.trim().toLowerCase() == lower)) {
      return 'A school year named "$n" already exists.';
    }
    return null;
  }

  /// The registry years a branch can still open: active, and not yet opened
  /// there (matched by id).
  static List<SchoolAcademicYear> openableIn(
    Iterable<SchoolAcademicYear> registry,
    Iterable<String> openedYearIds,
  ) {
    final opened = openedYearIds.toSet();
    return [
      for (final y in registry)
        if (y.isOpenable && !opened.contains(y.schoolYearId)) y,
    ];
  }
}
