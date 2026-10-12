import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../core/constants/activation_status.dart';
import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../domain/academic_record_status.dart';
import '../domain/paged_result.dart';
import '../domain/parent_student_link.dart';
import '../domain/relationship_type.dart';
import '../domain/student.dart';
import '../domain/student_academic_record.dart';
import '../domain/student_repository.dart';
import '../domain/student_status.dart';
import 'parent_access_sync.dart';

/// Nesting: `/schools/{s}/branches/{b}/students/{studentId}`, then
/// `.../academicRecords/{id}` (history source of truth) and
/// `.../parentLinks/{parentId}` (this student's guardians) — see
/// FIRESTORE_ARCHITECTURE.md and
/// `docs/milestone-3-student-parent-management.md`.
///
/// Admission-number uniqueness and the section/class/year referential
/// checks are enforced *here*, not in `firestore.rules` — same reasoning
/// as the academic-setup repository: data-quality, not tenant isolation.
class FirebaseStudentRepository implements StudentRepository {
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  FirebaseStudentRepository(this._firestore, this._storage)
    : _parentAccess = ParentAccessSync(_firestore);

  /// Derived per-family index used by the security rules (Milestone 12A).
  final ParentAccessSync _parentAccess;

  Future<void> _refreshFamilies(
    String schoolId,
    String branchId,
    String studentId,
    String updatedBy,
  ) => _parentAccess.refreshForStudentBestEffort(
    schoolId: schoolId,
    branchId: branchId,
    studentId: studentId,
    updatedBy: updatedBy,
  );

  CollectionReference<Map<String, dynamic>> _studentsCollection(
    String schoolId,
    String branchId,
  ) => _firestore
      .collection(FirestoreFields.schoolsCollection)
      .doc(schoolId)
      .collection(FirestoreFields.branchesCollection)
      .doc(branchId)
      .collection(FirestoreFields.studentsCollection);

  DocumentReference<Map<String, dynamic>> _studentDoc(
    String schoolId,
    String branchId,
    String studentId,
  ) => _studentsCollection(schoolId, branchId).doc(studentId);

  CollectionReference<Map<String, dynamic>> _academicRecordsCollection(
    String schoolId,
    String branchId,
    String studentId,
  ) => _studentDoc(
    schoolId,
    branchId,
    studentId,
  ).collection(FirestoreFields.academicRecordsCollection);

  CollectionReference<Map<String, dynamic>> _parentLinksCollection(
    String schoolId,
    String branchId,
    String studentId,
  ) => _studentDoc(
    schoolId,
    branchId,
    studentId,
  ).collection(FirestoreFields.parentLinksCollection);

  DocumentReference<Map<String, dynamic>> _sectionDoc(
    String schoolId,
    String branchId,
    String academicYearId,
    String classId,
    String sectionId,
  ) => _firestore
      .collection(FirestoreFields.schoolsCollection)
      .doc(schoolId)
      .collection(FirestoreFields.branchesCollection)
      .doc(branchId)
      .collection(FirestoreFields.academicYearsCollection)
      .doc(academicYearId)
      .collection(FirestoreFields.classesCollection)
      .doc(classId)
      .collection(FirestoreFields.sectionsCollection)
      .doc(sectionId);

  DocumentSnapshot<Map<String, dynamic>>? _cursorOf(Object? cursor) =>
      cursor as DocumentSnapshot<Map<String, dynamic>>?;

  PagedResult<Student> _toPage(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int pageSize,
    String schoolId,
    String branchId,
  ) {
    final hasMore = docs.length > pageSize;
    final pageDocs = hasMore ? docs.sublist(0, pageSize) : docs;
    return PagedResult(
      items: pageDocs
          .map((d) => Student.fromFirestore(schoolId, branchId, d.id, d.data()))
          .toList(),
      nextCursor: hasMore ? pageDocs.last : null,
    );
  }

