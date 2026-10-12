import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../../students/domain/student.dart';
import '../../students/domain/student_status.dart';
import '../domain/fee_enums.dart';
import '../domain/fee_planners.dart';
import '../domain/fee_repositories.dart';
import '../domain/fee_structure.dart';
import '../domain/student_fee_assignment.dart';
import 'fee_firestore.dart';

/// Fee structures and student assignments. Assignments are written in
/// atomic chunks of [assignChunkSize]; each chunk is a transaction that
/// re-checks existence, so re-running a bulk assignment never duplicates.
class FirebaseFeeConfigRepository implements FeeConfigRepository {
  final FirebaseFirestore _firestore;

  static const int assignChunkSize = 20;
  static const int maxPlacementStudents = 2000;

  FirebaseFeeConfigRepository(this._firestore);

  FeePaths _paths(String schoolId, String branchId) =>
      FeePaths(_firestore, schoolId, branchId);

  @override
  Stream<List<FeeStructure>> watchStructures(
    String schoolId,
    String branchId,
    String academicYearId,
  ) {
    return _paths(schoolId, branchId).structures
        .where('academicYearId', isEqualTo: academicYearId)
        .snapshots()
        .map(
          (s) =>
              (s.docs
                  .map(
                    (d) => FeeStructure.fromFirestore(
                      schoolId,
                      branchId,
                      d.id,
                      d.data(),
                    ),
                  )
                  .toList()
                ..sort((a, b) => a.name.compareTo(b.name))),
        )
        .handleError(
          (error, stackTrace) =>
              throw mapExceptionToFailure(error, stackTrace as StackTrace?),
        );
  }

