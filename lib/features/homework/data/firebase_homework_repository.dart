import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../../students/domain/paged_result.dart';
import '../domain/file_attachment.dart';
import '../domain/homework.dart';
import '../domain/homework_enums.dart';
import '../domain/homework_repositories.dart';
import '../domain/homework_rules.dart';
import 'homework_firestore.dart';
import 'homework_writes.dart';

/// Homework lifecycle.
///
/// Every state change is one batch: the homework update, its append-only
/// history record and (for publication / deadline change) its broadcast
/// notice. The revision is read fresh and incremented, and the rules require
/// `revision == previous + 1`, so two editors racing cannot both win and a
/// retry of a commit that already happened finds the new state and returns
/// quietly instead of duplicating the history or the notice.
class FirebaseHomeworkRepository implements HomeworkRepository {
  final FirebaseFirestore _firestore;

  FirebaseHomeworkRepository(this._firestore);

  HomeworkCollections _c(String schoolId, String branchId) =>
      HomeworkCollections(_firestore, schoolId, branchId);

  @override
  Future<List<String>> createDrafts({
    required List<Homework> homework,
    required HomeworkActor actor,
  }) async {
    final created = <String>[];
    var failed = 0;
    Object? lastError;
    StackTrace? lastStack;
    // One commit per section: each is independent and idempotent by id, and
    // the rules' per-request lookup budget is per commit.
    for (final h in homework) {
      final c = _c(h.schoolId, h.branchId);
      final batch = _firestore.batch();
      batch.set(
        c.homework.doc(h.homeworkId),
        h.toFirestoreCreate(actorId: actor.userId),
      );
      batch.set(
        c.homeworkHistory.doc(HomeworkWrites.historyId(h.homeworkId, 1)),
        HomeworkWrites.history(
          homework: h,
          revision: 1,
          event: HomeworkEvent.created,
          toStatus: HomeworkStatus.draft,
          actor: actor,
        ),
      );
      try {
        await batch.commit();
        created.add(h.homeworkId);
      } catch (error, stackTrace) {
        // A retry of a commit that went through is not a failure.
        if (await _existsFor(c, h, actor)) {
          created.add(h.homeworkId);
        } else {
          failed++;
          lastError = error;
          lastStack = stackTrace;
        }
      }
    }
    if (failed > 0) {
      final failure = mapExceptionToFailure(lastError!, lastStack);
      if (created.isEmpty) throw failure;
      throw ConflictFailure(
        '$failed of ${homework.length} sections could not be saved '
        '(${failure.message}). The others were saved; try again to add the '
        'rest.',
      );
    }
    return created;
  }

  Future<bool> _existsFor(
    HomeworkCollections c,
    Homework h,
    HomeworkActor actor,
  ) async {
    try {
      final snap = await c.homework.doc(h.homeworkId).get();
      return snap.exists && snap.data()?['createdBy'] == actor.userId;
    } catch (_) {
      return false;
    }
  }

  Future<Homework> _fresh(Homework h) async {
    final c = _c(h.schoolId, h.branchId);
    final snap = await c.homework.doc(h.homeworkId).get();
    if (!snap.exists) {
      throw const NotFoundFailure('This homework could not be found.');
    }
    return Homework.fromFirestore(snap.data()!, snap.id);
  }

