import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../domain/calendar_repository.dart';
import '../domain/holiday.dart';
import '../domain/holiday_rules.dart';
import '../domain/working_days.dart';

class FirebaseCalendarRepository implements CalendarRepository {
  final FirebaseFirestore _firestore;

  FirebaseCalendarRepository(this._firestore);

  DocumentReference<Map<String, dynamic>> _branchDoc(
    String schoolId,
    String branchId,
  ) => _firestore
      .collection(FirestoreFields.schoolsCollection)
      .doc(schoolId)
      .collection(FirestoreFields.branchesCollection)
      .doc(branchId);

  DocumentReference<Map<String, dynamic>> _settingsDoc(
    String schoolId,
    String branchId,
    String docId,
  ) => _branchDoc(
    schoolId,
    branchId,
  ).collection(FirestoreFields.settingsCollection).doc(docId);

  CollectionReference<Map<String, dynamic>> _holidaysCollection(
    String schoolId,
    String branchId,
    String academicYearId,
  ) => _branchDoc(schoolId, branchId)
      .collection(FirestoreFields.academicYearsCollection)
      .doc(academicYearId)
      .collection(FirestoreFields.holidaysCollection);

  @override
  Future<WorkingDays> getWorkingDays(String schoolId, String branchId) async {
    try {
      final snapshot = await _settingsDoc(
        schoolId,
        branchId,
        FirestoreFields.workingDaysSettingsDoc,
      ).get();
      if (!snapshot.exists) {
        return WorkingDays.defaults(schoolId: schoolId, branchId: branchId);
      }
      return WorkingDays.fromFirestore(schoolId, branchId, snapshot.data()!);
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> setWorkingDays(
    WorkingDays workingDays, {
    required String updatedBy,
  }) async {
    try {
      await _settingsDoc(
        workingDays.schoolId,
        workingDays.branchId,
        FirestoreFields.workingDaysSettingsDoc,
      ).set(workingDays.toFirestore(updatedBy: updatedBy));
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<bool> hasWorkingDaysConfigured(
    String schoolId,
    String branchId,
  ) async {
    try {
      final snapshot = await _settingsDoc(
        schoolId,
        branchId,
        FirestoreFields.workingDaysSettingsDoc,
      ).get();
      return snapshot.exists;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Stream<List<Holiday>> watchHolidays(
    String schoolId,
    String branchId,
    String academicYearId,
  ) {
    return _holidaysCollection(schoolId, branchId, academicYearId)
        .orderBy('date')
        .snapshots()
        .map(
          (s) => s.docs
              .map(
                (d) => Holiday.fromFirestore(
                  schoolId,
                  branchId,
                  academicYearId,
                  d.id,
                  d.data(),
                ),
              )
              .toList(),
        )
        .handleError((error, stackTrace) {
          throw mapExceptionToFailure(error, stackTrace as StackTrace?);
        });
  }

  @override
  Future<String> createHoliday(
    Holiday holiday, {
    required String createdBy,
  }) async {
    try {
      final normalized = Holiday.normalizeDate(holiday.date);
      final siblings = await _holidaysCollection(
        holiday.schoolId,
        holiday.branchId,
        holiday.academicYearId,
      ).where('date', isEqualTo: Timestamp.fromDate(normalized)).get();
      final rangeError = HolidayRules.checkRange(holiday.date, holiday.endDate);
      if (rangeError != null) throw ValidationFailure(rangeError);
      // Only the same name on the same first day is a duplicate; different
      // holidays may share a day (a festival inside a vacation).
      final dup = HolidayRules.duplicateOf(holiday, [
        for (final d in siblings.docs)
          Holiday.fromFirestore(
            holiday.schoolId,
            holiday.branchId,
            holiday.academicYearId,
            d.id,
            d.data(),
          ),
      ]);
      if (dup != null) {
        throw ValidationFailure(
          'A holiday named "${dup.name}" is already recorded for this date.',
        );
      }

      final ref = _holidaysCollection(
        holiday.schoolId,
        holiday.branchId,
        holiday.academicYearId,
      ).doc();
      await ref.set(holiday.toFirestoreCreate(createdBy: createdBy));
      return ref.id;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> updateHoliday(
    Holiday holiday, {
    required String updatedBy,
  }) async {
    try {
      final normalized = Holiday.normalizeDate(holiday.date);
      final siblings = await _holidaysCollection(
        holiday.schoolId,
        holiday.branchId,
        holiday.academicYearId,
      ).where('date', isEqualTo: Timestamp.fromDate(normalized)).get();
      final rangeError = HolidayRules.checkRange(holiday.date, holiday.endDate);
      if (rangeError != null) throw ValidationFailure(rangeError);
      final dup = HolidayRules.duplicateOf(holiday, [
        for (final d in siblings.docs)
          Holiday.fromFirestore(
            holiday.schoolId,
            holiday.branchId,
            holiday.academicYearId,
            d.id,
            d.data(),
          ),
      ]);
      if (dup != null) {
        throw ValidationFailure(
          'A holiday named "${dup.name}" is already recorded for this date.',
        );
      }

      await _holidaysCollection(
            holiday.schoolId,
            holiday.branchId,
            holiday.academicYearId,
          )
          .doc(holiday.holidayId)
          .update(holiday.toFirestoreUpdate(updatedBy: updatedBy));
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
