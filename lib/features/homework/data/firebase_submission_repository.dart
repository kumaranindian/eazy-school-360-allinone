import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../../students/domain/paged_result.dart';
import '../domain/file_attachment.dart';
import '../domain/homework.dart';
import '../domain/homework_enums.dart';
import '../domain/homework_repositories.dart';
import '../domain/homework_rules.dart';
import '../domain/homework_submission.dart';
import 'homework_firestore.dart';
import 'homework_writes.dart';

/// Submissions, their revisions, and review.
///
/// One document per student per homework (`{homeworkId}__{studentId}`), so a
/// double tap or a retry cannot create a second submission. Every change also
/// appends a revision document (what was written / said, by whom, when) in
/// the same batch; the rules require it, so history cannot be skipped.
/// Lateness is *decided by the rules* against the server clock — the status
/// computed here is a prediction that the rules confirm or refuse.
class FirebaseSubmissionRepository implements SubmissionRepository {
  final FirebaseFirestore _firestore;

  FirebaseSubmissionRepository(this._firestore);

  HomeworkCollections _c(String schoolId, String branchId) =>
      HomeworkCollections(_firestore, schoolId, branchId);

  Future<HomeworkSubmission> _fresh(
    HomeworkCollections c,
    String submissionId,
  ) async {
    final snap = await c.submissions.doc(submissionId).get();
    if (!snap.exists) {
      throw const NotFoundFailure('This submission could not be found.');
    }
    return HomeworkSubmission.fromFirestore(snap.data()!, snap.id);
  }