  @override
  Future<PagedResult<Student>> fetchStudents({
    required String schoolId,
    required String branchId,
    StudentStatus? status,
    int pageSize = 25,
    Object? cursor,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _studentsCollection(
        schoolId,
        branchId,
      );
      if (status != null) {
        query = query.where(
          FirestoreFields.status,
          isEqualTo: status.wireValue,
        );
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
  Future<PagedResult<Student>> fetchStudentsByPlacement({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    String? sectionId,
    int pageSize = 25,
    Object? cursor,
  }) async {
    try {
      Query<Map<String, dynamic>> query =
          _studentsCollection(schoolId, branchId)
              .where('currentAcademicYearId', isEqualTo: academicYearId)
              .where('currentClassId', isEqualTo: classId);
      if (sectionId != null) {
        query = query.where('currentSectionId', isEqualTo: sectionId);
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
  Future<PagedResult<Student>> searchStudentsByName({
    required String schoolId,
    required String branchId,
    required String query,
    int pageSize = 25,
    Object? cursor,
  }) async {
    try {
      final lower = query.trim().toLowerCase();
      Query<Map<String, dynamic>> q = _studentsCollection(schoolId, branchId)
          .orderBy('displayNameLower')
          .startAt([lower])
          .endAt(['$lower'])
          .limit(pageSize + 1);
      final startAfter = _cursorOf(cursor);
      if (startAfter != null) {
        q = _studentsCollection(schoolId, branchId)
            .orderBy('displayNameLower')
            .startAfterDocument(startAfter)
            .endAt(['$lower'])
            .limit(pageSize + 1);
      }
      final snapshot = await q.get();
      return _toPage(snapshot.docs, pageSize, schoolId, branchId);
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<PagedResult<Student>> searchStudentsByAdmissionNumber({
    required String schoolId,
    required String branchId,
    required String query,
    int pageSize = 25,
    Object? cursor,
  }) async {
    try {
      final trimmed = query.trim();
      Query<Map<String, dynamic>> q = _studentsCollection(schoolId, branchId)
          .orderBy('admissionNumber')
          .startAt([trimmed])
          .endAt(['$trimmed'])
          .limit(pageSize + 1);
      final startAfter = _cursorOf(cursor);
      if (startAfter != null) {
        q = _studentsCollection(schoolId, branchId)
            .orderBy('admissionNumber')
            .startAfterDocument(startAfter)
            .endAt(['$trimmed'])
            .limit(pageSize + 1);
      }
      final snapshot = await q.get();
      return _toPage(snapshot.docs, pageSize, schoolId, branchId);
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<Student?> getStudent(
    String schoolId,
    String branchId,
    String studentId,
  ) async {
    try {
      final snapshot = await _studentDoc(schoolId, branchId, studentId).get();
      if (!snapshot.exists) return null;
      return Student.fromFirestore(
        schoolId,
        branchId,
        studentId,
        snapshot.data()!,
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Stream<Student?> watchStudent(
    String schoolId,
    String branchId,
    String studentId,
  ) {
    return _studentDoc(schoolId, branchId, studentId)
        .snapshots()
        .map((snapshot) {
          if (!snapshot.exists) return null;
          return Student.fromFirestore(
            schoolId,
            branchId,
            studentId,
            snapshot.data()!,
          );
        })
        .handleError((error, stackTrace) {
          throw mapExceptionToFailure(error, stackTrace as StackTrace?);
        });
  }

  @override
  Future<bool> isAdmissionNumberAvailable(
    String schoolId,
    String branchId,
    String admissionNumber, {
    String? excludingStudentId,
  }) async {
    try {
      final matches = await _studentsCollection(
        schoolId,
        branchId,
      ).where('admissionNumber', isEqualTo: admissionNumber.trim()).get();
      return matches.docs.every((d) => d.id == excludingStudentId);
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  Future<void> _assertSectionBelongsToClass(
    String schoolId,
    String branchId,
    String academicYearId,
    String classId,
    String sectionId,
  ) async {
    final snapshot = await _sectionDoc(
      schoolId,
      branchId,
      academicYearId,
      classId,
      sectionId,
    ).get();
    if (!snapshot.exists) {
      throw const ValidationFailure(
        'The selected section does not belong to the selected class and academic year.',
      );
    }
  }

  @override
  Future<String> admitStudent({
    required Student student,
    required String academicYearId,
    required String classId,
    required String sectionId,
    String? rollNumber,
    required String createdBy,
  }) async {
    try {
      final available = await isAdmissionNumberAvailable(
        student.schoolId,
        student.branchId,
        student.admissionNumber,
      );
      if (!available) {
        throw const ValidationFailure(
          'This admission number is already in use.',
        );
      }
      await _assertSectionBelongsToClass(
        student.schoolId,
        student.branchId,
        academicYearId,
        classId,
        sectionId,
      );

      final studentRef = _studentsCollection(
        student.schoolId,
        student.branchId,
      ).doc();
      final studentCode = 'STU-${studentRef.id.substring(0, 8).toUpperCase()}';
      final studentToSave = Student(
        studentId: studentRef.id,
        schoolId: student.schoolId,
        branchId: student.branchId,
        admissionNumber: student.admissionNumber,
        studentCode: studentCode,
        firstName: student.firstName,
        middleName: student.middleName,
        lastName: student.lastName,
        dateOfBirth: student.dateOfBirth,
        gender: student.gender,
        bloodGroup: student.bloodGroup,
        photoUrl: student.photoUrl,
        email: student.email,
        phone: student.phone,
        addressLine1: student.addressLine1,
        addressLine2: student.addressLine2,
        city: student.city,
        state: student.state,
        country: student.country,
        postalCode: student.postalCode,
        admissionDate: student.admissionDate,
        status: StudentStatus.active,
      );

      final recordRef = _academicRecordsCollection(
        student.schoolId,
        student.branchId,
        studentRef.id,
      ).doc();
      final record = StudentAcademicRecord(
        recordId: recordRef.id,
        studentId: studentRef.id,
        schoolId: student.schoolId,
        branchId: student.branchId,
        academicYearId: academicYearId,
        classId: classId,
        sectionId: sectionId,
        rollNumber: rollNumber,
        startDate: student.admissionDate,
        status: AcademicRecordStatus.active,
      );

      final batch = _firestore.batch()
        ..set(studentRef, {
          ...studentToSave.toFirestoreCreate(createdBy: createdBy),
          'currentAcademicYearId': academicYearId,
          'currentClassId': classId,
          'currentSectionId': sectionId,
          'currentRollNumber': rollNumber,
        })
        ..set(recordRef, record.toFirestoreCreate(createdBy: createdBy));
      await batch.commit();

      return studentRef.id;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> updateStudentProfile(
    Student student, {
    required String updatedBy,
  }) async {
    try {
      if (student.admissionNumber.isNotEmpty) {
        final available = await isAdmissionNumberAvailable(
          student.schoolId,
          student.branchId,
          student.admissionNumber,
          excludingStudentId: student.studentId,
        );
        if (!available) {
          throw const ValidationFailure(
            'This admission number is already in use.',
          );
        }
      }
      await _studentDoc(
        student.schoolId,
        student.branchId,
        student.studentId,
      ).update(student.toFirestoreProfileUpdate(updatedBy: updatedBy));
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<String> uploadStudentPhoto({
    required String schoolId,
    required String branchId,
    required String studentId,
    required List<int> fileBytes,
    required String fileExtension,
    required String updatedBy,
  }) async {
    try {
      final ref = _storage.ref(
        'schools/$schoolId/branches/$branchId/students/$studentId/photo.$fileExtension',
      );
      await ref.putData(
        Uint8List.fromList(fileBytes),
        SettableMetadata(contentType: _contentTypeFor(fileExtension)),
      );
      final url = await ref.getDownloadURL();
      await _studentDoc(schoolId, branchId, studentId).update({
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
  Future<void> changeStudentStatus({
    required String schoolId,
    required String branchId,
    required String studentId,
    required StudentStatus status,
    required DateTime effectiveDate,
    String? reason,
    String? notes,
    required String updatedBy,
  }) async {
    try {
      await _studentDoc(schoolId, branchId, studentId).update(
        Student.firestoreStatusChange(
          status: status,
          effectiveDate: effectiveDate,
          reason: reason,
          notes: notes,
          updatedBy: updatedBy,
        ),
      );
      await _refreshFamilies(schoolId, branchId, studentId, updatedBy);
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> transferStudent({
    required String schoolId,
    required String branchId,
    required String studentId,
    required String newAcademicYearId,
    required String newClassId,
    required String newSectionId,
    String? newRollNumber,
    required AcademicRecordStatus closeOldRecordAs,
    required String updatedBy,
  }) async {
    try {
      await _assertSectionBelongsToClass(
        schoolId,
        branchId,
        newAcademicYearId,
        newClassId,
        newSectionId,
      );

      final now = DateTime.now();
      final activeRecords =
          await _academicRecordsCollection(schoolId, branchId, studentId)
              .where(
                FirestoreFields.status,
                isEqualTo: AcademicRecordStatus.active.wireValue,
              )
              .get();

      final batch = _firestore.batch();
      for (final doc in activeRecords.docs) {
        batch.update(
          doc.reference,
          StudentAcademicRecord.fromFirestore(
            schoolId,
            branchId,
            studentId,
            doc.id,
            doc.data(),
          ).toFirestoreClose(
            status: closeOldRecordAs,
            endDate: now,
            updatedBy: updatedBy,
          ),
        );
      }

      final newRecordRef = _academicRecordsCollection(
        schoolId,
        branchId,
        studentId,
      ).doc();
      final newRecord = StudentAcademicRecord(
        recordId: newRecordRef.id,
        studentId: studentId,
        schoolId: schoolId,
        branchId: branchId,
        academicYearId: newAcademicYearId,
        classId: newClassId,
        sectionId: newSectionId,
        rollNumber: newRollNumber,
        startDate: now,
        status: AcademicRecordStatus.active,
      );
      batch.set(
        newRecordRef,
        newRecord.toFirestoreCreate(createdBy: updatedBy),
      );

      batch.update(_studentDoc(schoolId, branchId, studentId), {
        'currentAcademicYearId': newAcademicYearId,
        'currentClassId': newClassId,
        'currentSectionId': newSectionId,
        'currentRollNumber': newRollNumber,
        FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
        FirestoreFields.updatedBy: updatedBy,
      });

      await batch.commit();
      await _refreshFamilies(schoolId, branchId, studentId, updatedBy);
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Stream<List<StudentAcademicRecord>> watchAcademicHistory(
    String schoolId,
    String branchId,
    String studentId,
  ) {
    return _academicRecordsCollection(schoolId, branchId, studentId)
        .orderBy('startDate')
        .snapshots()
        .map(
          (s) => s.docs
              .map(
                (d) => StudentAcademicRecord.fromFirestore(
                  schoolId,
                  branchId,
                  studentId,
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
  Stream<List<ParentStudentLink>> watchParentLinks(
    String schoolId,
    String branchId,
    String studentId,
  ) {
    return _parentLinksCollection(schoolId, branchId, studentId)
        .snapshots()
        .map(
          (s) => s.docs
              .map(
                (d) => ParentStudentLink.fromFirestore(
                  schoolId,
                  branchId,
                  studentId,
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
  Future<void> linkParentToStudent({
    required String schoolId,
    required String branchId,
    required String studentId,
    required String parentId,
    required RelationshipType relationshipType,
    bool isPrimary = false,
    bool isEmergencyContact = false,
    bool canAccessPortal = false,
    required String createdBy,
  }) async {
    try {
      final link = ParentStudentLink(
        relationshipId: parentId,
        schoolId: schoolId,
        branchId: branchId,
        studentId: studentId,
        parentId: parentId,
        relationshipType: relationshipType,
        isPrimary: isPrimary,
        isEmergencyContact: isEmergencyContact,
        canAccessPortal: canAccessPortal,
        status: ActivationStatus.active,
      );
      await _parentLinksCollection(
        schoolId,
        branchId,
        studentId,
      ).doc(parentId).set(link.toFirestoreCreate(createdBy: createdBy));
      await _refreshFamilies(schoolId, branchId, studentId, createdBy);
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> updateParentLink(
    ParentStudentLink link, {
    required String updatedBy,
  }) async {
    try {
      await _parentLinksCollection(
        link.schoolId,
        link.branchId,
        link.studentId,
      ).doc(link.parentId).update(link.toFirestoreUpdate(updatedBy: updatedBy));
      await _refreshFamilies(
        link.schoolId,
        link.branchId,
        link.studentId,
        updatedBy,
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  String _contentTypeFor(String extension) {
    switch (extension.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }
}
