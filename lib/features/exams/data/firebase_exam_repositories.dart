import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../../students/domain/paged_result.dart';
import '../domain/exam_enums.dart';
import '../domain/exam_repositories.dart';
import '../domain/exam_rules.dart';
import '../domain/examination.dart';
import '../domain/grading_scheme.dart';
import '../domain/marks.dart';
import '../domain/result_calculator.dart';
import '../domain/result_summary.dart';
import 'exam_writes.dart';

/// Marks entries are written a few at a time: each carries a student
/// enrolment lookup in the security rules, and a commit has a limit on how
/// many documents the rules may read.
const int kMarksBatchSize = 5;

class ExamCollections {
  final FirebaseFirestore firestore;
  final String schoolId;
  final String branchId;

  ExamCollections(this.firestore, this.schoolId, this.branchId);

  DocumentReference<Map<String, dynamic>> get branch => firestore
      .collection(FirestoreFields.schoolsCollection)
      .doc(schoolId)
      .collection(FirestoreFields.branchesCollection)
      .doc(branchId);

  CollectionReference<Map<String, dynamic>> c(String name) =>
      branch.collection(name);

  CollectionReference<Map<String, dynamic>> get schemes =>
      c(FirestoreFields.gradingSchemesCollection);
  CollectionReference<Map<String, dynamic>> get exams =>
      c(FirestoreFields.examinationsCollection);
  CollectionReference<Map<String, dynamic>> get subjects =>
      c(FirestoreFields.examSubjectsCollection);
  CollectionReference<Map<String, dynamic>> get history =>
      c(FirestoreFields.examHistoryCollection);
  CollectionReference<Map<String, dynamic>> get sheets =>
      c(FirestoreFields.marksSheetsCollection);
  CollectionReference<Map<String, dynamic>> get sheetHistory =>
      c(FirestoreFields.marksSheetHistoryCollection);
  CollectionReference<Map<String, dynamic>> get entries =>
      c(FirestoreFields.marksEntriesCollection);
  CollectionReference<Map<String, dynamic>> get revisions =>
      c(FirestoreFields.marksRevisionsCollection);
  CollectionReference<Map<String, dynamic>> get remarks =>
      c(FirestoreFields.examRemarksCollection);
  CollectionReference<Map<String, dynamic>> get results =>
      c(FirestoreFields.resultSummariesCollection);
  CollectionReference<Map<String, dynamic>> get notices =>
      c(FirestoreFields.broadcastNoticesCollection);
}

class FirebaseGradingSchemeRepository implements GradingSchemeRepository {
  final FirebaseFirestore _firestore;

  FirebaseGradingSchemeRepository(this._firestore);

  ExamCollections _c(String s, String b) => ExamCollections(_firestore, s, b);

  @override
  Stream<List<GradingScheme>> watch(String schoolId, String branchId) =>
      _c(schoolId, branchId).schemes.snapshots().map((s) {
        final list = [
          for (final d in s.docs) GradingScheme.fromMap(d.data(), id: d.id),
        ]..sort((a, b) => a.name.compareTo(b.name));
        return list;
      });

