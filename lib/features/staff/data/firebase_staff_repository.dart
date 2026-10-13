import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../core/constants/activation_status.dart';
import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../../students/domain/paged_result.dart';
import '../domain/employment_type.dart';
import '../domain/staff.dart';
import '../domain/staff_document.dart';
import '../domain/staff_repository.dart';
import '../domain/staff_search_field.dart';
import '../domain/staff_status.dart';
import '../domain/teacher_assignment.dart';
import '../domain/teacher_assignment_status.dart';

/// `/schools/{s}/branches/{b}/staff/{staffId}`, plus:
/// - `.../staffCodes/{codeLower}` — one reservation per employee code, so
///   uniqueness is enforced atomically by `firestore.rules` and not by a
///   racy "query then write";
/// - `.../staff/{staffId}/documents/{docId}` — document metadata.
///
/// Referential checks (department/designation exist and are active, the
/// linked user belongs to this school) are made here for good error
/// messages *and* re-enforced in `firestore.rules` so a hand-crafted client
/// can't skip them.
class FirebaseStaffRepository implements StaffRepository {
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  FirebaseStaffRepository(this._firestore, this._storage);

  DocumentReference<Map<String, dynamic>> _branchDoc(
    String schoolId,
    String branchId,
  ) => _firestore
      .collection(FirestoreFields.schoolsCollection)
      .doc(schoolId)
      .collection(FirestoreFields.branchesCollection)
      .doc(branchId);

  CollectionReference<Map<String, dynamic>> _staffCollection(
    String schoolId,
    String branchId,
  ) => _branchDoc(
    schoolId,
    branchId,
  ).collection(FirestoreFields.staffCollection);

  DocumentReference<Map<String, dynamic>> _staffDoc(
    String schoolId,
    String branchId,
    String staffId,
  ) => _staffCollection(schoolId, branchId).doc(staffId);

  DocumentReference<Map<String, dynamic>> _codeDoc(
    String schoolId,
    String branchId,
    String codeLower,
  ) => _branchDoc(
    schoolId,
    branchId,
  ).collection(FirestoreFields.staffCodesCollection).doc(codeLower);

  CollectionReference<Map<String, dynamic>> _documentsCollection(
    String schoolId,
    String branchId,
    String staffId,
  ) => _staffDoc(
    schoolId,
    branchId,
    staffId,
  ).collection(FirestoreFields.staffDocumentsCollection);

  CollectionReference<Map<String, dynamic>> _assignments(
    String schoolId,
    String branchId,
  ) => _branchDoc(
    schoolId,
    branchId,
  ).collection(FirestoreFields.teacherAssignmentsCollection);

  CollectionReference<Map<String, dynamic>> _slots(
    String schoolId,
    String branchId,
  ) => _branchDoc(
    schoolId,
    branchId,
  ).collection(FirestoreFields.assignmentSlotsCollection);

  DocumentSnapshot<Map<String, dynamic>>? _cursorOf(Object? cursor) =>
      cursor as DocumentSnapshot<Map<String, dynamic>>?;

  PagedResult<Staff> _toPage(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int pageSize,
    String schoolId,
    String branchId,
  ) {
    final hasMore = docs.length > pageSize;
    final pageDocs = hasMore ? docs.sublist(0, pageSize) : docs;
    return PagedResult(
      items: pageDocs
          .map((d) => Staff.fromFirestore(schoolId, branchId, d.id, d.data()))
          .toList(),
      nextCursor: hasMore ? pageDocs.last : null,
    );
  }

  // ---- Reads --------------------------------------------------------------