  @override
  Future<void> submit({
    required Homework homework,
    required String studentId,
    required String studentName,
    required String text,
    required List<FileAttachment> attachments,
    required HomeworkActor actor,
  }) async {
    final now = DateTime.now();
    final decision = HomeworkRules.checkSubmit(homework: homework, now: now);
    if (decision.error != null) throw ValidationFailure(decision.error!);
    final content = HomeworkRules.checkContent(
      homework: homework,
      text: text,
      attachmentCount: attachments.length,
    );
    if (content != null) throw ValidationFailure(content);

    final c = _c(homework.schoolId, homework.branchId);
    final id = HomeworkSubmission.idFor(homework.homeworkId, studentId);
    final batch = _firestore.batch();
    batch.set(
      c.submissions.doc(id),
      HomeworkWrites.submissionCreate(
        homework: homework,
        studentId: studentId,
        studentName: studentName,
        text: text,
        attachments: attachments,
        status: decision.status!,
        uid: actor.userId,
      ),
    );
    batch.set(
      c.revisions.doc(SubmissionRevision.idFor(id, 1)),
      HomeworkWrites.revisionRecord(
        submissionId: id,
        homework: homework,
        studentId: studentId,
        revision: 1,
        event: SubmissionEvent.submit,
        status: decision.status!,
        text: text.trim(),
        attachments: attachments,
        actor: actor,
      ),
    );
    try {
      await batch.commit();
    } catch (error, stackTrace) {
      // A retry of a commit that actually succeeded is not an error.
      try {
        final existing = await c.submissions.doc(id).get();
        if (existing.exists &&
            existing.data()?['submittedBy'] == actor.userId) {
          return;
        }
      } catch (_) {}
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> resubmit({
    required Homework homework,
    required HomeworkSubmission current,
    required String text,
    required List<FileAttachment> attachments,
    required HomeworkActor actor,
  }) async {
    final c = _c(homework.schoolId, homework.branchId);
    try {
      final fresh = await _fresh(c, current.submissionId);
      final now = DateTime.now();
      final decision = HomeworkRules.checkResubmit(
        homework: homework,
        current: fresh,
        now: now,
      );
      if (decision.error != null) throw ValidationFailure(decision.error!);
      final content = HomeworkRules.checkContent(
        homework: homework,
        text: text,
        attachmentCount: attachments.length,
      );
      if (content != null) throw ValidationFailure(content);
      final rev = fresh.revision + 1;
      final late = fresh.late || homework.isPastDue(now);
      final batch = _firestore.batch();
      batch.update(
        c.submissions.doc(fresh.submissionId),
        HomeworkWrites.submissionResubmit(
          text: text,
          attachments: attachments,
          late: late,
          revision: rev,
          uid: actor.userId,
        ),
      );
      batch.set(
        c.revisions.doc(SubmissionRevision.idFor(fresh.submissionId, rev)),
        HomeworkWrites.revisionRecord(
          submissionId: fresh.submissionId,
          homework: homework,
          studentId: fresh.studentId,
          revision: rev,
          event: SubmissionEvent.resubmit,
          status: SubmissionStatus.resubmitted,
          text: text.trim(),
          attachments: attachments,
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

  Future<void> _review({
    required Homework homework,
    required HomeworkSubmission current,
    required HomeworkActor actor,
    required SubmissionEvent event,
    required SubmissionStatus toStatus,
    required String? Function(HomeworkSubmission fresh) check,
    required Map<String, dynamic> Function(int rev) fields,
    String? feedback,
    int? marks,
    String? notificationType,
  }) async {
    final c = _c(homework.schoolId, homework.branchId);
    try {
      final fresh = await _fresh(c, current.submissionId);
      // The student may have resubmitted since the teacher opened it.
      if (fresh.revision != current.revision) {
        throw const ConflictFailure(
          'This submission changed while you were reviewing it. '
          'Reload to see the latest work.',
        );
      }
      final problem = check(fresh);
      if (problem != null) throw ValidationFailure(problem);
      final rev = fresh.revision + 1;
      final batch = _firestore.batch();
      batch.update(c.submissions.doc(fresh.submissionId), fields(rev));
      batch.set(
        c.revisions.doc(SubmissionRevision.idFor(fresh.submissionId, rev)),
        HomeworkWrites.revisionRecord(
          submissionId: fresh.submissionId,
          homework: homework,
          studentId: fresh.studentId,
          revision: rev,
          event: event,
          status: toStatus,
          text: fresh.textAnswer,
          attachments: fresh.attachments,
          feedback: feedback,
          marks: marks,
          actor: actor,
        ),
      );
      if (notificationType != null) {
        batch.set(
          c.notifications.doc(
            HomeworkWrites.targetedNoticeId(
              fresh.submissionId,
              event.wireValue,
              rev,
            ),
          ),
          HomeworkWrites.targetedNotification(
            submission: fresh,
            homework: homework,
            type: notificationType,
            revision: rev,
            createdBy: actor.userId,
          ),
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
  Future<void> grade({
    required Homework homework,
    required HomeworkSubmission current,
    required int? marks,
    required String feedback,
    required HomeworkActor actor,
  }) => _review(
    homework: homework,
    current: current,
    actor: actor,
    event: SubmissionEvent.grade,
    toStatus: SubmissionStatus.graded,
    check: (f) => HomeworkRules.checkGrade(
      homework: homework,
      submission: f,
      marks: marks,
      feedback: feedback,
    ),
    fields: (rev) => HomeworkWrites.submissionGrade(
      marks: marks,
      feedback: feedback,
      revision: rev,
      actor: actor,
    ),
    feedback: feedback.trim().isEmpty ? null : feedback.trim(),
    marks: marks,
    notificationType: 'HOMEWORK_GRADED',
  );

  @override
  Future<void> returnForRevision({
    required Homework homework,
    required HomeworkSubmission current,
    required String feedback,
    required HomeworkActor actor,
  }) => _review(
    homework: homework,
    current: current,
    actor: actor,
    event: SubmissionEvent.returnForRevision,
    toStatus: SubmissionStatus.returnedForRevision,
    check: (f) => HomeworkRules.checkReturn(submission: f, feedback: feedback),
    fields: (rev) => HomeworkWrites.submissionReturn(
      feedback: feedback,
      revision: rev,
      actor: actor,
    ),
    feedback: feedback.trim(),
    notificationType: 'HOMEWORK_RETURNED',
  );

  @override
  Future<void> markReviewed({
    required Homework homework,
    required HomeworkSubmission current,
    required HomeworkActor actor,
  }) => _review(
    homework: homework,
    current: current,
    actor: actor,
    event: SubmissionEvent.review,
    toStatus: current.status,
    check: (f) =>
        const {
          SubmissionStatus.submitted,
          SubmissionStatus.lateSubmitted,
          SubmissionStatus.resubmitted,
        }.contains(f.status)
        ? null
        : 'Only submitted work can be marked reviewed.',
    fields: (rev) =>
        HomeworkWrites.submissionReview(revision: rev, uid: actor.userId),
  );

  @override
  Stream<HomeworkSubmission?> watch(
    String schoolId,
    String branchId,
    String submissionId,
  ) => _c(schoolId, branchId).submissions
      .doc(submissionId)
      .snapshots()
      .map(
        (s) =>
            s.exists ? HomeworkSubmission.fromFirestore(s.data()!, s.id) : null,
      );

  @override
  Future<PagedResult<HomeworkSubmission>> fetchForHomework({
    required String schoolId,
    required String branchId,
    required String homeworkId,
    SubmissionStatus? status,
    int pageSize = 25,
    Object? cursor,
  }) async {
    try {
      Query<Map<String, dynamic>> q = _c(
        schoolId,
        branchId,
      ).submissions.where('homeworkId', isEqualTo: homeworkId);
      if (status != null) {
        q = q.where('status', isEqualTo: status.wireValue);
      }
      q = q.orderBy('studentName').limit(pageSize);
      if (cursor is DocumentSnapshot) q = q.startAfterDocument(cursor);
      final snap = await q.get();
      return PagedResult(
        items: [
          for (final d in snap.docs)
            HomeworkSubmission.fromFirestore(d.data(), d.id),
        ],
        nextCursor: snap.docs.length == pageSize ? snap.docs.last : null,
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<List<HomeworkSubmission>> fetchForStudents({
    required String schoolId,
    required String branchId,
    required String homeworkId,
    required List<String> studentIds,
  }) async {
    if (studentIds.isEmpty) return const [];
    try {
      final result = <HomeworkSubmission>[];
      for (var i = 0; i < studentIds.length; i += 30) {
        final chunk = studentIds.skip(i).take(30).toList();
        final snap = await _c(schoolId, branchId).submissions
            .where('homeworkId', isEqualTo: homeworkId)
            .where('studentId', whereIn: chunk)
            .get();
        result.addAll([
          for (final d in snap.docs)
            HomeworkSubmission.fromFirestore(d.data(), d.id),
        ]);
      }
      return result;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<List<HomeworkSubmission>> fetchForStudent({
    required String schoolId,
    required String branchId,
    required String studentId,
    required String academicYearId,
  }) async {
    try {
      final snap = await _c(schoolId, branchId).submissions
          .where('studentId', isEqualTo: studentId)
          .where('academicYearId', isEqualTo: academicYearId)
          .get();
      return [
        for (final d in snap.docs)
          HomeworkSubmission.fromFirestore(d.data(), d.id),
      ];
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Stream<List<SubmissionRevision>> watchRevisions(
    String schoolId,
    String branchId,
    String submissionId,
  ) {
    // The id is `{homeworkId}__{studentId}`; both are pinned in the query so
    // the rules can prove access for the homework's teacher and for the
    // child's linked parent alike.
    final cut = submissionId.lastIndexOf('__');
    final homeworkId = submissionId.substring(0, cut);
    final studentId = submissionId.substring(cut + 2);
    return _c(schoolId, branchId).revisions
        .where('homeworkId', isEqualTo: homeworkId)
        .where('studentId', isEqualTo: studentId)
        .snapshots()
        .map((s) {
          final list = [
            for (final d in s.docs) SubmissionRevision.fromFirestore(d.data()),
          ]..sort((a, b) => a.revision.compareTo(b.revision));
          return list;
        });
  }

  Future<int> _count(Query<Map<String, dynamic>> q) async =>
      (await q.count().get()).count ?? 0;

  @override
  Future<SubmissionCounts> counts({
    required String schoolId,
    required String branchId,
    required String homeworkId,
  }) async {
    try {
      final base = _c(
        schoolId,
        branchId,
      ).submissions.where('homeworkId', isEqualTo: homeworkId);
      final results = await Future.wait([
        _count(
          base.where(
            'status',
            whereIn: [
              for (final s in SubmissionStatus.values)
                if (s.isStored && HomeworkRules.countsAsComplete(s))
                  s.wireValue,
            ],
          ),
        ),
        _count(base.where('late', isEqualTo: true)),
        _awaiting(base),
        _count(
          base.where(
            'status',
            isEqualTo: SubmissionStatus.returnedForRevision.wireValue,
          ),
        ),
        _count(
          base.where('status', isEqualTo: SubmissionStatus.graded.wireValue),
        ),
      ]);
      return SubmissionCounts(
        submitted: results[0],
        late: results[1],
        awaitingReview: results[2],
        returned: results[3],
        graded: results[4],
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  /// Awaiting review = resubmitted work, plus first submissions nobody has
  /// marked reviewed yet. (A resubmission always needs another look; the
  /// UI offers grade / return for it, not "mark reviewed".)
  Future<int> _awaiting(Query<Map<String, dynamic>> base) async {
    final r = await Future.wait([
      _count(
        base
            .where(
              'status',
              whereIn: [
                SubmissionStatus.submitted.wireValue,
                SubmissionStatus.lateSubmitted.wireValue,
              ],
            )
            .where('reviewedBy', isNull: true),
      ),
      _count(
        base.where('status', isEqualTo: SubmissionStatus.resubmitted.wireValue),
      ),
    ]);
    return r[0] + r[1];
  }

  @override
  Future<int> countAwaitingReview({
    required String schoolId,
    required String branchId,
    required String homeworkId,
  }) async {
    try {
      return await _awaiting(
        _c(
          schoolId,
          branchId,
        ).submissions.where('homeworkId', isEqualTo: homeworkId),
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
