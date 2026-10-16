import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../domain/academic_structure_repository.dart';
import '../domain/academic_year.dart';
import '../domain/academic_year_status.dart';
import '../domain/class_subject_link.dart';
import '../domain/school_class.dart';
import '../domain/section.dart';
import '../domain/subject.dart';

/// Nesting: `/schools/{schoolId}/branches/{branchId}/academicYears/{id}`,
/// then `.../classes/{id}`, `.../classes/{id}/sections/{id}`,
/// `.../subjects/{id}`, and `.../classes/{id}/classSubjects/{subjectId}` —
/// see FIRESTORE_ARCHITECTURE.md → "Academic structure".
///
/// Uniqueness (duplicate names/codes, overlapping active years) is
/// enforced *here*, not in `firestore.rules`: it's a data-quality concern,
/// not a tenant-isolation one, and rules can't efficiently check "does any
/// sibling document have this name" without reading the whole collection
/// on every write. Tenant/role authorization for these writes is still
/// enforced server-side by rules, same as everywhere else in this app.
class FirebaseAcademicStructureRepository
    implements AcademicStructureRepository {
  final FirebaseFirestore _firestore;

  FirebaseAcademicStructureRepository(this._firestore);

  CollectionReference<Map<String, dynamic>> _yearsCollection(
    String schoolId,
    String branchId,
  ) => _firestore
      .collection(FirestoreFields.schoolsCollection)
      .doc(schoolId)
      .collection(FirestoreFields.branchesCollection)
      .doc(branchId)
      .collection(FirestoreFields.academicYearsCollection);

  DocumentReference<Map<String, dynamic>> _yearDoc(
    String schoolId,
    String branchId,
    String yearId,
  ) => _yearsCollection(schoolId, branchId).doc(yearId);

  CollectionReference<Map<String, dynamic>> _classesCollection(
    String schoolId,
    String branchId,
    String yearId,
  ) => _yearDoc(
    schoolId,
    branchId,
    yearId,
  ).collection(FirestoreFields.classesCollection);

  DocumentReference<Map<String, dynamic>> _classDoc(
    String schoolId,
    String branchId,
    String yearId,
    String classId,
  ) => _classesCollection(schoolId, branchId, yearId).doc(classId);

  CollectionReference<Map<String, dynamic>> _sectionsCollection(
    String schoolId,
    String branchId,
    String yearId,
    String classId,
  ) => _classDoc(
    schoolId,
    branchId,
    yearId,
    classId,
  ).collection(FirestoreFields.sectionsCollection);

  CollectionReference<Map<String, dynamic>> _subjectsCollection(
    String schoolId,
    String branchId,
    String yearId,
  ) => _yearDoc(
    schoolId,
    branchId,
    yearId,
  ).collection(FirestoreFields.subjectsCollection);

  CollectionReference<Map<String, dynamic>> _classSubjectsCollection(
    String schoolId,
    String branchId,
    String yearId,
    String classId,
  ) => _classDoc(
    schoolId,
    branchId,
    yearId,
    classId,
  ).collection(FirestoreFields.classSubjectsCollection);

  // ---- Academic years ----------------------------------------------

  @override
  Stream<List<AcademicYear>> watchAcademicYears(
    String schoolId,
    String branchId,
  ) {
    return _yearsCollection(schoolId, branchId)
        .orderBy('startDate', descending: true)
        .snapshots()
        .map(
          (s) => s.docs
              .map(
                (d) => AcademicYear.fromFirestore(
                  schoolId,
                  branchId,
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
  Future<AcademicYear?> getAcademicYear(
    String schoolId,
    String branchId,
    String academicYearId,
  ) async {
    try {
      final snapshot = await _yearDoc(schoolId, branchId, academicYearId).get();
      if (!snapshot.exists) return null;
      return AcademicYear.fromFirestore(
        schoolId,
        branchId,
        academicYearId,
        snapshot.data()!,
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> updateAcademicYear(
    AcademicYear year, {
    required String updatedBy,
  }) async {
    try {
      if (!year.endDate.isAfter(year.startDate)) {
        throw const ValidationFailure('End date must be after the start date.');
      }
      final siblings = await _yearsCollection(
        year.schoolId,
        year.branchId,
      ).get();
      _assertNoDuplicateYear(
        siblings.docs,
        name: year.name,
        excludingId: year.academicYearId,
      );
      if (year.status == AcademicYearStatus.active) {
        _assertNoOtherActiveYear(
          siblings.docs,
          excludingId: year.academicYearId,
        );
      }

      await _yearDoc(
        year.schoolId,
        year.branchId,
        year.academicYearId,
      ).update(year.toFirestoreUpdate(updatedBy: updatedBy));
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  void _assertNoDuplicateYear(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> siblings, {
    required String name,
    required String? excludingId,
  }) {
    final exists = siblings.any(
      (d) =>
          d.id != excludingId &&
          (d.data()[FirestoreFields.name] as String?)?.toLowerCase() ==
              name.toLowerCase(),
    );
    if (exists) {
      throw ValidationFailure(
        'An academic year named "$name" already exists for this branch.',
      );
    }
  }

  void _assertNoOtherActiveYear(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> siblings, {
    required String? excludingId,
  }) {
    final hasOtherActive = siblings.any(
      (d) =>
          d.id != excludingId &&
          d.data()[FirestoreFields.status] ==
              AcademicYearStatus.active.wireValue,
    );
    if (hasOtherActive) {
      throw const ValidationFailure(
        'Another academic year is already active for this branch. Close it before activating a new one.',
      );
    }
  }

  // ---- Classes --------------------------------------------------------

  @override
  Stream<List<SchoolClass>> watchClasses(
    String schoolId,
    String branchId,
    String academicYearId,
  ) {
    return _classesCollection(schoolId, branchId, academicYearId)
        .orderBy('displayOrder')
        .snapshots()
        .map(
          (s) => s.docs
              .map(
                (d) => SchoolClass.fromFirestore(
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
  Future<String> createClass(
    SchoolClass schoolClass, {
    required String createdBy,
  }) async {
    try {
      final siblings = await _classesCollection(
        schoolClass.schoolId,
        schoolClass.branchId,
        schoolClass.academicYearId,
      ).get();
      _assertNoDuplicateClass(siblings.docs, schoolClass, excludingId: null);

      final ref = _classesCollection(
        schoolClass.schoolId,
        schoolClass.branchId,
        schoolClass.academicYearId,
      ).doc();
      await ref.set(schoolClass.toFirestoreCreate(createdBy: createdBy));
      return ref.id;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> updateClass(
    SchoolClass schoolClass, {
    required String updatedBy,
  }) async {
    try {
      final siblings = await _classesCollection(
        schoolClass.schoolId,
        schoolClass.branchId,
        schoolClass.academicYearId,
      ).get();
      _assertNoDuplicateClass(
        siblings.docs,
        schoolClass,
        excludingId: schoolClass.classId,
      );

      await _classDoc(
        schoolClass.schoolId,
        schoolClass.branchId,
        schoolClass.academicYearId,
        schoolClass.classId,
      ).update(schoolClass.toFirestoreUpdate(updatedBy: updatedBy));
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  void _assertNoDuplicateClass(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> siblings,
    SchoolClass schoolClass, {
    required String? excludingId,
  }) {
    for (final d in siblings) {
      if (d.id == excludingId) continue;
      final data = d.data();
      if ((data[FirestoreFields.name] as String?)?.toLowerCase() ==
          schoolClass.name.toLowerCase()) {
        throw ValidationFailure(
          'A class named "${schoolClass.name}" already exists for this academic year.',
        );
      }
      final code = schoolClass.code;
      if (code != null &&
          code.isNotEmpty &&
          (data['code'] as String?)?.toLowerCase() == code.toLowerCase()) {
        throw ValidationFailure(
          'A class with code "$code" already exists for this academic year.',
        );
      }
    }
  }

  @override
  Future<void> reorderClasses(
    List<SchoolClass> classesInNewOrder, {
    required String updatedBy,
  }) async {
    if (classesInNewOrder.isEmpty) return;
    try {
      final first = classesInNewOrder.first;
      final batch = _firestore.batch();
      for (var i = 0; i < classesInNewOrder.length; i++) {
        final c = classesInNewOrder[i];
        batch.update(
          _classDoc(
            first.schoolId,
            first.branchId,
            first.academicYearId,
            c.classId,
          ),
          {
            'displayOrder': i,
            FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
            FirestoreFields.updatedBy: updatedBy,
          },
        );
      }
      await batch.commit();
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  // ---- Sections ---------------------------------------------------------

  @override
  Stream<List<Section>> watchSections(
    String schoolId,
    String branchId,
    String academicYearId,
    String classId,
  ) {
    return _sectionsCollection(schoolId, branchId, academicYearId, classId)
        .orderBy(FirestoreFields.name)
        .snapshots()
        .map(
          (s) => s.docs
              .map(
                (d) => Section.fromFirestore(
                  schoolId,
                  branchId,
                  academicYearId,
                  classId,
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
  Future<String> createSection(
    Section section, {
    required String createdBy,
  }) async {
    try {
      final siblings = await _sectionsCollection(
        section.schoolId,
        section.branchId,
        section.academicYearId,
        section.classId,
      ).get();
      _assertNoDuplicateSection(siblings.docs, section, excludingId: null);

      final ref = _sectionsCollection(
        section.schoolId,
        section.branchId,
        section.academicYearId,
        section.classId,
      ).doc();
      await ref.set(section.toFirestoreCreate(createdBy: createdBy));
      return ref.id;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> updateSection(
    Section section, {
    required String updatedBy,
  }) async {
    try {
      final siblings = await _sectionsCollection(
        section.schoolId,
        section.branchId,
        section.academicYearId,
        section.classId,
      ).get();
      _assertNoDuplicateSection(
        siblings.docs,
        section,
        excludingId: section.sectionId,
      );

      await _sectionsCollection(
            section.schoolId,
            section.branchId,
            section.academicYearId,
            section.classId,
          )
          .doc(section.sectionId)
          .update(section.toFirestoreUpdate(updatedBy: updatedBy));
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  void _assertNoDuplicateSection(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> siblings,
    Section section, {
    required String? excludingId,
  }) {
    final exists = siblings.any(
      (d) =>
          d.id != excludingId &&
          (d.data()[FirestoreFields.name] as String?)?.toLowerCase() ==
              section.name.toLowerCase(),
    );
    if (exists) {
      throw ValidationFailure(
        'Section "${section.name}" already exists for this class.',
      );
    }
  }

  // ---- Subjects -----------------------------------------------------

  @override
  Stream<List<Subject>> watchSubjects(
    String schoolId,
    String branchId,
    String academicYearId,
  ) {
    return _subjectsCollection(schoolId, branchId, academicYearId)
        .orderBy('displayOrder')
        .snapshots()
        .map(
          (s) => s.docs
              .map(
                (d) => Subject.fromFirestore(
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
  Future<String> createSubject(
    Subject subject, {
    required String createdBy,
  }) async {
    try {
      final siblings = await _subjectsCollection(
        subject.schoolId,
        subject.branchId,
        subject.academicYearId,
      ).get();
      _assertNoDuplicateSubject(siblings.docs, subject, excludingId: null);

      final ref = _subjectsCollection(
        subject.schoolId,
        subject.branchId,
        subject.academicYearId,
      ).doc();
      await ref.set(subject.toFirestoreCreate(createdBy: createdBy));
      return ref.id;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> updateSubject(
    Subject subject, {
    required String updatedBy,
  }) async {
    try {
      final siblings = await _subjectsCollection(
        subject.schoolId,
        subject.branchId,
        subject.academicYearId,
      ).get();
      _assertNoDuplicateSubject(
        siblings.docs,
        subject,
        excludingId: subject.subjectId,
      );

      await _subjectsCollection(
            subject.schoolId,
            subject.branchId,
            subject.academicYearId,
          )
          .doc(subject.subjectId)
          .update(subject.toFirestoreUpdate(updatedBy: updatedBy));
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  void _assertNoDuplicateSubject(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> siblings,
    Subject subject, {
    required String? excludingId,
  }) {
    for (final d in siblings) {
      if (d.id == excludingId) continue;
      final data = d.data();
      if ((data[FirestoreFields.name] as String?)?.toLowerCase() ==
          subject.name.toLowerCase()) {
        throw ValidationFailure(
          'A subject named "${subject.name}" already exists for this academic year.',
        );
      }
      final code = subject.code;
      if (code != null &&
          code.isNotEmpty &&
          (data['code'] as String?)?.toLowerCase() == code.toLowerCase()) {
        throw ValidationFailure(
          'A subject with code "$code" already exists for this academic year.',
        );
      }
    }
  }

  // ---- Class-subject links ---------------------------------------------

  @override
  Stream<List<ClassSubjectLink>> watchClassSubjects(
    String schoolId,
    String branchId,
    String academicYearId,
    String classId,
  ) {
    return _classSubjectsCollection(schoolId, branchId, academicYearId, classId)
        .snapshots()
        .map(
          (s) => s.docs
              .map(
                (d) => ClassSubjectLink.fromFirestore(
                  schoolId,
                  branchId,
                  academicYearId,
                  classId,
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
  Future<void> linkSubjectToClass(
    ClassSubjectLink link, {
    required String createdBy,
  }) async {
    try {
      await _classSubjectsCollection(
        link.schoolId,
        link.branchId,
        link.academicYearId,
        link.classId,
      ).doc(link.subjectId).set(link.toFirestoreCreate(createdBy: createdBy));
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> unlinkSubjectFromClass(
    String schoolId,
    String branchId,
    String academicYearId,
    String classId,
    String subjectId,
  ) async {
    try {
      await _classSubjectsCollection(
        schoolId,
        branchId,
        academicYearId,
        classId,
      ).doc(subjectId).delete();
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