  @override
  Future<PagedResult<Staff>> fetchStaff({
    required String schoolId,
    required String branchId,
    StaffStatus? status,
    String? departmentId,
    String? designationId,
    EmploymentType? employmentType,
    bool? isTeacher,
    int pageSize = 25,
    Object? cursor,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _staffCollection(schoolId, branchId);
      if (status != null) {
        query = query.where(
          FirestoreFields.status,
          isEqualTo: status.wireValue,
        );
      }
      if (departmentId != null) {
        query = query.where('departmentId', isEqualTo: departmentId);
      }
      if (designationId != null) {
        query = query.where('designationId', isEqualTo: designationId);
      }
      if (employmentType != null) {
        query = query.where(
          'employmentType',
          isEqualTo: employmentType.wireValue,
        );
      }
      if (isTeacher != null) {
        query = query.where('isTeacher', isEqualTo: isTeacher);
      }
      query = query.orderBy('displayNameLower').limit(pageSize + 1);
      final startAfter = _cursorOf(cursor);
      if (startAfter != null) query = query.startAfterDocument(startAfter);

      final snapshot = await query.get();
      return _toPage(snapshot.docs, pageSize, schoolId, branchId);
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<int> countStaff({
    required String schoolId,
    required String branchId,
    StaffStatus? status,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _staffCollection(schoolId, branchId);
      if (status != null) {
        query = query.where(
          FirestoreFields.status,
          isEqualTo: status.wireValue,
        );
      }
      final snapshot = await query.count().get();
      return snapshot.count ?? 0;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<PagedResult<Staff>> searchStaff({
    required String schoolId,
    required String branchId,
    required StaffSearchField field,
    required String query,
    bool? isTeacher,
    int pageSize = 25,
    Object? cursor,
  }) async {
    try {
      assert(
        isTeacher == null || field == StaffSearchField.name,
        'isTeacher is only indexed together with the name search',
      );
      final term = field.normalize(query);
      Query<Map<String, dynamic>> q = _staffCollection(schoolId, branchId);
      if (isTeacher != null) q = q.where('isTeacher', isEqualTo: isTeacher);
      q = q.orderBy(field.firestoreField);
      final startAfter = _cursorOf(cursor);
      q = startAfter == null
          ? q.startAt([term])
          : q.startAfterDocument(startAfter);
      q = q.endAt(['$term']).limit(pageSize + 1);

      final snapshot = await q.get();
      return _toPage(snapshot.docs, pageSize, schoolId, branchId);
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<Staff?> getStaff(
    String schoolId,
    String branchId,
    String staffId,
  ) async {
    try {
      final snapshot = await _staffDoc(schoolId, branchId, staffId).get();
      if (!snapshot.exists) return null;
      return Staff.fromFirestore(schoolId, branchId, staffId, snapshot.data()!);
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<List<Staff>> getStaffByIds(
    String schoolId,
    String branchId,
    List<String> staffIds,
  ) async {
    try {
      final found = <String, Staff>{};
      // whereIn accepts at most 30 values per query.
      for (var i = 0; i < staffIds.length; i += 30) {
        final chunk = staffIds.sublist(
          i,
          i + 30 > staffIds.length ? staffIds.length : i + 30,
        );
        final snapshot = await _staffCollection(
          schoolId,
          branchId,
        ).where(FieldPath.documentId, whereIn: chunk).get();
        for (final doc in snapshot.docs) {
          found[doc.id] = Staff.fromFirestore(
            schoolId,
            branchId,
            doc.id,
            doc.data(),
          );
        }
      }
      return [
        for (final id in staffIds)
          if (found[id] != null) found[id]!,
      ];
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Stream<Staff?> watchStaff(String schoolId, String branchId, String staffId) {
    return _staffDoc(schoolId, branchId, staffId)
        .snapshots()
        .map((snapshot) {
          if (!snapshot.exists) return null;
          return Staff.fromFirestore(
            schoolId,
            branchId,
            staffId,
            snapshot.data()!,
          );
        })
        .handleError((error, stackTrace) {
          throw mapExceptionToFailure(error, stackTrace as StackTrace?);
        });
  }

  @override
  Future<Staff?> findStaffByUserId(
    String schoolId,
    String branchId,
    String userId,
  ) async {
    try {
      final snapshot = await _staffCollection(
        schoolId,
        branchId,
      ).where('userId', isEqualTo: userId).limit(1).get();
      if (snapshot.docs.isEmpty) return null;
      final doc = snapshot.docs.first;
      return Staff.fromFirestore(schoolId, branchId, doc.id, doc.data());
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<bool> isEmployeeCodeAvailable(
    String schoolId,
    String branchId,
    String employeeCode, {
    String? excludingStaffId,
  }) async {
    try {
      final reservation = await _codeDoc(
        schoolId,
        branchId,
        Staff.normalizeEmployeeCode(employeeCode),
      ).get();
      if (!reservation.exists) return true;
      return excludingStaffId != null &&
          reservation.data()?['staffId'] == excludingStaffId;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  // ---- Validation helpers ---------------------------------------------------

  void _assertValidCode(String code) {
    if (!Staff.employeeCodePattern.hasMatch(code.trim())) {
      throw const ValidationFailure(
        'Employee code must be 2-20 letters, digits, "-" or "_".',
      );
    }
  }

  Future<void> _assertActiveReference({
    required String schoolId,
    required String branchId,
    required String collection,
    required String id,
    required String label,
  }) async {
    final snapshot = await _branchDoc(
      schoolId,
      branchId,
    ).collection(collection).doc(id).get();
    if (!snapshot.exists ||
        snapshot.data()?[FirestoreFields.status] !=
            ActivationStatus.active.wireValue) {
      throw ValidationFailure('Select an active $label.');
    }
  }

  Map<String, dynamic> _codeReservation(
    Staff staff,
    String staffId,
    String actorId,
  ) => {
    FirestoreFields.schoolId: staff.schoolId,
    FirestoreFields.branchId: staff.branchId,
    'staffId': staffId,
    'employeeCode': staff.employeeCode.trim(),
    FirestoreFields.createdAt: FieldValue.serverTimestamp(),
    FirestoreFields.createdBy: actorId,
  };

  // ---- Writes ---------------------------------------------------------------

  @override
  Future<String> createStaff({
    required Staff staff,
    required String createdBy,
  }) async {
    try {
      _assertValidCode(staff.employeeCode);
      if (!await isEmployeeCodeAvailable(
        staff.schoolId,
        staff.branchId,
        staff.employeeCode,
      )) {
        throw const ValidationFailure('This employee code is already in use.');
      }
      await _assertActiveReference(
        schoolId: staff.schoolId,
        branchId: staff.branchId,
        collection: FirestoreFields.departmentsCollection,
        id: staff.departmentId,
        label: 'department',
      );
      await _assertActiveReference(
        schoolId: staff.schoolId,
        branchId: staff.branchId,
        collection: FirestoreFields.designationsCollection,
        id: staff.designationId,
        label: 'designation',
      );

      final ref = _staffCollection(staff.schoolId, staff.branchId).doc();
      final codeRef = _codeDoc(
        staff.schoolId,
        staff.branchId,
        Staff.normalizeEmployeeCode(staff.employeeCode),
      );
      final batch = _firestore.batch()
        ..set(ref, staff.toFirestoreCreate(createdBy: createdBy))
        ..set(codeRef, _codeReservation(staff, ref.id, createdBy));
      await batch.commit();
      return ref.id;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> updateStaff({
    required Staff staff,
    required String updatedBy,
  }) async {
    try {
      final ref = _staffDoc(staff.schoolId, staff.branchId, staff.staffId);
      final currentSnapshot = await ref.get();
      if (!currentSnapshot.exists) {
        throw const NotFoundFailure('This staff member could not be found.');
      }
      final current = Staff.fromFirestore(
        staff.schoolId,
        staff.branchId,
        staff.staffId,
        currentSnapshot.data()!,
      );

      final batch = _firestore.batch();

      final oldCode = Staff.normalizeEmployeeCode(current.employeeCode);
      final newCode = Staff.normalizeEmployeeCode(staff.employeeCode);
      if (newCode != oldCode) {
        _assertValidCode(staff.employeeCode);
        if (!await isEmployeeCodeAvailable(
          staff.schoolId,
          staff.branchId,
          staff.employeeCode,
          excludingStaffId: staff.staffId,
        )) {
          throw const ValidationFailure(
            'This employee code is already in use.',
          );
        }
        batch
          ..delete(_codeDoc(staff.schoolId, staff.branchId, oldCode))
          ..set(
            _codeDoc(staff.schoolId, staff.branchId, newCode),
            _codeReservation(staff, staff.staffId, updatedBy),
          );
      }

      if (staff.departmentId != current.departmentId) {
        await _assertActiveReference(
          schoolId: staff.schoolId,
          branchId: staff.branchId,
          collection: FirestoreFields.departmentsCollection,
          id: staff.departmentId,
          label: 'department',
        );
      }
      if (staff.designationId != current.designationId) {
        await _assertActiveReference(
          schoolId: staff.schoolId,
          branchId: staff.branchId,
          collection: FirestoreFields.designationsCollection,
          id: staff.designationId,
          label: 'designation',
        );
      }

      if (current.isTeacher && !staff.isTeacher) {
        final active = await _activeAssignmentDocs(
          staff.schoolId,
          staff.branchId,
          staff.staffId,
          limit: 1,
        );
        if (active.isNotEmpty) {
          throw const ValidationFailure(
            'End this teacher\'s active assignments before removing teaching responsibility.',
          );
        }
      }

      batch.update(ref, staff.toFirestoreProfileUpdate(updatedBy: updatedBy));
      await batch.commit();
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _activeAssignmentDocs(
    String schoolId,
    String branchId,
    String staffId, {
    int limit = 500,
  }) async {
    final snapshot = await _assignments(schoolId, branchId)
        .where('teacherStaffId', isEqualTo: staffId)
        .where(
          FirestoreFields.status,
          isEqualTo: TeacherAssignmentStatus.active.wireValue,
        )
        .limit(limit)
        .get();
    return snapshot.docs;
  }

  @override
  Future<void> changeStaffStatus({
    required String schoolId,
    required String branchId,
    required String staffId,
    required StaffStatus status,
    required DateTime effectiveDate,
    String? reason,
    String? notes,
    required String updatedBy,
  }) async {
    try {
      final ref = _staffDoc(schoolId, branchId, staffId);
      final snapshot = await ref.get();
      if (!snapshot.exists) {
        throw const NotFoundFailure('This staff member could not be found.');
      }
      final current = Staff.fromFirestore(
        schoolId,
        branchId,
        staffId,
        snapshot.data()!,
      );

      final transitionError = current.status.transitionError(status);
      if (transitionError != null) throw ValidationFailure(transitionError);

      // Leaving the active workforce ends the member's active teaching
      // assignments (history kept) and frees their slots, so the sections
      // can be given to someone else. Chunked well under the 500-write
      // batch limit; the status change rides in the final chunk.
      final toEnd = status.endsActiveAssignments && current.isTeacher
          ? await _activeAssignmentDocs(schoolId, branchId, staffId)
          : <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      const chunkSize = 200;
      final statusChange = Staff.firestoreStatusChange(
        status: status,
        effectiveDate: effectiveDate,
        reason: reason,
        notes: notes,
        updatedBy: updatedBy,
      );

      for (var start = 0; start < toEnd.length; start += chunkSize) {
        final end = start + chunkSize > toEnd.length
            ? toEnd.length
            : start + chunkSize;
        final isLast = end >= toEnd.length;
        final batch = _firestore.batch();
        for (final doc in toEnd.sublist(start, end)) {
          final assignment = TeacherAssignment.fromFirestore(
            schoolId,
            branchId,
            doc.id,
            doc.data(),
          );
          // An effective date earlier than the assignment's own start
          // (a back-dated resignation) must not produce end < start.
          final endDate = effectiveDate.isBefore(assignment.startDate)
              ? assignment.startDate
              : effectiveDate;
          batch
            ..update(
              doc.reference,
              TeacherAssignment.firestoreEnd(
                endDate: endDate,
                updatedBy: updatedBy,
              ),
            )
            ..delete(_slots(schoolId, branchId).doc(assignment.slotKey));
        }
        if (isLast) batch.update(ref, statusChange);
        await batch.commit();
      }
      if (toEnd.isEmpty) await ref.update(statusChange);
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> linkUserAccount({
    required String schoolId,
    required String branchId,
    required String staffId,
    required String? userId,
    required String updatedBy,
  }) async {
    try {
      if (userId != null) {
        final user = await _firestore
            .collection(FirestoreFields.usersCollection)
            .doc(userId)
            .get();
        if (!user.exists ||
            user.data()?[FirestoreFields.schoolId] != schoolId) {
          throw const ValidationFailure(
            'No user account with that ID exists in this school.',
          );
        }
        final existing = await _staffCollection(
          schoolId,
          branchId,
        ).where('userId', isEqualTo: userId).limit(2).get();
        if (existing.docs.any((d) => d.id != staffId)) {
          throw const ValidationFailure(
            'That user account is already linked to another staff member.',
          );
        }
      }
      await _staffDoc(schoolId, branchId, staffId).update({
        'userId': userId,
        FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
        FirestoreFields.updatedBy: updatedBy,
      });
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  // ---- Photo ----------------------------------------------------------------

  // One fixed object name per staff member (no extension) so replacing the
  // photo overwrites it instead of orphaning the previous file; the real
  // type is carried in the object's content type.
  Reference _photoRef(String schoolId, String branchId, String staffId) =>
      _storage.ref('schools/$schoolId/branches/$branchId/staff/$staffId/photo');

  @override
  Future<String> uploadStaffPhoto({
    required String schoolId,
    required String branchId,
    required String staffId,
    required List<int> fileBytes,
    required String fileExtension,
    required String updatedBy,
  }) async {
    try {
      final ref = _photoRef(schoolId, branchId, staffId);
      await ref.putData(
        Uint8List.fromList(fileBytes),
        SettableMetadata(
          contentType: StaffDocument.contentTypeForExtension(fileExtension),
        ),
      );
      final url = await ref.getDownloadURL();
      await _staffDoc(schoolId, branchId, staffId).update({
        'photoUrl': url,
        FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
        FirestoreFields.updatedBy: updatedBy,
      });
      return url;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> removeStaffPhoto({
    required String schoolId,
    required String branchId,
    required String staffId,
    required String updatedBy,
  }) async {
    try {
      try {
        await _photoRef(schoolId, branchId, staffId).delete();
      } on FirebaseException catch (e) {
        if (e.code != 'object-not-found') rethrow;
      }
      await _staffDoc(schoolId, branchId, staffId).update({
        'photoUrl': null,
        FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
        FirestoreFields.updatedBy: updatedBy,
      });
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  // ---- Documents ------------------------------------------------------------

  @override
  Stream<List<StaffDocument>> watchDocuments(
    String schoolId,
    String branchId,
    String staffId,
  ) {
    return _documentsCollection(schoolId, branchId, staffId)
        .orderBy(FirestoreFields.createdAt, descending: true)
        .limit(100)
        .snapshots()
        .map(
          (s) => s.docs
              .map(
                (d) => StaffDocument.fromFirestore(
                  schoolId,
                  branchId,
                  staffId,
                  d.id,
                  d.data(),
                ),
              )
              .where((d) => !d.isRemoved)
              .toList(),
        )
        .handleError((error, stackTrace) {
          throw mapExceptionToFailure(error, stackTrace as StackTrace?);
        });
  }

  @override
  Future<void> uploadDocument({
    required String schoolId,
    required String branchId,
    required String staffId,
    required StaffDocumentType type,
    required String title,
    required String fileName,
    required List<int> fileBytes,
    required String createdBy,
  }) async {
    Reference? uploaded;
    try {
      final validationError = StaffDocument.validateFile(
        fileName: fileName,
        sizeBytes: fileBytes.length,
      );
      if (validationError != null) throw ValidationFailure(validationError);

      final docRef = _documentsCollection(schoolId, branchId, staffId).doc();
      final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final storagePath =
          'schools/$schoolId/branches/$branchId/staff/$staffId/documents/${docRef.id}/$safeName';
      final contentType = StaffDocument.contentTypeForExtension(
        fileName.split('.').last,
      );

      uploaded = _storage.ref(storagePath);
      await uploaded.putData(
        Uint8List.fromList(fileBytes),
        SettableMetadata(contentType: contentType),
      );

      final document = StaffDocument(
        documentId: docRef.id,
        schoolId: schoolId,
        branchId: branchId,
        staffId: staffId,
        type: type,
        title: title,
        fileName: safeName,
        contentType: contentType,
        sizeBytes: fileBytes.length,
        storagePath: storagePath,
      );
      await docRef.set(document.toFirestoreCreate(createdBy: createdBy));
    } catch (error, stackTrace) {
      // Don't leave an unreferenced file behind if the metadata write failed.
      try {
        await uploaded?.delete();
      } catch (_) {}
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> removeDocument({
    required String schoolId,
    required String branchId,
    required String staffId,
    required String documentId,
    required String updatedBy,
  }) async {
    try {
      await _documentsCollection(
        schoolId,
        branchId,
        staffId,
      ).doc(documentId).update({
        FirestoreFields.status: 'REMOVED',
        FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
        FirestoreFields.updatedBy: updatedBy,
      });
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<String> getDocumentDownloadUrl(String storagePath) async {
    try {
      return await _storage.ref(storagePath).getDownloadURL();
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
