import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../domain/department.dart';
import '../domain/designation.dart';
import '../domain/staff_setup_repository.dart';

/// `/schools/{s}/branches/{b}/departments/{code}` and `.../designations/
/// {code}`. The document id is the lower-cased code, so duplicate codes are
/// impossible rather than merely checked-for: a second create on the same
/// id is refused by Firestore itself (and by `firestore.rules`).
class FirebaseStaffSetupRepository implements StaffSetupRepository {
  final FirebaseFirestore _firestore;

  FirebaseStaffSetupRepository(this._firestore);

  CollectionReference<Map<String, dynamic>> _collection(
    String schoolId,
    String branchId,
    String name,
  ) => _firestore
      .collection(FirestoreFields.schoolsCollection)
      .doc(schoolId)
      .collection(FirestoreFields.branchesCollection)
      .doc(branchId)
      .collection(name);

  Stream<List<T>> _watch<T>(
    String schoolId,
    String branchId,
    String collection,
    T Function(String id, Map<String, dynamic> data) fromDoc,
  ) {
    return _collection(schoolId, branchId, collection)
        .orderBy(FirestoreFields.name)
        .snapshots()
        .map((s) => s.docs.map((d) => fromDoc(d.id, d.data())).toList())
        .handleError((error, stackTrace) {
          throw mapExceptionToFailure(error, stackTrace as StackTrace?);
        });
  }

  /// Creates `{collection}/{idForCode(code)}`, refusing an invalid or
  /// already-used code. Returns the new document id.
  Future<String> _create({
    required String schoolId,
    required String branchId,
    required String collection,
    required String code,
    required String label,
    required Map<String, dynamic> data,
  }) async {
    try {
      if (!Department.codePattern.hasMatch(code.trim())) {
        throw ValidationFailure(
          'A $label code must be 2-20 letters, digits, "-" or "_".',
        );
      }
      final ref = _collection(
        schoolId,
        branchId,
        collection,
      ).doc(Department.idForCode(code));
      if ((await ref.get()).exists) {
        throw ValidationFailure('A $label with this code already exists.');
      }
      await ref.set(data);
      return ref.id;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Stream<List<Department>> watchDepartments(String schoolId, String branchId) =>
      _watch(
        schoolId,
        branchId,
        FirestoreFields.departmentsCollection,
        (id, data) => Department.fromFirestore(schoolId, branchId, id, data),
      );

  @override
  Future<String> createDepartment(
    Department department, {
    required String createdBy,
  }) => _create(
    schoolId: department.schoolId,
    branchId: department.branchId,
    collection: FirestoreFields.departmentsCollection,
    code: department.code,
    label: 'department',
    data: department.toFirestoreCreate(createdBy: createdBy),
  );

  @override
  Future<void> updateDepartment(
    Department department, {
    required String updatedBy,
  }) async {
    try {
      await _collection(
            department.schoolId,
            department.branchId,
            FirestoreFields.departmentsCollection,
          )
          .doc(department.departmentId)
          .update(department.toFirestoreUpdate(updatedBy: updatedBy));
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Stream<List<Designation>> watchDesignations(
    String schoolId,
    String branchId,
  ) => _watch(
    schoolId,
    branchId,
    FirestoreFields.designationsCollection,
    (id, data) => Designation.fromFirestore(schoolId, branchId, id, data),
  );

  @override
  Future<String> createDesignation(
    Designation designation, {
    required String createdBy,
  }) => _create(
    schoolId: designation.schoolId,
    branchId: designation.branchId,
    collection: FirestoreFields.designationsCollection,
    code: designation.code,
    label: 'designation',
    data: designation.toFirestoreCreate(createdBy: createdBy),
  );

  @override
  Future<void> updateDesignation(
    Designation designation, {
    required String updatedBy,
  }) async {
    try {
      await _collection(
            designation.schoolId,
            designation.branchId,
            FirestoreFields.designationsCollection,
          )
          .doc(designation.designationId)
          .update(designation.toFirestoreUpdate(updatedBy: updatedBy));
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