  @override
  Future<GradingScheme?> fetch(
    String schoolId,
    String branchId,
    String schemeId,
  ) async {
    try {
      final snap = await _c(schoolId, branchId).schemes.doc(schemeId).get();
      return snap.exists
          ? GradingScheme.fromMap(snap.data()!, id: snap.id)
          : null;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<String> save(GradingScheme scheme, {required ExamActor actor}) async {
    final problem = scheme.validate();
    if (problem != null) throw ValidationFailure(problem);
    final c = _c(scheme.schoolId, scheme.branchId);
    try {
      if (scheme.schemeId.isEmpty) {
        final id =
            'gs_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
        await c.schemes
            .doc(id)
            .set(ExamWrites.schemeCreate(scheme, actor.userId));
        return id;
      }
      final ref = c.schemes.doc(scheme.schemeId);
      final fresh = await ref.get();
      final rev = ((fresh.data()?['revision'] as num?)?.toInt() ?? 1) + 1;
      await ref.update(ExamWrites.schemeUpdate(scheme, rev, actor.userId));
      return scheme.schemeId;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}

class FirebaseExamRepository implements ExamRepository {
  final FirebaseFirestore _firestore;

  FirebaseExamRepository(this._firestore);

  ExamCollections _c(String s, String b) => ExamCollections(_firestore, s, b);

  Future<Examination> _fresh(Examination e) async {
    final snap = await _c(e.schoolId, e.branchId).exams.doc(e.examId).get();
    if (!snap.exists) {
      throw const NotFoundFailure('This examination could not be found.');
    }
    return Examination.fromFirestore(snap.data()!, snap.id);
  }

  @override
  Future<PagedResult<Examination>> fetch({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    String? classId,
    ExamStatus? status,
    int pageSize = 25,
    Object? cursor,
  }) async {
    try {
      Query<Map<String, dynamic>> q = _c(
        schoolId,
        branchId,
      ).exams.where('academicYearId', isEqualTo: academicYearId);
      if (classId != null) q = q.where('classId', isEqualTo: classId);
      if (status != null) {
        q = q.where(FirestoreFields.status, isEqualTo: status.wireValue);
      }
      q = q.orderBy('startDateKey', descending: true).limit(pageSize);
      if (cursor is DocumentSnapshot) q = q.startAfterDocument(cursor);
      final snap = await q.get();
      return PagedResult(
        items: [
          for (final d in snap.docs) Examination.fromFirestore(d.data(), d.id),
        ],
        nextCursor: snap.docs.length == pageSize ? snap.docs.last : null,
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Stream<Examination?> watch(String schoolId, String branchId, String examId) =>
      _c(schoolId, branchId).exams
          .doc(examId)
          .snapshots()
          .map(
            (s) => s.exists ? Examination.fromFirestore(s.data()!, s.id) : null,
          );

  @override
  Stream<List<ExaminationSubject>> watchSubjects(
    String schoolId,
    String branchId,
    String examId,
  ) => _c(schoolId, branchId).subjects
      .where('examId', isEqualTo: examId)
      .snapshots()
      .map(
        (s) =>
            [for (final d in s.docs) ExaminationSubject.fromFirestore(d.data())]
              ..sort((a, b) => a.subjectName.compareTo(b.subjectName)),
      );

  @override
  Future<void> create(Examination exam, {required ExamActor actor}) async {
    final problem = exam.validate();
    if (problem != null) throw ValidationFailure(problem);
    final c = _c(exam.schoolId, exam.branchId);
    final batch = _firestore.batch();
    batch.set(
      c.exams.doc(exam.examId),
      exam.toFirestoreCreate(actorId: actor.userId),
    );
    batch.set(
      c.history.doc(ExamWrites.historyId(exam.examId, 1)),
      ExamWrites.history(
        exam: exam,
        revision: 1,
        event: ExamEvent.created,
        toStatus: ExamStatus.draft,
        actor: actor,
      ),
    );
    try {
      await batch.commit();
    } catch (error, stackTrace) {
      // A retry of a commit that already happened is not an error.
      final existing = await c.exams
          .doc(exam.examId)
          .get()
          .catchError((_) => throw error);
      if (existing.exists && existing.data()?['createdBy'] == actor.userId) {
        return;
      }
      if (existing.exists) {
        throw const ConflictFailure(
          'An examination with this name already exists for this class '
          'and section.',
        );
      }
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  /// Read fresh → precondition → one batch (document change + history).
  Future<void> _transition({
    required Examination exam,
    required ExamActor actor,
    required ExamEvent event,
    required ExamStatus to,
    required String? Function(Examination fresh) precondition,
    required Map<String, dynamic> Function(int rev, Examination fresh) fields,
    String? note,
    void Function(
      WriteBatch batch,
      ExamCollections c,
      Examination fresh,
      int rev,
    )?
    extra,
  }) async {
    try {
      final fresh = await _fresh(exam);
      final problem = precondition(fresh);
      if (problem != null) throw ConflictFailure(problem);
      final c = _c(fresh.schoolId, fresh.branchId);
      final rev = fresh.revision + 1;
      final batch = _firestore.batch();
      batch.update(c.exams.doc(fresh.examId), fields(rev, fresh));
      batch.set(
        c.history.doc(ExamWrites.historyId(fresh.examId, rev)),
        ExamWrites.history(
          exam: fresh,
          revision: rev,
          event: event,
          toStatus: to,
          actor: actor,
          note: note,
        ),
      );
      extra?.call(batch, c, fresh, rev);
      await batch.commit();
    } on AppFailure {
      rethrow;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> update(Examination exam, {required ExamActor actor}) {
    final problem = exam.validate();
    if (problem != null) throw ValidationFailure(problem);
    return _transition(
      exam: exam,
      actor: actor,
      event: ExamEvent.edited,
      to: exam.status,
      precondition: (f) => f.status.isConfigurable
          ? null
          : 'Only a draft or scheduled examination can be edited.',
      fields: (rev, f) => ExamWrites.examEdit(exam, rev, actor.userId),
    );
  }

  @override
  Future<void> saveSubject(
    Examination exam,
    ExaminationSubject subject, {
    required bool isNew,
    required ExamActor actor,
  }) async {
    final problem = subject.validate(
      examStartKey: exam.startDateKey,
      examEndKey: exam.endDateKey,
    );
    if (problem != null) throw ValidationFailure(problem);
    try {
      final fresh = await _fresh(exam);
      if (!fresh.status.isConfigurable) {
        throw const ConflictFailure(
          'Subjects can only change while the examination is a draft or '
          'scheduled.',
        );
      }
      final c = _c(fresh.schoolId, fresh.branchId);
      final batch = _firestore.batch();
      final ref = c.subjects.doc(subject.id);
      if (isNew) {
        batch.set(ref, subject.toFirestoreCreate(actorId: actor.userId));
        batch.update(
          c.exams.doc(fresh.examId),
          ExamWrites.counter(
            'subjectCount',
            fresh.subjectCount + 1,
            actor.userId,
          ),
        );
      } else {
        batch.update(
          ref,
          ExamWrites.subjectEdit(subject, subject.revision + 1, actor.userId),
        );
      }
      await batch.commit();
    } on AppFailure {
      rethrow;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> removeSubject(
    Examination exam,
    ExaminationSubject subject, {
    required ExamActor actor,
  }) async {
    try {
      final fresh = await _fresh(exam);
      if (!fresh.status.isConfigurable) {
        throw const ConflictFailure(
          'Subjects can only change while the examination is a draft or '
          'scheduled.',
        );
      }
      final c = _c(fresh.schoolId, fresh.branchId);
      final batch = _firestore.batch();
      batch.delete(c.subjects.doc(subject.id));
      batch.update(
        c.exams.doc(fresh.examId),
        ExamWrites.counter(
          'subjectCount',
          fresh.subjectCount - 1,
          actor.userId,
        ),
      );
      await batch.commit();
    } on AppFailure {
      rethrow;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> schedule(Examination exam, {required ExamActor actor}) =>
      _transition(
        exam: exam,
        actor: actor,
        event: ExamEvent.scheduled,
        to: ExamStatus.scheduled,
        precondition: ExamRules.checkSchedule,
        fields: (rev, f) => ExamWrites.examStatus(
          to: ExamStatus.scheduled,
          event: ExamEvent.scheduled,
          revision: rev,
          uid: actor.userId,
        ),
      );

  @override
  Future<void> startMarksEntry(
    Examination exam, {
    required int sheetCount,
    required ExamActor actor,
  }) => _transition(
    exam: exam,
    actor: actor,
    event: ExamEvent.started,
    to: ExamStatus.inProgress,
    precondition: (f) => ExamRules.checkStart(f, sheetCount),
    fields: (rev, f) => ExamWrites.examStatus(
      to: ExamStatus.inProgress,
      event: ExamEvent.started,
      revision: rev,
      uid: actor.userId,
      extra: {'sheetCount': sheetCount, 'approvedSheets': 0},
    ),
  );

  @override
  Future<void> cancel(
    Examination exam, {
    required String reason,
    required ExamActor actor,
  }) => _transition(
    exam: exam,
    actor: actor,
    event: ExamEvent.cancelled,
    to: ExamStatus.cancelled,
    note: reason,
    precondition: (f) => ExamRules.checkCancel(f, reason),
    fields: (rev, f) => ExamWrites.examStatus(
      to: ExamStatus.cancelled,
      event: ExamEvent.cancelled,
      revision: rev,
      uid: actor.userId,
    ),
  );

  @override
  Future<void> withdraw(
    Examination exam, {
    required String reason,
    required ExamActor actor,
  }) => _transition(
    exam: exam,
    actor: actor,
    event: ExamEvent.withdrawn,
    to: ExamStatus.withdrawn,
    note: reason,
    precondition: (f) => ExamRules.checkWithdraw(f, reason),
    fields: (rev, f) => ExamWrites.examStatus(
      to: ExamStatus.withdrawn,
      event: ExamEvent.withdrawn,
      revision: rev,
      uid: actor.userId,
    ),
  );

  @override
  Future<void> reopen(
    Examination exam, {
    required String reason,
    required ExamActor actor,
  }) => _transition(
    exam: exam,
    actor: actor,
    event: ExamEvent.reopened,
    to: ExamStatus.inProgress,
    note: reason,
    precondition: (f) => ExamRules.checkReopen(f, reason),
    fields: (rev, f) => ExamWrites.examStatus(
      to: ExamStatus.inProgress,
      event: ExamEvent.reopened,
      revision: rev,
      uid: actor.userId,
      extra: {'resultsWritten': 0, 'resultCount': 0},
    ),
  );

  @override
  Future<List<ExamAuditEntry>> fetchAudit(
    String schoolId,
    String branchId,
    String examId,
  ) async {
    try {
      final c = _c(schoolId, branchId);
      final exam = await c.history.where('examId', isEqualTo: examId).get();
      final sheets = await c.sheetHistory
          .where('examId', isEqualTo: examId)
          .get();
      final all = [
        for (final d in exam.docs)
          ExamAuditEntry.fromFirestore(d.data(), 'EXAM'),
        for (final d in sheets.docs)
          ExamAuditEntry.fromFirestore(d.data(), 'SHEET'),
      ]..sort((a, b) => (a.at ?? DateTime(0)).compareTo(b.at ?? DateTime(0)));
      return all;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}

class FirebaseMarksRepository implements MarksRepository {
  final FirebaseFirestore _firestore;

  FirebaseMarksRepository(this._firestore);

  ExamCollections _c(String s, String b) => ExamCollections(_firestore, s, b);

  @override
  Future<MarksSheet?> fetchSheet(
    Examination exam,
    String subjectId,
    String sectionId,
  ) async {
    try {
      final snap = await _c(
        exam.schoolId,
        exam.branchId,
      ).sheets.doc(MarksSheet.idFor(exam.examId, subjectId, sectionId)).get();
      return snap.exists ? MarksSheet.fromFirestore(snap.data()!) : null;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<List<MarksSheet>> fetchSheets(Examination exam) async {
    try {
      final snap = await _c(
        exam.schoolId,
        exam.branchId,
      ).sheets.where('examId', isEqualTo: exam.examId).get();
      return [for (final d in snap.docs) MarksSheet.fromFirestore(d.data())];
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<List<MarksEntry>> fetchEntries(
    Examination exam,
    String subjectId,
    String sectionId,
  ) async {
    try {
      // Every field the rules use to authorise the read is pinned.
      final snap = await _c(exam.schoolId, exam.branchId).entries
          .where('examId', isEqualTo: exam.examId)
          .where('subjectId', isEqualTo: subjectId)
          .where('sectionId', isEqualTo: sectionId)
          .where('classId', isEqualTo: exam.classId)
          .where('academicYearId', isEqualTo: exam.academicYearId)
          .get();
      return [
        for (final d in snap.docs) MarksEntry.fromFirestore(d.data(), d.id),
      ];
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<List<MarksEntry>> fetchAllEntries(Examination exam) async {
    try {
      final out = <MarksEntry>[];
      DocumentSnapshot? cursor;
      while (true) {
        Query<Map<String, dynamic>> q = _c(exam.schoolId, exam.branchId).entries
            .where('examId', isEqualTo: exam.examId)
            .orderBy(FieldPath.documentId)
            .limit(300);
        if (cursor != null) q = q.startAfterDocument(cursor);
        final snap = await q.get();
        out.addAll([
          for (final d in snap.docs) MarksEntry.fromFirestore(d.data(), d.id),
        ]);
        if (snap.docs.length < 300) break;
        cursor = snap.docs.last;
      }
      return out;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<int> saveEntries({
    required Examination exam,
    required ExaminationSubject subject,
    required String sectionId,
    required List<MarksEntry> changed,
    required int rosterCount,
    required ExamActor actor,
  }) async {
    if (changed.isEmpty) return 0;
    for (final e in changed) {
      final problem = e.validate(subject);
      if (problem != null) {
        throw ValidationFailure('${e.studentName}: $problem');
      }
    }
    final c = _c(exam.schoolId, exam.branchId);
    final sheetId = MarksSheet.idFor(exam.examId, subject.subjectId, sectionId);
    try {
      final existing = await c.sheets.doc(sheetId).get();
      var sheetExists = existing.exists;
      if (sheetExists) {
        final status = SheetStatus.fromWireValue(
          existing.data()![FirestoreFields.status] as String,
        );
        if (!status.isEditable) {
          throw ConflictFailure(
            'This sheet is ${status.displayName.toLowerCase()} and cannot '
            'be edited.',
          );
        }
      }
      var written = 0;
      for (var i = 0; i < changed.length; i += kMarksBatchSize) {
        final chunk = changed.skip(i).take(kMarksBatchSize);
        final batch = _firestore.batch();
        if (!sheetExists) {
          batch.set(
            c.sheets.doc(sheetId),
            ExamWrites.sheetCreate(
              exam: exam,
              subjectId: subject.subjectId,
              sectionId: sectionId,
              rosterCount: rosterCount,
              uid: actor.userId,
            ),
          );
          batch.set(
            c.sheetHistory.doc(ExamWrites.sheetHistoryId(sheetId, 1)),
            ExamWrites.sheetHistory(
              exam: exam,
              sheetId: sheetId,
              revision: 1,
              event: SheetEvent.saved,
              toStatus: SheetStatus.draft,
              actor: actor,
            ),
          );
        }
        for (final e in chunk) {
          final rev = e.revision + 1;
          final ref = c.entries.doc(e.id);
          if (e.isUnsaved) {
            batch.set(
              ref,
              ExamWrites.entryCreate(
                e: e,
                components: subject.hasComponents,
                uid: actor.userId,
              ),
            );
          } else {
            batch.update(
              ref,
              ExamWrites.entryUpdate(
                e: e,
                components: subject.hasComponents,
                revision: rev,
                uid: actor.userId,
              ),
            );
          }
          batch.set(
            c.revisions.doc('${e.id}__$rev'),
            ExamWrites.entryRevision(
              e: e,
              components: subject.hasComponents,
              revision: rev,
              actor: actor,
            ),
          );
        }
        await batch.commit();
        sheetExists = true;
        written += chunk.length;
      }
      // Keep the sheet's roster size current (no state change).
      final data = (await c.sheets.doc(sheetId).get()).data();
      if (data != null &&
          (data['rosterCount'] as num?)?.toInt() != rosterCount) {
        await c.sheets.doc(sheetId).update({
          'rosterCount': rosterCount,
          ...ExamWrites.stamp(actor.userId),
        });
      }
      return written;
    } on AppFailure {
      rethrow;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  Future<MarksSheet> _freshSheet(ExamCollections c, MarksSheet sheet) async {
    final snap = await c.sheets.doc(sheet.id).get();
    if (!snap.exists) {
      throw const NotFoundFailure('This marks sheet could not be found.');
    }
    return MarksSheet.fromFirestore(snap.data()!);
  }

  @override
  Future<void> submitSheet({
    required Examination exam,
    required MarksSheet sheet,
    required ExamActor actor,
  }) async {
    final c = _c(exam.schoolId, exam.branchId);
    try {
      final fresh = await _freshSheet(c, sheet);
      if (!fresh.status.isEditable) {
        throw ConflictFailure(
          'This sheet is already ${fresh.status.displayName.toLowerCase()}.',
        );
      }
      final rev = fresh.revision + 1;
      final batch = _firestore.batch();
      batch.update(
        c.sheets.doc(fresh.id),
        ExamWrites.sheetSubmit(rev, actor.userId),
      );
      batch.set(
        c.sheetHistory.doc(ExamWrites.sheetHistoryId(fresh.id, rev)),
        ExamWrites.sheetHistory(
          exam: exam,
          sheetId: fresh.id,
          revision: rev,
          event: SheetEvent.submitted,
          toStatus: SheetStatus.submitted,
          actor: actor,
        ),
      );
      await batch.commit();
    } on AppFailure {
      rethrow;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> approveSheet({
    required Examination exam,
    required MarksSheet sheet,
    required ExamActor actor,
  }) async {
    final c = _c(exam.schoolId, exam.branchId);
    try {
      final fresh = await _freshSheet(c, sheet);
      final problem = ExamRules.checkApprove(
        sheet: fresh,
        approverUserId: actor.userId,
        approverIsSchoolAdmin: actor.isSchoolAdmin,
      );
      if (problem != null) throw ConflictFailure(problem);
      final examSnap = await c.exams.doc(exam.examId).get();
      final approved =
          (examSnap.data()?['approvedSheets'] as num?)?.toInt() ?? 0;
      final rev = fresh.revision + 1;
      final batch = _firestore.batch();
      batch.update(
        c.sheets.doc(fresh.id),
        ExamWrites.sheetApprove(rev, actor.userId),
      );
      batch.update(
        c.exams.doc(exam.examId),
        ExamWrites.counter('approvedSheets', approved + 1, actor.userId),
      );
      batch.set(
        c.sheetHistory.doc(ExamWrites.sheetHistoryId(fresh.id, rev)),
        ExamWrites.sheetHistory(
          exam: exam,
          sheetId: fresh.id,
          revision: rev,
          event: SheetEvent.approved,
          toStatus: SheetStatus.approved,
          actor: actor,
        ),
      );
      await batch.commit();
    } on AppFailure {
      rethrow;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> returnSheet({
    required Examination exam,
    required MarksSheet sheet,
    required String note,
    required ExamActor actor,
  }) async {
    final c = _c(exam.schoolId, exam.branchId);
    try {
      final fresh = await _freshSheet(c, sheet);
      final problem = ExamRules.checkReturn(fresh, note);
      if (problem != null) throw ConflictFailure(problem);
      final rev = fresh.revision + 1;
      final batch = _firestore.batch();
      batch.update(
        c.sheets.doc(fresh.id),
        ExamWrites.sheetReturn(rev, actor.userId, note),
      );
      if (fresh.status == SheetStatus.approved) {
        final examSnap = await c.exams.doc(exam.examId).get();
        final approved =
            (examSnap.data()?['approvedSheets'] as num?)?.toInt() ?? 0;
        batch.update(
          c.exams.doc(exam.examId),
          ExamWrites.counter('approvedSheets', approved - 1, actor.userId),
        );
      }
      batch.set(
        c.sheetHistory.doc(ExamWrites.sheetHistoryId(fresh.id, rev)),
        ExamWrites.sheetHistory(
          exam: exam,
          sheetId: fresh.id,
          revision: rev,
          event: SheetEvent.returned,
          toStatus: SheetStatus.returned,
          actor: actor,
          note: note,
        ),
      );
      await batch.commit();
    } on AppFailure {
      rethrow;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}

class FirebaseResultRepository implements ResultRepository {
  final FirebaseFirestore _firestore;

  FirebaseResultRepository(this._firestore);

  ExamCollections _c(String s, String b) => ExamCollections(_firestore, s, b);

  @override
  Future<Map<String, ExamRemark>> fetchRemarks(Examination exam) async {
    try {
      final snap = await _c(
        exam.schoolId,
        exam.branchId,
      ).remarks.where('examId', isEqualTo: exam.examId).get();
      return {
        for (final d in snap.docs)
          d.data()['studentId'] as String: ExamRemark(
            studentId: d.data()['studentId'] as String,
            teacherRemark: d.data()['teacherRemark'] as String? ?? '',
            principalRemark: d.data()['principalRemark'] as String? ?? '',
          ),
      };
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> saveRemark({
    required Examination exam,
    required ExamRemark remark,
    required String sectionId,
    required ExamActor actor,
    required bool principal,
  }) async {
    try {
      await _c(exam.schoolId, exam.branchId).remarks
          .doc('${exam.examId}__${remark.studentId}')
          .set(
            ExamWrites.remark(
              exam: exam,
              studentId: remark.studentId,
              sectionId: sectionId,
              teacherRemark: remark.teacherRemark,
              principalRemark: remark.principalRemark,
              uid: actor.userId,
            ),
          );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<int> finalize({
    required Examination exam,
    required GradingScheme scheme,
    required List<StudentResult> results,
    required Map<String, AttendanceSnapshot?> attendance,
    required Map<String, ExamRemark> remarks,
    required Map<String, String> classLabels,
    required ExamActor actor,
  }) async {
    final c = _c(exam.schoolId, exam.branchId);
    try {
      final snap = await c.exams.doc(exam.examId).get();
      if (!snap.exists) {
        throw const NotFoundFailure('This examination could not be found.');
      }
      final fresh = Examination.fromFirestore(snap.data()!, snap.id);
      final problem = ExamRules.checkFinalize(fresh);
      if (problem != null) throw ConflictFailure(problem);
      final incomplete = results.where((r) => !r.isComplete).length;
      if (incomplete > 0) {
        throw ValidationFailure(
          '$incomplete student(s) still have missing marks, so the result '
          'cannot be finalised.',
        );
      }
      if (results.isEmpty) {
        throw const ValidationFailure('There are no students to calculate.');
      }
      final version = fresh.resultVersion + 1;
      final rev = fresh.revision + 1;
      final batch = _firestore.batch();
      batch.update(
        c.exams.doc(fresh.examId),
        ExamWrites.examStatus(
          to: ExamStatus.completed,
          event: ExamEvent.finalized,
          revision: rev,
          uid: actor.userId,
          extra: {
            'resultVersion': version,
            'resultCount': results.length,
            'resultsWritten': 0,
            'schemeSnapshot': scheme.policyMap(),
            'finalizedBy': actor.userId,
          },
        ),
      );
      batch.set(
        c.history.doc(ExamWrites.historyId(fresh.examId, rev)),
        ExamWrites.history(
          exam: fresh,
          revision: rev,
          event: ExamEvent.finalized,
          toStatus: ExamStatus.completed,
          actor: actor,
          note: 'Result version $version, ${results.length} students',
        ),
      );
      await batch.commit();

      final completed = Examination.fromFirestore({
        ...snap.data()!,
        FirestoreFields.status: ExamStatus.completed.wireValue,
        'revision': rev,
        'resultVersion': version,
        'resultCount': results.length,
        'resultsWritten': 0,
        'schemeSnapshot': scheme.policyMap(),
      }, fresh.examId);
      await _writeResults(
        exam: completed,
        scheme: scheme,
        results: results,
        attendance: attendance,
        remarks: remarks,
        classLabels: classLabels,
        actor: actor,
      );
      return version;
    } on AppFailure {
      rethrow;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  Future<void> _writeResults({
    required Examination exam,
    required GradingScheme scheme,
    required List<StudentResult> results,
    required Map<String, AttendanceSnapshot?> attendance,
    required Map<String, ExamRemark> remarks,
    required Map<String, String> classLabels,
    required ExamActor actor,
  }) async {
    final c = _c(exam.schoolId, exam.branchId);
    final version = exam.resultVersion;
    final stored = await c.results
        .where('examId', isEqualTo: exam.examId)
        .where('version', isEqualTo: version)
        .get();
    final have = {for (final d in stored.docs) d.data()['studentId'] as String};
    final todo = [
      for (final r in results)
        if (!have.contains(r.studentId)) r,
    ];
    var written = have.length;
    const chunk = 10;
    for (var i = 0; i < todo.length; i += chunk) {
      final batch = _firestore.batch();
      for (final r in todo.skip(i).take(chunk)) {
        final remark = remarks[r.studentId];
        batch.set(
          c.results.doc('${exam.examId}__${r.studentId}__v$version'),
          ExamWrites.resultSummary(
            exam: exam,
            version: version,
            result: r,
            schemeSnapshot: scheme.policyMap(),
            attendance: attendance[r.studentId],
            teacherRemark: remark?.teacherRemark ?? '',
            principalRemark: remark?.principalRemark ?? '',
            classLabel: classLabels[r.sectionId] ?? exam.classLabel ?? '',
            uid: actor.userId,
          ),
        );
      }
      await batch.commit();
      written += todo.skip(i).take(chunk).length;
      await c.exams
          .doc(exam.examId)
          .update(ExamWrites.counter('resultsWritten', written, actor.userId));
    }
  }

  @override
  Future<void> completeResults({
    required Examination exam,
    required GradingScheme scheme,
    required List<StudentResult> results,
    required Map<String, AttendanceSnapshot?> attendance,
    required Map<String, ExamRemark> remarks,
    required String classLabel,
    required ExamActor actor,
  }) async {
    try {
      if (exam.status != ExamStatus.completed) {
        throw const ConflictFailure('This result is not awaiting completion.');
      }
      await _writeResults(
        exam: exam,
        scheme: scheme,
        results: results,
        attendance: attendance,
        remarks: remarks,
        classLabels: {for (final r in results) r.sectionId: classLabel},
        actor: actor,
      );
    } on AppFailure {
      rethrow;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> publish(Examination exam, {required ExamActor actor}) async {
    final c = _c(exam.schoolId, exam.branchId);
    try {
      final snap = await c.exams.doc(exam.examId).get();
      if (!snap.exists) {
        throw const NotFoundFailure('This examination could not be found.');
      }
      final fresh = Examination.fromFirestore(snap.data()!, snap.id);
      if (fresh.status == ExamStatus.published) return; // already done
      final problem = ExamRules.checkPublish(fresh);
      if (problem != null) throw ConflictFailure(problem);
      final rev = fresh.revision + 1;
      final batch = _firestore.batch();
      batch.update(
        c.exams.doc(fresh.examId),
        ExamWrites.examStatus(
          to: ExamStatus.published,
          event: ExamEvent.published,
          revision: rev,
          uid: actor.userId,
          extra: {
            'publishedBy': actor.userId,
            'publishedAt': FieldValue.serverTimestamp(),
          },
        ),
      );
      batch.set(
        c.history.doc(ExamWrites.historyId(fresh.examId, rev)),
        ExamWrites.history(
          exam: fresh,
          revision: rev,
          event: ExamEvent.published,
          toStatus: ExamStatus.published,
          actor: actor,
          note: 'Result version ${fresh.resultVersion}',
        ),
      );
      batch.set(
        c.notices.doc(ExamWrites.noticeId(fresh.examId, fresh.resultVersion)),
        ExamWrites.resultNotice(fresh, actor.userId),
      );
      await batch.commit();
    } on AppFailure {
      rethrow;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<PagedResult<ResultSummary>> fetchResults({
    required Examination exam,
    int pageSize = 50,
    Object? cursor,
  }) async {
    try {
      Query<Map<String, dynamic>> q = _c(exam.schoolId, exam.branchId).results
          .where('examId', isEqualTo: exam.examId)
          .where('version', isEqualTo: exam.resultVersion)
          .orderBy('studentName')
          .limit(pageSize);
      if (cursor is DocumentSnapshot) q = q.startAfterDocument(cursor);
      final snap = await q.get();
      return PagedResult(
        items: [
          for (final d in snap.docs) ResultSummary.fromFirestore(d.data()),
        ],
        nextCursor: snap.docs.length == pageSize ? snap.docs.last : null,
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<ResultSummary?> fetchResult({
    required String schoolId,
    required String branchId,
    required String examId,
    required String studentId,
    required int version,
  }) async {
    try {
      final snap = await _c(
        schoolId,
        branchId,
      ).results.doc(ResultSummary.idFor(examId, studentId, version)).get();
      return snap.exists ? ResultSummary.fromFirestore(snap.data()!) : null;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  /// Published examinations that cover a child: class-wide ones
  /// (`sectionId == null`) and ones for the child's own section. Two queries
  /// because the security rules judge each by its own `sectionId`.
  @override
  Future<List<Examination>> fetchPublishedForClass({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    String? sectionId,
  }) async {
    try {
      Future<QuerySnapshot<Map<String, dynamic>>> q(String? section) =>
          _c(schoolId, branchId).exams
              .where('academicYearId', isEqualTo: academicYearId)
              .where('classId', isEqualTo: classId)
              .where(FirestoreFields.status, isEqualTo: 'PUBLISHED')
              .where('sectionId', isEqualTo: section)
              .get();
      final snaps = [await q(null), if (sectionId != null) await q(sectionId)];
      return [
        for (final snap in snaps)
          for (final d in snap.docs) Examination.fromFirestore(d.data(), d.id),
      ]..sort((a, b) => b.startDateKey.compareTo(a.startDateKey));
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
