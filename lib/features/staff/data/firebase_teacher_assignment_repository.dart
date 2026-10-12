import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/activation_status.dart';
import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../../academic_setup/domain/academic_year_status.dart';
import '../../students/domain/paged_result.dart';
import '../domain/staff.dart';
import '../domain/teacher_assignment.dart';
import '../domain/teacher_assignment_repository.dart';
import '../domain/teacher_assignment_rules.dart';
import '../domain/teacher_assignment_status.dart';

/// `/schools/{s}/branches/{b}/teacherAssignments/{id}` and the
/// `assignmentSlots/{slotKey}` reservations that make "one class teacher
/// per section" and "one teacher per section+subject" hold under
/// concurrency.
///
/// [assignTeacher] checks every reference against the real documents before
/// writing, for precise error messages. `firestore.rules` re-checks the
/// same references server-side (staff active + teacher, section active,
/// subject linked to the class, slot free), so the client is not trusted.
class FirebaseTeacherAssignmentRepository
    implements TeacherAssignmentRepository {
  final FirebaseFirestore _firestore;

  FirebaseTeacherAssignmentRepository(this._firestore);

  DocumentReference<Map<String, dynamic>> _branchDoc(
    String schoolId,
    String branchId,
  ) => _firestore
      .collection(FirestoreFields.schoolsCollection)
      .doc(schoolId)
      .collection(FirestoreFields.branchesCollection)
      .doc(branchId);

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

  DocumentReference<Map<String, dynamic>> _yearDoc(
    String schoolId,
    String branchId,
    String yearId,
  ) => _branchDoc(
    schoolId,
    branchId,
  ).collection(FirestoreFields.academicYearsCollection).doc(yearId);

  DocumentReference<Map<String, dynamic>> _classDoc(
    String schoolId,
    String branchId,
    String yearId,
    String classId,
  ) => _yearDoc(
    schoolId,
    branchId,
    yearId,
  ).collection(FirestoreFields.classesCollection).doc(classId);

  /// Throws a [ValidationFailure] carrying [reason] when a rule refuses.
  void _refuse(String? reason) {
    if (reason != null) throw ValidationFailure(reason);
  }

  AcademicYearStatus? _yearStatus(String? wire) =>
      wire == null ? null : AcademicYearStatus.fromWireValue(wire);

  TeacherAssignment _fromDoc(
    String schoolId,
    String branchId,
    DocumentSnapshot<Map<String, dynamic>> d,
  ) => TeacherAssignment.fromFirestore(schoolId, branchId, d.id, d.data()!);

  @override
  Stream<List<TeacherAssignment>> watchTeacherAssignments(
    String schoolId,
    String branchId,
    String teacherStaffId, {
    int limit = 300,
  }) {
    return _assignments(schoolId, branchId)
        .where('teacherStaffId', isEqualTo: teacherStaffId)
        .orderBy('startDate', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map((d) => _fromDoc(schoolId, branchId, d)).toList())
        .handleError((error, stackTrace) {
          throw mapExceptionToFailure(error, stackTrace as StackTrace?);
        });
  }

  @override
  Future<PagedResult<TeacherAssignment>> fetchActiveAssignments({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    String? classId,
    String? sectionId,
    String? subjectId,
    int pageSize = 25,
    Object? cursor,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _assignments(schoolId, branchId)
          .where('academicYearId', isEqualTo: academicYearId)
          .where(
            FirestoreFields.status,
            isEqualTo: TeacherAssignmentStatus.active.wireValue,
          );
      if (classId != null) query = query.where('classId', isEqualTo: classId);
      if (sectionId != null) {
        query = query.where('sectionId', isEqualTo: sectionId);
      }
      if (subjectId != null) {
        query = query.where('subjectId', isEqualTo: subjectId);
      }
      query = query.limit(pageSize + 1);
      final startAfter = cursor as DocumentSnapshot<Map<String, dynamic>>?;
      if (startAfter != null) query = query.startAfterDocument(startAfter);

      final snapshot = await query.get();
      final hasMore = snapshot.docs.length > pageSize;
      final docs = hasMore ? snapshot.docs.sublist(0, pageSize) : snapshot.docs;
      return PagedResult(
        items: docs.map((d) => _fromDoc(schoolId, branchId, d)).toList(),
        nextCursor: hasMore ? docs.last : null,
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<List<TeacherAssignment>> fetchAssignmentsForTeachers({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required List<String> teacherStaffIds,
  }) async {
    try {
      final result = <TeacherAssignment>[];
      for (var i = 0; i < teacherStaffIds.length; i += 30) {
        final chunk = teacherStaffIds.sublist(
          i,
          i + 30 > teacherStaffIds.length ? teacherStaffIds.length : i + 30,
        );
        final snapshot = await _assignments(schoolId, branchId)
            .where('teacherStaffId', whereIn: chunk)
            .where('academicYearId', isEqualTo: academicYearId)
            .get();
        result.addAll(
          snapshot.docs.map((d) => _fromDoc(schoolId, branchId, d)),
        );
      }
      return result;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Stream<List<TeacherAssignment>> watchSectionAssignments(
    String schoolId,
    String branchId,
    String academicYearId,
    String classId,
    String sectionId,
  ) {
    return _assignments(schoolId, branchId)
        .where('academicYearId', isEqualTo: academicYearId)
        .where('classId', isEqualTo: classId)
        .where('sectionId', isEqualTo: sectionId)
        .where(
          FirestoreFields.status,
          isEqualTo: TeacherAssignmentStatus.active.wireValue,
        )
        .snapshots()
        .map((s) => s.docs.map((d) => _fromDoc(schoolId, branchId, d)).toList())
        .handleError((error, stackTrace) {
          throw mapExceptionToFailure(error, stackTrace as StackTrace?);
        });
  }

  @override
  Future<String> assignTeacher({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String teacherStaffId,
    required String classId,
    required String sectionId,
    String? subjectId,
    required bool isClassTeacher,
    required DateTime startDate,
    required String createdBy,
  }) async {
    try {
      _refuse(
        TeacherAssignmentRules.checkSubject(
          isClassTeacher: isClassTeacher,
          subjectId: subjectId,
          linkedToClass: true,
        ),
      );

      final staffSnapshot = await _branchDoc(
        schoolId,
        branchId,
      ).collection(FirestoreFields.staffCollection).doc(teacherStaffId).get();
      final staff = staffSnapshot.exists
          ? Staff.fromFirestore(
              schoolId,
              branchId,
              teacherStaffId,
              staffSnapshot.data()!,
            )
          : null;
      _refuse(
        TeacherAssignmentRules.checkTeacher(
          exists: staff != null,
          isTeacher: staff?.isTeacher ?? false,
          status: staff?.status,
        ),
      );

      final yearSnapshot = await _yearDoc(
        schoolId,
        branchId,
        academicYearId,
      ).get();
      _refuse(
        TeacherAssignmentRules.checkAcademicYear(
          exists: yearSnapshot.exists,
          status: _yearStatus(
            yearSnapshot.data()?[FirestoreFields.status] as String?,
          ),
        ),
      );

      final classRef = _classDoc(schoolId, branchId, academicYearId, classId);
      final sectionSnapshot = await classRef
          .collection(FirestoreFields.sectionsCollection)
          .doc(sectionId)
          .get();
      _refuse(
        TeacherAssignmentRules.checkSection(
          exists: sectionSnapshot.exists,
          status:
              sectionSnapshot.data()?[FirestoreFields.status] ==
                  ActivationStatus.active.wireValue
              ? ActivationStatus.active
              : ActivationStatus.inactive,
        ),
      );

      if (!isClassTeacher) {
        final link = await classRef
            .collection(FirestoreFields.classSubjectsCollection)
            .doc(subjectId)
            .get();
        _refuse(
          TeacherAssignmentRules.checkSubject(
            isClassTeacher: false,
            subjectId: subjectId,
            linkedToClass: link.exists,
          ),
        );
      }

      final slotKey = TeacherAssignment.slotKeyFor(
        academicYearId: academicYearId,
        classId: classId,
        sectionId: sectionId,
        subjectId: isClassTeacher ? null : subjectId,
      );
      final slotRef = _slots(schoolId, branchId).doc(slotKey);
      final slot = await slotRef.get();
      _refuse(
        TeacherAssignmentRules.checkSlotFree(
          isClassTeacher: isClassTeacher,
          teacherStaffId: teacherStaffId,
          holderStaffId: slot.exists
              ? (slot.data()?['teacherStaffId'] as String? ?? '')
              : null,
        ),
      );

      final ref = _assignments(schoolId, branchId).doc();
      final assignment = TeacherAssignment(
        assignmentId: ref.id,
        schoolId: schoolId,
        branchId: branchId,
        academicYearId: academicYearId,
        teacherStaffId: teacherStaffId,
        classId: classId,
        sectionId: sectionId,
        subjectId: isClassTeacher ? null : subjectId,
        isClassTeacher: isClassTeacher,
        startDate: startDate,
        status: TeacherAssignmentStatus.active,
      );
      await (_firestore.batch()
            ..set(ref, assignment.toFirestoreCreate(createdBy: createdBy))
            ..set(slotRef, assignment.toSlotData(createdBy: createdBy)))
          .commit();
      return ref.id;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> endAssignment({
    required TeacherAssignment assignment,
    required DateTime endDate,
    required String updatedBy,
  }) async {
    try {
      _refuse(
        TeacherAssignmentRules.checkEnd(
          isActive: assignment.isActive,
          startDate: assignment.startDate,
          endDate: endDate,
        ),
      );
      final schoolId = assignment.schoolId;
      final branchId = assignment.branchId;
      await (_firestore.batch()
            ..update(
              _assignments(schoolId, branchId).doc(assignment.assignmentId),
              TeacherAssignment.firestoreEnd(
                endDate: endDate,
                updatedBy: updatedBy,
              ),
            )
            ..delete(_slots(schoolId, branchId).doc(assignment.slotKey)))
          .commit();
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
