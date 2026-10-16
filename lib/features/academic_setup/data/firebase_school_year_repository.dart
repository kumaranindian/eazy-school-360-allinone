import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../domain/school_academic_year.dart';
import '../domain/school_year_repository.dart';

class FirebaseSchoolYearRepository implements SchoolYearRepository {
  final FirebaseFirestore _firestore;
  FirebaseSchoolYearRepository(this._firestore);

  CollectionReference<Map<String, dynamic>> _registry(String schoolId) =>
      _firestore
          .collection(FirestoreFields.schoolsCollection)
          .doc(schoolId)
          .collection(FirestoreFields.academicYearsCollection);

  DocumentReference<Map<String, dynamic>> _branchYear(
    String schoolId,
    String branchId,
    String yearId,
  ) => _firestore
      .collection(FirestoreFields.schoolsCollection)
      .doc(schoolId)
      .collection(FirestoreFields.branchesCollection)
      .doc(branchId)
      .collection(FirestoreFields.academicYearsCollection)
      .doc(yearId);

  @override
  Stream<List<SchoolAcademicYear>> watchSchoolYears(String schoolId) {
    return _registry(schoolId)
        .orderBy('startDate', descending: true)
        .snapshots()
        .map(
          (s) => [
            for (final d in s.docs)
              SchoolAcademicYear.fromFirestore(schoolId, d.id, d.data()),
          ],
        )
        .handleError((Object error, StackTrace stackTrace) {
          throw mapExceptionToFailure(error, stackTrace);
        });
  }

  @override
  Future<String> createSchoolYear(
    SchoolAcademicYear year, {
    required String createdBy,
  }) async {
    try {
      final existing = await _registry(year.schoolId).get();
      final problem = SchoolYearRules.validate(
        name: year.name,
        start: year.startDate,
        end: year.endDate,
        existingNames: [
          for (final d in existing.docs)
            d.data()[FirestoreFields.name] as String? ?? '',
        ],
      );
      if (problem != null) throw ValidationFailure(problem);
      final ref = _registry(year.schoolId).doc();
      await ref.set(year.toFirestoreCreate(createdBy: createdBy));
      return ref.id;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> setArchived(
    String schoolId,
    String schoolYearId, {
    required bool archived,
    required String updatedBy,
  }) async {
    try {
      await _registry(schoolId).doc(schoolYearId).update({
        FirestoreFields.status:
            (archived ? SchoolYearStatus.archived : SchoolYearStatus.active)
                .wireValue,
        FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
        FirestoreFields.updatedBy: updatedBy,
      });
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<List<OpenYearResult>> openInBranches(
    SchoolAcademicYear year,
    List<String> branchIds, {
    required String createdBy,
  }) async {
    final results = <OpenYearResult>[];
    for (final branchId in branchIds) {
      try {
        final ref = _branchYear(year.schoolId, branchId, year.schoolYearId);
        if ((await ref.get()).exists) {
          results.add(OpenYearResult(branchId, OpenYearOutcome.alreadyOpen));
          continue;
        }
        await ref.set(
          year.forBranch(branchId).toFirestoreCreate(createdBy: createdBy),
        );
        results.add(OpenYearResult(branchId, OpenYearOutcome.opened));
      } catch (error, stackTrace) {
        results.add(
          OpenYearResult(
            branchId,
            OpenYearOutcome.failed,
            mapExceptionToFailure(error, stackTrace).message,
          ),
        );
      }
    }
    return results;
  }

  @override
  Future<Set<String>> openedIn(
    String schoolId,
    String schoolYearId,
    List<String> branchIds,
  ) async {
    final opened = <String>{};
    try {
      for (final b in branchIds) {
        if ((await _branchYear(schoolId, b, schoolYearId).get()).exists) {
          opened.add(b);
        }
      }
      return opened;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
