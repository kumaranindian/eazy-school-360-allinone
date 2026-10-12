import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/error_mapper.dart';
import '../domain/academic_settings.dart';
import '../domain/academic_settings_repository.dart';

class FirebaseAcademicSettingsRepository implements AcademicSettingsRepository {
  final FirebaseFirestore _firestore;

  FirebaseAcademicSettingsRepository(this._firestore);

  DocumentReference<Map<String, dynamic>> _settingsDoc(
    String schoolId,
    String branchId,
  ) => _firestore
      .collection(FirestoreFields.schoolsCollection)
      .doc(schoolId)
      .collection(FirestoreFields.branchesCollection)
      .doc(branchId)
      .collection(FirestoreFields.settingsCollection)
      .doc(FirestoreFields.academicSettingsDoc);

  @override
  Future<AcademicSettings> getSettings(String schoolId, String branchId) async {
    try {
      final snapshot = await _settingsDoc(schoolId, branchId).get();
      if (!snapshot.exists) {
        return AcademicSettings(schoolId: schoolId, branchId: branchId);
      }
      return AcademicSettings.fromFirestore(
        schoolId,
        branchId,
        snapshot.data()!,
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> updateSettings(
    AcademicSettings settings, {
    required String updatedBy,
  }) async {
    try {
      await _settingsDoc(
        settings.schoolId,
        settings.branchId,
      ).set(settings.toFirestore(updatedBy: updatedBy));
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