  @override
  Future<List<FeeStructure>> getStructures(
    String schoolId,
    String branchId,
    Iterable<String> structureIds,
  ) async {
    try {
      final result = <FeeStructure>[];
      for (final chunk in chunked(structureIds.toSet().toList(), 30)) {
        final snapshot = await _paths(
          schoolId,
          branchId,
        ).structures.where(FieldPath.documentId, whereIn: chunk).get();
        result.addAll(
          snapshot.docs.map(
            (d) =>
                FeeStructure.fromFirestore(schoolId, branchId, d.id, d.data()),
          ),
        );
      }
      return result;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> createStructure(
    FeeStructure structure, {
    required String actorId,
  }) async {
    try {
      final problems = structure.validate();
      if (problems.isNotEmpty) throw ValidationFailure(problems.first);
      final paths = _paths(structure.schoolId, structure.branchId);
      final ref = paths.structures.doc(
        FeeStructure.idFor(structure.academicYearId, structure.code),
      );
      if ((await ref.get()).exists) {
        throw const ValidationFailure(
          'A fee with this code already exists for this academic year.',
        );
      }
      final batch = _firestore.batch()
        ..set(ref, structure.toFirestoreCreate(createdBy: actorId));
      paths.audit(
        batch,
        type: 'FEE_STRUCTURE_CREATED',
        actorId: actorId,
        details: {'structureId': ref.id, 'amountMinor': structure.amountMinor},
      );
      await batch.commit();
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> updateStructure(
    FeeStructure structure, {
    required String actorId,
  }) async {
    try {
      final problems = structure.validate();
      if (problems.isNotEmpty) throw ValidationFailure(problems.first);
      final paths = _paths(structure.schoolId, structure.branchId);
      final ref = paths.structures.doc(structure.structureId);
      final previous = await ref.get();
      final batch = _firestore.batch()
        ..update(ref, structure.toFirestoreUpdate(updatedBy: actorId));
      paths.audit(
        batch,
        type: 'FEE_STRUCTURE_UPDATED',
        actorId: actorId,
        details: {
          'structureId': structure.structureId,
          'previousAmountMinor': previous.data()?['amountMinor'],
          'amountMinor': structure.amountMinor,
          'status': structure.status.wireValue,
        },
      );
      await batch.commit();
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Stream<List<StudentFeeAssignment>> watchStudentAssignments(
    String schoolId,
    String branchId,
    String studentId,
    String academicYearId,
  ) {
    return _paths(schoolId, branchId).assignments
        .where('studentId', isEqualTo: studentId)
        .where('academicYearId', isEqualTo: academicYearId)
        .snapshots()
        .map(
          (s) => s.docs
              .map(
                (d) => StudentFeeAssignment.fromFirestore(
                  schoolId,
                  branchId,
                  d.id,
                  d.data(),
                ),
              )
              .toList(),
        )
        .handleError(
          (error, stackTrace) =>
              throw mapExceptionToFailure(error, stackTrace as StackTrace?),
        );
  }

  @override
  Future<List<StudentFeeAssignment>> fetchAssignmentsForPlacement({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    String? sectionId,
  }) async {
    try {
      Query<Map<String, dynamic>> q = _paths(schoolId, branchId).assignments
          .where('academicYearId', isEqualTo: academicYearId)
          .where('classId', isEqualTo: classId);
      if (sectionId != null) q = q.where('sectionId', isEqualTo: sectionId);
      // Firestore rejects limit() above 10,000, so read in pages. The cap
      // keeps one placement bounded (a student can hold several fee
      // assignments, hence the multiplier).
      const pageSize = 500;
      const cap = maxPlacementStudents * 8;
      final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
      while (docs.length < cap) {
        final page =
            await (cursor == null
                    ? q.limit(pageSize)
                    : q.startAfterDocument(cursor).limit(pageSize))
                .get();
        docs.addAll(page.docs);
        if (page.docs.length < pageSize) break;
        cursor = page.docs.last;
      }
      return docs
          .map(
            (d) => StudentFeeAssignment.fromFirestore(
              schoolId,
              branchId,
              d.id,
              d.data(),
            ),
          )
          .toList();
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<List<FeeStudent>> loadPlacementStudents({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    String? sectionId,
  }) async {
    try {
      final paths = _paths(schoolId, branchId);
      final classDoc = paths.branch
          .collection(FirestoreFields.academicYearsCollection)
          .doc(academicYearId)
          .collection(FirestoreFields.classesCollection)
          .doc(classId);
      final className =
          (await classDoc.get()).data()?[FirestoreFields.name] as String? ?? '';
      final sectionNames = {
        for (final d
            in (await classDoc
                    .collection(FirestoreFields.sectionsCollection)
                    .get())
                .docs)
          d.id: d.data()[FirestoreFields.name] as String? ?? '',
      };

      Query<Map<String, dynamic>> base = paths.students
          .where('currentAcademicYearId', isEqualTo: academicYearId)
          .where('currentClassId', isEqualTo: classId);
      if (sectionId != null) {
        base = base.where('currentSectionId', isEqualTo: sectionId);
      }
      base = base.orderBy('displayNameLower');

      final students = <FeeStudent>[];
      DocumentSnapshot<Map<String, dynamic>>? cursor;
      while (students.length < maxPlacementStudents) {
        final page =
            await (cursor == null
                    ? base.limit(200)
                    : base.startAfterDocument(cursor).limit(200))
                .get();
        for (final d in page.docs) {
          final s = Student.fromFirestore(schoolId, branchId, d.id, d.data());
          students.add(
            FeeStudent(
              studentId: s.studentId,
              name: s.displayName,
              admissionNumber: s.admissionNumber,
              classId: classId,
              className: className,
              sectionId: s.currentSectionId,
              sectionName: sectionNames[s.currentSectionId] ?? '',
              isEnrolled:
                  s.status == StudentStatus.active && s.hasCurrentPlacement,
            ),
          );
        }
        if (page.docs.length < 200) break;
        cursor = page.docs.last;
      }
      return students;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  StudentFeeAssignment _assignment({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required FeeStudent student,
    required FeeStructure structure,
    ConcessionType concessionType = ConcessionType.none,
    int concessionValue = 0,
    String? concessionReason,
  }) {
    return StudentFeeAssignment(
      assignmentId: StudentFeeAssignment.idFor(
        student.studentId,
        structure.structureId,
      ),
      schoolId: schoolId,
      branchId: branchId,
      academicYearId: academicYearId,
      studentId: student.studentId,
      structureId: structure.structureId,
      structureName: structure.name,
      classId: student.classId,
      sectionId: student.sectionId,
      concessionType: concessionType,
      concessionValue: concessionValue,
      concessionReason: concessionReason,
    );
  }

  @override
  Future<BulkResult> createAssignments(
    List<PlannedAssignment> planned, {
    required String actorId,
    void Function(int done, int total)? onProgress,
  }) async {
    var created = 0, skipped = 0, failed = 0, done = 0;
    final errors = <String>[];
    if (planned.isEmpty) {
      return const BulkResult(created: 0, skippedExisting: 0, failed: 0);
    }
    final first = planned.first;
    final paths = _paths(first.structure.schoolId, first.structure.branchId);

    for (final chunk in chunked(planned, assignChunkSize)) {
      try {
        final result = await _firestore.runTransaction<int>((
          transaction,
        ) async {
          var made = 0;
          final pending =
              <DocumentReference<Map<String, dynamic>>, Map<String, dynamic>>{};
          for (final p in chunk) {
            final a = _assignment(
              schoolId: p.structure.schoolId,
              branchId: p.structure.branchId,
              academicYearId: p.structure.academicYearId,
              student: p.student,
              structure: p.structure,
            );
            final ref = paths.assignments.doc(a.assignmentId);
            if ((await transaction.get(ref)).exists) continue;
            pending[ref] = a.toFirestoreCreate(createdBy: actorId);
            made++;
          }
          pending.forEach(transaction.set);
          return made;
        });
        created += result;
        skipped += chunk.length - result;
      } catch (error, stackTrace) {
        failed += chunk.length;
        errors.add(userMessageFor(mapExceptionToFailure(error, stackTrace)));
      }
      done += chunk.length;
      onProgress?.call(done, planned.length);
    }

    if (created > 0) {
      try {
        final batch = _firestore.batch();
        paths.audit(
          batch,
          type: 'FEE_ASSIGNMENT_BULK',
          actorId: actorId,
          details: {'created': created, 'skipped': skipped, 'failed': failed},
        );
        await batch.commit();
      } catch (_) {
        // The assignments themselves are the record; a failed log entry must not mask success.
      }
    }
    return BulkResult(
      created: created,
      skippedExisting: skipped,
      failed: failed,
      errors: errors.toSet().toList(),
    );
  }

  @override
  Future<void> assignOne({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required FeeStudent student,
    required FeeStructure structure,
    required ConcessionType concessionType,
    required int concessionValue,
    String? concessionReason,
    required String actorId,
  }) async {
    try {
      final problem = StudentFeeAssignment.validateConcession(
        concessionType,
        concessionValue,
        concessionReason,
      );
      if (problem != null) throw ValidationFailure(problem);
      if (!student.isEnrolled) {
        throw const ValidationFailure(
          'This student is not currently enrolled, so cannot be charged.',
        );
      }
      if (!structure.isActive) {
        throw const ValidationFailure('This fee is inactive.');
      }
      if (!structure.appliesTo(
        classId: student.classId,
        sectionId: student.sectionId,
      )) {
        throw ValidationFailure(
          '${structure.name} does not apply to this student\'s class/section.',
        );
      }
      final paths = _paths(schoolId, branchId);
      final a = _assignment(
        schoolId: schoolId,
        branchId: branchId,
        academicYearId: academicYearId,
        student: student,
        structure: structure,
        concessionType: concessionType,
        concessionValue: concessionValue,
        concessionReason: concessionReason,
      );
      final ref = paths.assignments.doc(a.assignmentId);
      if ((await ref.get()).exists) {
        throw ValidationFailure(
          '${structure.name} is already assigned to this student.',
        );
      }
      final batch = _firestore.batch()
        ..set(ref, a.toFirestoreCreate(createdBy: actorId));
      paths.audit(
        batch,
        type: a.hasConcession ? 'FEE_ASSIGNED_WITH_CONCESSION' : 'FEE_ASSIGNED',
        actorId: actorId,
        details: {
          'assignmentId': a.assignmentId,
          'concessionType': concessionType.wireValue,
          'concessionValue': concessionValue,
          'reason': concessionReason,
        },
      );
      await batch.commit();
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> setAssignmentActive(
    StudentFeeAssignment assignment,
    bool active, {
    required String actorId,
  }) async {
    try {
      final paths = _paths(assignment.schoolId, assignment.branchId);
      final batch = _firestore.batch()
        ..update(paths.assignments.doc(assignment.assignmentId), {
          FirestoreFields.status: active ? 'ACTIVE' : 'CANCELLED',
          FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
          FirestoreFields.updatedBy: actorId,
        });
      paths.audit(
        batch,
        type: active
            ? 'FEE_ASSIGNMENT_REACTIVATED'
            : 'FEE_ASSIGNMENT_CANCELLED',
        actorId: actorId,
        details: {'assignmentId': assignment.assignmentId},
      );
      await batch.commit();
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> setConcession(
    StudentFeeAssignment assignment, {
    required ConcessionType type,
    required int value,
    String? reason,
    required String actorId,
  }) async {
    try {
      final problem = StudentFeeAssignment.validateConcession(
        type,
        value,
        reason,
      );
      if (problem != null) throw ValidationFailure(problem);
      final paths = _paths(assignment.schoolId, assignment.branchId);
      final batch = _firestore.batch()
        ..update(paths.assignments.doc(assignment.assignmentId), {
          'concessionType': type.wireValue,
          'concessionValue': type == ConcessionType.none ? 0 : value,
          'concessionReason': type == ConcessionType.none ? null : reason,
          'concessionApprovedBy': actorId,
          FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
          FirestoreFields.updatedBy: actorId,
        });
      paths.audit(
        batch,
        type: 'FEE_CONCESSION_CHANGED',
        actorId: actorId,
        details: {
          'assignmentId': assignment.assignmentId,
          'previousType': assignment.concessionType.wireValue,
          'previousValue': assignment.concessionValue,
          'type': type.wireValue,
          'value': value,
          'reason': reason,
        },
      );
      await batch.commit();
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