  @override
  Future<void> saveDraft({
    required Homework homework,
    required HomeworkActor actor,
  }) async {
    final c = _c(homework.schoolId, homework.branchId);
    try {
      final fresh = await _fresh(homework);
      if (fresh.status != HomeworkStatus.draft) {
        throw const ConflictFailure(
          'Only a draft can be edited this way. Reload and try again.',
        );
      }
      final rev = fresh.revision + 1;
      final edited = fresh.copyWith(
        title: homework.title,
        description: homework.description,
        dueDateKey: homework.dueDateKey,
        dueTimeMin: homework.dueTimeMin,
        clearDueTime: homework.dueTimeMin == null,
        dueAt: homework.dueAt,
        attachments: homework.attachments,
        requiresSubmission: homework.requiresSubmission,
        allowFiles: homework.allowFiles,
        allowLate: homework.allowLate,
        allowResubmission: homework.allowResubmission,
      );
      final batch = _firestore.batch();
      batch.update(
        c.homework.doc(fresh.homeworkId),
        HomeworkWrites.draftEdit(edited, rev, actor.userId),
      );
      batch.set(
        c.homeworkHistory.doc(HomeworkWrites.historyId(fresh.homeworkId, rev)),
        HomeworkWrites.history(
          homework: fresh,
          revision: rev,
          event: HomeworkEvent.edited,
          toStatus: HomeworkStatus.draft,
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

  /// Shared transition: read fresh → skip if already done → one batch.
  Future<void> _transition({
    required Homework homework,
    required HomeworkActor actor,
    required HomeworkEvent event,
    required HomeworkStatus toStatus,
    required bool Function(Homework fresh) alreadyDone,
    required String? Function(Homework fresh) precondition,
    required Map<String, dynamic> Function(int rev, Homework fresh) fields,
    String? noticeType,
    Homework Function(Homework fresh)? afterState,
    String? note,
  }) async {
    try {
      final fresh = await _fresh(homework);
      if (alreadyDone(fresh)) return;
      final problem = precondition(fresh);
      if (problem != null) throw ConflictFailure(problem);
      final c = _c(fresh.schoolId, fresh.branchId);
      final rev = fresh.revision + 1;
      final batch = _firestore.batch();
      batch.update(c.homework.doc(fresh.homeworkId), fields(rev, fresh));
      batch.set(
        c.homeworkHistory.doc(HomeworkWrites.historyId(fresh.homeworkId, rev)),
        HomeworkWrites.history(
          homework: fresh,
          revision: rev,
          event: event,
          toStatus: toStatus,
          actor: actor,
          note: note,
        ),
      );
      if (noticeType != null) {
        final after = afterState?.call(fresh) ?? fresh;
        batch.set(
          c.notices.doc(
            HomeworkWrites.noticeId(fresh.homeworkId, event.wireValue, rev),
          ),
          HomeworkWrites.homeworkNotice(after, noticeType, rev, actor.userId),
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
  Future<void> publish({
    required Homework homework,
    required HomeworkActor actor,
  }) => _transition(
    homework: homework,
    actor: actor,
    event: HomeworkEvent.published,
    toStatus: HomeworkStatus.published,
    alreadyDone: (f) => f.status != HomeworkStatus.draft,
    precondition: (f) => HomeworkRules.checkPublish(f, now: DateTime.now()),
    fields: (rev, f) => HomeworkWrites.publish(rev, actor.userId),
    noticeType: 'HOMEWORK_PUBLISHED',
  );

  @override
  Future<void> changeDue({
    required Homework homework,
    required String dueDateKey,
    required int? dueTimeMin,
    required DateTime dueAt,
    required HomeworkActor actor,
  }) => _transition(
    homework: homework,
    actor: actor,
    event: HomeworkEvent.dueChanged,
    toStatus: HomeworkStatus.published,
    // A repeat of the same extension finds the deadline already there.
    alreadyDone: (f) =>
        f.dueAt.isAtSameMomentAs(dueAt) && f.dueDateKey == dueDateKey,
    precondition: (f) {
      if (f.status != HomeworkStatus.published) {
        return 'Only published homework can have its deadline changed.';
      }
      return HomeworkRules.checkDueChange(f, dueAt);
    },
    fields: (rev, f) => HomeworkWrites.dueChange(
      dueDateKey: dueDateKey,
      dueTimeMin: dueTimeMin,
      dueAt: dueAt,
      revision: rev,
      uid: actor.userId,
    ),
    noticeType: 'HOMEWORK_DUE_CHANGED',
    afterState: (f) => f.copyWith(
      dueDateKey: dueDateKey,
      dueTimeMin: dueTimeMin,
      clearDueTime: dueTimeMin == null,
      dueAt: dueAt,
    ),
  );

  @override
  Future<void> editPublished({
    required Homework homework,
    required String description,
    required List<FileAttachment> attachments,
    required HomeworkActor actor,
  }) => _transition(
    homework: homework,
    actor: actor,
    event: HomeworkEvent.edited,
    toStatus: HomeworkStatus.published,
    alreadyDone: (_) => false,
    precondition: (f) => f.status == HomeworkStatus.published
        ? null
        : 'Only published homework can be edited this way.',
    fields: (rev, f) => HomeworkWrites.editPublished(
      description: description,
      attachments: attachments,
      revision: rev,
      uid: actor.userId,
    ),
  );

  @override
  Future<void> close({
    required Homework homework,
    required HomeworkActor actor,
  }) => _transition(
    homework: homework,
    actor: actor,
    event: HomeworkEvent.closed,
    toStatus: HomeworkStatus.closed,
    alreadyDone: (f) => f.status == HomeworkStatus.closed,
    precondition: (f) => f.status == HomeworkStatus.published
        ? null
        : 'Only published homework can be closed.',
    fields: (rev, f) => HomeworkWrites.statusChange(
      to: HomeworkStatus.closed,
      event: HomeworkEvent.closed,
      revision: rev,
      uid: actor.userId,
    ),
  );

  @override
  Future<void> archive({
    required Homework homework,
    required HomeworkActor actor,
  }) => _transition(
    homework: homework,
    actor: actor,
    event: HomeworkEvent.archived,
    toStatus: HomeworkStatus.archived,
    alreadyDone: (f) => f.status == HomeworkStatus.archived,
    precondition: (f) =>
        f.status == HomeworkStatus.draft || f.status == HomeworkStatus.closed
        ? null
        : 'Close published homework before archiving it.',
    fields: (rev, f) => HomeworkWrites.statusChange(
      to: HomeworkStatus.archived,
      event: HomeworkEvent.archived,
      revision: rev,
      uid: actor.userId,
    ),
  );

  @override
  Stream<Homework?> watch(String schoolId, String branchId, String id) =>
      _c(schoolId, branchId).homework
          .doc(id)
          .snapshots()
          .map(
            (s) => s.exists ? Homework.fromFirestore(s.data()!, s.id) : null,
          );

  /// Server-side: year, then the teacher (+ status) or class/section (+
  /// status), ordered by due date. Subject is applied to the page afterwards
  /// (a page can therefore hold fewer than [pageSize] items while more
  /// remain — `hasMore` is authoritative).
  @override
  Future<PagedResult<Homework>> fetch({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required HomeworkFilter filter,
    int pageSize = 25,
    Object? cursor,
  }) async {
    try {
      final c = _c(schoolId, branchId);
      Query<Map<String, dynamic>> q = c.homework.where(
        'academicYearId',
        isEqualTo: academicYearId,
      );
      if (filter.teacherStaffId != null) {
        q = q.where('teacherStaffId', isEqualTo: filter.teacherStaffId);
      } else {
        if (filter.classId != null) {
          q = q.where('classId', isEqualTo: filter.classId);
          if (filter.sectionId != null) {
            q = q.where('sectionId', isEqualTo: filter.sectionId);
          }
        }
      }
      if (filter.status != null) {
        q = q.where('status', isEqualTo: filter.status!.wireValue);
      }
      q = q.orderBy('dueDateKey', descending: true).limit(pageSize);
      if (cursor is DocumentSnapshot) q = q.startAfterDocument(cursor);
      final snap = await q.get();
      var items = [
        for (final d in snap.docs) Homework.fromFirestore(d.data(), d.id),
      ];
      items = [
        for (final h in items)
          if ((filter.subjectId == null || h.subjectId == filter.subjectId) &&
              (filter.teacherStaffId == null ||
                  filter.classId == null ||
                  h.classId == filter.classId) &&
              (filter.teacherStaffId == null ||
                  filter.sectionId == null ||
                  h.sectionId == filter.sectionId))
            h,
      ];
      return PagedResult(
        items: items,
        nextCursor: snap.docs.length == pageSize ? snap.docs.last : null,
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<List<Homework>> fetchForSection({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    required String sectionId,
    int limit = 100,
  }) async {
    try {
      final snap = await _c(schoolId, branchId).homework
          .where('academicYearId', isEqualTo: academicYearId)
          .where('classId', isEqualTo: classId)
          .where('sectionId', isEqualTo: sectionId)
          .where(
            'status',
            whereIn: [
              HomeworkStatus.published.wireValue,
              HomeworkStatus.closed.wireValue,
            ],
          )
          .orderBy('dueDateKey', descending: true)
          .limit(limit)
          .get();
      return [
        for (final d in snap.docs) Homework.fromFirestore(d.data(), d.id),
      ];
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Stream<List<HomeworkHistoryEntry>> watchHistory(
    String schoolId,
    String branchId,
    String homeworkId,
  ) => _c(schoolId, branchId).homeworkHistory
      .where('homeworkId', isEqualTo: homeworkId)
      .snapshots()
      .map((s) {
        final list = [
          for (final d in s.docs) HomeworkHistoryEntry.fromFirestore(d.data()),
        ]..sort((a, b) => a.revision.compareTo(b.revision));
        return list;
      });

  @override
  Future<int> countByStatus({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required HomeworkStatus status,
    String? teacherStaffId,
  }) async {
    try {
      Query<Map<String, dynamic>> q = _c(schoolId, branchId).homework
          .where('academicYearId', isEqualTo: academicYearId)
          .where('status', isEqualTo: status.wireValue);
      if (teacherStaffId != null) {
        q = q.where('teacherStaffId', isEqualTo: teacherStaffId);
      }
      final agg = await q.count().get();
      return agg.count ?? 0;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
